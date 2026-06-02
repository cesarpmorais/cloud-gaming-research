# Idea: Adaptive Bitrate — Fixed vs Rule-based Controller

Status: 🔍 exploring

## Description
A TCC contribution that implements and compares two bitrate control strategies
for Sunshine game streaming:

1. **Fixed bitrate** (baseline) — current Sunshine behavior: user sets a target,
   no adaptation.
2. **Rule-based adaptive controller** — an AIMD controller driven by
   **server-side RTT inflation**. It reduces bitrate multiplicatively when the
   round-trip time rises above its stable baseline, and increases it additively
   after a calm period.

Each controller is evaluated under the same **bandwidth-limited** network
scenarios (NetEm/`htb`), replicating ABRAGame's 6 scenario shapes. The
comparison is the research contribution.

**Timeline:** 2 months. RL controller is out of scope.

## Narrative arc
```
Fixed bitrate  →  Rule-based adaptive controller
  (baseline)         (our contribution)
```
Research question: does an adaptive controller reduce streaming degradation
under varying network conditions compared to fixed bitrate, and at what cost
(false positives, unnecessary drops on clean networks)?

## Research question
> "Does a server-side rule-based adaptive bitrate controller reduce streaming
> degradation under varying network conditions compared to a fixed-bitrate
> baseline in Sunshine, without significantly degrading the experience on
> stable networks?"

## Positioning relative to prior work

C³G (Alós et al., 2019) is the closest prior work; the novelty axis is no
longer "server-side RTT-based ABR for cloud gaming" (Alós et al. did that
first) but the open-source, no-client-modification, HW-encoder,
simpler-policy Pareto point.

ABRAGame (Armendariz & Joskowicz, 2025) is the closest algorithmic prior
work on the ABR side. Key differences that define our novelty:

| Dimension | ABRAGame | This TCC |
|---|---|---|
| Architecture | Client-side, separate process | Server-side, integrated into Sunshine |
| Clock sync required | Yes (one-way latency) | **No** (round-trip time only) |
| Congestion signal | Cumulative one-way latency | **ENet RTT inflation** + frame-send latency (server-observable) |
| Increase strategy | Linear (+0.5 Mbps / 20s) | Linear + exponential variant |
| Platform | Proprietary (ABYA Go) | Open-source (Sunshine) — reproducible |
| Encoder integration | Bitrate commands via control channel | Direct NVENC reconfiguration |

Differences against C³G:

| Dimension | C³G (Alós et al. 2019) | This TCC |
|---|---|---|
| Platform | PlayGiga (proprietary) | Sunshine (open-source, reproducible) |
| RTT signal | Per-frame RTVL via client frame-ACKs | ENet `peer->roundTripTime` (no client mods) |
| Encoder | Software AVC, QP knob | NVENC via FFmpeg avcodec (HW pipeline) |
| Policy | Reactive drain + proactive state dictionary | Plain AIMD (simpler) |
| Target | First server-side RTT-based CG congestion control | Open-source instantiation; tests whether simpler policy suffices |

## Congestion signal: RTT (server-side, no clock sync)

The signal design went through several corrections — see [[research-journey]]
for the full arc. Short version of the dead ends:

- **`IDX_LOSS_STATS`** is legacy-GFE-only dead code for Sunshine.
- **`SS_FRAME_FEC_STATUS` (0x5502)** is event-driven *and* sent unreliably
  (`ENET_PACKET_FLAG_UNSEQUENCED`) — it self-destructs under the very loss it
  reports. PR #1 added a handler for it anyway, but it cannot be the controller
  signal.
- **IDR-request rate** detects loss but **saturates**: 10% vs 50% loss barely
  changes it. A ~3-level indicator, not a graded gauge.
- More fundamentally, **random packet loss is the wrong impairment**: an
  adaptive bitrate controller adapts to *bandwidth*, and lowering the bitrate
  does not fix uniform random loss.

The signal we build on instead:

- **RTT inflation.** Under bandwidth constriction the bottleneck queue fills,
  and queueing delay inflates round-trip time. RTT *trend* (rise above a
  per-session baseline) is a clean, graded congestion signal.
- It needs **no clock synchronization** — ABRAGame needed clock sync only
  because it measured *one-way* latency. RTT is round-trip, derived by each
  ENet peer from its own ACK timing.
