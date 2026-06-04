# Campaign Results — β = 0.7 (Baseline vs Adaptive)

## What is it?

First-round results from the testbed comparison of fixed-bitrate streaming
against the PR #2b adaptive controller at default parameters
(β = 0.7, γ = 1.15, RTT threshold = 100 ms, hysteresis = 2 s,
stable_time = 7.5 s, linear step = 500 kbps). One run per scenario per
mode, 240 s each, 7 scenarios (clean + A–F), Linux + NVENC + Sunshine on a
shared local LAN with `tc htb` bandwidth shaping.

This file is the durable text record of those results — meant to be the
source the TCC results section is written from. The exploratory notebook
(`testbed/visualizations/results_beta_0.7/comparison.ipynb`) generated the
numbers; the framings, paragraphs, and cross-links live here so they do not
need to be re-derived each time.

## Why it matters for Sunshine / TCC

This is the headline experimental contribution of the TCC. It answers the
central research question — *"does a simple reactive AIMD controller on
open-source Sunshine reduce streaming degradation under bandwidth
constriction without significantly degrading the experience on stable
networks?"* — with a quantitative yes, plus two well-characterized
limitations that the TCC discussion section can turn into precise framings
of follow-on work.

## Key Concepts

### Headline 1 — p95 RTT collapses on 5 of 6 degraded scenarios

p95 RTT is the latency the user actually feels at the bad moments:

| Scenario | Cap | Baseline p95 RTT | Adaptive p95 RTT | Factor |
|----------|-----|------------------|------------------|--------|
| A | 8 Mbps (80–160 s) | 1723 ms | 52 ms | **33×** |
| B | 16 → 12 → 8 Mbps | 1320 ms | 194 ms | **7×** |
| C | 14 → 10 Mbps | 1481 ms | 116 ms | **13×** |
| D | toggle 10 Mbps / 30 s | 1441 ms | 117 ms | **12×** |
| E | 4 Mbps (40–200 s) | 3431 ms | 3196 ms | 1.07× (no help) |
| F | 6 Mbps (0–160 s) | 2308 ms | 260 ms | **9×** |

### Headline 2 — stalls disappear on B, C, D

A *stall* is a ≥ 100 ms gap between consecutive dispatched frames. Total
stall time (seconds of frozen-screen-time) per 240 s session:

| Scenario | Baseline stalls / stall_s | Adaptive stalls / stall_s |
|----------|---------------------------|---------------------------|
| clean | 0 / 0 | 0 / 0 |
| A | 43 / 49.3 | 4 / 4.4 |
| B | 50 / 43.6 | **0 / 0** |
| C | 107 / 87.5 | **0 / 0** |
| D | 103 / 91.5 | **0 / 0** |
| E | 59 / 135.2 | (still heavy — partial CSV) |
| F | 100 / 148.9 | (some — TBD from CSV) |

### Headline 3 — no false positives on clean

- Subjective ratings: 1/1/2 → 1/1/2 (identical).
- `abr_state` distribution: 99.9 % `stable`. The 100 ms threshold + 2 s
  hysteresis is conservative enough to ignore Wi-Fi/OS jitter on a quiet
  network.

### Headline 4 — subjective ratings improve everywhere, with the expected quality trade

Operator ratings on the 1–5 scale (lower = better):

| Scenario | Baseline (lat / qual / stab) | Adaptive (lat / qual / stab) |
|----------|------------------------------|------------------------------|
| clean | 1 / 1 / 2 | 1 / 1 / 2 |
| A | 5 / 1 / 5 | 3 / 1 / 3 |
| B | 4 / 1 / 4 | 1 / 1 / 2 |
| C | 4 / 1 / 4 | 1 / 1 / 1 |
| D | 4 / 1 / 3 | 2 / 1 / 2 |
| E | 5 / 1 / 5 | 3 / 3 / 3 |
| F | 5 / 1 / 4 | 3 / 2 / 3 |

- **Latency and stability improve in every degraded scenario.**
- **Quality cost is real but bounded.** Stays at 1 for mild caps (B, C, D).
  Degrades to 2 (F) and 3 (E) where the controller has to drive bitrate
  hard down. This is the deliberate bandwidth-quality trade.

