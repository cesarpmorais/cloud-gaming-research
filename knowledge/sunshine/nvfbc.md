# NVFBC & CUDA in Sunshine

## What is it?
**CUDA** is NVIDIA's parallel computing platform that allows programs to run code directly on the GPU.
**NVFBC** (NVIDIA Frame Buffer Capture) is a proprietary NVIDIA API that captures the screen at the GPU level — intercepting the framebuffer inside the driver before it reaches the display output.

## Why it matters for Sunshine / TCC
Sunshine supports multiple screen capture backends. NVFBC is one of them, and it offers the lowest possible capture latency on NVIDIA hardware. CUDA is required as the interface layer to access NVFBC.

Capture backend choice directly affects streaming latency and compatibility — a core concern for any game streaming system.

## Key Concepts
- **NVFBC**: NVIDIA's framebuffer capture API; captures screen inside the GPU driver, before display output
- **NVENC**: NVIDIA's hardware video *encoder* — separate from NVFBC; used for encoding the captured frames into H.264/H.265/AV1; works on consumer GPUs without any unlock
- **KMS capture**: Kernel Mode Setting capture — the Linux alternative to NVFBC; works on any GPU via the DRM subsystem
- **Consumer GPU lock**: NVIDIA restricts NVFBC to Quadro/professional cards at the driver level; consumer GPUs (e.g. RTX 4070 Super) have it disabled. Reason: market segmentation — professional Quadro cards are sold at massive markups (5-10x) partly justified by exclusive software features like NVFBC. The hardware is often the same silicon; the restriction is a driver-level software decision.
- **nvfbc-unlock**: A third-party kernel patch that bypasses NVIDIA's consumer GPU restriction; unofficial and may cause driver instability
- **Headless capture**: NVFBC works without a monitor attached; KMS requires an active display

## nvfbc-unlock Risks
- **Driver updates break it** — must reapply after every NVIDIA driver update
- **System instability** — patching a running kernel module can cause crashes or GPU hangs
- **No official support** — NVIDIA won't help if something breaks
- **DKMS complexity** — surviving reboots requires a DKMS module, adding maintenance overhead
- **Wayland issues** — NVFBC was designed for X11; Wayland support is limited/broken on patched consumer cards

## NVFBC vs KMS: Latency Reality
NVFBC's advantage over KMS is often overstated for typical use:
- Latency difference is **single-digit milliseconds** — imperceptible during gaming
- NVFBC's real advantages are **near-zero CPU overhead** and **headless operation**
- What actually dominates streaming latency:
  1. **Network** — by far the biggest factor
  2. **Encoder latency** — NVENC quality/speed (same regardless of capture method)
  3. **Client decode** — on the receiving device (e.g. Android phone)
- Conclusion: on a local network, capture backend choice is not a meaningful latency factor

## Related
- [[kms-drm]]

## Sources
- NVIDIA NVFBC documentation (proprietary, requires developer registration)
- Sunshine source: `src/platform/linux/graphics.h`, `src/platform/linux/cuda.cpp`