- It is **already computed**: Sunshine's control channel is ENet, which
  maintains `peer->roundTripTime`, kept fresh by Moonlight's *reliable* periodic
  ping. Sunshine simply never reads it today.

## Input signals

```
Primary trigger:   RTT inflation = rtt_current − rtt_baseline
                   — from ENet peer->roundTripTime
                   — graded and continuous; rises with queueing delay

Fine-grained:      frame_send_ms (per-frame send latency)
                   — already measured server-side (frame_network_latency_logger)
                   — finer granularity than ENet RTT (~30/s vs ~sub-second)

Confirmation:      IDR-request rate over a sliding window
                   — lagging; cross-checks the RTT trigger against noise
```

No explicit bandwidth estimate is needed — the AIMD controller *probes* (it
does not estimate). This deliberately drops the fragile server-side `estBW` the
earlier design relied on.

## Rule-based controller algorithm

AIMD with **two-phase increase** (multiplicative recovery + linear probe),
RTT-driven, with hysteresis on both trigger and stability detector:

```
// Runs once per control window (~1 Hz, aligned to ENet's
// peer->roundTripTime refresh rate, not the 200 ms CSV tick).

// --- Trigger with hysteresis ---
if rtt_ms > RTT_THRESHOLD for K consecutive windows:    // congestion confirmed
    last_known_good = current_bitrate                   // remember the ceiling
    new_bitrate = current_bitrate * BETA                // multiplicative decrease
    new_bitrate = max(new_bitrate, MIN_BITRATE)
    arm stability detector

// --- Stability detector with margin ---
else if rtt_ms < (RTT_THRESHOLD - MARGIN) for STABLE_TIME:
    if current_bitrate < 0.9 * last_known_good:
        new_bitrate = current_bitrate * GAMMA           // phase 1: mult. recovery
    else:
        new_bitrate = current_bitrate + STEP            // phase 2: linear probe
    new_bitrate = min(new_bitrate, MAX_BITRATE)
    restart stability detector

if new_bitrate != current_bitrate:
    encoder.reconfigure(new_bitrate)
```

The two-phase increase directly addresses **ABRAGame's acknowledged
limitation** of pure-linear increase: after a decrease, we *know*
`last_known_good` worked recently, so it is safe to catch up to it quickly
(phase 1, multiplicative). Only past 90% of that known-good ceiling do we
switch to slow linear probing (phase 2). Same philosophy as CUBIC.

**Parameters are starting points — to be calibrated against Step 3 baseline
data.** The *shape* of the algorithm is fixed now; the *numbers* come from data.
`BETA` is deliberately exposed as a sweep parameter — exploring its tradeoff
between drain speed and quality drop is part of the experimental contribution.

| Param | Role | Starting point |
|---|---|---|
| `RTT_THRESHOLD` | RTT level that triggers a decrease | 100 ms absolute (RTVL_th from C³G); baseline-inflation form retained as guard for sessions whose stable RTT already exceeds 100 ms |
| `BETA` | multiplicative decrease factor | **swept** — candidate values {0.5, 0.7, 0.85} spanning TCP-Reno, midpoint, and GCC; pick winner from Step 3 data |
| `GAMMA` | multiplicative recovery factor (phase 1) | 1.15 |
| `STEP` | linear increase per window (phase 2) | +0.5 Mbps |
| `K` | consecutive over-threshold windows to fire decrease | 2 |
| `MARGIN` | RTT margin below threshold before increase | 20 ms |
| `STABLE_TIME` | calm time before an increase | 5–10 s |
| `MIN_BITRATE` / `MAX_BITRATE` | clamp | 1 Mbps / ~19 Mbps (18988 kbps negotiated target) |

The controller starts at `MAX_BITRATE` (the configured target) and adapts down.
`frame_send_ms` and IDR-request rate guard the RTT trigger against single
spurious spikes (the K-window hysteresis is the primary defense).

### What each choice borrows from which paper

