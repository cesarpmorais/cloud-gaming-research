# Paper Analysis: GCC — Google Congestion Control for WebRTC
**Carlucci, De Cicco, Holmer, Mascolo, 2016 — ACM MMSys'16**

The canonical delay-based congestion controller for real-time media. Shipped
in Chromium / WebRTC and used by Google Hangouts. Closest non-gaming analog
to what we are building, and the algorithm ABRAGame explicitly positions
against ("slope-based methods produce too many false positives").

---

## 1. Problem Framing

GCC adapts the sending rate of a real-time RTP/UDP video flow to keep
**queuing delay low** at the bottleneck while still achieving high link
utilization and fairness against both other GCC flows and concurrent loss-based
TCP flows. Designed for interactive video conferencing (WebRTC), where
buffering / retransmission are not options — same constraints as game
streaming.

Optimization priority is explicitly **delay over throughput** (delay-sensitive
flow), with a hard fairness requirement against TCP.

---

## 2. Input Signals

All signals are produced from RTP packets and RTCP feedback — no clock
synchronization between sender and receiver is required because GCC works on
the **one-way delay gradient** (a derivative), not absolute delay.

- **Inter-frame arrival gradient `d_m(t_i)`**: per video frame,
  `d_m(t_i) = (t_i − t_{i-1}) − (T_i − T_{i-1})`
  where `T_i` is send time of first packet of frame `i`, `t_i` is receive time
  of last packet of frame `i`. The constant clock offset cancels in the
  subtraction — this is why no NTP sync is needed.
- **Filtered delay gradient `m(t_i)`**: Kalman-filtered version of `d_m(t_i)`,
  reducing jitter noise. In the simplified scalar model the Kalman update is
  equivalent to an EWMA with adaptive gain.
- **Adaptive threshold `γ(t_i)`**: low-pass filtered envelope of `|m(t_i)|`.
  Adapts faster on the way up (`k_u`) than down (`k_d`) so concurrent TCP
  cannot starve the GCC flow.
- **Fraction lost `f_l(t_k)`**: from RTCP receiver reports, used by the
  loss-based sender-side controller as a safety net.

Not used: explicit bandwidth estimate, RTT, jitter variance directly,
buffer occupancy.

---

## 3. Algorithm / Approach

Two controllers running in parallel; the encoder is fed `A = min(A_r, A_s)`.

### Delay-based controller (at the receiver)

1. **Arrival-time filter (Kalman)** produces `m(t_i)` from frame arrivals.
2. **Over-use detector** compares `m(t_i)` against `±γ(t_i)`:
   - `m > γ` for >100 ms → `overuse`
   - `m < −γ` → `underuse`
   - otherwise → `normal`
3. **Remote rate controller FSM** (Decrease / Hold / Increase):
   - `overuse` → Decrease: `A_r ← α · R(t_i)`, **α = 0.85**, where `R` is
     measured receive rate over the last 500 ms (multiplicative decrease).
   - `underuse` → Hold.
   - `normal` → Increase: `A_r ← η · A_r(t_{i-1})`, **η = 1.05** (5%
     multiplicative increase per frame).
   - Cap: `A_r ≤ 1.5 · R(t_i)`.
4. **REMB** message ships `A_r` back to the sender every 1 s, or immediately
   if `A_r` drops by >3%.

### Loss-based controller (at the sender)

```
A_s(t_k) =
    A_s(t_{k-1}) · (1 − 0.5 · f_l)   if f_l > 0.10
    1.05 · A_s(t_{k-1})              if f_l < 0.02
    A_s(t_{k-1})                     otherwise
```

Loss kicks in only when delay-based signal is already saturated (typically
when sharing a small buffer with loss-based TCP). Otherwise the delay-based
controller dominates and `f_l ≈ 0`.

### Sending-rate actuation

The encoder targets `A = min(A_r, A_s)`. To smooth encoder rate flicker the
Pacer drains its queue at `f · A` with `f = 1.5`; when the encoder
under-produces, padding/FEC packets fill to `A`. So the on-the-wire rate
tracks `A` even though the encoder cannot retune every frame.

### Adaptive threshold (key design point)

`γ(t_i) = γ(t_{i-1}) + ΔT · k_γ(t_i) · (|m(t_i)| − γ(t_{i-1}))`,
with `k_γ = k_u` when `|m| > γ` and `k_d` otherwise. The authors fit
`(k_u, k_d) = (0.01, 0.00018)` via a Pareto optimization over throughput vs.
delay. A **static** threshold either ignores small delay gradients (large
buffer regime) or is starved by TCP — the adaptive form fixes both.

