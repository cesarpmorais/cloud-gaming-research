# Idea 5b (t-origin Fix) — Implementation and Results

## What is it?

A one-line code change on top of [[results-idea-5]] (Idea 5, the CUBIC
port). Idea 5b moves the cubic recovery curve's `t = 0` origin from
`last_decrease_at` to `rtt_clear_since`, so the curve only starts
counting time once RTT has actually returned below the margin
threshold — not from the moment of the cut, when the bottleneck queue
may still be draining for tens of seconds.

The motivation came from the Idea 5 K=5 s run on Scenario A: the
~27 s queue-drain delay between the cut and the moment RTT cleared
left `t − K ≈ 22 s`, deep inside the cubic's convex (accelerating)
region. The first growth tick after the clear streak fired with a
large step and triggered a second cascade. Anchoring `t` at
`rtt_clear_since` was supposed to fix this by ensuring growth always
begins in the concave region around `B(0) = β · last_known_good`.

This document captures the result of testing the fix on three runs
(A K=15 s, A K=5 s, E K=15 s) at git commit state of 2026-06-08.
**The fix did not deliver what was predicted. On Scenario E it is a
clear regression on the metric we cared about most (peak RTT), and
on Scenario A it is at best neutral.** The conclusion is that the
t-origin fix has a second-order side effect — `rtt_clear_since` is
reset on every successful growth tick — that neutralises the cubic
curve into a permanent slow drip and dramatically increases the
number of recovery → re-saturation → cut cycles during sustained
constriction.

## Why it matters for Sunshine / TCC

Three reasons this matters for the TCC narrative even though the fix
fails empirically.

1. It is a **clean negative result with a structural explanation** —
   the kind of finding that turns into a discussion section
   paragraph rather than being silently discarded. The "right
   direction" intuition (don't sample the convex region while the
   queue is still draining) is preserved by the data; the failure is
   in the implementation detail of *what counts as time spent
   recovering*.
2. It exposes a previously-unnoticed property of [[results-idea-5]]:
   the pre-fix design happened to **suppress recovery during
   sustained constriction** because `last_decrease_at` is set once
   and never reset by growth ticks, while `rtt_clear_since` is reset
   constantly. That "bug" was carrying part of the Scenario E peak
   RTT win — a humbling finding that reframes the Idea 5 result.
3. It defines the next concrete edit (Idea 5c, below) precisely,
   without requiring further exploration.

## Key Concepts

- **The fix itself** — in `bitrate_controller.cpp` (line ~117), the
  `t` argument to the cubic is computed from `rtt_clear_since`
  instead of `last_decrease_at`. The expanded comment in the code
  documents the original reasoning.
- **The side effect that broke it** — the increase branch resets
  `rtt_clear_since = now` after every successful growth actuation
  (see line ~129 of the same function, which was already present
  before Idea 5b and was used to gate the next decision interval).
  Combined with the new t-origin choice, this means every growth
  tick re-anchors `t = 0` and the next sample of the cubic returns
  `B(0) = β · last_known_good`. The curve never reaches its convex
  region inside a single recovery streak, growth is forced into
  permanent concave-region steps, and they fire **once per
  decision cycle** as long as RTT stays clear.
- **Cascading recovery** — on a long-constriction scenario like E,
  this manifests as a ping-pong: grow one step, re-saturate, cut
  (fast convergence further shrinks `last_known_good`), wait for
  RTT to clear, repeat. The 9 / 9 decrease / increase counts on
  E K=15 s vs Idea 5's mostly-suppressed-during-constraint pattern
  is the visible signature.

## Results

All three runs were captured at 2026-06-08 in
`testbed/results/test-last-15k/` and `testbed/results/test-last-5k/`
with `bitrate_mode = adaptive`, `abr_beta = 0.70`,
`abr_fast_convergence = true`, x11 capture, full 240 s scenarios.
Gameplay was rated 1/1/1 (latency/quality/stability) on all three
runs — subjectively the worst experience of any Idea 5 / 5b campaign.

| Run | Pre-fix peak RTT | Post-fix peak RTT | Pre-fix channel use | Post-fix channel use |
|---|---|---|---|---|
| A, K = 15 s | ~1221 ms | **1313 ms** (+8 %) | — | 32.9 % |
| A, K = 5 s  | ~796 ms (2nd spike) | **1105 ms** (+39 %) | — | 28.7 % |
| E, K = 15 s | 2305 ms | **3192 ms** (+39 %) | 14.9 % | **38.0 %** (+155 %) |

Decision-event counts on the post-fix runs:

