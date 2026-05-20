# PipeWire

## What is it?
PipeWire is a modern Linux multimedia server that handles routing of both audio and video streams between applications and hardware. It replaced PulseAudio (audio) and V4L2/GStreamer ad-hoc solutions (video) with a single unified framework.

For screen capture on Wayland, PipeWire sits between the compositor (KDE Plasma) and any application that wants to record or stream the screen (like Sunshine). The compositor captures the screen into GPU memory, then PipeWire brokers access to that data.

## Why it matters for Sunshine / TCC
The `portal` capture backend in Sunshine (`portalgrab.cpp`) is entirely PipeWire-based. Every frame Sunshine captures on Wayland goes through PipeWire. Understanding PipeWire's role is essential for understanding:
- How format negotiation works (and why the 10-bit bug happens)
- How DMA-BUF frames flow from KDE to Sunshine
- Why the portal backend exists at all on Wayland

## Key Concepts

### Role in the capture pipeline
```
KDE Plasma (Wayland compositor)
    │  renders desktop into GPU framebuffer
    ▼
xdg-desktop-portal  ←── D-Bus request from Sunshine
    │  asks KDE for screen capture permission
    ▼
PipeWire (stream negotiation + frame routing)
    │  negotiates format, delivers frames
    ▼
Sunshine / portalgrab.cpp
```

### xdg-desktop-portal
The entry point. When Sunshine requests a screen capture on Wayland, it goes through the **XDG Desktop Portal** — a D-Bus API that abstracts portal access (screen capture, file picker, etc.) in a desktop-agnostic way. The portal asks the user for permission, then creates a PipeWire stream between the compositor and Sunshine.

This is the "portal" in `portalgrab.cpp` and `capture = portal`.

### PipeWire streams
A PipeWire stream is a negotiated connection between a producer (KDE) and a consumer (Sunshine). Before frames flow, they go through **format negotiation**:

1. Sunshine proposes the formats it accepts (from `format_map` in `portalgrab.cpp`)
2. PipeWire/KDE responds with the format it will use
3. If they agree → stream starts; frames arrive in the negotiated format
4. If the negotiated format isn't in Sunshine's `format_map` → `drm_format = 0` → bug

### SPA (Simple Plugin API)
PipeWire's internal type system. Format names like `SPA_VIDEO_FORMAT_BGRx` are SPA constants — Sunshine must map between SPA formats and DRM/FFmpeg formats to use frames correctly.

### Frame delivery: two modes
PipeWire can deliver frames in two ways (negotiated per stream):

| Mode | How | When |
|------|-----|-------|
| **DMA-BUF** | File descriptor to GPU memory | Format known, GPU supports it |
| **MemPtr** | Pointer to CPU RAM copy | Fallback when DMA-BUF unavailable |

See [[dmabuf]] for detail on why `drm_format` controls which path is taken.

### Audio
PipeWire also handles audio capture for Sunshine (`src/audio.cpp`). On Linux, Sunshine uses PipeWire/PulseAudio to capture system audio and stream it alongside video.

## Related
- [[dmabuf]] — the GPU memory sharing mechanism PipeWire uses for fast frame delivery
- [[wayland-vs-x11]] — why PipeWire is needed at all (Wayland security model)
- [[capture-backends]] — how portalgrab.cpp uses PipeWire; the 10-bit bug

## Sources
- Sunshine source: `src/platform/linux/portalgrab.cpp`
- PipeWire docs: https://pipewire.pages.freedesktop.org/pipewire/
- xdg-desktop-portal: https://flatpak.github.io/xdg-desktop-portal/
