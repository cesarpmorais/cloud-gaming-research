# Improvement Roadmap — Closing the Gap to C³G

## What is it?

A catalogue of independent algorithmic changes we can apply on top of the
PR #2b AIMD controller to narrow the measured gap against C³G
([[alos2019]]). Each entry is self-contained: it can be implemented,
landed, and measured on its own. They are intentionally *not* sequenced
as a single roadmap — pick any subset, in any order.

This document is the planning input for the next experimental round
following [[results-beta-0.7]] and the β-sweep diagnosis (β=0.5 =
over-drain, β=0.7 ≈ candidate sweet spot, β=0.85 = under-drain).

## Why it matters for Sunshine / TCC

After the β sweep, the central observation is that our reactive AIMD
controller sits at ~27 % effective channel use on Scenario A vs C³G's
93–96 %, with an AP (time above 100 ms) of ~17 s vs C³G's < 1 s. Closing
this gap on open-source Sunshine *without* requiring client modifications
is the publishable contribution. The ideas below are the levers we have.

Effort is scored 0–10 (10 = full week of work). Result expectancy is a
qualitative read of how strongly the change should move the C³G
comparison metrics (channel use, AP, RTVL_peak, decrease count).

---

# Tier 1 — same Pareto cell as today (simpler than C³G), tighter

## Idea 1 — Computed-drain step (replace fixed β)  ❌ Discarded

**Outcome:** implemented in both live-EMA and pre-congestion-snapshot
variants and measured on Scenario A. Both under-performed plain
β = 0.7 on channel use and L_AP. The structural reason — server-side
encoder output rate is not a reliable proxy for channel capacity — is
captured in [[idea-1-postmortem]]. The implementation is preserved as
`stash@{0}` in `Sunshine/`. The text below is kept as the *original
proposal* for the historical record.



### Idea
On a decrease, instead of `new_target = β · current_target`, set
`new_target = α · observed_effective_rate` where
`observed_effective_rate` is an EMA of `bitrate_kbps` (the actual
encoded output that made it onto the wire) over the last ~500 ms and
`α ≈ 0.95`. The cut lands *just below* what the channel is currently
absorbing, not at an arbitrary fraction of what we *asked* the encoder
to do.

### Inspiration
C³G's reactive drain equation
`λ_drain = μ̄ − qdData/Δt` (Alós Eq. 2). We cannot measure `μ̄` directly
because Moonlight does not report receive rate, but `bitrate_kbps` —
already in our CSV — is a close server-side proxy: it is what the
encoder actually produced after rate-control responded to the
configured target.

### How it works today and why this should help
The current decrease is purely target-driven:
`current_kbps = max(min_kbps, current_kbps * beta)`. It ignores the
fact that the encoder may already be sending well *below* the target
because of back-pressure. The β sweep made this concrete:

- **β=0.85 (under-drain).** The first cut takes the target from 19000
  to 16150 kbps. But the channel cap is 8000 kbps. The cut is a no-op
  for the bottleneck. 12 cuts are then needed to converge — the
  signature of cutting from the *wrong number*.
- **β=0.5 (over-drain).** The first cut takes the target from 19000 to
  9500 kbps, then a second one to ~4700, then further. Settles at
  1186 kbps target / 672 kbps actual on an 8 Mbps link — 8 % channel use.
  The cut overshoots downward because each step is relative to the old
  inflated target, not the achievable rate.

If the cut were instead computed from observed effective rate, both
failure modes collapse: starting from observed ~4 Mbps with α=0.95
gives a single decrease to ~3.8 Mbps that lands just under the
bottleneck immediately, regardless of what the target said.

### Effort
**4 / 10.** Plumb `bitrate_kbps` (or an EMA of it) into
`bitrate_controller_t::on_sample`. Add an EMA accumulator to
`sample_t`. Replace the decrease line in `bitrate_controller.cpp`. The
`β` parameter becomes vestigial (could be kept as a floor:
`max(α · observed, β · current_target)` so a noise burst doesn't
crash the rate to zero).

### Result expectancy
**High.** Directly targets the two diagnosed failure modes. Realistic
target on Scenario A: channel use 70–85 %, single decrease per drop,
L_AP collapsing toward the blind-spot floor (~2–3 s).

---

## Idea 2 — Predictive trigger (lookahead on RTT slope)

### Idea
Replace the K=2 sustained-over-threshold trigger with a one-step linear
extrapolation: maintain a small ring buffer of the last N RTT samples,
compute the slope, and fire a decrease if
`rtt_now + slope · decision_interval > RTT_THRESHOLD`. Keep the
hysteresis as a *floor* (still need some sustained signal) but allow
the lookahead to fire earlier when the slope is steep.

