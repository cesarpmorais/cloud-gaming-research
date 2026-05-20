# Idea: Adaptive Bitrate — Fixed vs Rule-based Controller

Status: 🔍 exploring

## Description
A TCC contribution that implements and compares two bitrate control strategies for Sunshine game streaming:

1. **Fixed bitrate** (baseline) — current Sunshine behavior: user sets a target, no adaptation.
2. **Rule-based adaptive controller** — triggered by server-observable congestion signals over a sliding window. Decrease: `new_bitrate = estBW - BWmargin`. Increase: additive steps after a stability timer, with an exponential variant as a differentiator over ABRAGame.

Each controller is evaluated under the same controlled network conditions using NetEm, replicating ABRAGame's 6 scenario types. The comparison is the research contribution.

**Timeline:** 2 months. RL controller is out of scope.

## Narrative arc
```
Fixed bitrate  →  Rule-based adaptive controller
  (baseline)         (our contribution)
```
Research question: does an adaptive controller reduce streaming degradation under varying network conditions compared to fixed bitrate, and at what cost (false positives, unnecessary drops on clean networks)?

## Research question
> "Does a server-side rule-based adaptive bitrate controller reduce streaming degradation under varying network conditions compared to a fixed-bitrate baseline in Sunshine, without significantly degrading the experience on stable networks?"

## Positioning relative to ABRAGame
ABRAGame (Armendariz & Joskowicz, 2025) is the closest prior work. Key differences that define our novelty:

| Dimension | ABRAGame | This TCC |
|---|---|---|
| Architecture | Client-side, separate process | Server-side, integrated into Sunshine |
| Clock sync required | Yes (one-way latency) | No (server-side signals only) |
| Congestion signal | Cumulative one-way latency | `SS_FRAME_FEC_STATUS` events + IDR request rate (server-observable) |
| Increase strategy | Linear (+0.5 Mbps / 20s) | Linear + exponential variant |
| Platform | Proprietary (ABYA Go) | Open-source (Sunshine) — reproducible |
| Encoder integration | Bitrate commands via control channel | Direct NVENC reconfiguration |

## Loss signal: verified (the protocol question is answered)

ABRAGame's congestion signal (cumulative one-way latency) is **predictive** — it rises before frames are lost. We do not have one-way latency without clock sync. The verified server-observable alternative:

**The only loss feedback a modern Moonlight client sends to Sunshine is `SS_FRAME_FEC_STATUS` (packet type `0x5502`).** Verified in `moonlight-common-c/src/RtpVideoQueue.c` and `ControlStream.c`:

- **`IDX_LOSS_STATS` is never sent to Sunshine.** It is a legacy-GFE-only codepath, guarded by `LC_ASSERT(!IS_SUNSHINE())` (`ControlStream.c:1370`). The handler at `stream.cpp:936` is dead code for our sessions. *(This corrects an earlier wrong assumption that misled a first implementation attempt.)*
- `SS_FRAME_FEC_STATUS` is sent **only on a loss or FEC-recovery condition** — three send sites in `RtpVideoQueue.c` (344, 596, 640), all loss paths. A cleanly received frame sends nothing. On a clean network the server hears silence.
- It fires on FEC *recovery*, not just on unrecoverable loss — so "FEC had to work" arrives slightly before "frame actually lost". Mildly leading, but still fundamentally reactive.
- **Sunshine has no handler for incoming `0x5502` — it is currently dropped.** Adding `server->map(0x5502, ...)` is PR #1's first task. Apollo does not handle it either; the contribution space is open.
- Payload (big-endian): `frameIndex`, `highestReceivedSequenceNumber`, `nextContiguousSequenceNumber`, `missingPacketsBeforeHighestReceived`, `totalDataPackets`, `totalParityPackets`, `receivedDataPackets`, `receivedParityPackets`, `fecPercentage`, multi-FEC block index/count.

**Design consequence:** the controller's sliding window cannot be event-driven by these packets (silence on a clean network ≠ no data). The window must be **time-based and server-paced** — accumulate FEC-status events between fixed ticks; an interval with zero events is a clean interval.

Remaining signal-design questions (the genuine research problem):
- Is the FEC-recovery trigger leading enough to act on, or does it arrive too late to matter? Measure empirically.
- How tightly do events cluster under sustained loss vs. transient loss?
- IDR request rate stays useful as a lagging severity/confirmation signal.
- Bandwidth estimate: `encoded_bits_sent / window`, computed server-side from NVENC output.

## Input signals (current best candidates)

```
Primary trigger:  SS_FRAME_FEC_STATUS events (0x5502)
                  — event-driven: sent only on loss/FEC-recovery
                  — Sunshine currently drops these (no handler)
                  — accumulate per fixed time tick, NOT per packet

Confirmation:     IDR_request_rate over sliding window
                  — lagging indicator; confirms decoder-side failure
                  — ABRAGame explicitly did not have this signal

Bandwidth estimate: encoded_bits_sent / window
                    (server-side estBW, derived from NVENC output)
```

## Rule-based controller algorithm

```
// Runs every N ms (N = fixed server-side tick, e.g. 100ms)

if sliding_window_signal > threshold:
    new_bitrate = estBW - BWmargin      // aggressive decrease
    new_bitrate = max(new_bitrate, MIN_BITRATE)
    reset stability_timer

else if stability_timer >= 20s:
    new_bitrate = bitrate + BWstep      // conservative increase (linear)
    // variant: exponential increase after N consecutive stable windows
    new_bitrate = min(new_bitrate, MAX_BITRATE)
    restart stability_timer

encoder.reconfigure(new_bitrate)  // NvEncReconfigureEncoder()
```

