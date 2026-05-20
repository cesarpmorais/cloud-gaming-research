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

### Implication for idea #10 — runtime bitrate reconfiguration

Each backend has its own API for accepting a new bitrate mid-session:

| Backend | Reconfigure support | Notes |
|---|---|---|
| NVENC | Yes — dedicated `NvEncReconfigureEncoder()` call | Most reliable |
| VAAPI | Driver-dependent | May or may not support mid-session changes |
| AMF | Likely yes via `AMFComponent::SetProperty()` | Needs verification |
| Vulkan | Unknown — new backend, not yet investigated | Default rate control changed VBR → CBR (Sunshine#5032) |
| Software (FFmpeg) | Yes — update `ctx->bit_rate` and call `avcodec_parameters_from_context` | Always available |

The adaptive controller will need either a unified abstraction layer or per-backend implementations.

## Related
- [[bitrate-control]] — how bitrate flows through the pipeline and is passed to these backends
- [[architecture]] — where encoding fits in the full pipeline
- [[idea-10-abr-comparison]] — requires runtime bitrate reconfiguration across all backends

## Sources
- `src/video.cpp` — encoder selection logic and AVCodec initialization
- `src/nvenc/nvenc_base.cpp` — NVENC rate control config
- `src/platform/linux/vaapi.cpp` — VAAPI rate control config
- `src/platform/windows/display_base.cpp` — AMF/Windows encoder