---

## 4. Evaluation Methodology

### Testbed
- 4 Linux machines (kernel 3.16) running Chromium with `v4l2loopback`
  feeding the "Four People" YUV test sequence into VP8.
- NetEm + Token Bucket Filter on a bottleneck node for capacity `C`, queue
  `T̄_q`, and one-way propagation delay (`RTT_min = 50 ms`).
- Cross-traffic from real CUBIC TCP flows (long-lived and short-lived).

### Metrics (RMCAT-aligned)
- Channel utilization `U = R_r / C`
- Loss ratio `l`
- 50th / 95th percentile queuing delay (`RTT(t) − RTT_min`)
- Jain's fairness index `J_FI`

### Scenarios
1. Single GCC, variable link capacity (1 / 2.5 / 0.5 / 1 Mbps, 50 s each).
2. 3 concurrent GCC over 3 Mbps (intra-protocol fairness).
3. 1 GCC vs 1 long-lived TCP CUBIC; 2 GCC vs short-lived TCP bursts.
4. GCC with reverse-path TCP (tests one-way delay assumption).

---

## 5. Key Results

| Scenario | Utilization | Queuing delay (p50 – p95) | Loss | Fairness |
|---|---|---|---|---|
| Single GCC, variable cap | 84% | 20 – 195 ms | 0.02% | — |
| 3 GCC, 3 Mbps | 86% | 10 – 61 ms | 0% | **0.93** |
| 2 GCC, variable cap | 85% | 15 – 103 ms | 1% | 0.87 |
| 1 GCC vs 99 TCP, 100 Mbps | GCC = 1.3 Mbps | 250 – 295 ms | 1.2% | 0.81 |
| 2 GCC + short-lived TCP | 72% | 109 – 285 ms | 0.7% | 0.78 |
| GCC + reverse TCP | 90% | 10 – 159 ms | 0% | — |

**Headline findings:**
- Tracks variable link capacity within ~25 s of an upward step.
- Adaptive threshold: reduces 95th-percentile RTT from 187 ms → 130 ms
  vs. static threshold, on the same 150 ms buffer.
- Adaptive threshold also prevents starvation by concurrent TCP.
- Reverse-path TCP **does not** corrupt the signal — the one-way delay
  gradient is direction-independent.

---

## 6. Game Streaming Specifics — What Transfers and What Does Not

### What transfers cleanly to Sunshine

- **Signal philosophy.** GCC validates the design instinct behind our TCC:
  use a **delay gradient** as the trigger, not an absolute threshold or a loss
  count. Queueing delay is the earliest, gradedest, server-observable signal
  of bandwidth constriction. ABRAGame's "cumulative one-way latency >
  threshold" trigger and our "RTT inflation" trigger are both
  approximations of GCC's `m(t)`.
- **Multiplicative decrease, additive/multiplicative increase.** GCC uses
  `α = 0.85` for decrease and `η = 1.05` for *per-frame* increase. The
  decrease constant is in the same ballpark as our `BETA = 0.7` (we are more
  aggressive because game streaming tolerates a hard cut better than a
  conference call). The per-frame increase rate is much faster than our
  per-window step — see "where we differ".
- **No clock sync required.** GCC's derivation of why one-way delay gradient
  cancels the clock offset is the formal justification for our RTT-based
  trigger. We use a different statistic (round-trip) but the same trick:
  differentiate to kill the constant offset.
- **Adaptive threshold idea.** The "raise the threshold faster than you
  lower it" trick (`k_u ≫ k_d`) is directly applicable to our RTT baseline
  EWMA. Worth porting as a future refinement to avoid being starved by
  competing traffic on a home Wi-Fi link.
- **Loss as a secondary backstop, not the primary signal.** Matches our
  research-journey finding that IDR-request rate (a loss proxy) saturates
  and is only useful as a confirmation signal.

### What does not transfer

- **Receiver-side controller.** GCC computes `A_r` at the receiver and ships
  REMB messages back. Sunshine cannot modify Moonlight, so all signal
  derivation and decision-making has to live on the server. This is the
  same constraint that forces us to use **RTT** instead of one-way delay —
  we cannot get per-frame `d_m(t_i)` without a client-side timestamp
  feedback channel.
- **Per-frame control loop.** GCC retunes the encoder rate every video frame
  (~30 Hz). Sunshine's NVENC reconfiguration cost on Linux (full
  AVCodecContext rebuild + forced IDR) is too high for that cadence — we
  measured 0 broadcast stalls but each transition is at minimum one IDR
  frame. Our controller runs on a ~1 s window aligned to ENet RTT updates;
  GCC-style 30 Hz adjustment is infeasible without the Windows
  `nvEncReconfigureEncoder()` fast-path.