Tunable parameters: `BWmargin`, `BWstep`, `threshold`, `stability_timer`.
Starting point from ABRAGame: 1.5 Mbps / 0.5 Mbps / TBD / 20s.

## Evaluation methodology (replicating ABRAGame's testbed)

- Linux bridge + NetEm (`tc netem`) for traffic shaping
- Moonlight client: Android phone
- 6 network scenarios (240s each):
  - **A:** Abrupt drop + rapid recovery
  - **B:** Gradual drop + fast recovery
  - **C:** Slow drop + fast recovery
  - **D:** Intermittent fluctuations
  - **E:** Long drop + abrupt recovery
  - **F:** Low start + late improvement
- Latency conditions: low (~7ms) and high (+50ms)
- Game genres: FPS, RPG, Racing (racing had highest ABRAGame failure rate — worth replicating)

### Metrics
- Effective loss cancellation rate (primary — matches ABRAGame for direct comparison)
- Recovery time after disruption (ABRAGame achieved 4.5s — our target reference)
- False positive rate (unnecessary bitrate drops on stable networks)
- Bitrate variance over time
- IDR request rate
- Freeze/stall events

## Encoder scope

**Implementation targets NVENC only** (NVIDIA GPU backend).

Rationale:
- NVENC is the dominant backend for Sunshine's primary user base (NVIDIA GPU owners)
- NVENC provides `NvEncReconfigureEncoder()` — confirmed to support mid-session bitrate changes in CBR mode without full reinit. GOP structure changes require reinit; bitrate does not.
- Caveats: B-frames + finite GOP can cause reconfiguration failures — not a concern since Sunshine does not use B-frames in game streaming.
- Narrowing to one backend keeps scope manageable without reducing research value

Thesis framing: *"This implementation targets the NVENC backend, which is the most widely used encoder in Sunshine deployments and provides the most robust API for mid-session reconfiguration. Extension to VAAPI and AMF is left as future work."*

Hardware used for development and evaluation: NVIDIA GeForce RTX 4070 Super.

## Implementation plan

### Step 1 — CSV export (PR #1 to Sunshine)
Export streaming stats (IDR request rate, FEC-status loss events, estimated bandwidth, bitrate over time) to a structured CSV file. Required by all subsequent steps. See [[idea-07-stats-export]] for scope.

**Includes a prerequisite sub-task:** add a `server->map(0x5502, ...)` handler for incoming `SS_FRAME_FEC_STATUS` packets — Sunshine currently drops them, so without this there is no loss data to export at all. CSV rows are written on a fixed server-side time tick (not per packet, not per frame); FEC-status events are accumulated into each row's loss columns. While testing, observe how the event stream clusters under loss to inform the sliding-window design.

### Step 2 — Testbed setup (lab environment, not a PR)
Set up Linux bridge + NetEm to emulate the 6 network scenarios above. External infrastructure — `tc netem` commands, not Sunshine code.

### Step 3 — Baseline data collection
Run fixed-bitrate Sunshine across all 6 scenarios. Collect CSV output. No new code beyond Step 1.

### Step 4 — Open a GitHub issue on Sunshine
Before writing any controller code, open a discussion issue on the Sunshine repo describing:
- The problem (fixed bitrate degrades under packet loss with no recovery)
- The proposed solution (optional adaptive mode, off by default, NVENC-only initially)
- The data (attach a CSV sample from Step 3 showing degradation under fixed bitrate)
- The algorithm sketch (ABRAGame-inspired, cumulative signal trigger, estBW − margin decrease)

Goals: confirm the feature is wanted, get architectural feedback early, establish prior art with a timestamp. Do this after Step 3 so you have real data to back the proposal.

The config flag should live in `sunshine.conf` and the Sunshine Web UI (`localhost:47990`) — **not** in Moonlight, which is a separate client-side project maintained by a different team.

### Step 5 — Adaptive controller (PR #2 to Sunshine)
Implement the rule-based adaptive bitrate controller as a new optional mode in Sunshine (`bitrate_mode = adaptive` config flag + Web UI toggle), targeting NVENC via `NvEncReconfigureEncoder()`. Finalize signal design and algorithm parameters based on Step 1 findings, baseline data, and issue feedback.

Collect CSV output across all 6 scenarios. Compare against baseline.

## Why it matters for TCC
- Directly extends ABRAGame: server-side, open-source, reproducible by the community
- Signal design challenge (server-side without clock sync) is a genuine research problem
- Exponential increase variant is a direct improvement over ABRAGame's acknowledged limitation
- Two-month timeline is realistic: CSV export + testbed + baseline + controller is achievable
- Open-source contribution helps the Sunshine community beyond the thesis

## Related Ideas
- [[idea-07-stats-export]] — PR #1; instrumentation layer
- [[idea-08-adaptive-streaming]] — rule-based controller detail
- [[idea-02-10bit-portal]] — deprioritized; separate contribution, not part of this plan

## Related Knowledge
- [[architecture]] — control channel in `src/stream.cpp`; bitrate logic in `src/video.cpp`
- [[bitrate-control]] — full bitrate flow and the gap for runtime reconfiguration
- [[encoders]] — NVENC reconfiguration support confirmed
- [[frame-types]] — IDR request rate as a degradation signal
- [[abragame]] — closest prior work; evaluation methodology and algorithm to extend
- [[related-work]] — full paper survey and positioning
