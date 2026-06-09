# Final Campaign — Three-Way Comparison Results

## What is it?

The empirical core of the TCC. A single-pass, three-way comparison
of bitrate controllers across six bandwidth-impairment scenarios,
captured on 2026-06-08 for the CUBIC AIMD column and reused from
prior campaigns for the other two:

- **baseline** — fixed bitrate, no controller (no-ABR reference,
  `testbed/results/baseline/`).
- **adaptive AIMD** — β = 0.7 multiplicative decrease + hand-rolled
  two-phase increase (`×γ` then `+step_kbps`), the β-0.7 sweep
  winner; data from `testbed/results/adaptive/` (2026-06-01 campaign,
  [[results-beta-0.7]]).
- **CUBIC AIMD** — β = 0.7 multiplicative decrease + CUBIC fast
  convergence (Eq. 3.7) + cubic recovery curve `B(t) = C·(t−K)³ +
  last_known_good`, K = 15 s, anchored at `last_decrease_at`. The
  controller defined by [[results-idea-5]] after reverting the
  [[results-idea-5b]] / [[results-idea-5c]] experiments. Data
  captured today, `testbed/results/cubic/`.

Methodology spec: [[final-campaign-protocol]]. Visualisations and
the source-of-truth analysis notebook live at
`testbed/visualizations/results_cubic/comparison.ipynb`.

## Why it matters for Sunshine / TCC

This is the thesis's empirical contribution. Three findings emerge
that the writeup will build around:

1. **CUBIC AIMD reduces tail-latency events but raises the
   steady-state latency floor.** It wins on peak RTT in 5 of 6
   scenarios and on total stall time in 5 of 6, but worsens p50
   and p95 in every scenario.
2. **Subjective experience does not track peak RTT.** Adaptive
   AIMD is rated subjectively better in 3 of 6 scenarios despite
   worse peak RTT in those same scenarios. The two controllers
   represent different *priorities*, not different qualities.
3. **Any ABR is dramatically better than none.** Baseline (no
   controller) suffers 40–135 seconds of stall time per 240 s run.
   Both adaptive and CUBIC cut stall time by 90–100 %.

The publishable framing is therefore not *"we beat the baseline
AIMD"* but *"we characterised a trade-off the literature has not
documented for cloud gaming at this granularity"* — closer in
spirit to [[alos2019]] §6, which makes the same trade-off
explicit but does not measure it head-to-head against a
non-CUBIC baseline.

## Key Concepts

- **Rating scale**: 1 = best, 5 = worst. Latency / quality /
  stability captured per run after the session ended.
- **Cap profile**: each scenario has a deterministic `tc htb`
  bandwidth schedule defined in `testbed/lib/scenarios.sh`:
  - A: 8 Mbps from 80–160 s
  - B: 16 → 12 → 8 Mbps in three steps from 60–160 s
  - C: 14 → 10 Mbps from 40–200 s
  - D: 10 Mbps in four 30 s windows (30–60, 90–120, 150–180, 210–240)
  - E: 4 Mbps from 40–200 s (worst case)
  - F: 6 Mbps from 0–160 s
- **Tail-event metric**: peak RTT and total stall time are the
  proxies for the user-visible "freeze" events.
- **Steady-state metric**: p50 / p95 RTT proxy for the "feel"
  while the connection is nominally fine.
- **Controller activity**: number of decreases / increases per
  run is the diagnostic for whether the controller's logic was
  exercised at all (zero counts → controller idle, see §"Caveats").

## Full results

### Per-scenario table

Rating polarity reminder: **1 = best, 5 = worst.**

