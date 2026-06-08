# Idea 5 (CUBIC Port) — Implementation and Results So Far

## What is it?

Implementation log and result summary for [[improvement-roadmap]] Idea 5
— porting the TCP CUBIC algorithm ([[cubic]]) into the
`bitrate_controller_t` to replace the hand-rolled two-phase increase
(`×γ` then `+STEP`) with a single time-based cubic curve, and adding
CUBIC's fast convergence rule (Eq. 3.7) to shrink the recovery target
on cascading decreases.

This document captures the work as of three completed Scenario A and E
runs at two values of `K`. It does **not** describe a finished
contribution — there is a known design subtlety (the cubic's
`t`-origin choice) that the next implementation cycle is meant to
address. The document is here so anyone resuming this branch has the
full state on disk, not in commit messages or chat logs.

## Why it matters for Sunshine / TCC

Idea 5 is the first change that produced a **publishable headline**
without an asterisk:

> *Peak RTT inflation on Scenario E reduced 40 % (3808 ms → 2305 ms)
> vs the β-only AIMD baseline, with a single big spike + two minor
> ones instead of four catastrophic ping-pong spikes.*

The mechanism behind the improvement (CUBIC fast convergence) is
peer-reviewed (Ha, Rhee, Xu 2008) and corresponds to a non-trivial
piece of C³G's proactive layer — without requiring any Moonlight
modification. That validates the central TCC framing: *"the simplest
peer-reviewed AIMD improvements close part of the gap C³G's
state-dictionary opened."*

It is also the first change where a **clean trade-off** emerges
between two metrics the surveyed literature both cares about (peak
RTT vs channel use during constraint), and the trade-off matches
C³G's own (Alós et al. 2019, §6) — *"prioritise minimal losses
followed by low latency over fast bitrate increase."*

## Key Concepts

- **Cubic recovery curve** — `B(t) = C · (t − K)³ + last_known_good`,
  with `K = cubic_recovery_ms / 1000` and
  `C = (1 − β) · last_known_good / K³`. Concave for `t < K`,
  plateau near `t = K`, convex for `t > K`. The wall-clock origin
  `t = 0` is **the moment of the last decrease**, regardless of
  whether the controller was actually growing during that interval.
  See [[cubic]] §2 — *time-based growth*.
- **Fast convergence** (CUBIC Eq. 3.7) — on a decrease that fires
  while `current_kbps < last_known_good` (the controller had not
  yet recovered to the previous ceiling), set
  `last_known_good ← current_kbps · (1 + β) / 2`. With β = 0.7,
  factor = 0.85, so the new ceiling is *15 % below the current
  rate*. The cubic then plateaus at the smaller ceiling next time.
- **t-origin design choice** — where the cubic's `t = 0` is anchored.
  We anchor at `last_decrease_at` (TCP-faithful). The alternative is
  `rtt_clear_since` (preserves the concave region across queue-drain
  delays). The differences surface clearly in the K = 5 s run on A
  and the first-recovery overshoot on E.
- **C³G recovery trade-off** — C³G's EP (exploration period) is
  36 ± 16 s, deliberately slower than BBR's 8.3 s, *to keep losses
  near zero*. Idea 5 inherits this philosophy: the cubic plateau
  around `last_known_good` is what buys stability at the cost of
  channel use during sustained constraint.

## Implementation summary

### Files changed

| File | Change |
|---|---|
| `src/bitrate_controller.h` | Removed `gamma`, `step_kbps`. Added `cubic_recovery_ms = 15000`, `fast_convergence = true`. Reduced `stable_time_ms` default 7500 → 1000. Added private member `last_decrease_at` (optional `time_point`). Updated class docstring. |
| `src/bitrate_controller.cpp` | `#include <cmath>`. Added fast-convergence branch in decrease (before β cut). Replaced phase-1/phase-2 if/else with a single cubic evaluation in the increase branch. Records `last_decrease_at = now` on every decrease. |
| `src/config.h` | Removed `abr_gamma`, `abr_step_kbps`. Added `abr_cubic_recovery_ms`, `abr_fast_convergence`. |
| `src/config.cpp` | Defaults table and parser entries updated (`bool_f` for `abr_fast_convergence`). |
| `src/stream.cpp` | Wired new params into `abr_params`. Startup log line reports K and fast-convergence state. |

The implementation removed ~20 lines (the phase-1/phase-2 if/else)
and added ~30 lines (cubic math + fast convergence). Net +10 lines.

