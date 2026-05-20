# Sunshine Linux Capture Backends

## What is it?
Sunshine supports multiple screen capture backends on Linux, selected based on the display server, compositor, and GPU. The right backend must be chosen depending on the environment — a wrong choice causes either silent failure or a frame conversion error.

## Why it matters for Sunshine / TCC
Capture is the first stage of the streaming pipeline. If capture fails or produces an incompatible pixel format, nothing downstream (encoding, streaming) can work. Understanding which backend works where is essential for debugging and for contributing fixes.

## Key Concepts

### Architecture (post-May 2026 refactor)

A major refactor (LizardByte/Sunshine#4417, [[xdgportal-pipewire-migration]]) reorganized the Wayland capture path. The PipeWire stream consumption logic was extracted from `portalgrab.cpp` into a new `pipewire.cpp` so it can be reused by other backends (KWin, generic xdgportal). `portalgrab.cpp` now only handles the XDG Desktop Portal D-Bus negotiation; the actual frame consumption + format mapping lives in `pipewire.cpp`.

### Available backends (Linux)

| Backend | Config value | Display server / Compositor | Notes |
|---------|-------------|----------------------------|-------|
| x11grab | `x11` | X11 (also works on XWayland) | Reliable, mature; reads framebuffer via X11 protocol |
| wlr-screencopy | `wlr` | Wayland (wlroots / KDE Plasma 6+) | Uses `wlr-screencopy-unstable-v1` protocol |
| XDG Portal | `portal` | Wayland (any portal-supporting compositor) | D-Bus → PipeWire via `xdg-desktop-portal` |
| KWin direct | `kwin` (new — May 2026) | Wayland (KDE Plasma 6) | Direct screencast via KDE-specific protocol; bypasses portal |
| KMS/DRM | `kms` | Any (requires `cap_sys_admin`) | Kernel-level capture; display-server agnostic |
| NVFBC | `nvfbc` | Any (NVIDIA only) | GPU-level capture; requires CUDA + unlocked driver |

### Backend selection
Sunshine tries backends in priority order if none is explicitly set. To force a backend, set in `~/.config/sunshine/sunshine.conf`:
```
capture = x11   # or wlr, portal, kwin, kms, nvfbc
```

### Pixel format handling — the 10-bit issue (partially fixed upstream)

The 10-bit format mismatch on KDE Plasma 6 with HDR-capable displays was a recurring issue. The upstream merge of May 2026 added partial support — `pipewire.cpp` now includes one 10-bit format:

```cpp
// pipewire.cpp:47-50 (current upstream)
static constexpr std::array<format_map_t, 3> format_map = {{
    {DRM_FORMAT_XBGR2101010, SPA_VIDEO_FORMAT_xBGR_210LE},
    {DRM_FORMAT_ARGB8888,    SPA_VIDEO_FORMAT_BGRA},
    {DRM_FORMAT_XRGB8888,    SPA_VIDEO_FORMAT_BGRx},
}};
```

Three other 10-bit DRM formats are still missing: `XRGB2101010`, `ARGB2101010`, `ABGR2101010`. KDE typically negotiates `XRGB2101010` for HDR-capable displays, so the original bug may still trigger depending on the compositor's choice. See [[fix-10bit-portal/plan]] for status.

**Workaround when it triggers:** use `capture = x11` (XWayland) or try `capture = kwin` on Plasma 6.

## Related
- [[xdgportal-pipewire-migration]] — the May 2026 refactor that split portalgrab → pipewire + kwingrab
- [[wayland-vs-x11]]
- [[nvfbc]]
- [[pipewire]]
- [[dmabuf]]

## Sources
- Sunshine source: `src/platform/linux/portalgrab.cpp` — XDG portal D-Bus negotiation only (post-refactor)
- Sunshine source: `src/platform/linux/pipewire.cpp:47` — `format_map` (where 10-bit handling lives now)
- Sunshine source: `src/platform/linux/kwingrab.cpp` — KWin direct screencast (new)
- Sunshine source: `src/platform/linux/x11grab.cpp`, `wlgrab.cpp`, `kmsgrab.cpp`
- LizardByte/Sunshine#4417 — XDG portal + PipeWire migration