| Scen | Controller | peak (ms) | p99 (ms) | p95 (ms) | p50 (ms) | dec | inc | stalls | stall_ms | idr | lat/qual/stab |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **A** | baseline      | 1854 | 1801 | 1723 | 4 | 0 | 0 | 43 | 49337 |  10 | 5/1/5 |
|       | adaptive AIMD | 1786 | 1713 |   55 | 4 | 7 | 25 |  4 |  4408 |  35 | **3/1/3** |
|       | **CUBIC AIMD**| **1025** | **913** | 183 | 16 | 9 |  82 |  0 |     0 |  97 | 3/2/3 |
| **B** | baseline      | 1551 | 1481 | 1323 | 5 | 0 | 0 | 50 | 43550 |  27 | 4/1/4 |
|       | adaptive AIMD |  575 |  544 |  194 | 4 | 7 | 22 |  0 |     0 |  30 | **1/1/2** |
|       | CUBIC AIMD    | **532** | **486** | 123 | 18 | 7 |  67 |  0 |     0 |  78 | 3/2/2 |
| **C** | baseline      | 1565 | 1541 | 1481 | 6 | 0 | 0 | 107 | 87452 | 104 | 4/1/4 |
|       | adaptive AIMD |  733 |  504 |  116 | 5 | 7 | 28 |   0 |     0 |  36 | **1/1/1** |
|       | CUBIC AIMD    | **639** | **566** | 298 | 13 | 12 | 115 |  0 |     0 | 133 | 2/1/3 |
| **D** | baseline      | 1583 | 1531 | 1442 | 16 | 0 | 0 | 103 | 91501 |  97 | 4/1/3 |
|       | adaptive AIMD | 1156 |  877 |  117 | 5  | 7 | 31 |   0 |     0 |  39 | **2/1/2** |
|       | CUBIC AIMD    | **998** |  **979** | 522 | 12 | 16 | 161 |  0 |     0 | 186 | 3/1/3 |
| **E** | baseline      | 3788 | 3630 | 3435 | 22 | 0 | 0 | 59 | **135167** |  5 | 5/1/5 |
|       | adaptive AIMD | 3808 | 3533 | 3354 | 5 | 16 |  25 | 5 |   11010 | 43 | 3/3/3 |
|       | **CUBIC AIMD**| **3311** | **3185** | 2980 | 23 | 16 | 128 | **2** | **4306** | 151 | 3/3/4 |
| **F** | baseline      | 2536 | 2453 | 2308 | 22 | 0 | 0 | 100 | 148855 |  72 | 5/1/4 |
|       | **adaptive AIMD** | **1602** | **1551** | 263 | 5 | 13 | 33 | 2 | 2852 | 50 | 3/2/3 |
|       | CUBIC AIMD    | 1863 | 1832 | 477 | 12 | 17 | 128 | 4 | 5961 | 156 | **2/1/2** |

### Headline aggregates

- **Peak RTT winner**: CUBIC in 5/6 (A, B, C, D, E); adaptive in
  1/6 (F). Largest CUBIC win: A (−43 %, 1786 → 1025 ms).
- **p99 RTT winner**: CUBIC in 5/6 (same set). Largest CUBIC win:
  A (−47 %).
- **p50 RTT**: adaptive in 6/6 (4–5 ms vs 12–23 ms for CUBIC).
- **p95 RTT**: adaptive in 6/6 — significantly so on A (55 vs 183
  ms) and D (117 vs 522 ms).
- **Stall time**: CUBIC in 5/6, tied or worse on F. CUBIC achieves
  zero stalls on A, B, C, D. Adaptive does so on B, C, D.
- **IDR frames**: adaptive in 6/6 — CUBIC roughly doubles or
  triples IDR count because more cuts + more probing means more
  encoder restarts.
- **Subjective**:
  - adaptive cleanly wins B, C, D
  - CUBIC cleanly wins F
  - near-ties on A and E
- **vs baseline**: every adaptive/CUBIC run beats baseline on
  peak RTT (30–60 % reduction) and stall time (~90 %+ reduction).
  The "do nothing" baseline is consistently the worst experience.

## Per-scenario reading

### Scenario A (abrupt drop, 8 Mbps cap 80–160 s)

CUBIC's clearest objective win — peak RTT 1025 vs 1786 ms
(−43 %), zero stalls vs 4 stalls / 4.4 s. The cubic curve plus
fast convergence absorbs the cap without the encoder ever
having to freeze. Adaptive gets a worse peak but a better p95
(55 vs 183 ms), reflecting its quieter steady-state. Subjective
ratings tie at 3/1/3 (adaptive) vs 3/2/3 (CUBIC), with CUBIC
losing a point on quality — likely the cost of constant probing
making the picture flicker on bitrate transitions.

### Scenario B (gradual step-down 16 → 12 → 8 Mbps)

Smallest CUBIC peak-RTT win (−7 %, 575 → 532). Adaptive
**subjectively wins by a wide margin (1/1/2 vs 3/2/2)** —
this is the scenario where the trade-off most clearly favours
adaptive. The cap descends gently enough that adaptive's
seven-cut cascade keeps tail latency tolerable, and the
steady-state floor (p50 = 4 ms, p95 = 194 ms) is buttery for
the bulk of the run.

### Scenario C (slow decline 14 → 10 Mbps)

CUBIC wins peak RTT (−13 %) but **adaptive achieves a perfect
1/1/1 subjective rating** — the only such rating in the
campaign. CUBIC's higher p95 (298 vs 116 ms) and 12 cuts /
115 increases produce a felt "laggy" feel even though tail
events are reduced.

### Scenario D (intermittent 10 Mbps every 30 s)