### Inspiration
C³G's two-prediction step (their `RTVL₁` linear extrapolation +
`RTVL₂` `qdData`-growth projection — Alós §IV.A). They explicitly
"react if either prediction exceeds 100 ms next step." This is the
mechanism that makes their AP < 1 s while reacting on signals comparable
to ours in cadence.

### How it works today and why this should help
The current trigger is `rtt_over_since` set when RTT first crosses
100 ms; fire if it has been continuously crossed for `hysteresis_ms` =
2000 ms. By construction this cannot fire in less than 2 seconds. The
β=0.7 run on Scenario A peaked at 1786 ms RTT — the controller saw
RTT climb from 50 ms to 1700 ms within the 2-second hysteresis window
and could not act until it was already deep into the spike.

Linear extrapolation of slope catches this early: if the last 500 ms of
samples show RTT rising at 1500 ms/s, we know in ~300 ms that we'll
cross 100 ms in the next decision interval, even though RTT is still
below threshold at sample time.

### Effort
**3 / 10.** Add a 5–10 sample ring buffer to the controller; least-
squares slope on each `on_sample`; add the predicted-trigger branch.
Tunable: window length, slope sensitivity floor (don't fire on
1 ms/s ambient noise).

### Result expectancy
**Medium.** Should trim 1–2 s off AP and meaningfully reduce
RTVL_peak. Will not move channel use much (that is Idea 1's job).
Pairs well with Idea 1 — early trigger + correctly-sized cut is the
combined C³G analogue. Risk: false positives on jittery RTT (mitigated
by keeping the hysteresis floor as a second condition).

---

## Idea 3 — Sub-second trigger via `frame_send_ms`

### Idea
Add a secondary trigger driven by per-frame send latency: maintain a
short EMA of `frame_send_ms` and fire if it exceeds a separate
threshold (e.g. 30 ms over baseline) for a short sustained window
(~300 ms). Independent of the RTT trigger; either path can declare
congestion.

### Inspiration
ABRAGame's 20 ms sampling cadence ([[abragame]]) and the general
observation that *send-side* queue inflation precedes *round-trip*
inflation by exactly the propagation delay of the path. `frame_send_ms`
is already computed server-side and already in the CSV — the per-frame
analogue C³G needed client ACKs to obtain.

### How it works today and why this should help
`frame_send_ms` is collected by `frame_network_latency_logger` but
never consumed by the controller. It updates per frame (~30 Hz),
roughly 30× faster than ENet's `peer->roundTripTime` (~1 Hz). When the
bottleneck queue starts filling, the first symptom is that
`frame_send_ms` rises — the server's UDP send call blocks/queues. That
happens *before* the ACK on a later frame comes back late, which is when
ENet RTT moves.

Estimated win: ~500–800 ms shaved off the detection delay, dropping the
[[reactive-blind-spot]] floor from ~2–3 s closer to ~1.5–2 s. Combined
with Idea 2, the AP target becomes "blind-spot floor + a few hundred
ms," which is in C³G territory.

### Effort
**5 / 10.** Wire `frame_send_ms` through `record_rtt`-adjacent code in
`src/stream.cpp` into `bitrate_controller_t::on_sample`. Add EMA state
and a second hysteresis path. The harder part is calibrating the
threshold — `frame_send_ms` is much noisier than ENet RTT and a wrong
threshold means spurious decreases on the clean scenario.

### Result expectancy
**Medium-high *if calibrated well*, Low-medium if not.** The signal is
real and the literature supports it (it's the ABRAGame cadence), but
the noise floor of `frame_send_ms` on a healthy link is unknown to us
empirically. The clean-scenario data from PR #1 baseline must be the
calibration source.

---

# Tier 2 — structural changes to the increase curve and memory

## Idea 4 — Per-session memory of safe targets

### Idea
Maintain a small in-memory table of `(rtt_regime, safe_target_kbps)`
pairs that the controller has observed during the current session.
"Regime" can be a coarse RTT bucket (e.g. {<50 ms, 50–100 ms, 100–
200 ms, >200 ms}). On entering a regime, set an upper cap on
`current_kbps` equal to the lowest target previously found safe in
that regime. Within the cap, the AIMD logic is unchanged.

### Inspiration
C³G's network state dictionary `S = {s(λ̄)}` with rating
`R(λ̄) = [a·RTVL_avg + b·σ(RTVL) + c·max(RTVL) + d·qdData] / λ̄`
(Alós Eq. 3). This is C³G's mechanism for shrinking the reactive blind
spot ([[reactive-blind-spot]]) — recognise a regime, jump straight to a
known-safe target instead of probing into trouble. Our version is the
"three buckets and a max-cap" sketch of theirs.

### How it works today and why this should help
The controller has exactly one piece of memory: `last_known_good`,
which is the target *just before the most recent decrease* — i.e. the
ceiling that the network just rejected. Nothing remembers a target
that ever *worked*. On Scenario D (10 Mbps cap that toggles every
30 s) and Scenario C (slow decline + fast recovery), the network
returns to the same constrained state repeatedly. Each re-entry today
triggers the full reactive cascade again from scratch.

With a regime table, the second visit to a constrained regime caps
immediately at the previously-found safe rate. The decrease cascade
fires once per regime, not once per visit.

### Effort
**7 / 10.** Needs a regime classifier, the table structure, update
logic on both decreases and stable-window increases, and a sanity check
on table staleness (the link can change). Also needs new CSV columns
to make the table observable during analysis. Most of the effort is
test cases and calibration of bucket boundaries.

### Result expectancy
**Medium.** Strong impact on D (repeated toggles), moderate on B/C
(single recovery), negligible on A and clean (no repeat visits). The
TCC story it enables: *"a one-page proactive layer reproduces most of
C³G's repeated-state advantage."* That's a publishable bullet.

---

## Idea 5 — CUBIC-shaped increase curve + fast convergence

### Idea
Replace the controller's two-phase increase (Phase 1 multiplicative
`×γ` until `0.9 · last_known_good`, then Phase 2 linear `+STEP`) with
a single **time-based cubic function** of wall-clock seconds since
the last decrease:

```
B(t) = C · (t − K)³ + last_known_good
K    = ∛(last_known_good · β / C)
```

where `t` is elapsed time in seconds since the last decrease, `β` is
the multiplicative decrease factor (already in `params_t`), and `C` is
a new shape constant. Calibration runs the other direction from TCP:
pick a *desired recovery time* `K_desired` (e.g. 10 s) and let
`C = last_known_good · β / K_desired³` fall out.

Add a companion rule — **fast convergence**: if a new decrease fires
while `current_kbps < last_known_good` (i.e. before the curve had
recovered to the ceiling), update memory with
`last_known_good ← current_kbps · (2 − β) / 2` instead of the usual
`last_known_good ← current_kbps`. The ceiling shrinks on repeated
congestion, the curve replans accordingly, and the controller stops
chasing a saturation point the link can no longer carry.

### Inspiration
**Ha, Rhee, Xu, "CUBIC: A New TCP-Friendly High-Speed TCP Variant",
ACM SIGOPS Operating Systems Review, 2008** — the default Linux TCP
congestion control since kernel 2.6.18 (2006). See [[cubic]] for the
full paper analysis. The professor pointed at this paper noting
*"TCP CUBIC reacts faster"* — specifically, faster on the *recovery*
side via the concave portion of the cubic curve. Fast convergence
(their Eq. 3.7) is CUBIC's mechanism for the same problem the
deprecated `last_known_good`-decay sketch tried to address, but
event-driven instead of time-decay.

### How it works today and why this should help
The current two-phase logic is a discrete, tick-based approximation
of what the cubic curve does continuously and analytically:

| Today | CUBIC analogue | Problem with today |
|---|---|---|
| Phase 1 `×γ` per tick until `0.9 · last_known_good` | Concave region of `B(t)` | Tick-based; rate depends on `decision_interval_ms` |
| Phase 2 `+STEP` linear past `0.9 · last_known_good` | Plateau (`t ≈ K`) + convex region (`t > K`) | Never accelerates; flat forever past the ceiling |
| Discrete jump at `0.9 · last_known_good` | Smooth transition built into the cubic shape | Sharp regime change → small instabilities |
| `last_known_good` static until next decrease | Fast convergence (Eq. 3.7) shrinks it on second decrease | Old ceiling can keep dragging the curve toward a number the link no longer carries |

Both the β=0.85 under-drain pattern (gentle cut → fast Phase 1 ramp
re-overshoots → second cut) and the Scenario E ping-pong from
[[results-beta-0.7]] (long-sustained constraint where the curve keeps
probing toward the pre-drop ceiling) collapse cleanly under the
cubic + fast-convergence pair. Concrete predictions:

- Near `last_known_good`, the cubic *plateau* slows growth right where
  Phase 1's `×γ` is currently most dangerous. Fewer re-overshoots,
  fewer follow-up decreases.
- Past `last_known_good`, growth is **convex** (not linear): cautious
  at first, then accelerating. Better channel use on long stable
  windows than the current `+STEP` ever achieves.
- A second decrease before recovery shrinks the ceiling by ~10 % (with
  β = 0.2; the factor is `(2−β)/2`). After 2–3 cuts on a chronically
  degraded link, `last_known_good` settles near the actual current
  capacity instead of remaining at the pre-drop value forever.

### Effort
**5 / 10.** The math is three lines (`B(t)`, `K`, fast-convergence
update). The supporting work: track `last_decrease_time` (a single
`std::chrono::time_point`); add `params_t::C` and a calibration helper
(`compute_C_from_recovery_time`); replace the if/else increase branch
with the cubic evaluation; add the fast-convergence branch on the
decrease path. Removes the now-vestigial `gamma` and `step_kbps`
parameters from the config (or leaves them with deprecation comments).
Unit tests for the curve shape and the fast-convergence trigger.

We deliberately do **not** port CUBIC's TCP-friendly mode (Eq. 4 /
`cubic_tcp_friendliness()`) — see [[cubic]] §7.4 for why it does not
apply to single-stream UDP cloud gaming. That is the largest piece of
CUBIC we skip, and skipping it cuts ~half the algorithm out of scope.

