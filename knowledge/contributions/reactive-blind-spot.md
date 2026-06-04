# Reactive Blind Spot

## What is it?

A reactive bitrate controller — one that adjusts the encoder rate only *after*
observing congestion in the network — has an unavoidable detection delay. From
the moment a capacity drop occurs to the moment the controller actuates, the
queue at the bottleneck is already filling and RTT is already inflating. That
window between *capacity change* and *controller response* is what we call the
**reactive blind spot**.

The blind spot is bounded *from below* by

```
detection_delay ≥ hysteresis_window + one_decision_interval
```

For our PR #2b controller (`abr_hysteresis_ms = 2000`,
`decision_interval_ms = 1000`) that floor is **≈ 2–3 seconds**. In practice
it is what produces the initial RTT spike at the onset of every capacity drop
in our [[results-beta-0.7]] runs.

Crucially, **no choice of threshold, smoothing, or sampling rate can shrink
this floor to zero** as long as the controller is purely reactive — the
controller needs *some* evidence that congestion is occurring, and producing
that evidence takes time.

## Why it matters for Sunshine / TCC

The initial RTT spike in our scenario A/E/F runs is not a controller bug.
It is the architectural cost of the simpler-policy choice. Framing it that way
in the TCC turns an apparent weakness ("the controller can't stop the first
spike") into a measured property of the design ("the simpler reactive policy
has a 2–3 s detection floor; the channel-use gap of 35–55 % vs C³G's 93–96 %
measures the value of a proactive layer above that floor").

It also defines the *future-work boundary*: the cleanest extension of this
TCC is to add a proactive layer (state dictionary, learned model, RTT-based
preselection) and show how it tightens the blind spot. That is C³G's
contribution above pure reactivity; replicating it on open-source Sunshine
is a publishable follow-on.

## Key Concepts

- **Reactive control** — the controller only acts on observed network state.
  No anticipation. Examples in our literature: GCC, ABRAGame, C³G's reactive
  drain layer, BBR-on-UDP, and our PR #2b.
- **Proactive control** — the controller pre-selects a target based on
  *predicted* network state, before any RTT inflation is measured. Examples:
  C³G's state dictionary, ML-based controllers like DeepGame and EdgeGame.
- **Detection delay** — time between an external network change and the
  controller's first actuation. For reactive controllers, lower-bounded by
  `hysteresis + decision interval`.
- **Channel-use gap** — the headline quantitative consequence of the blind
  spot. Our [[results-beta-0.7]] shows 35–55 % vs C³G's 93–96 %; the
  difference is roughly what their proactive layer buys them.

## What each surveyed paper says about the blind spot

### GCC (Carlucci 2016) — mitigated by gradient
GCC is reactive, but the **input signal is the delay gradient `m(t)`** rather
than absolute delay. A gradient fires earlier than a threshold: it detects
*"delay is rising fast"* before delay crosses any fixed line. This shortens
the blind spot but does not eliminate it — GCC still needs enough samples to
estimate the gradient and traverse the over-use detector FSM. The paper
acknowledges this as an inherent detector latency. See [[gcc]].

### ABRAGame (Armendariz 2025) — same architecture as ours
Cumulative one-way latency above threshold → react. They explicitly report
"recovery time ~4.5 s" — essentially the blind-spot floor plus the
controller's settling time. They do not propose mitigation; it is treated as
a known limitation. See [[abragame]].

### C³G / Alós (2019) — the only paper in our survey that mitigates it
C³G's controller is two-layered:

- **Reactive drain** (`λ_drain = μ̄ − qdData/Δt`) — same fundamental
  blind-spot floor as ours.
- **Proactive state dictionary** — a learned table of (RTT regime, safe
  bitrate) pairs. On entering a known-bad RTT regime, the controller
  *preemptively* selects a known-safe bitrate, **before the reactive trigger
  would fire**.

C³G frames the proactive layer explicitly as *"reducing the reactive
blind spot"* and attributes the bulk of their 93–96 % channel use and the
42 % loss-free capacity-drop bound to this layer. **Remove the proactive
layer and C³G would have approximately the same initial-spike behavior we
observe.** See [[alos2019]].

### BBR-on-UDP (C³G's baseline) — purely reactive, no memory
C³G's paper measures BBR's initial spikes as the comparison point that
motivates their proactive layer. Visually identical pattern to ours.

### ML-based approaches (out of scope) — anticipate via learned models
- **DeepGame** (Mossad 2021): per-frame attention prediction.
- **EdgeGame** (Zhang 2019): edge-side deep learning, claims 50 % network
  delay reduction.
- **Themis** (Li 2019): RL for server-side resource partitioning, not ABR
  (see correction in [[baldovino2022]]).

These can anticipate but trade simplicity, portability, and explainability
for it. Deliberately scoped out of this TCC.

## How to write this into the TCC results section

Draft paragraph for the discussion:

> *Reactive controllers necessarily have a detection delay bounded below by
> the hysteresis window plus one decision interval. Our default settings
> (2 s hysteresis, 1 Hz gate) place that floor at ~2–3 s — visible as the
> unavoidable RTT spike at the onset of each capacity drop in scenarios A,
> B, E, and F. The literature converges on this property: GCC partially
> mitigates it via the delay-gradient signal; ABRAGame accepts it as
> intrinsic; C³G explicitly addresses it with a proactive state-dictionary
> layer above the reactive controller. Our channel-use gap (35–55 % vs
> C³G's 93–96 %) is the quantitative cost of omitting that proactive
> layer — a deliberate scope choice that defines the cleanest follow-on
> contribution.*

## Related
- [[gcc]] — delay-gradient signal as partial mitigation
- [[abragame]] — same purely-reactive architecture, same blind spot
- [[alos2019]] — proactive state dictionary, the only mitigation in the survey
- [[baldovino2022]] — survey hub; lists ML approaches as the other mitigation path
- [[related-work]] — synthesis across the surveyed papers
- [[idea-10-abr-comparison]] — our controller; the simpler-policy comparison point
- [[research-journey]] — how the TCC's framing arrived at this tradeoff

## Sources
- Carlucci, G. et al. *Analysis and design of the Google Congestion Control
  for Web real-time communication (WebRTC)*. MMSys '16.
- Armendariz, A. & Joskowicz, L. *ABRAGame: Adaptive Bit Rate Algorithm for
  cloud gaming*. 2025.
- Alós, J. et al. *Congestion Control for Cloud Gaming Over UDP Based on
  Round-Trip Video Latency*. IEEE Access, 2019.
- Our PR #2b runs at β = 0.7 (see `testbed/visualizations/results_beta_0.7/comparison.ipynb`).