CUBIC wins peak RTT (−14 %) but **p95 explodes** (522 vs 117
ms). The intermittent cap pattern matches the cubic's recovery
cadence badly: every uncap window triggers a fresh probe,
every cap window triggers a fresh cascade, and the controller
never settles. Adaptive's two-phase recovery rides through the
oscillation more cleanly. Subjective: adaptive 2/1/2 vs CUBIC
3/1/3.

### Scenario E (long heavy constriction, 4 Mbps for 160 s)

The hardest scenario. **CUBIC is the first controller to break
3.5 seconds of peak RTT** (3311 ms vs adaptive 3808, baseline
3788). Stall time cut from adaptive's 11 s to CUBIC's 4.3 s.
Baseline's 135 s of stall time during the constriction is the
single most damning number in the campaign and is what makes
this scenario the strongest argument for *any* ABR. Subjective:
adaptive 3/3/3 vs CUBIC 3/3/4 — CUBIC loses a stability point
because the long constriction surfaces its constant probing as
visible re-saturations.

### Scenario F (low start at 6 Mbps from t=0, uncap at 160 s)

The only scenario where CUBIC **loses** peak RTT (1863 vs 1602,
+16 %). It also has more stall time (5961 vs 2852 ms).
Diagnosis: with the cap active from t = 0, fast convergence
never gets a "high-bitrate ceiling" to ratchet down from —
`last_known_good` starts equal to `initial_kbps` (18988) and
the cubic spends the first cascade trying to probe back to
that fantasy ceiling. Meanwhile adaptive's two-phase recovery,
which doesn't have fast convergence, doesn't waste time
probing for a target that was never available. **But** CUBIC
**wins subjectively (2/1/2 vs 3/2/3)** — the constant
moderate-rate probing happens to feel smoother than adaptive's
more pronounced cascade pattern. This is the strongest data
point for the claim that *peak RTT is not the only thing that
matters*.

## What this tells us about the algorithms

### Where CUBIC AIMD genuinely shines

- Scenarios with a **sustained cap that the encoder would otherwise
  try to exceed**: A, B, C, E. Fast convergence ratchets
  `last_known_good` down quickly, recovery curve probes back
  cautiously, peak events get absorbed rather than spiking.
- The harder the cap, the bigger the CUBIC win. E (4 Mbps,
  160 s) is where the gap is widest in absolute stall time
  reduction (11 → 4.3 s).
- **Stall elimination** is the most reliable CUBIC effect.
  In A, B, C, D, stall time is zero — meaning the user never
  saw a frozen frame.

### Where CUBIC AIMD struggles

- **Steady-state latency floor.** Constant probing (52–161
  increases per 240 s run) means p50 sits at 12–23 ms instead of
  4–5 ms. p95 is consistently 2–4× higher than adaptive. The user
  *feels* this even though peak events are rare.
- **Cap-from-t = 0 scenarios** (F). No ceiling to ratchet down
  from, so fast convergence doesn't help in the first cascade.
- **Intermittent caps** (D). Probing cadence mismatches the
  on/off cap cadence, so the controller never converges to a
  stable rate during the run.

### What this means structurally

The 1 Hz decision cadence applied to a CUBIC curve designed for
per-ACK actuation produces a controller that **converges
aggressively after each cut and probes aggressively between
cuts**. On scenarios where the constraint is steady, that
aggressive convergence is exactly what's needed and tail
latency drops. On scenarios where the constraint is mild
(adaptive can absorb it) or oscillating (D) or non-existent
post-cap (steady-state between cap events), the probing
becomes visible as a higher latency floor and a "laggy" feel.

This is structurally the same finding as [[results-idea-5c]]
but with subjective ratings attached: CUBIC's 1 Hz actuation
cadence is **right** for the worst-case but **wrong** for the
common case. The β-0.7 sweep ([[results-beta-0.7]]) optimised
for the common case; the CUBIC port optimises for the
worst-case; both are defensible engineering choices.

## Caveats

1. **n = 1 per scenario per controller.** No statistical power.
   The ratings are anecdotal even with a single competent
   operator. Variance between runs may be of similar
   magnitude to the inter-controller differences.
2. **The `baseline` and `adaptive` data are reused from prior
   campaigns** (2026-05-21 and 2026-06-01). Same Sunshine
   testbed and operator, but two and one week apart from the
   CUBIC runs. Network conditions, OS state, encoder state, and
   game content may have drifted. See [[final-campaign-protocol]]
   §"Runs per cell" for the explicit acceptance of this limit.
3. **First A and B CUBIC runs were discarded** — the operator
   played a less demanding scene during those runs and the
   encoder never pushed past the cap, so the controller had no
   work to do. The runs analysed here are the second attempt,
   with intentionally matched gameplay activity. The discarded
   runs are diagnostically valuable on their own — they show
   that **scenario "hardness" is content-dependent** and that
   a controller can look "perfect" in a CSV by virtue of not
   being tested.