- A K=15 s: 9 decreases / 4 increases
- A K=5 s: 9 decreases / 13 increases
- E K=15 s: 9 decreases / 9 increases

The increase counts are the diagnostic signal — Idea 5 in its
original form had recovery largely suppressed during the shaping
windows, especially on E. After the t-origin fix, growth fires
every clear streak, and on the constrained scenarios that growth
is what is producing the additional cascades.

### Honest reading

- **A K=15 s.** Roughly neutral. Slight peak-RTT regression but in
  noise range; this is what we'd called the "regression check" and
  it passed in the weak sense (we didn't break it badly).
- **A K=5 s.** The fix's headline target. **It did not deliver.**
  Peak RTT went the wrong direction. The convex-region overshoot we
  thought we were eliminating has been replaced by a slow drip of
  many small over-probes that collectively still saturate the link.
- **E K=15 s.** The most damaging result. Peak RTT regressed 39 %
  and we lost the 40 % win that was the publishable headline of
  Idea 5. Channel use more than doubled, but at the cost of the
  metric we said we were prioritising (and that C³G itself
  prioritises in Alós §6).

## Diagnosis

The fix's *direction* — don't sample the convex region during queue
drain — is right and is preserved by the data. The fix's
*implementation* fails because of the interaction with the
already-present reset of `rtt_clear_since` on each growth tick.

The pre-fix design was buggy in a way that **accidentally suppressed
recovery during sustained constriction**, which was carrying part of
the Scenario E peak-RTT win. The post-fix design is buggy in the
opposite way: it permits recovery too eagerly and never lets the
cubic reach the part of its curve that gives meaningful catch-up.

Neither is the design the CUBIC paper actually describes. The paper's
`t` is wall-clock time since the last decrease, and the curve is
sampled once per ACK without resetting `t` on growth events.

## Next steps — Idea 5c

Three options on the table, in order of preference:

1. **Don't reset `rtt_clear_since` on growth.** Anchor `t` at
   `rtt_clear_since`, but only reset that anchor on a *decrease*
   (or when the clear streak is broken by a sample above the
   margin threshold). `t` then accumulates across growth ticks and
   the curve genuinely enters the concave plateau and then the
   convex catch-up region after K seconds of total clear time.
   This is closest to what CUBIC actually does.
2. **Hybrid:** anchor at `rtt_clear_since` (so queue-drain delay is
   excluded) but track time accumulated, not absolute timestamps.
   Same end result as option 1, slightly different code shape.
3. **Revert 5b.** Accept the K=5 s overshoot on A as the lesser of
   two evils and restore the E peak-RTT win. Useful as a fallback
   if option 1 also disappoints.

Recommended starting point: **option 1.** It is the smallest
deviation from CUBIC-as-published, the diagnosis points directly at
it, and it leaves `last_decrease_at` and `rtt_clear_since` with
unambiguous roles (decrease event vs queue-drain detector).

## Reframing of [[results-idea-5]]

The Idea 5 result still stands — the 40 % peak-RTT reduction on E
is real, was measured cleanly, and reproduces. But the mechanism is
not *"fast convergence alone"*; it is *"fast convergence plus a
recovery branch that mostly does not fire during sustained
constriction because `last_decrease_at` never moves while
`rtt_clear_since` thrashes."* The next iteration needs to deliver
the same peak-RTT behaviour with a recovery branch that fires
*intentionally*, not by accident.

## Related

- [[results-idea-5]] — the parent CUBIC port and the result this
  fix was supposed to extend
- [[cubic]] — the paper that describes `t` as time since last
  decrease (not since last clear streak start)
- [[improvement-roadmap]] — overall plan
- [[idea-1-postmortem]] — the previous failed-idea writeup;
  template for how to honestly document a negative result
- [[reactive-blind-spot]] — adjacent structural property
- [[alos2019]] — C³G; §6 explicitly prioritises low latency over
  fast bitrate increase, which is the trade-off Idea 5b inverts

## Sources

- `Sunshine/src/bitrate_controller.cpp` (lines ~115–132 — increase
  branch with the t-origin fix in place)
- `testbed/results/test-last-15k/A_run0_20260608-194818.csv`
  (Scenario A, K = 15 s, post-fix)
- `testbed/results/test-last-15k/E_run0_20260608-195406.csv`
  (Scenario E, K = 15 s, post-fix)
- `testbed/results/test-last-5k/A_run0_20260608-200148.csv`
  (Scenario A, K = 5 s, post-fix)
- Notes files in the same directories (subjective gameplay ratings
  of 1/1/1 on all three runs)
