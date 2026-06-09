# Idea 5c (Accumulating-`t` Fix) — Implementation and Results

## What is it?

A one-line code change on top of [[results-idea-5b]]. Idea 5c removes
the reset of `rtt_clear_since = now` from the increase branch, so that
when the cubic curve fires a successful growth tick the anchor is not
re-set. The wall-clock `t` fed to `B(t)` therefore accumulates
monotonically across all growth ticks within a single clean-RTT
streak — matching the CUBIC paper's invariant ([[cubic]] §3.1, where
`t` is sampled continuously without resetting on any growth event).

The motivation came from the [[results-idea-5b]] diagnosis: 5b's
`rtt_clear_since` anchor was being reset on every successful growth
tick, which meant the cubic was always sampled at the concave
plateau `B(0) = β · last_known_good` and growth degenerated into a
permanent slow drip firing every decision tick. 5c was meant to make
the curve actually reach its plateau, then its convex region, over a
real K-second recovery epoch — the way CUBIC actually behaves.

This document captures the results of testing 5c on three runs
(A K = 15 s, A K = 5 s, E K = 15 s) at git commit state of
2026-06-08. **The fix did not deliver the expected behaviour either.
The cubic now fires aggressively (52 / 68 / 34 growth ticks in
240 s windows vs 5b's 4 / 9 / 13), and the constrained scenarios
cannot absorb that growth: peak RTT on E stays 31 % worse than
Idea 5 original, and on A K = 5 s the encoder was driven to
18 988 kbps inside an 8 Mbps shaping window.** This closes the
cycle of CUBIC implementation cleanups: every attempt to make the
recovery branch fire "intentionally" makes the empirical result
worse than the original Idea 5 implementation, whose win turns out
to have been carried by an accidental recovery suppression.

## Why it matters for Sunshine / TCC

This is the third and decisive iteration of the CUBIC port and it
makes the structural finding unambiguous. The Idea 5 result
([[results-idea-5]]) was real — 40 % peak-RTT reduction on
Scenario E — but the *mechanism* was not the one the paper
prescribes. It was a side effect of how `last_decrease_at` and
`rtt_clear_since` interact in the original implementation:

- `last_decrease_at` is set once on a decrease and never moves until
  the next decrease. By the time RTT clears after the
  queue-drain delay (~27 s on Scenario A), `t − K` is already
  large and the cubic's `B(t)` returns a value at or above
  `last_known_good`. Clamping at `current_kbps` then makes the
  controller a no-op during sustained constraint — recovery does
  not fire, the bitrate stays at the floor.
- The two "honest" fixes (5b and 5c) each broke this accidental
  property in different ways, with the result that recovery fires
  *too often* and triggers re-saturation cascades.

The publishable finding parallels [[idea-1-postmortem]]:

> *Direct ports of TCP-era congestion control algorithms to
> coarse-grained (1 Hz, frame-rate-sampled) cloud-gaming feedback
> break the algorithm's damping assumptions. The cubic curve, when
> sampled per-ACK at thousands of Hz, gives gentle nudges; sampled
> once per second and applied as a full curve delta, the same
> curve becomes far more aggressive than its authors intended.*

This gives the TCC a clean structural conclusion to the algorithmic
exploration, and a strong basis for the final framing: *the simple
AIMD with β-only multiplicative decrease — augmented by CUBIC's
fast-convergence rule — outperforms more faithful CUBIC ports
because of its coarser actuation cadence.*

## Key Concepts

- **The fix itself** — in `bitrate_controller.cpp`, the line
  `rtt_clear_since = now;` was removed from the increase branch
  (it remains in the per-sample tracking, where it sets the anchor
  at the start of a streak, and in the implicit reset when a sample
  breaks the streak). Combined with the 5b t-origin choice, this
  means `rtt_clear_since` is set once when the streak begins and
  not touched again until the streak breaks.
- **The CUBIC invariant that 5c finally honours** — within a
  recovery epoch, `t` is monotonically increasing and the curve
  passes from concave (rapid catch-up) through plateau
  (`t ≈ K`) into convex (cautious then accelerating probe). 5c
  achieves this; 5b did not.
- **Why this still loses on constrained scenarios** — the cubic
  was designed for per-ACK actuation at thousands of Hz, with each
  update being a tiny nudge. Our 1 Hz decision cadence applies the
  full curve delta on each tick. The curve climbs quickly enough
  to re-saturate the link, the controller cuts, and the cycle
  repeats. The 68 increase events observed on E K = 15 s is the
  visible signature of this.

## Results

All three runs were captured at 2026-06-08 in
`testbed/results/test-5c-15k/` and `testbed/results/test-5c-5k/`,
240 s scenarios, x11 capture, `bitrate_mode = adaptive`,
`abr_beta = 0.70`, `abr_fast_convergence = true`. Gameplay was
rated 1 / 1 / 1 (latency / quality / stability) on all three runs.

### Comparison across the full 5 → 5b → 5c arc

| Metric | Idea 5 | 5b | **5c** |
|---|---|---|---|
| A K = 15 s peak RTT | ~1221 ms | 1313 ms | **1264 ms** |
| A K = 15 s increases | few (suppressed) | 4 | **52** |
| A K = 15 s channel use during shaping | — | 32.9 % | **44.4 %** |
| **E K = 15 s peak RTT** | **2305 ms** ⭐ | 3192 ms | **3013 ms** |
| E K = 15 s increases | suppressed | 9 | **68** |
| E K = 15 s channel use during shaping | 14.9 % | 38.0 % | **41.4 %** |
| A K = 5 s peak RTT | ~796 ms (2nd spike) | 1105 ms | **1116 ms** |
| A K = 5 s anomaly | recovery overshoot | — | encoder reached 18 988 kbps inside 8 Mbps shaping; late cascade at t = 256 s |

### Honest reading

- **A K = 15 s.** Peak RTT essentially neutral across all three
  iterations, but the *behaviour* changed dramatically: from "almost
  no recovery during shaping" (Idea 5) to "52 growth ticks in a
  240 s run" (5c). Channel use rose accordingly (32.9 % → 44.4 %),
  but at no peak-RTT benefit.
- **E K = 15 s.** The most decisive negative result. The original
  Idea 5 peak of 2305 ms stays unbeaten; 5c's 3013 ms is a 31 %
  regression versus Idea 5 and only a 21 % improvement versus the
  no-CUBIC baseline (3808 ms). The channel-use trade is in the wrong
  direction for our stated priority (low latency over channel
  utilisation, matching [[alos2019]] §6).
- **A K = 5 s.** The most diagnostic run. The cubic, with `t`
  accumulating freely, drove the encoder target up to 18 988 kbps
  while the channel was capped at 8 Mbps. This is the cubic
  *escaping the constraint envelope* — visible proof that the
  curve sampled at 1 Hz cannot be trusted to back off cleanly. A
  late cascade at t = 256 s (96 s after shaping ended) suggests the
  controller carried residual instability past the constraint
  window itself.

## Diagnosis

The cubic curve is **too aggressive when sampled at 1 Hz**. CUBIC
was designed for the per-ACK feedback loop of TCP — thousands of
gentle updates per second. Our decision cadence applies the full
analytic curve delta once per second, with no smoothing. On a
constrained scenario this looks like:

1. Decrease fires, `last_known_good ← current · (1+β)/2`.
2. RTT clears, anchor set; growth ticks fire every 1 s.
3. After K seconds, the curve reaches its plateau near
   `last_known_good` — but `last_known_good` is still well above
   the new channel capacity (because cut counts are finite).
4. Reaching `last_known_good` re-saturates the link.
5. Another cascade fires; repeat.

The 5c invariant is "correct" in the sense that it matches what
CUBIC actually does, but it exposes the underlying mismatch between
TCP CUBIC's per-ACK actuation and our 1 Hz decision cadence.

## What survives from the CUBIC port

- **Fast convergence (Eq. 3.7)** — still empirically valuable.
  On E, ratcheting `last_known_good` from 18 988 kbps down through
  the cascade to ~930 kbps in nine cuts is what produced Idea 5's
  40 % peak-RTT win. This mechanism is independent of the recovery
  curve shape; it acts on the *decrease* path.
- **The recovery target shrinks across cascades** — without fast
  convergence, the controller would keep aiming at a stale ceiling
  forever. This piece of CUBIC is structurally right for our use
  case.

## What does not survive

- **The cubic curve as a 1 Hz recovery primitive.** Neither the
  literal port (`t` since last decrease, 5c equivalent) nor the
  queue-drain-aware port (`t` since RTT clears, 5b) produces a
  recovery profile that respects sustained constraint. The
  algorithm needs damping at our sampling cadence.

## Decision

Revert to Idea 5 (original implementation) as the final
controller for the TCC. Document the 5b → 5c iteration as the
structural finding that motivates this choice. The final
comparison the thesis presents is:

> *Hand-rolled two-phase AIMD recovery (baseline, [[results-beta-0.7]])
> vs. AIMD with cubic-shaped recovery + fast convergence (Idea 5,
> [[results-idea-5]]) — across all six scenarios, with re-gathered
> Idea 5 data on the current machine state for a clean comparison.*

The 5b / 5c attempts are not failed code — they are the experiment
that established *why* the simpler Idea 5 implementation works,
and what kind of damping a future iteration would need.

## Related

- [[results-idea-5]] — the implementation that stays as the final
  controller
- [[results-idea-5b]] — the previous failed iteration whose
  diagnosis motivated 5c
- [[cubic]] — the CUBIC paper; §3.1 defines the invariant 5c
  honours
- [[idea-1-postmortem]] — structural sibling: another direct port
  of a control technique that failed because of a sampling-rate
  mismatch
- [[improvement-roadmap]] — to be updated to mark Idea 5 as the
  chosen final and 5b / 5c as the closure iterations
- [[alos2019]] — C³G; §6 prioritises low latency over fast bitrate
  increase, the trade-off both 5b and 5c invert

## Sources

- `Sunshine/src/bitrate_controller.cpp` (increase branch with
  `rtt_clear_since` no longer reset on growth)
- `testbed/results/test-5c-15k/A_run0_20260608-202333.csv`
  (Scenario A, K = 15 s)
- `testbed/results/test-5c-15k/E_run0_20260608-202806.csv`
  (Scenario E, K = 15 s)
- `testbed/results/test-5c-5k/A_run0_20260608-201854.csv`
  (Scenario A, K = 5 s)
- Notes files in the same directories (subjective ratings 1 / 1 / 1
  on all three runs)
