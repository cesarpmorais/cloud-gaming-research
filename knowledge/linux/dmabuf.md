# DMA-BUF (Direct Memory Access Buffer)

## What is it?
DMA-BUF is a Linux kernel mechanism that lets different hardware components share the same chunk of GPU memory without copying it. Instead of transferring pixel data, one component hands another a **file descriptor** — a lightweight reference/handle to the GPU memory allocation.

This means a frame that was rendered on the GPU can be passed directly to a hardware video encoder (also on the GPU) without ever touching CPU RAM.

## Why it matters for Sunshine / TCC
Sunshine uses DMA-BUF as the **fast path** for portal (PipeWire) capture on Wayland. When available, it avoids a full CPU copy of every frame, reducing latency and CPU overhead. Understanding DMA-BUF is essential for understanding the 10-bit pixel format bug (idea #2) and why it causes the fallback to fail.

## Key Concepts

### The two capture paths in portalgrab.cpp
When a frame arrives from PipeWire, Sunshine chooses between two paths based on whether it knows the pixel format (`drm_format != 0`):

**DMA-BUF path (fast — GPU stays on GPU)**
```
KDE (GPU memory)
    │  file descriptor (no data copy)
    ▼
Sunshine portalgrab.cpp
    │  passes fd to NVENC/VAAPI
    ▼
Hardware encoder (GPU memory)
```
The GPU driver needs `drm_format` to know how to interpret the bytes in the buffer (channel layout, bit depth). Without it, the driver can't safely access the memory.

**MemPtr path (fallback — CPU copy)**
```
KDE (GPU memory)
    │  [full pixel copy to CPU RAM]
    ▼
CPU RAM (raw bytes, plain pointer)
    │
Sunshine portalgrab.cpp → sws_scale() → encoder
```
PipeWire copies the frame to regular CPU RAM and gives Sunshine a pointer. No GPU format knowledge needed to read the bytes — but `sws_scale()` still needs to know the pixel format to convert it for encoding.

### Why drm_format = 0 breaks both paths
`drm_format` serves double duty:
- **DMA-BUF**: the GPU driver uses it to interpret the buffer's memory layout
- **MemPtr**: `sws_scale()` uses it to know what pixel format the bytes are in

When `drm_format = 0` (format not in `format_map`):
1. DMA-BUF path is skipped (correctly — can't use DMA-BUF without knowing the format)
2. MemPtr path is used — but `sws_scale()` still receives format `0` (unknown)
3. `sws_scale()` fails: **"Couldn't scale frame: Invalid argument"**

The fallback is incomplete: it falls back to MemPtr without resolving the unknown format.

### Pixel format basics
A pixel format defines how color data is stored in memory:
- `XRGB8888`: 32 bits/pixel — 8 bits each for padding (X), Red, Green, Blue
- `XRGB2101010`: 32 bits/pixel — 2 bits padding, 10 bits each for R, G, B (HDR)

Same total size, completely different bit layout. The decoder/encoder must know which one it's reading.

### Format negotiation
Before frames flow, PipeWire and Sunshine negotiate which pixel format to use:
1. Sunshine advertises the formats it supports (from `format_map`)
2. PipeWire/KDE picks one it can provide
3. If KDE only offers a format not in Sunshine's list (e.g. `XRGB2101010`), negotiation "succeeds" but Sunshine can't look it up → `drm_format = 0`

## Related
- [[pipewire]] — the multimedia server that delivers DMA-BUF frames to Sunshine
- [[capture-backends]] — the 10-bit bug that drm_format=0 causes
- [[wayland-vs-x11]]

## Sources
- Sunshine source: `src/platform/linux/portalgrab.cpp` — `on_param_changed()` (line ~1128), `format_map` (line 126)
- Linux kernel DMA-BUF docs: https://www.kernel.org/doc/html/latest/driver-api/dma-buf.html