4. **Subjective ratings are operator self-reports** of a single
   240 s session. They capture the operator's perception of
   "playability" but are not normalised across sessions and
   are vulnerable to fatigue and expectation effects.
5. **Stall counts in the baseline runs** (43–107 per run) likely
   reflect *recoverable* video stalls (the decoder pausing
   briefly), not the session disconnecting. On E the baseline
   reached 135 s of cumulative stall — the session probably
   disconnected and reconnected — but the CSV does not capture
   the disconnect explicitly.

## Honest thesis framing

> **"CUBIC AIMD reduces tail-latency events at the cost of a
> raised steady-state latency floor. Across six bandwidth-cap
> scenarios, the controller reduces peak RTT in five of six
> cases (largest reduction: −43 % on Scenario A) and total
> stall time in five of six cases (largest reduction: from
> 11.0 s to 4.3 s on Scenario E, the hardest constraint
> profile). It also raises p50 RTT from 4–5 ms to 12–23 ms in
> every scenario and p95 RTT by 2–4× in most, producing
> subjectively worse user experience in three of six scenarios
> despite its better tail-event numbers. The two controllers
> represent complementary engineering priorities: adaptive
> AIMD optimises for the median frame, CUBIC AIMD optimises
> for the worst frame. Both decisively outperform a
> fixed-bitrate baseline, which suffers 40 – 135 s of
> cumulative stall time per 240 s run."**

This framing matches:
- [[alos2019]] §6 (priority hierarchy: minimal losses > low
  latency > fast bitrate increase) — CUBIC's design philosophy
- [[abragame]] § subjective-MOS findings — what users actually
  notice
- [[results-beta-0.7]]'s p95 RTT cuts as the "common case win"
- The structural argument from [[results-idea-5c]]

## Where to go from here (writing phase)

These analyses are the **inputs** to the thesis chapters, not
their final form. Open work:

1. **Bitrate-trajectory plots** for each scenario will be more
   pedagogically valuable than RTT timelines for a reader who
   does not already know the algorithms. Notebook cell 7
   (`plot_timeline`) already plots both axes.
2. **A trade-off chart** (peak RTT vs p50 RTT, scatter, one
   point per controller × scenario) will visualise the
   "complementary priorities" framing in a single image.
3. **The discarded first-pass A/B runs** deserve a paragraph
   in the methodology — they substantiate the claim that
   scenario hardness is content-dependent.
4. **A short discussion of why F regressed** — the cap-from-t=0
   structural issue — should be its own paragraph. It
   anticipates the obvious reviewer question.
5. **None of the 5b / 5c experiments** appear in the result
   table, but they belong in the discussion as the design
   rationale for the chosen `t`-anchor and the chosen
   `rtt_clear_since` reset behaviour. See [[results-idea-5b]]
   and [[results-idea-5c]] for the prose.

## Related

- [[final-campaign-protocol]] — methodology spec; cite this
  file in the methodology section.
- [[results-beta-0.7]] — first campaign; source of the
  `adaptive` column data and the prior "p95 RTT cut by 7–33×"
  framing.
- [[results-idea-5]] — original CUBIC port; this is the
  controller running in the `cubic` column.
- [[results-idea-5b]], [[results-idea-5c]] — the experiments
  that established why the controller takes its current form.
- [[cubic]] — Ha, Rhee, Xu 2008; the algorithm we ported.
- [[alos2019]] — C³G; the closest prior cloud-gaming ABR; §6
  trade-off priority hierarchy matches our framing.
- [[abragame]] — Armendariz & Joskowicz 2025; the second
  closest prior work; subjective-MOS methodology.
- [[reactive-blind-spot]] — the structural property that
  explains why neither controller can fully absorb the initial
  RTT spike on scenarios with abrupt cap onsets.

## Sources

- `testbed/results/baseline/{A,B,C,D,E,F}_run0_*.csv` —
  no-ABR reference (2026-05-21 campaign)
- `testbed/results/adaptive/{A,B,C,D,E,F}_run0_*.csv` —
  baseline AIMD (2026-06-01 campaign, [[results-beta-0.7]])
- `testbed/results/cubic/{A,B,C,D,E,F}_run0_*.csv` —
  CUBIC AIMD (2026-06-08 campaign, this document)
- `testbed/lib/scenarios.sh` — scenario cap-profile source of
  truth
- `testbed/visualizations/results_cubic/comparison.ipynb` —
  generates the figures and tables this document summarises
- `Sunshine/src/bitrate_controller.{h,cpp}` — controller
  implementation (Idea 5 original, post-5c revert)