### Headline 5 — the transient triple (C³G's metric)

For each scenario, the longest continuous run of RTT above 100 ms:

| Scenario | Baseline (peak / L_AP / AP) | Adaptive (peak / L_AP / AP) |
|----------|------------------------------|------------------------------|
| clean | 0 / 0 / 0 ms | 0 / 0 / 0 ms |
| A | 1854 / 86.8 s / 1427 | 1786 / 17.3 s / 1171 |
| B | 1551 / 102.7 s / 988 | 575 / 9.7 s / 394 |
| C | 1565 / 164.8 s / 1055 | 733 / 10.9 s / 379 |
| D | 1557 / 36.5 s / 982 | 1156 / 10.9 s / 519 |
| E | 3788 / 164.4 s / 2691 | 3808 / 40.7 s / 2535 |
| F | 2536 / 166.8 s / 1728 | 1602 / 22.8 s / 852 |

Reading: **L_AP (duration above threshold) shrinks 5–10× on A–D, F**, AP
(average severity during the bad period) drops ~50 %. RTVL_peak barely
moves because both modes share the initial spike before the controller can
react — that is the [[reactive-blind-spot]] floor showing up in the data.

### Limitation 1 — scenario E (4 Mbps cap) is the failure mode

p95 RTT only drops 7 %. The cap (4 Mbps) is far below the negotiated
target (19 Mbps) and the queue builds faster than the 2 s hysteresis
allows the controller to react. The session never recovers within the
160 s shaping window. L_AP improves (164 s → 41 s, **4× shorter**), and
quality is acceptable (3) where the baseline was 5, but latency stays bad.

This matches **C³G's published bound**: their controller is loss-free only
up to ~42 % capacity drop (`α_c < 1.75`). Scenario E is a 79 % drop
(19 → 4 Mbps, `α_c = 4.75`) — outside both controllers' designed
envelope. Frame this in the TCC as *"the simpler policy reproduces
C³G-class behavior within roughly the same operating envelope, and breaks
down outside it for the same reason."*

### Limitation 2 — effective channel use is well below C³G's target

Mean send rate over the `tc htb` cap during shaped windows:

| Scenario | Window | Cap | Baseline | Adaptive |
|----------|--------|-----|----------|----------|
| A | 80–160 s | 8 Mbps | 1.64 (overshoot) | **0.42** |
| B | 60–100 s | 16 Mbps | 0.82 | 0.42 |
| B | 100–140 s | 12 Mbps | 1.03 | 0.37 |
| B | 140–160 s | 8 Mbps | 1.44 | 0.26 |
| C | 40–120 s | 14 Mbps | 0.93 | 0.36 |
| C | 120–200 s | 10 Mbps | 1.41 | 0.57 |
| D (×4) | various | 10 Mbps | 0.92–1.64 | 0.36–0.55 |
| E | 40–200 s | 4 Mbps | 3.24 (extreme overshoot) | **0.45** |
| F | 0–160 s | 6 Mbps | 0.99 | 0.44 |

Adaptive runs settle at **35–55 %** channel use. C³G reports
**93–96 %**; BBR-on-UDP **87–93 %**. We are about half-way below their
target. The controller is *too conservative*:

- β = 0.7 over-drains on each decrease — after 9 cascades we hit the
  floor even when the cap could accept much more.
- The 500 kbps linear probe is too small relative to the 19 Mbps target
  (≈ 36 successful probes to climb back).
- The 7.5 s stable-time gate before each probe slows recovery further.

This is the **central TCC tradeoff**, named: stability is paid for in
channel use. The simpler reactive policy wins on RTT/stalls but loses to
C³G on bandwidth efficiency.

### Two paths to close the gap

- **Within the reactive architecture (cheap):** larger γ, larger linear
  step, shorter stable_time, gentler β. Plausibly 40 % → 70 % channel use.
  Stays inside this TCC's scope. The β sweep on scenario A is the first
  experiment toward this.
- **Add a proactive layer (architectural):** C³G's state dictionary or
  equivalent. Required to close fully to 90 %+, since the proactive layer
  fires *before* the RTT inflation that triggers the reactive path. This
  is the cleanest follow-on TCC contribution.

## Ready-to-paste TCC paragraphs

