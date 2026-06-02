# Network Scenarios — ABRAGame-shaped, Bandwidth-limited

Six scenarios adapted from Armendariz & Joskowicz (2025), Section 4, plus a
clean baseline. We preserve the **temporal shapes** of the paper's scenarios
(abrupt drop + recovery, gradual decline, intermittent fluctuations, etc.) and
apply them to **bandwidth caps** via `tc htb` — the impairment an adaptive
bitrate controller is actually designed to handle.

Each scenario lasts **240 s**. Baseline encoder target: **~19 Mbps** (18988 kbps
— the value Sunshine negotiates from a 25 Mbps client bitrate slider).

## Why bandwidth (and not loss)

An adaptive bitrate controller's job is to **match the send rate to available
bandwidth**. That makes the impairment choice central:

- Under **uniform random loss**, lowering the bitrate barely helps — loss
  percentage is independent of send rate. The controller has nothing to
  optimize, and could even drop bitrate for no benefit.
- Under **bandwidth constriction**, loss and latency become a *function of* the
  bitrate: overshoot the cap and the bottleneck queue fills, inflating RTT and
  send latency. Dropping the bitrate directly fixes it. **This is the regime
  ABR exists for.**

An earlier version of this testbed used packet loss (see [[research-journey]],
Stage 5). The reason was a measurement limitation: the only sensor at the time
(`SS_FRAME_FEC_STATUS`) reacted to loss but not to bandwidth shaping — so the
experiment was reshaped around what the sensor could detect. With `rtt_ms` and
`frame_send_ms` now in the CSV, bandwidth constriction produces a real, graded
signal (queueing delay inflates RTT). So the testbed returns to bandwidth-shaped
scenarios. The TCC report should disclose this divergence transparently.

## Bandwidth profiles

```
                Cap (Mbps)
            free ┤  clean ───────────────────────────────────
              25 ┤
              16 ┤  B      ───╲
              14 ┤  C      ─────╲___
              12 ┤  B          ╲___
              10 ┤  C / D      ────────────  D toggles every 30 s
               8 ┤  A / B  ─┐   ╲___────────┐
               6 ┤  F      ─────────┐       │
               4 ┤  E      ──────╲__________│____  (worst case)
                 └──────────────────────────────────────────────
                 0s        60s       120s      180s      240s
```

(Schematic. The "good"/recovered state is **unshaped** — `htb` set to a rate far
above the 20 Mbps target. Degraded states apply the caps below.)

## Definitions

The negotiated target is ~19 Mbps, so every degraded cap sits **below** it — the
controller always has work to do.

| ID | Description | Bandwidth profile |
|----|-------------|-------------------|
| **clean** | No impairment | unshaped throughout |
| **A** | Abrupt drop + rapid recovery | unshaped → **8 Mbps** (80–160 s) → unshaped |
| **B** | Gradual decline + fast recovery | step ramp 16 → 12 → **8 Mbps** (60–160 s) → unshaped |
| **C** | Slow decline + fast recovery | step ramp 14 → **10 Mbps** (40–200 s) → unshaped |
| **D** | Intermittent fluctuations | toggle unshaped / **10 Mbps** every 30 s |
| **E** | Long heavy constriction + abrupt recovery | unshaped → **4 Mbps** (40–200 s) → unshaped (worst case) |
| **F** | Low start + late improvement | **6 Mbps** (0–160 s) → unshaped |

Caps span ABRAGame's qualitative severity ranking:
- "Mild congestion" (C, D) → ~10–14 Mbps
- "Moderate degradation" (A, B, F) → ~6–8 Mbps
- "Severe stress" (E) → 4 Mbps

## tc commands

Keep one `htb` class present for the whole run and drive every transition with
`tc class change` — atomic, no traffic interruption.

```bash
# Setup at the start of a run (unshaped: rate far above the target)
sudo tc qdisc replace dev eno1 root handle 1: htb default 1
sudo tc class replace dev eno1 parent 1: classid 1:1 htb rate 1000mbit

# Optional: a fixed base latency ("distance" to the server)
sudo tc qdisc replace dev eno1 parent 1:1 handle 10: netem delay 15ms

# Enter a degraded state (example: 8 Mbps)
sudo tc class change dev eno1 parent 1: classid 1:1 htb rate 8mbit

# Return to the good state
sudo tc class change dev eno1 parent 1: classid 1:1 htb rate 1000mbit

# Tear down at the end of the run
sudo tc qdisc del dev eno1 root
```

Shape **egress** of the server's interface — that is the video path; no `ifb`
needed. Find the interface with `ip route get <client-ip>`. Verify shaping with
`iperf3 -u` and inspect queue stats with `tc -s qdisc show dev eno1`.

## Per-scenario expected behavior (fixed-bitrate baseline)

| Scenario | Expected pattern |
|----------|------------------|
| clean | Stable RTT at baseline, low `frame_send_ms`, no IDR storm. High MOS. |
| A | Calm for 80 s, then the cap drops to 8 Mbps: RTT inflates, `frame_send_ms` rises, the queue fills, IDR storm, visible stutter. Recovers at 160 s. |
| B | RTT inflates gradually from 60 s as the cap steps down; peaks 120–160 s; abrupt recovery. |
| C | Slow, sustained RTT inflation across the long 40–200 s ramp. |
| D | RTT oscillates in sync with the 30 s toggles; gameplay alternates good/degraded. |
| E | Heavy sustained RTT inflation 40–200 s at 4 Mbps « ~19 Mbps target. **Risk: the session may disconnect.** Partial CSVs are acceptable and informative. |
| F | High congestion for the first 160 s; sudden relief after recovery. |

If the baseline does not roughly match these patterns, something is wrong —
wrong interface for `tc`, Moonlight not connected, or Sunshine not exporting.

## E disconnect risk — feature, not bug

E is the most aggressive scenario (4 Mbps for 160 s against a ~19 Mbps target).
Under fixed bitrate the encoder keeps overshooting the cap, the queue overflows,
and Moonlight's heartbeat may time out mid-run. **This is informative:**

- Without an adaptive controller, severe constriction can kill the session.
- With the controller (PR #2), the bitrate should drop fast enough to keep the
  session alive at reduced quality.

Defense narrative: "in scenario E the baseline disconnected at ~T s; with the
adaptive controller the session survived the full 240 s at reduced quality."

## Latency: now the primary signal

Earlier this testbed dropped latency from the scenario design. That is reversed:
**RTT is the controller's primary input signal.** Two latency components:

- **Base latency** — added with a `netem delay` child of the `htb` class
  (the optional command above). It models server "distance" and is constant.
- **Queueing latency** — arises *naturally* when the send rate exceeds the
  `htb` cap. This is the variable part the controller reads as RTT inflation,
  and it is produced by the bandwidth caps themselves — no extra `tc` knob.

So the bandwidth profiles already generate the latency signal; the `netem
delay` child only sets a realistic baseline above which inflation is measured.

## What we do not vary

`tc netem` also supports jitter, corruption, reordering, duplication, and
random loss. This campaign uses **only bandwidth shaping** (plus an optional
fixed base delay):

- Keeps the campaign tractable (7 scenarios × 3 runs × 2 controllers).
- Matches the impairment the controller is designed to handle.
- Avoids confounding effects.

Random loss specifically is out of scope as a primary impairment — see
[[research-journey]], Stage 5. Expanding the scenario matrix (jitter, mixed
loss + bandwidth) is future work.
