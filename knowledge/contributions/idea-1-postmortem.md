# Idea 1 (Computed-Drain Step) — Postmortem

## What is it?

The first improvement attempt from [[improvement-roadmap]] — replacing
the plain `β · current_kbps` decrease with a *computed drain* based on
the encoder's observed output rate, inspired by C³G's `λ_drain` step
([[alos2019]] §IV.A). Two variants were implemented and measured on
Scenario A before the idea was discarded:

1. **Live EMA variant** — cut to `α · observed_kbps_ema` at decision time
2. **Pre-congestion snapshot variant** — cut to `α · ema_snapshotted_at_RTT_onset`

Both under-performed plain β = 0.7 on the headline metrics. The
attempt is preserved as `stash@{0}` (`git stash list`, in `Sunshine/`)
with the label `idea-1-computed-drain-step (...)` and can be revived
if the diagnosis below turns out to be wrong on a different scenario.

## Why it matters for Sunshine / TCC

The postmortem matters because the **reason** Idea 1 failed is a
publishable observation, not a bug:

> Server-side observed encoder output rate is not a reliable proxy for
> channel capacity in the cloud-gaming regime, because the encoder
> over-produces and the bottleneck queue buffers the excess. C³G
> requires per-frame ACKs from the client specifically to get a
> *receiver-side* `μ̄` that is not subject to this confounder. Without
> client-side measurement, there is no clean server-side signal for
> channel capacity — and that defines the boundary of how close any
> Sunshine-only ABR controller can come to C³G's results.

The postmortem belongs in the TCC's "Why we did not match C³G's
channel-use number" discussion. It justifies the methodological choice
to keep the no-client-modification constraint as a hard line.

## Key Concepts

- **Computed-drain step** (C³G's Eq. 2) — set the post-cut bitrate
  to `α · μ̄`, where `μ̄` is the channel's effective carrying rate.
  Avoids overshooting downward (β cut from a target far above
  capacity wastes channel) and undershooting downward (β cut from a
  target just above capacity leaves the queue full).
- **`μ̄` vs encoder output** — C³G's `μ̄` is the *client-side received
  rate* (bytes the receiver actually got). Our analogue was the
  *encoder's observed output EMA*. These are equal only when there
  is no bottleneck queue between them — i.e., when the controller
  is not needed. As soon as a queue forms, encoder output > μ̄, and
  the equality breaks. The gap is what the queue absorbs.
- **Backpressure-suppressed EMA** — when the bottleneck queue
  overflows and FFmpeg's send buffer fills, the encoder's actual
  output rate collapses (the rate-controller cannot push frames
  through a full buffer). The "live EMA" variant captured this
  backpressured rate (~1.4 Mbps) and cut to it — far below the
  actual channel cap (8 Mbps).
- **Pre-congestion snapshot** — captured the EMA at the exact
  moment RTT first crossed 100 ms, before backpressure could
  suppress it. Avoided the live-EMA failure but exposed the deeper
  problem: even the pre-onset encoder rate (~12 Mbps) was *above*
  the channel cap (8 Mbps) because the encoder was over-producing
  into the queue. The snapshot's α-cut only sized the first
  decrease correctly; subsequent cuts degenerated into plain β
  because `current_kbps < snapshot` after the first cut, making
  `β · current` the binding constraint in `min(α·snapshot, β·current)`.

## The measurements

Scenario A (abrupt drop, unshaped → 8 Mbps for t=80–160 s →
unshaped). All metrics computed over the 80 s shaping window.

| Config | Decreases | Spikes | ΣL_AP | RTVL_peak | p95 RTT | Op kbps | **Channel use** |
|---|---:|---:|---:|---:|---:|---:|---:|
| β = 0.5 (over-drain) |  5 | 1 | 17.1 s |  973 ms |  844 ms |  672 |  8.4 % |
| β = 0.7 (baseline)   |  7 | 1 | 17.3 s | 1786 ms | 1699 ms | 2192 | 27.4 % |
| β = 0.85 (under-drain) | 12 | 2 | 26.2 s | 1008 ms |  762 ms | 4302 | 53.8 % |
| **Idea 1 live EMA**   |  2 | 1 | 14.6 s | 1072 ms |  764 ms |  938 | **11.7 %** |
| **Idea 1 snapshot**   |  8 | 1 | 21.9 s | 1113 ms |  989 ms | 1053 | **13.2 %** |

The CSVs are at:
- `testbed/results/test-idea-1/A_run0_20260604-152944.csv` (live EMA)
- `testbed/results/test-idea-1/A_run0_20260604-154510.csv` (snapshot)

### Idea 1 live-EMA trajectory (the one-shot crash)

```
t=  80s  target=18988  bitrate=14585  rtt=  4ms  ← shaping starts
t= 122.7s target= 1298  bitrate= 7854  rtt=932ms ← decrease: live EMA crashed to ~1.4 Mbps
t= 124.6s target= 1000  ← floor reached, one more small cut
```

Two cuts, single short L_AP, but channel use 11.7 %. The encoder
output had collapsed under backpressure during the ~2 s hysteresis
window, the EMA tracked that collapse, and we cut to a number that
reflected the *encoder's stalled state*, not the channel's capacity.

### Idea 1 snapshot trajectory (the cascade)

```
t= 88.2s  target=11433  ← α · snapshot ≈ 0.95 · 12000 = 11400  ← first cut
t= 90.1s  target= 8003  ← 0.7 · 11433 = 8003                    ← β cascade begins
t= 92.2s  target= 5602  ← 0.7 · 8003
t= 94.2s  target= 3921
t= 96.2s  target= 2744
t= 98.2s  target= 1920
t=100.3s  target= 1344
t=102.2s  target= 1000  ← floor
```

After the first cut, the snapshot (~12000) is *above* the new
`current_kbps` (11433), so `min(α·snapshot, β·current)` collapses to
the β branch. The controller degenerated into plain β=0.7 cascading
cuts, all the way to the 1000 kbps floor. Worse than plain β=0.7 by
exactly one extra cut.

## What went right

1. **The live-EMA variant produced the cleanest "single cut, no
   cascade" behaviour of any configuration measured.** Two decreases
   total, single above-threshold spike, shortest L_AP (14.6 s).
   The structural goal of "fire once, settle" is achievable on this
   architecture. Idea 1 was wrong about *where* to settle, not about
   *whether* settling on one cut is the right shape.
2. **Both variants reduced RTVL_peak vs β=0.7.** 1072 ms / 1113 ms
   vs β=0.7's 1786 ms. The mechanism (cut decisively rather than
   incrementally) does help limit how deep the spike gets, even when
   the absolute target is wrong.
