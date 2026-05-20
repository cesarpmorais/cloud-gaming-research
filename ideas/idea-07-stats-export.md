# Idea: Streaming Stats Export

Status: 💡 raw

## Description
Add structured export of server-side streaming metrics from Sunshine. The internal `stat_trackers` infrastructure already computes min/max/avg for encode time per interval and fires callbacks — but those callbacks only write to the log as plain text. The idea is to wire those callbacks (and add new ones) to a proper export path:

1. **CSV/JSON file** written per session to a configurable path
2. **REST API endpoint** in `confighttp.cpp` that exposes current session stats as JSON, pollable by external tools

Metrics already tracked (or trivially addable):
- Encode time (min/max/avg) — already in `nvenc_base.cpp`
- Frame rate (actual vs target)
- Bitrate (actual)
- Frame drops / FEC usage

## Why it matters for TCC
- **Zero prior art** — no issues, no PRs, no discussion about this in the Sunshine repo
- **Clear PR story**: "add structured stats export for benchmarking and debugging"
- **Directly useful for the TCC itself**: baseline numbers for the proposal/paper can be collected with this tool
- **Well-scoped**: builds on existing `stat_trackers` infrastructure; doesn't require new tracking logic, just a new output path
- **Two deliverables in one**: the implementation *is* the benchmarking tool used in the research

## Related Ideas
- [[idea-01-nvfbc-benchmark]] — benchmark would use this to collect data
- [[idea-04-dynamic-quality]] — dynamic quality needs to read these stats; this export is a prerequisite

## Related Knowledge
- [[architecture]] — `stat_trackers` lives in `src/stat_trackers.h`; encode stats in `src/nvenc/nvenc_base.cpp`; API endpoint would go in `src/confighttp.cpp`