### Result expectancy
**Medium-high on Scenario E**, **medium elsewhere**.

The strongest gain is on the Scenario E failure mode (long sustained
constraint, where the current controller never settled). Fast
convergence directly addresses it.

On Scenarios A–D the gain is structural rather than dramatic: the
controller behaves more predictably, the under-drain at β=0.85 is
less likely to spawn cascading cuts, and the channel use during the
stable portion of each scenario should rise modestly because the
convex region eventually accelerates past `last_known_good` instead of
adding 500 kbps per second forever.

The biggest *qualitative* win is for the TCC writing: we move from
"we picked γ=1.15 and STEP=500 by hand" to "the increase curve is
CUBIC-shaped, the canonical peer-reviewed high-speed AIMD recovery
function (Ha et al., 2008)." That framing is worth a section of the
report on its own.

---

## Picking the first move

**Updated after the Idea 1 postmortem.** Idea 1 was tried and
discarded ([[idea-1-postmortem]]); the structural finding is that
server-side encoder output is not a usable proxy for channel
capacity, and there is no other server-only signal that closes the
gap without modifying Moonlight. The decrease side therefore stays
as plain β = 0.7 for the foreseeable future.

**The new recommended starting point is Idea 5 (CUBIC port).** It
addresses the orthogonal axis — the *increase* curve and the
`last_known_good` memory — neither of which depends on a
channel-capacity estimate. The cubic-time recovery curve should
improve channel use during the stable plateau and recovery speed
after the constraint lifts. Fast convergence (Eq. 3.7 of [[cubic]])
addresses the Scenario E ping-pong failure mode from
[[results-beta-0.7]] directly.

