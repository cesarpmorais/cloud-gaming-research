# XDG Portal + PipeWire Migration (May 2026)

## What is it?
A breaking architectural refactor in Sunshine ([LizardByte/Sunshine#4417](https://github.com/LizardByte/Sunshine/pull/4417), `feat(linux)!:`) that split the monolithic `portalgrab.cpp` into separate concerns: D-Bus portal negotiation, PipeWire stream consumption, and compositor-specific direct paths. The change paved the way for new capture backends like `kwingrab` (KDE-direct) without duplicating PipeWire logic.

## Why it matters for Sunshine / TCC
This migration was merged into upstream master between September 2025 and May 2026 — it landed in the chunk our fork merged via "Update branch". It changes:
1. **Where to look for capture bugs** on Wayland — many existing references to `portalgrab.cpp` are now misleading because the actual frame consumption logic moved.
2. **What format support means** — pixel format mapping is now in `pipewire.cpp` and shared by every Wayland backend that goes through PipeWire.
3. **What the user can pick** — new `capture = kwin` option for KDE Plasma 6 users that bypasses the portal entirely.

For PR #2 (the adaptive bitrate controller), this matters mainly as **runtime context**: when testing the controller on Wayland we need to know which capture backend is active so we can rule it out as a cause of degraded frames.

## Key Concepts

### Before (single file)
`portalgrab.cpp` did three things mixed together:
1. Talked to `org.freedesktop.portal.Desktop` over D-Bus to negotiate a screencast session
2. Connected to the resulting PipeWire stream
3. Decoded incoming PipeWire buffers into Sunshine's frame format

### After (3 files, separated concerns)
| File | Responsibility |
|------|----------------|
| `portalgrab.cpp` (~750 lines, slimmed) | XDG Desktop Portal D-Bus dance only — RemoteDesktop, ScreenCast, Request interfaces |
| `pipewire.cpp` (~1100 lines, new) | Generic PipeWire stream consumer + DRM/SPA format mapping. Reusable. |
| `kwingrab.cpp` (~700 lines, new) | KDE-specific direct screencast protocol. Bypasses xdg-desktop-portal entirely; uses `pipewire.cpp` for the buffer side. |

### Why split them
The portal flow is one of *several* ways to obtain a PipeWire stream on Linux. KWin offers a direct D-Bus interface that skips the portal (faster, no popup permission prompt for trusted apps). Wlroots compositors have `wlr-screencopy`. By making `pipewire.cpp` a reusable library, each frontend (portal, kwin, future ones) only has to handle the negotiation and hand the stream node ID to the consumer.

### Format map relocation
The crucial `format_map` (DRM ↔ SPA pixel format mapping) moved with the consumer logic to `pipewire.cpp:47`. Anyone hunting the 10-bit HDR bug or adding new pixel formats now edits this file — see [[fix-10bit-portal/plan]].

### Side effects of the migration we hit while merging
- Mandatory `vulkan-loader-devel` and `glslang` packages (new Vulkan encoder needs shader compilation)
- Static linking of `libstdc++` requires `libstdc++-static` package
- NVENC SDK headers bumped from v12 to v13 (`NV_ENC_SPLIT_ENCODE_MODE`, `inputBitDepth` and friends)
- CUDA mandatory by default (workaround: `-DSUNSHINE_ENABLE_CUDA=OFF`)
- See [[dev-workflow]] for the updated build deps list

## Related
- [[capture-backends]]
- [[pipewire]]
- [[wayland-vs-x11]]
- [[fix-10bit-portal/plan]]
- [[vulkan-encoder]]
- [[dev-workflow]]

## Sources
- LizardByte/Sunshine#4417 — `feat(linux)!: Support streaming through XDG portals and Pipewire`
- LizardByte/Sunshine#5008 — `refactor(linux/xdgportal): Split pipewire code into its own file so it can be reused`
- LizardByte/Sunshine#5009 — `feat(capture/linux): add KWin direct screencast capture method`
- `src/platform/linux/portalgrab.cpp`
- `src/platform/linux/pipewire.cpp`
- `src/platform/linux/kwingrab.cpp`
