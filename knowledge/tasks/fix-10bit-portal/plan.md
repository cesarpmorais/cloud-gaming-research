# Task: Fix 10-bit Pixel Format in Portal Capture

**Status:** 🟡 partially solved upstream — needs re-evaluation
**Idea:** [[idea-02-10bit-portal]]
**Target file (post-May 2026 refactor):** `src/platform/linux/pipewire.cpp` (NOT `portalgrab.cpp` anymore)
**Original PR title:** `fix(capture): add 10-bit pixel format support in portalgrab`

---

## Update — May 2026

The XDG portal capture path was reorganized upstream (LizardByte/Sunshine#4417, see [[xdgportal-pipewire-migration]]). The PipeWire stream consumption + format mapping moved from `portalgrab.cpp` to a new `pipewire.cpp`. The new `format_map` is at `pipewire.cpp:47` and **already includes one 10-bit format**:

```cpp
static constexpr std::array<format_map_t, 3> format_map = {{
    {DRM_FORMAT_XBGR2101010, SPA_VIDEO_FORMAT_xBGR_210LE},
    {DRM_FORMAT_ARGB8888,    SPA_VIDEO_FORMAT_BGRA},
    {DRM_FORMAT_XRGB8888,    SPA_VIDEO_FORMAT_BGRx},
}};
```

**What's still missing** (and likely what triggers the original bug on KDE):
- `DRM_FORMAT_XRGB2101010` — common KDE choice
- `DRM_FORMAT_ARGB2101010`
- `DRM_FORMAT_ABGR2101010`

So the task is **partially obsolete**: the `portalgrab.cpp` patch is no longer applicable, but the underlying fix is still incomplete.

---

## Original problem (still relevant for the missing 3 formats)

On KDE Plasma 6 with an HDR-capable display, `capture = portal` could fail:
```
Error: Couldn't scale frame: Invalid argument
Error: Could not convert image
```

KDE negotiated a 10-bit format (`DRM_FORMAT_XRGB2101010`) via PipeWire. Sunshine's `format_map` only contained 8-bit entries (back then) → format unrecognized → `drm_format = 0` → DMA-BUF path skipped → MemPtr path taken with unknown format → `sws_scale()` fails.

---

## Re-evaluation plan

### Step 1 — Reproduce on current upstream ⏳ pending
1. Switch to KDE Wayland session with HDR-capable display
2. Set `capture = portal` (or try the new `capture = kwin` first)
3. Run `sunshine --log-level debug` and check the negotiated format in `"Video format:"`
4. Three outcomes:
   - **`xBGR_210LE`** → already supported, no fix needed for your setup
   - **`xRGB_210LE` / `ARGB_210LE` / `ABGR_210LE`** → bug still triggers, fix is needed
   - **8-bit format** → no HDR negotiation happening, can't reproduce

### Step 2 — Decide course of action
- If bug reproduces → small follow-up PR adding the missing 3 entries to `pipewire.cpp:47`
- If bug doesn't reproduce → mark this idea as ✅ solved (upstream's partial fix happens to cover your case)
- Either way, lower priority than PR #1 (CSV metrics) and PR #2 (controller)

### Step 3 (if needed) — Open small fix PR
- File: `src/platform/linux/pipewire.cpp:47`
- Add 3 entries (XRGB2101010, ARGB2101010, ABGR2101010) before the existing XBGR
- PR title: `fix(linux/pipewire): add missing 10-bit pixel formats`
- Reference upstream merge that added XBGR

---

## Why this is no longer a priority for the TCC

The May 2026 merge brought xdgportal-pipewire-migration which already addressed the *architecture* concern that motivated this task. Whether the remaining 3 missing formats matter to *your* setup depends on the compositor — you might not even hit it. PR #1 (metrics CSV) and PR #2 (adaptive bitrate controller) remain the primary contributions.

## Related
- [[xdgportal-pipewire-migration]] — the refactor that partially solved this
- [[capture-backends]]
- [[pipewire]]
- [[dmabuf]]
- [[dev-workflow]]