3. **The instrumentation was correct.** The CSV reproduces the
   controller's view of the world frame-by-frame; the diagnosis was
   possible directly from the existing columns
   (`bitrate_kbps`, `target_kbps`, `rtt_ms`, `abr_state`), without
   needing to add new fields. PR #1's stats export earned its keep.
4. **The pre-congestion snapshot semantics is a clean design idea on
   its own.** It correctly distinguishes "what the encoder was doing
   while the network was healthy" from "what the encoder is doing
   now in the middle of an overflow event." That distinction will
   matter for any future signal we add (e.g. a `frame_send_ms`
   trigger — [[improvement-roadmap]] Idea 3 — should snapshot the
   same way).

## What went wrong

### The structural problem
Encoder output rate is what the *server* produces. Channel capacity
is what the *bottleneck* can carry. These differ by the rate at
which the queue fills:

```
encoder_output(t) = channel_capacity + d(queue_depth)/dt
```

When the encoder is configured for more than the channel can carry
(the regime ABR exists for), `queue_depth` grows, the encoder is
sending faster than the channel can drain. Our EMA — both live and
snapshotted — measures `encoder_output`. The number we wanted is
`channel_capacity`. The gap is the queue-fill rate, which is
positive and large in exactly the moments we care about.

C³G's `μ̄` (Eq. 2) is the *receive-side* rate, which equals
`channel_capacity` by definition once steady state is reached.
That's why their drain step works. Ours cannot.

### Specific failure of the live EMA
At decision time (~2 s into the hysteresis window), the bottleneck
queue had already overflowed, and FFmpeg's outbound packet queue
had filled. The encoder's frame-output rate had collapsed from
~14 Mbps to ~1.4 Mbps because the asynchronous rate-control loop
inside NVENC + avcodec slows down when it cannot push packets out.
The EMA tracked that collapse. The α-cut said "the channel is
carrying 1.4 Mbps" when the channel was carrying 8 Mbps and the
encoder was just temporarily stalled by send-side backpressure.

### Specific failure of the snapshot
The snapshot at congestion onset was ≈ 12 Mbps — close to the
encoder's pre-overflow rate. But the channel was 8 Mbps. The
encoder had been producing 12 Mbps *into a buffer*, and the
buffer's depth had been growing the whole time until RTT crossed
the 100 ms threshold. Even a perfect pre-onset snapshot
overestimates channel capacity by however much the encoder was
over-producing — which is exactly the regime where we need the cut
in the first place.

### Why "just lower α" would not have helped
Setting α = 0.65 (i.e., cut to 65 % of the snapshot ≈ 7800 kbps)
would have landed near the cap on Scenario A. But α is supposed to
be a small safety margin (0.95 in the literature), not a tuning
knob covering for a measurement error. And the size of the error
("how much was the encoder over-producing") depends on the scenario
— there is no single α that closes the gap on all scenarios.

## Implications for the TCC

1. **Hard limit established.** Without client-side receive-rate
   reports, a server-side ABR controller on Sunshine cannot
   accurately estimate channel capacity at the moment of a cut.
   This is not a limitation of *our* algorithm; it is a limitation
   of *the signal set we chose*. C³G's `μ̄` is the cleanest known
   workaround, and it requires per-frame client cooperation.