| Choice | Source | Reasoning |
|---|---|---|
| **β swept around 0.7** (not 0.5 TCP, not 0.85 GCC fixed) | Midpoint between GCC's gentle 0.85 and TCP-Reno's aggressive 0.5 | 0.85 may not actually drain the queue; 0.5 over-reacts and tanks quality. Sweeping the value is itself an experimental contribution. |
| **Two-phase increase** (×1.15 recovery, then +0.5 linear) | Directly fixes **ABRAGame's acknowledged limitation** (slow pure-linear increase) | After a decrease we *know* `last_known_good` worked recently. Catch up fast to it, then probe past it slowly — same philosophy as CUBIC. |
| **Hysteresis on trigger** (K=2 windows over threshold) | **GCC's over-use detector** has the same idea — needs sustained over-use, not a single sample | RTT can spike for one sample due to Wi-Fi jitter unrelated to bottleneck queue. K=2 filters that. |
| **Margin on stability detector** (need RTT < 80 ms, not just < 100 ms) | Standard control-systems hysteresis | Without it, RTT at exactly 100 ms causes decrease→increase→decrease oscillation. |
| **Absolute threshold (100 ms)** rather than only baseline inflation | **C³G's RTVL_th** (peer-reviewed, CG-specific) | Cloud-gaming-specific number; the inflation form is kept as a guard for sessions whose stable RTT already exceeds 100 ms. |
| **1 Hz control window** | ENet update granularity | Faster control reads stale RTT; no information gain. |

### What we're explicitly NOT doing (and what it could cost us)

If results fall short of C³G's bounds, each row below is a candidate next
step that the gap would justify investigating.

| Paper feature | Why we're skipping it | Cost if it bites |
|---|---|---|
| **C³G's reactive drain** (compute `λ_drain = μ̄ − qdData/Δt` — the exact rate to drain the queue) | Needs a queue-occupancy estimate we don't have; multiplicative β is the "blind" substitute | If β over-drains, quality drops more than C³G would. If under-drains, queue persists and RTT stays high → second decrease. **This is the central tradeoff the TCC tests.** |
| **C³G's proactive state dictionary** | Needs offline calibration per platform; defeats the "simplest possible" claim | Slower convergence to optimum than C³G; the gap *is* a publishable result. |
| **GCC's Kalman-filtered delay gradient** | Subtle; needs a noise model; overkill for ENet RTT granularity | Coarser trigger; mitigated by K-window hysteresis. |
| **GCC's adaptive threshold γ(t)** | Adds tuning surface; deferred to future work | Fixed 100 ms may be too strict on bad baselines, too loose on great ones. The session-baseline guard partially compensates. |

## Evaluation methodology

- Linux `tc htb` for bandwidth shaping (see `testbed/scenarios.md`).
- Moonlight client: Android phone.
- 7 scenarios (clean + A–F), 240 s each, bandwidth-shaped, baseline target
  **~19 Mbps** (18988 kbps — the value Sunshine negotiates from a 25 Mbps
  client bitrate slider; the client slider value is not the on-the-wire
  target). 3 runs per scenario per controller.

### Metrics

**Objective (CSV, server-side — all runs):**
- RTT (median, p95) — congestion / latency proxy
- `frame_send_ms` — per-frame send latency
- bitrate trajectory and variance — controller stability
- recovery time — time to stabilize after a bandwidth drop (ABRAGame: 4.5 s ref)
- IDR-storm overhead — % of bytes spent on recovery keyframes
- session survival — did the session last the full 240 s?
- false-positive drops — unnecessary decreases on the clean scenario

**C³G-comparable metrics (for direct cross-paper comparison):**
- **RTT-transient triple** — for Scenario A (abrupt capacity drop), compute
  over each contiguous run where `rtt_ms > 100`:
  - `RTVL_peak` — maximum RTT during the run (worst moment of the spike).
  - `L_AP` — duration of the above-threshold run, in seconds (how long the
    user is suffering).
  - `AP` — mean RTT during the run (average severity inside the window).
  Pure post-processing on the existing RTT CSV column. Together they
  characterize the transient — peak alone misses long plateaus; length
  alone misses how bad they are; average alone smears the peak out.
- **Effective channel use** `λ̄ / c_btl` — average achieved rate over the
  shaped bottleneck capacity in stable windows. Target ≥ 90%. C³G reports
  93–96%; BBR-on-UDP reports 87–93%. Gives a directly comparable utilization
  number against the C³G paper.