### Parameter choices and rationale

| Param | Value | Why |
|---|---|---|
| `beta` | 0.7 | Kept from [[results-beta-0.7]] β-sweep diagnosis. CUBIC's 0.2 is wrong for our RTT-inflation trigger — see [[cubic]] §7.5. |
| `cubic_recovery_ms` | 15000 | First-pass guess. Initial growth rate `3·(1−β)·W_max/K = 1140 kbps/s` for K=15, W_max=19000 — visibly faster than the old algorithm without being a violent ramp. Pending sweep. |
| `fast_convergence` | true | CUBIC's recommendation; off-by-default makes no sense given it's free insurance with a clear win on cascading-cut scenarios. |
| `stable_time_ms` | 1000 | Reduced from 7500. The cubic naturally paces growth, so the long pre-growth wait is no longer needed — 1 s is enough to filter transient RTT-clear jitter. |

`gamma` and `step_kbps` were removed cleanly (no deprecation
shim). The pre-CUBIC implementation is recoverable from git history
if needed.

## The three runs so far

### Run 1 — Scenario A, K = 15 s, fast_convergence on
**Path:** `testbed/results/test-idea-1/A_run0_20260604-161336.csv`

**What we expected:** dramatically faster recovery from floor than
the two-phase algorithm. Fast convergence inactive (no expected
ping-pong on Scenario A's clean cut-then-recover shape).

**What happened:**
- Initial cascade unchanged from β-only baseline: 9 cuts to floor.
- Fast convergence ratcheted `last_known_good` internally from
  18 988 to 930 across the cascade, but cut depth is `β · current_kbps`
  independent of `last_known_good`, so the cut sequence looked the same.
- After RTT cleared (queue drained over ~27 s), the cubic recovery
  was visibly working — deltas grew from +62 to +868 kbps per tick,
  classic convex-region acceleration.
- Total recovery from 1000 → 18988 kbps took **76 seconds**. The
  β-only baseline never reaches max within the 240 s scenario (its
  `+500 / 7.5 s` linear ramp would need ~270 s).
- "Channel use" measured over the shaping window (t=110–160 s) looks
  bad (7.8 %) because the recovery only started at t = 136.6 s — most
  of the measurement window had the controller still at floor.
- Extended channel-use window (t=110–200 s) shows the honest picture:
  33.0 % vs baseline's 37.0 % — close, and by t=200 s Idea 5 is at
  16 Mbps while baseline is at 3 Mbps.

**Take-away:** The cubic curve works. The metric window matters.

### Run 2 — Scenario A, K = 5 s, fast_convergence on
**Path:** `testbed/results/test-idea-1/A_run0_20260604-162912.csv`

**What we expected:** aggressive recovery, possibly an overshoot
because the cubic is past K during the queue-drain window. Fast
convergence as a safety net.

**What happened:**
- Initial cascade identical (9 cuts to floor; `last_known_good` →
  930 via fast convergence).
- Queue drained over ~9 s; RTT cleared at t = 118 s.
- By that point the cubic was already 9 s past K = 5, deep in the
  convex region. First recovery ticks blew through targets:
  ```
  t=118.2s  target=1077   Δ=+77
  t=122.2s  target=2106   Δ=+391
  t=126.4s  target=4878   Δ=+915
  t=129.3s  target=8655   Δ=+1455   ← crossed the still-active 8 Mbps cap
  ```
- At t = 129.3 s the target crossed the 8 Mbps cap, queue refilled,
  RTT bumped to 45 ms (still under threshold).
- Hysteresis confirmed a second congestion event by t = 132.3 s.
  **Second cascade triggered** — 6 more cuts back to the floor.
- Fast convergence ratcheted `last_known_good` further on each of
  those 6 cuts; second recovery (t = 154.6 s onward) had a smaller
  cubic plateau and reached max more cautiously.
- **Second spike peak: 796 ms** vs first spike's 1221 ms — fast
  convergence visibly damped the re-overshoot.
- Channel use 46.3 % over extended window — best of any
  configuration measured on Scenario A.

**Take-away:** K = 5 s is too aggressive *given the t-origin choice*.
The cubic raced through the entire concave + plateau regions during
the queue-drain delay. Fast convergence rescued the situation but at
the cost of an extra cascade. The K parameter cannot be made too
small without also fixing the t-origin design.

### Run 3 — Scenario E (the fast-convergence stress test), K = 15 s
**Path:** `testbed/results/test-idea-5/E_run0_20260604-163946.csv`

**What we expected:** the headline fast-convergence demonstration.
β-only baseline ping-ponged 4 times on Scenario E. Idea 5 should
ratchet `last_known_good` down to near the actual 4 Mbps cap and
settle.

**What happened:**

| Metric | β=0.7 baseline | Idea 5 K=15 s | Δ |
|---|---:|---:|---|
| Decreases (constraint window) | 14 | 15 | +1 |
| Spikes (above-threshold runs) | 4 | **3** | −1 |
| ΣL_AP | 54.5 s | 58.3 s | +3.8 s |
| **RTVL_peak** | **3808 ms** | **2305 ms** | **−40 %** |
| p95 RTT | 3516 ms | 2105 ms | −40 % |
| Channel use (window) | 23.7 % | 14.9 % | −8.8 pp |

Per-spike:
```
Idea 5 spike 0:  t=52.0s   L_AP=37.2s  peak=2305 ms  ← initial cascade
Idea 5 spike 1:  t=111.0s  L_AP= 7.5s  peak= 230 ms  ← tiny
Idea 5 spike 2:  t=160.2s  L_AP=13.6s  peak= 369 ms  ← tiny
```

The β=0.7 baseline by contrast had **four** spikes all in the
3000–3800 ms peak range — the controller never settled.

**Trace of fast convergence during the initial cascade:**

```
Cut 1: current=18988, lkg=18988      (FC no-op)   → lkg=18988
Cut 2: current=13291 < lkg=18988     FC fires     → lkg=11297
Cut 3: current= 9303 < lkg=11297     FC fires     → lkg= 7907
Cut 4: current= 6512 < lkg= 7907     FC fires     → lkg= 5535
Cut 5: current= 4558 < lkg= 5535     FC fires     → lkg= 3874
Cut 6: current= 3190 < lkg= 3874     FC fires     → lkg= 2712
Cut 7: current= 2233 < lkg= 2712     FC fires     → lkg= 1898
Cut 8: current= 1563 < lkg= 1898     FC fires     → lkg= 1329
Cut 9: current= 1094 < lkg= 1329     FC fires     → lkg=  930
```

`last_known_good` ratcheted from 18 988 → 930 in one cascade — a
**20× shrink** of the recovery ceiling. The cubic on subsequent
recoveries plateaus near 930 instead of forever aiming at 19000, and
that is the mechanism that prevents the catastrophic ping-pong.

**The channel-use cost:** with the recovery ceiling at 930, the
controller spends much of the constraint window near the floor.
β=0.7 baseline's phase-1 `×1.15`-from-floor is a faster initial
ramp regardless of `last_known_good`, so it reaches higher average
bitrates between cuts. That is the C³G-style trade we've taken.

**Take-away:** Fast convergence works exactly as the paper
describes. The peak-RTT reduction is the central new result.

## Two design subtleties surfaced

### 1. The t-origin choice
The cubic's `t = 0` is anchored at `last_decrease_at`. When the
queue-drain delay (the time from "last cut fires" to "RTT actually
clears") is large, the cubic is already deep in the convex region
when growth resumes — and growth races forward with no plateau-around-
`last_known_good` stabilisation.

This surfaces as:
- **K=5 s on A**: cubic was 9 s past K when growth resumed. First
  recovery overshot the cap → second cascade.
- **K=15 s on E**: similar dynamic but milder. The first recovery
  reached 1524 kbps in 7 s — already in convex region, accelerating
  toward an overshoot — when the next congestion event saved the
  day by triggering a cut.

The alternative is to anchor at `rtt_clear_since`. Then the cubic
always re-enters from the concave region when growth resumes,
preserving the plateau-around-`last_known_good` benefit regardless
of queue-drain delay.

**Decision:** the next implementation cycle (Idea 5b) is the
t-origin fix. After it lands, we rerun A (K=5 and K=15) and E to
see if (a) K=5 stops overshooting and (b) E's channel use rises
without losing the peak-RTT win.

### 2. Fast convergence is "one-shot per cascade" by construction
Eq. 3.7 only fires when `current_kbps < last_known_good` at decrease
time. On Scenario E, after the initial cascade, the controller's
recoveries grew *past* the small post-FC `last_known_good` quickly
(convex region accelerates), so subsequent cut events found
`current > last_known_good` and FC was a no-op for them.

The 20× ratchet on the initial cascade is therefore the *only* FC
contribution on this scenario. Subsequent oscillation is held in
check because the cubic now anchors at the small ceiling, not
because FC keeps shrinking it.

This is faithful to TCP CUBIC's design (the rule is about fairness
to competing flows when they steal bandwidth). For our single-flow
ABR use case, a more aggressive variant — "FC fires on *every*
decrease, regardless of `current` vs `last_known_good`" — would
ratchet further and might close the channel-use gap. **We have not
explored this**; sticking to the paper for now.

## What's working

1. **Cubic recovery curve is visibly correct.** Deltas accelerate
   through convex region as predicted. Math verified against the
   data (sample-by-sample sanity check matches B(t) formula).
2. **Fast convergence ratchets `last_known_good`** during deep
   cascades, exactly as Eq. 3.7 prescribes.
3. **Peak RTT inflation reduced 40 %** on the hardest scenario.
4. **Build pipeline clean.** No warnings from our code; pre-existing
   third-party warnings only.
5. **CSV instrumentation is complete.** The `abr_state` column
   distinguishes `recovering` from `probing` (concave vs convex)
   and the trajectory analysis is fully reproducible from CSV.

## What's not yet working / open

1. **The t-origin issue.** Confirmed on both A (K=5) and E (K=15).
   Implementation pending.
2. **Channel use during sustained constraint** is worse than β=0.7
   baseline by ~9 percentage points on E. This is the documented
   C³G trade-off (stability vs throughput); we are choosing
   stability. Whether the t-origin fix moves this number is the
   next empirical question.
3. **K has not been swept on E.** K = 8 or 10 might recover some of
   the channel-use gap. Deferred until after the t-origin fix
   because the two interact.
4. **Other scenarios (B, C, D, F) untested with Idea 5.** Going to
   test after the t-origin fix; running them on a known-buggy
   t-origin would waste data.

## Knowledge artifacts produced during this cycle

- [[cubic]] — paper analysis, written before implementation began.
- [[improvement-roadmap]] — Idea 5 entry rewritten after the CUBIC
  paper read; this is the version that was implemented.
- This document — implementation log and result summary.

## Next step (committed)

**Implement the t-origin fix (Idea 5b):** anchor the cubic's `t = 0`
at `rtt_clear_since` instead of `last_decrease_at`. Predict:
- K = 5 s on A will stop overshooting (concave region preserved
  across queue drain).
- K = 15 s on E will plateau around `last_known_good` instead of
  racing into convex on the first recovery, possibly improving
  channel use without losing the peak-RTT win.

The fix is small (~10 lines) — replace the `t` computation in the
increase branch with `(now − *rtt_clear_since).count()`. The cubic
math is unchanged.

After landing it, rerun: A K=15, A K=5, E K=15. If the predictions
land, we have the full paper-ready story.

## Related
- [[cubic]] — CUBIC paper analysis; the source of Idea 5
- [[improvement-roadmap]] — Idea 5 proposal; status: in progress
- [[results-beta-0.7]] — first-round AIMD results; the comparison baseline
- [[idea-1-postmortem]] — the prior attempt (computed-drain step) and
  why we pivoted to Idea 5
- [[reactive-blind-spot]] — architectural floor; CUBIC's fast
  convergence partially mitigates its consequences on E
- [[alos2019]] — C³G; recovery trade-off philosophy Idea 5 inherits
- [[idea-10-abr-comparison]] — TCC research idea this work serves

## Sources
- Ha, S.; Rhee, I.; Xu, L. *CUBIC: A New TCP-Friendly High-Speed TCP
  Variant.* ACM SIGOPS Operating Systems Review, 2008. Eqs. 1, 2,
  3.7.
- Alós, J. et al. *Congestion Control for Cloud Gaming Over UDP
  Based on Round-Trip Video Latency.* IEEE Access, 2019.
  §6 — recovery trade-off philosophy.
- Implementation: `Sunshine/src/bitrate_controller.{h,cpp}`,
  `Sunshine/src/config.{h,cpp}`, `Sunshine/src/stream.cpp` —
  current `main` working tree.
- Run CSVs:
  - `testbed/results/test-idea-1/A_run0_20260604-161336.csv` —
    Idea 5 K=15 s on Scenario A.
  - `testbed/results/test-idea-1/A_run0_20260604-162912.csv` —
    Idea 5 K=5 s on Scenario A.
  - `testbed/results/test-idea-5/E_run0_20260604-163946.csv` —
    Idea 5 K=15 s on Scenario E.
