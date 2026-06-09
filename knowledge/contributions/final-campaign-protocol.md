# Final Campaign Protocol — Baseline AIMD vs CUBIC AIMD

## What is it?

The methodology specification for the TCC's final comparative
campaign. The campaign produces the central empirical result of
the thesis: a six-scenario comparison of two adaptive bitrate
controllers (plus a non-adaptive reference), evaluated on the same
Sunshine build and the same network testbed.

This document is the single source of truth for what was tested,
which code state was running, where the CSVs live, and how results
are to be reported. The thesis methodology section will reference
this file rather than re-deriving the protocol from chat logs.

## Why it matters for Sunshine / TCC

The TCC's argument is that **a simple AIMD controller augmented
with one peer-reviewed primitive (CUBIC fast convergence) and a
peer-reviewed recovery shape (CUBIC cubic curve) outperforms a
hand-rolled two-phase AIMD on the metric that matters most for
cloud gaming (peak RTT during sustained constraint), without
requiring client-side cooperation or per-frame video latency
estimation as in [[alos2019]]**.

To make that argument defensibly, the final-result table needs:

- A non-adaptive reference (so reviewers can see ABR is doing
  anything at all).
- The pre-CUBIC adaptive controller (so reviewers can see CUBIC
  is doing something on top of plain AIMD).
- The CUBIC controller (the contribution).

All three over the same six scenarios on the same testbed, with
the same Sunshine build chain otherwise. This file pins that
configuration down.

## The three controllers

| Label | Directory | What it is | Code state |
|---|---|---|---|
| **No-ABR (reference)** | `testbed/results/baseline/` | Fixed bitrate, no controller logic. Sunshine's default behaviour with `bitrate_mode = static`. | Pre-controller commit / `static` mode. |
| **Baseline AIMD** | `testbed/results/adaptive/` | β = 0.7 multiplicative decrease, two-phase increase (`×γ` then `+step_kbps`), `last_known_good` never reduced. The version from [[results-beta-0.7]]. | Sunshine commit just before Idea 5 landed; `bitrate_mode = adaptive`, `abr_beta = 0.70`. |
| **CUBIC AIMD** | `testbed/results/cubic/` (to be created) | β = 0.7 multiplicative decrease with CUBIC fast convergence (Eq. 3.7); cubic recovery curve `B(t) = C · (t − K)³ + last_known_good` with `K = 15 s`, `t` anchored at `last_decrease_at`. The Idea 5 implementation from [[results-idea-5]] after reverting 5b and 5c. | Sunshine post-5c revert; `bitrate_mode = adaptive`, `abr_beta = 0.70`, `abr_cubic_recovery_ms = 15000`, `abr_fast_convergence = true`. |

The 5b and 5c iterations ([[results-idea-5b]], [[results-idea-5c]])
are **not** part of the final campaign. They appear in the thesis
as the experiments that establish why the CUBIC AIMD implementation
takes the form it does — specifically, why `t` is anchored at
`last_decrease_at` and why `rtt_clear_since` is reset on successful
growth ticks.

## Scenarios

All six scenarios from the prior campaign, unchanged:

| Scenario | Shape | Cap | Window |
|---|---|---|---|
| A | abrupt drop | 8 Mbps | t = 80–160 s |
| B | (per testbed) | (per testbed) | (per testbed) |
| C | (per testbed) | (per testbed) | (per testbed) |
| D | (per testbed) | (per testbed) | (per testbed) |
| E | long heavy constriction | 4 Mbps | t = 40–200 s (160 s shaping) |
| F | (per testbed) | (per testbed) | (per testbed) |

