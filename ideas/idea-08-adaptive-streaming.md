# Idea: Adaptive Streaming — Dynamic Response to Network Conditions

Status: 💡 raw

## Description
Make Sunshine actively adapt streaming parameters (bitrate, resolution, FPS) in real time based on observed network conditions — primarily packet loss, but also RTT and FEC usage. The system should be self-correcting: when conditions degrade, it dials back quality gracefully; when conditions improve, it ramps back up.

Currently Sunshine reacts to IDR frame requests (forces a keyframe) but does **nothing** else with client feedback — it has no bitrate adaptation of any kind. The real per-frame loss signal a modern Moonlight client sends (`SS_FRAME_FEC_STATUS`, packet `0x5502`) is dropped unhandled, and the legacy `IDX_LOSS_STATS` packet is never sent to Sunshine at all. This idea is about building a proper adaptation loop on top of that signal.

This is distinct from game-side control (idea #4) — this is purely network/transport-layer responsiveness, independent of what's running on screen.

Key parameters to adapt:
- Bitrate (primary lever)
- Resolution (secondary, more impactful on quality)
- FPS target (last resort)

Input signals (from client feedback via control channel + idea #7 stats):
- `SS_FRAME_FEC_STATUS` events — the actual loss signal Moonlight sends (event-driven, loss/recovery only)
- RTT / jitter (from periodic pings)
- Actual delivered bitrate vs target

## Why it matters for TCC
- Directly improves user experience across varying network environments (LAN, WiFi, mobile data, internet)
- Well-scoped: builds on existing client feedback messages already in `stream.cpp`
- Natural follow-up to idea #7 (stats export) — uses the same metrics as input signals
- Strong PR story: "graceful quality degradation under packet loss"
- Testable with real data: compare streaming quality before/after across multiple environments

## Related Ideas
- [[idea-07-stats-export]] — provides the metrics this idea reads
- [[idea-04-dynamic-quality]] — game-side quality control, complementary
- [[idea-09-ml-abr]] — ML-based version of the same problem

## Related Knowledge
- [[architecture]] — control channel in `src/stream.cpp`; bitrate logic in `src/video.cpp`