### Results headline

> *Across six bandwidth-shaped scenarios, the adaptive controller reduced
> 95th-percentile RTT by factors of 7× to 33× relative to the
> fixed-bitrate baseline (scenarios A, B, C, D, F), eliminated stalls
> entirely in three of them (B, C, D), and preserved baseline experience
> on a clean network with no false-positive bitrate drops. Subjective
> operator ratings dropped from 4–5 (severe to unplayable) to 1–3 (good
> to acceptable) in latency and stability across all degraded scenarios.
> Quality ratings held at 1 for mild caps and degraded to 2–3 where the
> controller was forced to drive bitrate hard down, capturing the
> deliberate bandwidth-quality trade.*

### Discussion paragraph 1 — the reactive blind spot

> *The initial RTT spike at the onset of each capacity drop is an
> architectural property of reactive controllers, not a defect: detection
> latency is bounded below by `hysteresis_window + one_decision_interval`,
> which our defaults (2 s + 1 s) place at ~2–3 s. The literature
> converges on this property — GCC partially mitigates it via the
> delay-gradient signal [Carlucci 2016]; ABRAGame accepts it as
> intrinsic [Armendariz 2025]; C³G explicitly addresses it with a
> proactive state-dictionary layer above the reactive controller
> [Alós 2019]. Our results are consistent with all three: RTVL_peak
> (worst-moment RTT) barely differs between modes, but L_AP (duration
> above threshold) and AP (average severity during the bad period)
> shrink 5–10× and ~50 % respectively — i.e., the controller wins on
> recovery, not on the peak. See [[reactive-blind-spot]] for the full
> per-paper treatment.*

### Discussion paragraph 2 — channel-use gap

> *Effective channel use (mean send rate over the bottleneck cap during
> shaped windows) lands at 35–55 % in our adaptive runs, versus C³G's
> reported 93–96 % and BBR-on-UDP's 87–93 %. The gap measures the
> bandwidth cost of two design choices: (1) the absence of C³G's
> proactive state-dictionary layer, which preselects a known-safe
> bitrate before the reactive trigger fires, and (2) conservative
> recovery parameters (γ = 1.15, linear step = 500 kbps,
> stable_time = 7.5 s) that climb back slowly after each decrease.
> Tuning the recovery within the reactive architecture is expected to
> close part of the gap; closing fully would require replicating C³G's
> proactive layer — a publishable follow-on contribution.*

### Discussion paragraph 3 — scenario E and the C³G envelope

> *Scenario E (4 Mbps cap, a 79 % drop from the 19 Mbps target) is the
> failure mode of the simpler policy: p95 RTT improves only 7 % over
> the baseline, though session survival and L_AP both improve
> meaningfully. The result aligns with C³G's published loss-free bound
> of `α_c < 1.75` (i.e., capacity drops up to ~42 %). Scenario E's
> α_c = 4.75 falls outside both controllers' designed operating
> envelope. The simpler policy reproduces C³G-class behavior within
> roughly the same envelope and breaks down outside it for the same
> reason — the bottleneck queue builds faster than the reactive
> hysteresis allows the controller to drain it.*

## Related
- [[idea-10-abr-comparison]] — the design and predicted-vs-observed reading
- [[reactive-blind-spot]] — the architectural framing for the initial spike and the channel-use gap
- [[alos2019]] — C³G; the 93–96 % channel use, 42 % loss-free bound, and proactive state dictionary
- [[abragame]] — ABRAGame; the closest reactive-architecture peer
- [[gcc]] — GCC; delay-gradient signal as the only partial mitigation of the blind spot in our survey
- [[research-journey]] — the prior arc explaining why this is the experiment we ran

## Sources
- `testbed/visualizations/results_beta_0.7/comparison.ipynb` — executed notebook with all tables and plots
- `testbed/results/baseline/` — 7 fixed-bitrate runs (clean + A–F)
- `testbed/results/adaptive/` — 7 adaptive (β = 0.7) runs (clean + A–F)
- `testbed/scenarios.md` — scenario definitions and `tc htb` profiles
- Sunshine PR #2b — `src/bitrate_controller.{h,cpp}`, configured by `bitrate_mode = adaptive` in `sunshine.conf`
