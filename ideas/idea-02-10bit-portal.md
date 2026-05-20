# Idea: 10-bit Pixel Format Support in Portal Capture

Status: ❌ deprioritized

## Description
Add 10-bit pixel format entries (e.g. `DRM_FORMAT_XRGB2101010`) to the `format_map` in `portalgrab.cpp`. Currently Sunshine only maps two 8-bit formats, causing a crash on KDE Plasma 6 with HDR-capable displays.

## Why it matters for TCC
This is a real bug affecting a large and growing segment of users — anyone on KDE Wayland with a modern HDR display. The fix is well-scoped and directly in Sunshine's C++ codebase. High chance of PR acceptance.

## Related Ideas
- [[idea-05-virtual-display]]

## Related Knowledge
- [[capture-backends]]
- [[wayland-vs-x11]]