(Scenarios B, C, D, F definitions are stored in the testbed shaping
scripts; do not re-derive them here. The thesis methodology section
will paste the script's authoritative definitions.)

## Runs per cell

One run per `(controller, scenario)` cell — **18 runs total** for
the CUBIC AIMD column. The non-adaptive and baseline AIMD columns
are *reused from the existing* `baseline/` *and* `adaptive/`
*directories* and are **not** re-gathered, because (a) the prior
campaign showed low between-run variance and (b) re-running them
would not change their published numbers.

This is a deliberate methodological choice: the thesis says
*"we re-ran the contributed controller fresh; we relied on the
prior campaign data for the two reference columns, on the basis of
demonstrated low variance"*, and we own that limitation in the
discussion.

## Per-run configuration (CUBIC AIMD column)

```
capture = x11
stats_export_path = /home/cesarpmorais/code/ufmg/tcc/data/metrics
bitrate_mode = adaptive
abr_beta = 0.70
abr_cubic_recovery_ms = 15000
abr_fast_convergence = true
```

Sunshine binary: built from the post-revert tree (Idea 5 original)
at the commit recorded at the start of the campaign. The exact SHA
will be pinned in this file once the campaign begins.

## Output layout

```
testbed/results/cubic/
    A_run0_<timestamp>.csv          // shaping window 80–160 s
    A_run0_<timestamp>.notes.txt    // subjective ratings, gameplay note
    B_run0_<timestamp>.csv
    B_run0_<timestamp>.notes.txt
    C_run0_<timestamp>.csv
    C_run0_<timestamp>.notes.txt
    D_run0_<timestamp>.csv
    D_run0_<timestamp>.notes.txt
    E_run0_<timestamp>.csv          // shaping window 40–200 s
    E_run0_<timestamp>.notes.txt
    F_run0_<timestamp>.csv
    F_run0_<timestamp>.notes.txt
```

The `.notes.txt` files must record `rating_latency`,
`rating_quality`, `rating_stability` (each on the testbed's
established scale) and a short free-form gameplay note. These
ratings are part of the final result and will be reported in the
thesis. (The 1 / 1 / 1 ratings on the 5b / 5c iteration runs are
**not** part of the final result — they were exploratory tests and
the user has flagged them as not to be counted; see
[[results-idea-5b]] and [[results-idea-5c]].)

## Metrics reported in the final table

Per `(controller, scenario)` cell:

- **Peak RTT (ms)** — the headline metric; CUBIC AIMD's reason for
  existing
- **p95 RTT (ms)** — distribution-tail measure; matches the prior
  campaign's reporting in [[results-beta-0.7]]
- **p99 RTT (ms)**
- **Median (p50) RTT (ms)**
- **% time RTT > 100 ms** — share of the run spent above the
  congestion threshold
- **Average bitrate during shaping window (kbps)** — proxy for
  channel utilisation under constraint
- **Channel use (%)** — `avg_shaped / cap_kbps`; the C³G-style
  trade-off axis (lower is more conservative)
- **Subjective ratings** — latency / quality / stability per the
  testbed scale

For Scenario E specifically, the **peak-RTT reduction vs
baseline AIMD** is the single number the thesis will lead with.

## Analysis post-campaign

Once the `cubic/` directory is populated, the analysis script will
produce, per scenario, a side-by-side row containing the three
controllers' metrics. The script lives at (to be created)
`testbed/analyze_final.py` and is the same arithmetic as the
ad-hoc Python snippets used in [[results-idea-5]],
[[results-idea-5b]], and [[results-idea-5c]] — generalised to
read all six scenarios from all three directories.

## What is *not* in scope for the final campaign

- K sweep (only K = 15 s tested)
- Other β values (only β = 0.7 tested)
- Idea 1 / 2 / 3 / 4 from [[improvement-roadmap]] — these stay as
  documented future work in the thesis discussion
- Idea 5b / 5c implementations — these stay as documented closure
  iterations in the thesis discussion

## Related

- [[results-beta-0.7]] — the source of the `adaptive/` column data
- [[results-idea-5]] — the controller running in the `cubic/` column
- [[results-idea-5b]], [[results-idea-5c]] — the closure iterations
  that explain why CUBIC AIMD takes its final form
- [[improvement-roadmap]] — the broader idea space, of which only
  Idea 5 is taken to a campaign
- [[alos2019]] — the closest prior work; framing reference for
  peak-RTT-vs-channel-use trade-off

## Sources

- `Sunshine/src/bitrate_controller.{h,cpp}` — controller
  implementation
- `testbed/results/baseline/` — no-ABR reference data
- `testbed/results/adaptive/` — baseline AIMD reference data
- `testbed/results/cubic/` — CUBIC AIMD final data (to be created)
- Testbed shaping scripts — scenario definitions
