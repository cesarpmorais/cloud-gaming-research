# Vulkan Video Encoder (Linux)

## What is it?
A new hardware encoder backend added to Sunshine in May 2026 ([LizardByte/Sunshine#4603](https://github.com/LizardByte/Sunshine/pull/4603)) that uses FFmpeg's Vulkan video encoding support. Vulkan Video is a cross-vendor standard for hardware-accelerated video encode/decode that works on any GPU with a sufficiently new Vulkan driver — AMD, Intel, NVIDIA, and even Mesa software fallbacks.

## Why it matters for Sunshine / TCC
- **Vendor independence:** Unlike NVENC (NVIDIA-only), VAAPI (Linux + driver-dependent), or AMF (Windows-only), Vulkan Video runs anywhere Vulkan does. Long-term it could become the default Linux encoder.
- **For our adaptive bitrate controller (PR #2):** if we want to claim the controller works "across encoders", Vulkan must be on that list. Its mid-session reconfiguration story is unknown — needs investigation.
- **Build cost we already paid:** the migration we just merged required us to install `vulkan-loader-devel` and `glslang`. Those are now baked into our build environment whether we use the Vulkan encoder or not.

## Key Concepts

### Codec coverage
Per `src/video.cpp`, the Vulkan encoder advertises three codecs:
- `av1_vulkan` — AV1
- `hevc_vulkan` — H.265
- `h264_vulkan` — H.264

### Selection priority
Vulkan slots into the existing encoder selection chain (see [[encoders]]). Configurable via `encoder = vulkan` in `sunshine.conf` to force it.

### Recent fixes worth knowing
The May 2026 release shipped multiple Vulkan-specific fixes — the encoder is new and still maturing:
- Default rate control changed from VBR to CBR (#5032) — relevant for any bitrate analysis
- Multi-GPU + DMA-BUF metadata plane handling (#5030)
- Auto-detect GPU with connected display (#4961) — fixes the "wrong GPU selected" failure mode
- Removed deprecated FFmpeg Vulkan queue lock/unlock (#5031)
- 16-bit DRM format support for HDR DMA-BUF import (#4962)
- RADV (AMD Mesa) low-latency Vulkan Video encoding was added (#4984), reverted (#4989), and not re-added — open question for AMD users

### Build dependencies (Linux)
The encoder requires:
- `libvulkan` runtime + headers (`vulkan-loader-devel` on Fedora)
- `glslc` or `glslangValidator` (shader compiler — `glslang` package on Fedora)
- A Vulkan-capable GPU + driver

These are now mandatory to *build* Sunshine on Linux even if you don't plan to use the encoder. To skip CUDA (which is also mandatory by default) use `-DSUNSHINE_ENABLE_CUDA=OFF`.

### Reconfiguration support — open question
Whether `bit_rate` can be changed mid-session is not documented. FFmpeg's generic AVCodecContext bitrate update path (see [[encoders]]) probably works, but the underlying Vulkan Video extension may not honor it — needs empirical testing if PR #2 wants to support it.

## Related
- [[encoders]] — the broader backend selection picture
- [[bitrate-control]] — where the encoder reads its bitrate from
- [[xdgportal-pipewire-migration]] — same May 2026 batch of changes that brought this in
- [[dev-workflow]] — updated Linux build deps

## Sources
- LizardByte/Sunshine#4603 — `feat(linux): Add Vulkan video encoder`
- `src/platform/linux/vulkan_encode.cpp` (~1000 lines, new)
- `src/platform/linux/vulkan_encode.h`
- `src/video.cpp:1019` — encoder registration
- `src_assets/linux/assets/shaders/vulkan/rgb2yuv.comp` — RGB→YUV conversion shader
