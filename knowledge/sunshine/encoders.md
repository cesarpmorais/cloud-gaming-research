# Sunshine Encoder Backends

## What is it?
Sunshine ships multiple encoder backends and picks the best available one at runtime. Each backend targets different hardware and platforms — no single API covers everything.

## Why it matters for Sunshine / TCC
- Understanding which backend is active is essential for debugging encoding issues
- Any runtime bitrate reconfiguration (idea #10) must work across all backends — each has its own API for mid-session changes
- The selection logic determines which code path runs on any given machine

## Key Concepts

### The encoder backends

| Backend | Hardware | Platform | API |
|---|---|---|---|
| NVENC | NVIDIA GPUs | Windows + Linux | NVIDIA proprietary SDK |
| VAAPI | Intel, AMD, some NVIDIA | Linux only | Linux kernel VA-API standard |
| AMF | AMD GPUs | Windows | AMD AMF SDK |
| Vulkan (new — May 2026) | Any Vulkan-capable GPU | Linux | FFmpeg Vulkan video encoder |
| Software (libx264/libx265) | CPU (any) | All | FFmpeg software encoders |
| VideoToolbox | Apple Silicon / Intel Mac | macOS | Apple framework |

### Why so many?

**Hardware vs software:** GPU encoders (NVENC, VAAPI, AMF) offload encoding to dedicated silicon — much faster and lower CPU overhead. Software encoders use the CPU — universally available but expensive.

**Platform fragmentation:** NVENC is Windows + Linux but not macOS. VAAPI is Linux-only. AMF is Windows-only. VideoToolbox is macOS-only.

**Vendor lock-in:** NVENC only works on NVIDIA. AMF only works on AMD. VAAPI works on multiple vendors but with varying capabilities per driver. A user with an Intel iGPU and no discrete GPU needs VAAPI; a user with an NVIDIA card wants NVENC.

### Selection logic

`video.cpp` tries encoders in priority order at startup and uses the first that successfully initializes:

```
NVENC → AMF → VAAPI → Software
```

The user can override with `encoder =` in `sunshine.conf`.

### "NVENC" is two different code paths

This is the most important distinction in the file and the one easiest to miss. Sunshine has **two NVENC integrations**, selected by platform at compile time in `src/video.cpp` (the `#ifdef _WIN32` / `#elif !defined(__APPLE__)` branches starting around line 480):

| Platform | Path | Session class | Codec name | Reconfigure API |
|---|---|---|---|---|
| **Windows** | Standalone NVENC SDK | `nvenc_encode_session_t` → `nvenc_base` → `nvenc_d3d11*` | n/a (calls NVENC directly) | `nvEncReconfigureEncoder()` — true seamless mid-session reconfigure |
| **Linux** | FFmpeg avcodec wrapper around NVENC | `avcodec_encode_session_t` (same class VAAPI/software use) | `h264_nvenc` / `hevc_nvenc` / `av1_nvenc` | None at runtime — `bit_rate` is creation-time only |

The standalone `nvenc_base` class is **never instantiated on Linux**. The class hierarchy under `src/nvenc/` (`nvenc_d3d11`, `nvenc_d3d11_native`, `nvenc_d3d11_on_cuda`) is Windows-only — see `src/nvenc/*.h` — and is the only consumer of the linked NVENC SDK headers.

Consequence for cross-platform features:
- Any code that wants a "runtime bitrate change" cannot just call `nvEncReconfigureEncoder()` — that entry point doesn't exist on Linux.
- On Linux the implementation has to either (a) reinit the `AVCodecContext` mid-stream (works for every avcodec backend at once), or (b) add a new `nvenc_base` subclass that talks to NVENC through CUDA directly (mirror of Windows `nvenc_d3d11_on_cuda`). See [[idea-10-abr-comparison]] §"Step 5 mechanism" for the actual decision.

### Implication for idea #10 — runtime bitrate reconfiguration

Per backend, per platform:

| Backend / Platform | Reconfigure support | Notes |
|---|---|---|
| **NVENC (Windows)** | Yes — `nvEncReconfigureEncoder()` on `nvenc_base` | Seamless. Needs a `reconfigure_bitrate()` method added to `nvenc_base`; the encoder config is currently a stack local inside `create_encoder()` and would need to be promoted to a member field. |
| **NVENC (Linux)** | No direct API — must go through `AVCodecContext` | FFmpeg's `h264_nvenc` does not honor `ctx->bit_rate` after `avcodec_open2()`. The only way to change bitrate is to tear down and rebuild the `AVCodecContext`. |
| VAAPI | Driver-dependent in principle, but same Sunshine code path as Linux NVENC — goes through `avcodec_encode_session_t`. | A ctx-rebuild on bitrate change covers it. |
| AMF (Windows) | Likely yes via `AMFComponent::SetProperty()` | Needs verification; same avcodec-wrapper question on Windows. |
| Vulkan | Unknown — new backend, not yet investigated | Default rate control changed VBR → CBR (Sunshine#5032) |
| Software (FFmpeg) | Same as Linux NVENC — ctx-rebuild required | Always available |
| VideoToolbox | Out of scope for idea #10 | macOS only |

The cleanest abstraction is a `set_bitrate(kbps)` virtual on `encode_session_t`. On Linux it triggers a `AVCodecContext` rebuild (one mechanism for all avcodec backends). On Windows the `nvenc_encode_session_t` override calls into the standalone NVENC SDK. See [[idea-10-abr-comparison]] §"Step 5 mechanism" for the per-file plan.

## Related
- [[bitrate-control]] — how bitrate flows through the pipeline and is passed to these backends
- [[architecture]] — where encoding fits in the full pipeline
- [[idea-10-abr-comparison]] — requires runtime bitrate reconfiguration across all backends

## Sources
- `src/video.cpp` — encoder selection logic and AVCodec initialization
- `src/nvenc/nvenc_base.cpp` — NVENC rate control config
- `src/platform/linux/vaapi.cpp` — VAAPI rate control config
- `src/platform/windows/display_base.cpp` — AMF/Windows encoder