Idea 2 (lookahead) is the next reactive candidate after Idea 5 —
it could reduce L_AP by firing the decrease earlier in the streak.
Risk of false positives needs calibration against the clean scenario.

Idea 4 (per-session memory) is held until after Ideas 5 + 2 land,
because fast convergence may already absorb much of what Idea 4 was
meant to provide.

## Related
- [[reactive-blind-spot]] — the architectural floor each Tier-1 idea attacks
- [[results-beta-0.7]] — the gap these ideas are trying to close
- [[alos2019]] — C³G; primary inspiration for Ideas 1, 2, 4
- [[abragame]] — sampling cadence inspiration for Idea 3
- [[gcc]] — over-use-detector parallel for Idea 2's predictive trigger
- [[cubic]] — peer-reviewed source for Idea 5 (cubic increase curve + fast convergence)
- [[bitrate-control]] — current Sunshine bitrate flow
- [[idea-10-abr-comparison]] — TCC research question this work serves

## Sources
- Alós et al., *Congestion Control for Cloud Gaming Over UDP Based on
  Round-Trip Video Latency*, IEEE Access 2019 — Eqs. 1–3 and §IV.
- Armendariz & Joskowicz, *ABRAGame*, 2025 — 20 ms sampling cadence
  reference.
- Ha, Rhee, Xu, *CUBIC: A New TCP-Friendly High-Speed TCP Variant*,
  ACM SIGOPS OSR 2008 — Eqs. 1, 2, 3.7 for Idea 5; see [[cubic]] for
  the full analysis.
- `Sunshine/src/bitrate_controller.{h,cpp}` — current implementation
  the ideas modify.
- `testbed/visualizations/results_beta_sweep/comparison.ipynb` — the
  data that motivated the ideas.