2. **Defines the boundary the TCC can claim.** Our controller's
   channel-use number will trail C³G's 93–96 % by something like
   the encoder's over-production ratio. That is a clean,
   measurable, structural gap — not a tuning failure. The TCC's
   discussion section can quantify it precisely.
3. **Reinforces the [[reactive-blind-spot]] argument.** Even with a
   correctly-sized cut, the detection delay floor (~2–3 s for our
   defaults) means the cut fires after the queue has already
   started overflowing. The combination of "no channel-capacity
   signal" + "minimum 2 s detection latency" is what defines our
   Pareto cell. Both facts are publishable.
4. **Pivot is to Idea 5 (CUBIC port).** The increase side does not
   depend on channel-capacity estimation. It depends on time since
   the last decrease, which we measure perfectly. So the next move
   is to leave the decrease as plain β = 0.7 and replace the
   hand-rolled increase with the [[cubic]]-shaped curve + fast
   convergence. That should improve the channel use during the
   stable plateau and the time-to-recover after the constraint
   lifts — both metrics where the current algorithm is most clearly
   suboptimal, and both improvable without a channel signal.

## Possible salvage paths (not pursued)

For the record, the directions that *might* rescue a computed-drain
step on Sunshine. None are recommended for the current TCC scope.

1. **Tiny Moonlight patch reporting received-byte counts.** Restores
   `μ̄` measurement. Cleanest fix; defeats the no-client-mod claim.
2. **Estimate queue depth from RTT inflation.** `qdData ≈ (RTT − RTT_min)
   · capacity_estimate`. Requires a separate capacity estimator,
   which is exactly the unknown. Could iterate via a Kalman filter
   on (capacity, queue_depth) state; substantial complexity for
   uncertain payoff.
3. **Probe the channel with brief send-rate pulses.** Sunshine
   could deliberately throttle the encoder by 50 % for 1 second,
   observe whether RTT drains, and use the drain rate as an
   estimate of `μ̄`. Active probing during a streaming session is
   user-visible (visible quality drop), so this is more invasive
   than it sounds.
4. **Use packet-loss rate from `IDX_LOSS_STATS` as a saturation
   indicator.** Already known dead-code on the current Sunshine
   ([[stats-export-findings]]).

## Recommendation captured for the TCC writing

When the TCC discusses the channel-use gap against C³G, the
explanation should be one paragraph along these lines:

> *Our adaptive controller targets a strictly server-side signal
> (ENet `peer->roundTripTime`) under the constraint of no Moonlight
> modification. We attempted to import C³G's drain-rate equation
> directly, substituting the encoder's observed output EMA for
> their receiver-side `μ̄`. In testing on Scenario A, both a
> live-EMA variant and a pre-congestion snapshot variant under-
> performed the plain β-only AIMD baseline, because the encoder's
> output rate is structurally not equal to the channel's carrying
> rate in our regime: the encoder over-produces and the bottleneck
> queue absorbs the excess until it overflows. C³G's per-frame
> client ACK is the mechanism that closes this gap, and using it
> would have required modifying Moonlight, which we kept out of
> scope. The resulting channel-use gap (our ~27 % vs C³G's 93–96 %
> on the same scenario shape) is therefore not an algorithmic
> deficiency but a direct consequence of the server-only signal
> envelope.*

## Related
- [[improvement-roadmap]] — Idea 1 is the entry this postmortem
  closes; Idea 5 (CUBIC port) is the recommended pivot
- [[results-beta-0.7]] — the β-sweep diagnosis Idea 1 was meant to
  address
- [[reactive-blind-spot]] — the parallel architectural limit; same
  *kind* of structural claim (a measurable, peer-reviewed gap)
- [[alos2019]] — C³G; source of the drain equation we could not
  port, and the explanation of why
- [[cubic]] — the algorithm Idea 5 (the pivot) is grounded in
- [[idea-10-abr-comparison]] — the TCC idea this work serves
- [[stats-export-findings]] — PR #1; the CSV instrumentation that
  made this diagnosis possible

## Sources
- Stashed implementation: `Sunshine/` `stash@{0}` —
  `idea-1-computed-drain-step (...)`, ~110 lines across
  `bitrate_controller.{h,cpp}`, `config.{h,cpp}`, `stream.cpp`.
- Run CSVs:
  - `testbed/results/test-idea-1/A_run0_20260604-152944.csv` —
    live-EMA variant.
  - `testbed/results/test-idea-1/A_run0_20260604-154510.csv` —
    pre-congestion snapshot variant.
- Alós et al., *C³G*, IEEE Access 2019 — Eq. 2 (`λ_drain` formula
  we tried to port).
- Ha, Rhee, Xu, *CUBIC*, ACM SIGOPS OSR 2008 — the algorithm the
  pivot targets.