- **Loss-free capacity-drop bound** — largest capacity-drop ratio `α_c` for
  which the session survives loss-free. C³G's bound is ~1.75 (42% drop).
  Matching it ⇒ the simpler-policy claim holds; falling short ⇒ a
  measurable, publishable gap that motivates future work toward a C³G-class
  policy.

**Subjective (QoE — blind MOS, key runs):**
- MOS 1–5 on an a-priori rubric, rated **blind** (screen-recorded runs, shuffled,
  scored without knowing which controller produced them).
- The subjective scores *validate the objective proxies*: showing MOS falls as
  RTT rises justifies RTT as a QoE proxy, after which the CSV carries the
  fine-grained quantitative analysis. No Moonlight code is modified.

## Encoder scope

**Implementation targets NVENC only** (NVIDIA GPU backend).

Rationale:
- NVENC is the dominant backend for Sunshine's primary user base.
- NVENC provides `NvEncReconfigureEncoder()` — supports mid-session bitrate
  changes in CBR mode without full reinit. GOP changes need reinit; bitrate
  does not. B-frames are not used in game streaming, so the known
  reconfiguration caveat does not apply.
- Narrowing to one backend keeps scope manageable without reducing research
  value.

Thesis framing: *"This implementation targets the NVENC backend, the most
widely used encoder in Sunshine deployments. Extension to VAAPI and AMF is left
as future work."*

Hardware for development and evaluation: NVIDIA GeForce RTX 4070 Super.

## Implementation plan

### Step 1 — CSV export (PR #1 to Sunshine)
Per-session CSV of server-side streaming stats on a fixed 200 ms tick.
- **Done:** `server->map(0x5502, ...)` handler for `SS_FRAME_FEC_STATUS`;
  columns for frames, bitrate, encode latency, IDR frames/requests, RFI
  requests, FEC events. See [[stats-export-findings]].
- **To add (Tier 1, same PR):** `rtt_ms`, `rtt_var_ms`, `avg_send_ms`,
  `target_kbps`, `packets_sent`, and `stalls` / `stall_ms` (broadcast stalls —
  gaps ≥ 100 ms between dispatched frames). `rtt_ms` reads
  `peer->roundTripTime`.

### Step 2 — Testbed setup (lab environment, not a PR)
Linux `tc htb` bandwidth shaping for the 7 scenarios in `testbed/scenarios.md`.
`tc class change` drives the temporal profiles.

### Step 3 — Baseline data collection
Run fixed-bitrate Sunshine (~19 Mbps) across all 7 scenarios. Collect CSV +
blind-MOS for key runs. Use this data to calibrate the controller parameters.

### Step 4 — Open a GitHub issue on Sunshine
Before writing controller code, open a discussion issue: the problem (fixed
bitrate degrades under bandwidth constriction, no recovery), the proposed
solution (optional adaptive mode, off by default, NVENC-only), the data (a CSV
sample from Step 3), and the algorithm sketch. Goal: confirm the feature is
wanted and get architectural feedback early.

The config flag lives in `sunshine.conf` and the Sunshine Web UI — **not** in
Moonlight (a separate client-side project).

### Step 5 — Adaptive controller (PR #2 to Sunshine)
Two parts, split across two sequential PRs:

#### Step 5a — Mechanism (PR #2a)

A `set_bitrate(kbps)` path through Sunshine's encoder abstraction. The TCC
dev/test platform is **Linux + NVENC (RTX 4070 Super)**, and a critical finding
during planning is that on Linux Sunshine's "nvenc" backend goes through the
**FFmpeg avcodec wrapper** (`h264_nvenc`/`hevc_nvenc`/`av1_nvenc`), not the
standalone NVENC SDK. The standalone `nvenc_base` class is Windows-only — see
[[encoders]] §"NVENC is two different code paths". So
`nvEncReconfigureEncoder()` is unreachable on the platform we actually test on,
and the Linux mechanism has to go through an `AVCodecContext` rebuild instead.

**Plan (Linux/avcodec only; Windows path stubbed):**

1. `src/globals.h` — add `MAIL(bitrate_change)` (payload `int` kbps).
2. `src/video.h:210` — add `virtual bool set_bitrate(int kbps) = 0;` to
   `encode_session_t`.