- **Pacer + padding/FEC.** GCC separates the *encoder target rate* from the
  *on-the-wire rate* via a pacer that drains at `1.5 · A` and pads with FEC
  when the encoder under-produces. Sunshine does not have this layer — the
  on-the-wire rate is whatever NVENC emits. This means our controller must
  set the encoder bitrate directly (and accept that it will be noisier than
  GCC's actuated rate).
- **Adaptive threshold complexity.** GCC's Kalman filter + adaptive threshold
  + over-use FSM + remote rate FSM stack is substantially more complex than
  what fits in a 2-month TCC. We adopt the *shape* (delay-derived trigger,
  AIMD action) and explicitly defer the adaptive threshold as future work.
- **TCP fairness.** Game streaming is typically the only flow on a residential
  uplink during a play session. Multi-flow fairness is not a TCC requirement.

### One thing GCC suggests we should add to the evaluation

Channel utilization `U = R_r / C` as a first-class metric, **paired with**
queuing delay percentiles. ABRAGame's "effective frame loss cancellation"
is a binary outcome metric; GCC's `(U, queuing delay p50/p95)` pair is a
continuous metric that survives across all 7 scenarios. Adding it to our
CSV-side metric list would give the rule-vs-fixed comparison a sharper
quantitative axis.

---

## 7. Acknowledged and Implicit Limitations

### Acknowledged
- Per-frame encoder rate retune assumed feasible (true for VP8 software,
  not for hardware NVENC on Linux).
- Bottleneck buffer must be ≥ some minimum for the delay signal to exist —
  pure bufferless drop-tail links degenerate to loss-based control.
- Parameter set fitted to 1 Mbps – tens-of-Mbps bottleneck; not validated
  on wireless / cellular last hops in the original paper.

### Implicit
- Receiver-side instrumentation requires browser cooperation (Chromium ships
  it). No equivalent hook in commodity game streaming clients.
- Adaptive threshold parameters (`k_u`, `k_d`) are fitted from a Pareto
  optimization that requires a controllable testbed — not a closed-form
  derivation.

---

## 8. Directly Reusable Elements for Sunshine TCC

| Element | How we adapt it |
|---|---|
| Delay gradient as primary signal | RTT inflation = `rtt_current − rtt_baseline`; same shape, server-side, round-trip |
| Multiplicative decrease | `BETA = 0.7` (vs GCC's 0.85); justified by harder failure mode in gaming |
| `α / η` AIMD shape | Validates our AIMD framing as the right family |
| Adaptive threshold | Deferred future work; if false positives on the clean scenario are too high, port the `k_u ≫ k_d` envelope trick |
| Channel utilization metric | Add `U = encoded_bits_sent / shaped_capacity` to the CSV-derived metrics |
| Queuing delay percentiles | Already in our metric list as `RTT p50/p95` |
| Loss as confirmation, not trigger | Matches our IDR-rate-as-cross-check role |
| Decoupling state estimation (filter) from policy (FSM) | Our `bitrate_controller_t` already has this separation; the controller owns no I/O |

### Key Insight

**GCC and ABRAGame and our TCC all reduce to the same core algorithm:**
*estimate the delay derivative, threshold it, AIMD the rate.*

What differs is where the estimate is computed (receiver vs. server),
what statistic is used (one-way gradient vs. cumulative one-way latency vs.
round-trip inflation), and how fast the action loop runs (per-frame vs.
per-window). Our position in this design space — server-side, RTT-based,
per-window — is the **most constrained but most portable** point, because it
requires no client modification and no clock synchronization.

---

## Related
- [[abragame]] — closest prior work; explicitly positions against
  slope-based methods like GCC
- [[related-work]] — synthesis across all surveyed ABR papers
- [[idea-10-abr-comparison]] — our controller plan
- [[bitrate-control]] — Sunshine's current static bitrate model and the gap

## Sources
- Carlucci, De Cicco, Holmer, Mascolo. *Analysis and Design of the Google
  Congestion Control for Web Real-time Communication (WebRTC)*. ACM MMSys'16,
  Klagenfurt, Austria, May 2016. DOI: 10.1145/2910017.2910605.
- IETF draft draft-ietf-rmcat-gcc (referenced [15] in the paper).
- Chromium WebRTC source:
  `https://chromium.googlesource.com/external/webrtc/+/master/webrtc/`
