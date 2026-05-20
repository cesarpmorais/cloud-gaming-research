# Wayland vs X11

## What is it?
**X11** (X Window System) is the traditional Linux display server protocol, created in 1984. It follows a client-server model: the X server manages the display hardware, and applications (clients) send drawing commands to it over a socket. A separate process called the **compositor** (e.g. KWin, Mutter) sits on top and handles visual effects, window management, and compositing the final image. This layering means there are multiple processes involved in getting a pixel on screen, and any application can read the screen contents by querying the X server — which is both powerful and a security problem.

**Wayland** is the modern replacement, designed from scratch in 2008 to fix X11's architectural problems. In Wayland, the compositor *is* the display server — there's no separate X server. The compositor speaks directly to the kernel (via KMS/DRM) and to clients via the Wayland protocol. This eliminates the middleman, reduces latency, improves security, and simplifies the stack. The tradeoff: the compositor has full control, so operations that were trivially easy in X11 (like reading the framebuffer) now require explicit compositor cooperation through defined protocols.

On Fedora with KDE, **KWin** is the compositor for both sessions — but it speaks Wayland protocol in one and acts as an X11 compositor in the other.

## Why it matters for Sunshine / TCC
Sunshine uses different screen capture backends depending on the display server:
- **X11** → `x11grab` — mature, simple, works reliably; any app can grab the screen
- **Wayland** → must use one of: `wlr-screencopy` (wlroots-based compositors), `portal` (XDG Desktop Portal via PipeWire), or `kms` (kernel-level DRM capture)

Wayland's security model intentionally makes screen capture harder — applications can't freely read the framebuffer. This is why Sunshine needs explicit protocol support on Wayland, and why capture issues are more common there.

## Key Concepts
- **Compositor**: On Wayland, the single process that manages rendering, input, and display output (e.g. KWin for KDE, Mutter for GNOME)
- **KMS/DRM**: Kernel Mode Setting / Direct Rendering Manager — the Linux kernel subsystem the compositor talks to directly; see [[kms-drm]]
- **wlr-screencopy**: A Wayland protocol extension for screen capture from wlroots; KDE Plasma 6 added support for it
- **XDG Desktop Portal**: A standardized D-Bus interface for screen capture via PipeWire; works on KDE and GNOME
- **PipeWire**: Modern Linux multimedia server that routes video streams (including screen captures) between the compositor and applications
- **x11grab**: Sunshine's X11 capture backend — uses the X11 protocol directly; simple and reliable but unavailable on pure Wayland sessions
- **WAYLAND_DISPLAY**: Environment variable pointing to the Wayland socket; must be set for Wayland-aware apps to connect to the compositor

## Related
- [[nvfbc]]
- [[kms-drm]]
- [[sunshine-capture-backends]]

## Sources
- Sunshine source: `src/platform/linux/wlgrab.cpp`, `src/platform/linux/portalgrab.cpp`, `src/platform/linux/x11grab.cpp`