3. `src/video.cpp` — refactor `make_avcodec_encode_session` (~line 1614) into a
   helper `init_avcodec_ctx(session, config, bitrate_kbps, ...)`. Called both
   from the initial create path and from the reconfigure path. Single source of
   truth for the AVCodecContext build, including the VBV buffer sizing at line
   1819 area.
4. `src/video.cpp` — `avcodec_encode_session_t::set_bitrate` stores
   `pending_bitrate_kbps`; the next `encode_avcodec()` (line 1510) calls the
   helper, swaps the `AVCodecContext`, forces IDR, clears the field, and
   updates the CSV target column.
5. `src/video.cpp` — `nvenc_encode_session_t::set_bitrate` stubbed `return false;`
   with a TODO for the Windows path (`nvEncReconfigureEncoder()`). Cannot trip
   it on Linux.
6. `src/video.cpp` — both encode loops (async ~2086, sync ~2359) drain
   `bitrate_change_events` before each frame.
7. `src/stream.cpp:2108` — add the per-session event allocation alongside
   `idr_events`; add the matching field to `session_t::video` (~line 415).
8. `src/stat_trackers.{h,cpp}` — add `set_target_kbps(uint32_t)` so the
   `target_kbps` CSV column reflects the live target. Essential for the PR #2b
   plots.

**Test driver:** a hardcoded deterministic sweep behind a `bitrate_sweep_test`
config flag (off by default). Walks a known schedule (e.g. 19 → 1 → 19 Mbps in
2 Mbps steps every 30 s). Lets the testbed correlate CSV columns against a
known input. Logs each transition.

**Validation order before any matrix run:**

a. Clean network, sweep — confirm `target_kbps` and `bitrate_kbps` track the
   schedule, IDR per transition, no disconnect.
b. Sweep under `tc htb` 4 Mbps (scenario E shape) — does the session survive
   the full 240 s when the manual sweep drops below the cap in time? This is
   the defense-narrative test *before* the AIMD policy exists.
c. Measure the `stalls` / `stall_ms` impact of each transition. Quantifies the
   cost of the avcodec reinit. If intolerable, the lever is to add a CUDA
   subclass of `nvenc_base` for Linux (mirror of Windows `nvenc_d3d11_on_cuda`)
   — much bigger change, defer unless (c) forces it.

#### Step 5b — Policy (PR #2b)

The AIMD controller above, behind a `bitrate_mode = adaptive` flag. Reads RTT
where `record_rtt` already sees it (`src/stream.cpp:1659`) and writes via
`session->video.bitrate_change_events->raise(new_kbps)`. Collect CSV +
blind-MOS across all 7 scenarios; compare against the Step 3 baseline.

## Why it matters for TCC
- Directly extends ABRAGame: server-side, open-source, reproducible.
- The signal design (server-side, no clock sync) is a genuine research problem,
  and the RTT solution is a real simplification over ABRAGame's clock-synced
  one-way latency.
- The exponential-increase variant is a direct improvement over ABRAGame's
  acknowledged limitation.
- Two-month timeline is realistic: CSV export + testbed + baseline + controller.
- PR #1 (instrumentation) is independently mergeable — the merged-PR goal does
  not depend on PR #2 landing in time.

## Related Ideas
- [[idea-07-stats-export]] — PR #1; instrumentation layer
- [[idea-08-adaptive-streaming]] — rule-based controller detail
- [[idea-02-10bit-portal]] — deprioritized; separate contribution

## Related Knowledge
- [[research-journey]] — how the signal & methodology understanding evolved
- [[stats-export-findings]] — PR #1 dev notes; FEC/IDR signal reality
- [[loss-recovery]] — FEC / RFI / IDR escalation ladder
- [[architecture]] — control channel in `src/stream.cpp`; bitrate in `src/video.cpp`
- [[bitrate-control]] — bitrate flow; the missing runtime-reconfiguration path
- [[encoders]] — NVENC reconfiguration support
- [[abragame]] — closest algorithmic ABR prior work; methodology and algorithm to extend
- [[alos2019]] — closest prior work overall (C³G); defines the 100 ms RTVL threshold, effective-channel-use metric, and 42% loss-free bound we target
- [[related-work]] — full paper survey and positioning
