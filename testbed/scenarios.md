# Network Scenarios — ABRAGame-shaped, Loss-based

Six scenarios adapted from Armendariz & Joskowicz (2025), Section 4, plus a clean baseline. We preserve the **temporal shapes** of the paper's scenarios (abrupt drop + recovery, gradual rise, intermittent fluctuations, etc.) but apply them to **packet loss percentage** instead of bandwidth caps.

Each scenario lasts **240 s**.

## Why loss instead of bandwidth (methodology divergence)

ABRAGame's adaptive controller responds to **cumulative latency** as its primary signal. Bandwidth caps via `tc netem rate` naturally produce queueing delay, so their methodology — bandwidth-shaped scenarios — generates the signal their controller needs.

Our PR #1 captures `SS_FRAME_FEC_STATUS` events. These fire when:
1. FEC recovery succeeds
2. A frame is discarded for arriving late
3. A frame is discarded for block mismatch

All three are **loss-triggered**, not throughput-triggered. Smoke testing confirmed empirically that `tc netem rate 5mbit` against a 15 Mbps stream produces visible gameplay degradation (heavy stutter, eventual Moonlight disconnect) but **zero FEC events** before the session collapses — the queue overflow pattern fragments frames in a way that does not trigger `reportFinalFrameFecStatus` on the client.

So we pivoted: same temporal shapes from the paper, applied to `tc netem loss X%`. This deterministically generates FEC events that PR #2's controller can respond to. The TCC report should disclose this divergence transparently.

## Loss profiles

```
                Loss %
                 7  ┤  E     ─┐                              ┌─
                 5  ┤  A     ─────────┐        ┌───────────────
                    ┤  F     ╲                 ┌──────────────
                 3  ┤  D     ─╲╱─╲╱─╲╱─╲╱─╲╱─╲╱─╲╱─╲╱─╲╱─╲╱
                    ┤  B     ─────────────┐ ┌─
                 2  ┤                       │
                 1  ┤  C     ──────╲
                 0  ┤  clean ──────────────────────────────────
                    └────────────────────────────────────────────
                    0s        60s       120s      180s     240s
```

(Schematic. Step ramps approximate the paper's "gradual" with discrete loss transitions.)

## Definitions

| ID | Description | Loss profile |
|----|-------------|--------------|
| **clean** | No impairment | 0% throughout |
| **A** | Abrupt spike + rapid recovery | 0% → **5%** (80–160 s) → 0% |
| **B** | Gradual rise + fast recovery | step ramp 0 → 1 → 2 → 3 → **5%** (60–160 s) → 0% |
| **C** | Slow rise + fast recovery | step ramp 0 → 1 → 2 → **3%** (40–200 s) → 0% |
| **D** | Intermittent fluctuations | toggle 0% / **3%** every 30 s |
| **E** | Long heavy loss + abrupt recovery | 0% → **7%** (40–200 s) → 0% (worst case) |
| **F** | High-loss start + late improvement | **5%** (0–160 s) → 0% |

Loss values were chosen to span ABRAGame's qualitative severity ranking:
- "Mild congestion" (C, D) → 1–3%
- "Moderate degradation" (A, B, F) → 5%
- "Severe stress" (E) → 7%

## tc commands per state

```bash
# Clean / good phase
sudo tc qdisc del dev eno1 root

# Light loss (e.g., D toggle low, C ramp early)
sudo tc qdisc replace dev eno1 root netem loss 1%

# Moderate loss (A, B, F bad phases)
sudo tc qdisc replace dev eno1 root netem loss 5%

# Heavy loss (E worst case)
sudo tc qdisc replace dev eno1 root netem loss 7%
```

`tc qdisc replace` is idempotent — works whether or not a qdisc is already present, and swaps atomically without traffic interruption.

## Per-scenario expected behavior (fixed bitrate baseline)

| Scenario | Expected pattern |
|----------|------------------|
| clean | Zero or near-zero FEC events. Smooth gameplay. |
| A | Quiet for the first 80 s, then burst of FEC events from 80–160 s, then quiet again. Visible stutter at the 80 s transition. |
| B | Slow ramp-up of events from 60 s onwards, peaking 120–160 s, then sudden quiet. |
| C | Slow buildup of events from 40 s onwards; sustained mid-rate events throughout the long ramp. |
| D | Small bursts of events synced with the high-loss segments. Gameplay alternates between good and degraded. |
| E | Heavy event load from 40–200 s. **Risk: Moonlight session may disconnect** under sustained 7% loss. Partial CSVs are acceptable and informative (the script auto-marks them with `_partial-Ns`). |
| F | High event rate for the first 160 s; sudden quiet after recovery. |

If the baseline doesn't roughly match these patterns, something is wrong — wrong interface for tc, Moonlight not connected, Sunshine not exporting metrics, etc.

## E disconnect risk — feature, not bug

E is the most aggressive scenario (7% loss for 160 s). Under fixed bitrate, Moonlight's heartbeat may time out and the session may disconnect mid-run. **This is informative, not a defect:**

- Without an adaptive controller, severe sustained loss can kill the session
- With an adaptive controller (PR #2), the bitrate should drop fast enough to keep the session alive

The narrative for the TCC defense: "in scenario E, the baseline session disconnected at ~T seconds; with the adaptive controller, the session survived the full 240 s at reduced quality." If E does not disconnect, we still have comparison data; if it does, the contrast is stronger.

## What about latency?

ABRAGame's scenarios D and F added +50 ms latency in the bad phases. We dropped that:

- ABRAGame uses latency as their controller's input signal — adding it makes sense for them.
- Our PR #1 does not capture latency. Adding `tc netem delay` would not affect the data we collect, only the subjective playability rating.
- Keeping the testbed focused on what produces signal in our CSV simplifies analysis.

If a reviewer asks about latency-only conditions, we can run an ad-hoc scenario with `tc netem delay 200ms` to record the subjective rating, but it's out of scope for the 21-run campaign.

## What about packet jitter / corruption / reordering?

`tc netem` supports loss, delay, jitter, corruption, reordering, duplication. We use **only `loss`** in this campaign:

- Keeps the campaign tractable (7 scenarios × 3 runs is already 2–3 hours)
- Matches the failure mode our sensor detects
- Avoids confounding effects (e.g., reordering can trigger our FEC pathway too, but with different statistics)

Future work could expand the scenario matrix.
