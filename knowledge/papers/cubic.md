# Paper Analysis: CUBIC — A New TCP-Friendly High-Speed TCP Variant
**Ha, Rhee, Xu — ACM SIGOPS Operating Systems Review, Vol. 42, Issue 5, July 2008**

**The peer-reviewed reference for "AIMD with memory of a known-good
ceiling, recovering fast and then plateauing."** CUBIC has been the
default Linux TCP congestion control since kernel 2.6.18 (2006),
which makes it the most-deployed congestion-control algorithm on the
planet. It is not from the cloud-gaming literature — it is the
*lineage* our AIMD belongs to, and the algorithm our professor pointed
at when he said *"this looks a lot like TCP congestion control. Look
at CUBIC, it reacts faster."*

For our TCC, CUBIC matters because it provides a peer-reviewed,
well-analysed, **time-based** increase curve to replace the ad-hoc
two-phase (`×γ` then `+STEP`) recovery in
`bitrate_controller.cpp`, and it provides a mechanism (fast
convergence) for shrinking `last_known_good` on repeated congestion —
which directly supersedes our [[improvement-roadmap]] Idea 5.

---

## 1. Problem Framing

Standard TCP (Reno / NewReno / SACK) increases its congestion window
by 1 segment per RTT. On a 10 Gbps × 100 ms RTT path (Bandwidth-Delay
Product ≈ 100 000 packets at 1250 B), recovering from a single loss
event back to full utilisation takes ~50 000 RTTs ≈ **1.4 hours**.
Many flows finish before that, so the path is severely under-utilised
in steady state.

CUBIC's predecessor, BIC-TCP (Linux 2.6.8, 2005), addressed this by
performing a binary search between the pre-loss window `W_max` and
the post-loss window `W_min`, then growing aggressively past `W_max`
("max probing"). It worked, but introduced four window-control phases
(binary search, additive increase, max probing, slow start) and
parameter knobs (`S_max`, `S_min`) that made the protocol hard to
analyse and hard to tune for short-RTT / low-speed networks.

CUBIC replaces all of BIC-TCP's phase logic with **one continuous
cubic function of wall-clock time**. The simplification preserves all
of BIC-TCP's scalability while improving stability, TCP-friendliness,
and RTT-fairness. CUBIC became Linux default at 2.6.18 (2006) and is
still the default today.

---

## 2. The Central Idea — Time-Based Window Growth

The defining choice: CUBIC's window growth depends only on the
**wall-clock time elapsed since the last congestion event**, not on the
number of ACKs received and not on RTT. The paper calls this elapsed
time the *congestion epoch*.

Concretely:

```
W(t) = C · (t − K)³ + W_max                 (Equation 1)
K    = ∛(W_max · β / C)                     (Equation 2)
```

where:
- `t` — elapsed time (seconds) since the last window reduction
- `W_max` — window size right before the most recent loss
- `K` — time at which `W(K) = W_max` if no further loss happens
  (the curve's inflection point: end of concave, start of convex)
- `C` — a shape constant; the paper fixes `C = 0.4`
- `β` — multiplicative decrease factor; the paper sets `β = 0.2`,
  meaning `cwnd ← cwnd · (1 − β) = cwnd · 0.8` on a loss event

The curve has three operating regions, *automatically traversed* as
`t` advances:

1. **Concave region** (`t < K`, `cwnd < W_max`): `W(t)` rises
   quickly. CUBIC races back to the previous saturation point.
2. **Plateau** (`t ≈ K`, `cwnd ≈ W_max`): the cubic flattens.
   Stability around the known-good ceiling; minimal oscillation.
3. **Convex region** (`t > K`, `cwnd > W_max`): `W(t)` rises slowly
   at first, then accelerates. Cautious probe into unexplored
   capacity, ramping up if the link tolerates it.

Compare this to standard TCP, which is *always* in additive-increase
mode (linear in ACKs received): CUBIC says "the further we are below
the known-good ceiling, the more aggressively we should recover; the
closer we are to it, the more carefully we should explore."

> **Why time-based?** Because ACK-based or per-RTT growth couples the
> recovery rate to the RTT — long-RTT flows recover slower than
> short-RTT flows, which is exactly the under-utilisation problem
> CUBIC exists to solve. Pinning the growth to wall-clock time gives
> *RTT-independent* recovery, and as a bonus makes the protocol fair
> between flows with very different RTTs (their §6.3 measures this).

---

## 3. The Algorithm in Detail

The full Linux algorithm (their Algorithm 1, v2.2) fits on one page.
The relevant pieces for ABR adoption:

### 3.1 Multiplicative decrease

On packet loss:

```
W_last_max ← cwnd                   (memorise pre-loss window)
ssthresh   ← cwnd · (1 − β)         (Eq. 3.6; β = 0.2)
cwnd       ← ssthresh
epoch_start ← 0                     (reset the cubic clock)
```

The decrease is a plain multiplicative cut. The choice of β = 0.2
(retain 0.8 of the window) is **gentler** than TCP Reno's 0.5 — which
is justified explicitly in §3.6:

> *"While a more adaptive setting of β could result in faster
> convergence, it will make the analysis of the protocol much harder
> and also affects the stability of the protocol. This adaptive
> adjustment of β is a future research issue."*

So the paper deliberately picks a small, fixed β and relies on the
cubic *increase* curve to compensate. This is a different design
trade-off than ours: in TCP, the decrease is triggered by **packet
loss** (already-bad event), so aggressive cuts cause throughput
instability. In our cloud-gaming ABR, the decrease is triggered by
**RTT inflation** (early warning, before loss), so gentle cuts
under-drain the bottleneck queue (the failure mode we measured at
β = 0.85). The lesson transfers but the value of β does not.

### 3.2 Fast convergence (Equation 3.7)

When a loss event happens *before* the window has recovered to the
previous `W_max` — i.e., `cwnd < W_last_max` at the moment of loss —
CUBIC reduces `W_max` even further:

```
W_last_max ← cwnd · (2 − β) / 2     (Eq. 3.7)
```

With β = 0.2 that is `cwnd · 0.9`. The new `W_max` is therefore
**lower** than the current window, which in turn makes `K` smaller
(via Eq. 2), which in turn makes the cubic plateau happen earlier,
which gives competing flows (in TCP) — or in our case, the actual
constrained capacity — room to breathe.

This is event-driven memory shrinkage: a *single mechanism* that
forgets a known-good ceiling exactly when the evidence says the
ceiling is no longer reachable.

### 3.3 Concave and convex updates

Each ACK in congestion avoidance:

```
target ← origin_point + C · (t − K)³        // i.e. W(t + RTT)
if target > cwnd:
    cnt ← cwnd / (target − cwnd)            // ACKs needed to grow by 1
else:
    cnt ← 100 · cwnd                        // very slow growth
if ack_cnt > cnt:
    cwnd ← cwnd + 1
    ack_cnt ← 0
else:
    ack_cnt ← ack_cnt + 1
```

The cubic function gives the *next* RTT's target window; the
algorithm computes how many ACKs are needed to grow the current `cwnd`
by 1 segment to hit that target. Identical update form for both the
concave and convex regions — the cubic function takes care of the
phase by itself.

### 3.4 TCP-friendly mode

CUBIC also tracks what window standard TCP would have at the same
elapsed time `t`:

```
W_tcp(t) = W_max · (1 − β) + 3 · (β / (2 − β)) · (t / RTT)   (Eq. 4)
```

If `cwnd < W_tcp(t)`, CUBIC sets `cwnd ← W_tcp(t)` — i.e., falls
back to standard TCP behaviour. This guards against unfairness in
networks where TCP-Reno is already utilising the link well (short-RTT,
low-BDP paths), and is the reason CUBIC can coexist with legacy TCP
deployments.

**For our TCC, this mode is irrelevant.** A Sunshine cloud-gaming
session is a single UDP stream on a home-network bottleneck; there is
no competing TCP flow whose fair share we need to protect. Dropping
TCP-friendly mode is a clean simplification of CUBIC for the ABR port.

### 3.5 Multiplicative decrease parameter

`β = 0.2` (cwnd × 0.8). The paper does not explore β sweep; explicitly
labelled future work.

### 3.6 The C parameter

`C = 0.4`. Section 5 derives this: with `C = 0.4` and `β = 0.2`, the
expected window size becomes `E[W_cubic] ≈ 1.17 · (RTT/p)^(3/4)`
(their Eq. 6). This value is chosen so that the TCP-friendly region
encompasses most of the environments where standard TCP performs
well, while preserving scalability for high-BDP paths.

---

## 4. The Mathematical Skeleton (the bare minimum we need to port)

| Symbol | Meaning | Where it's set |
|---|---|---|
| `W(t)` | Target window (in our case: target bitrate) at time `t` since last decrease | Computed every decision tick |
| `t` | Elapsed wall-clock seconds since last decrease | Tracked from `last_decrease_time` |
| `W_max` | Pre-decrease ceiling (our `last_known_good`) | Updated on each decrease |
| `K = ∛(W_max · β / C)` | Plateau-arrival time | Recomputed each time `W_max` or `β` changes |
| `C` | Shape constant | Calibrated from desired recovery time (Eq. 2 inverted: `C = W_max · β / K³`) |
| `β` | Multiplicative decrease factor | Chosen for our signal (see §6 below) |

**Calibration question:** the natural way to set `C` is to first decide
the *target recovery time* `K_desired` — how long, in seconds, should
the controller take to recover from a decrease back to the previous
ceiling? Once `K_desired` and `β` are fixed, `C` falls out.

For a typical Sunshine session with `W_max = 19000 kbps`, β = 0.5, and
`K_desired = 10 s`, `C = 19000 · 0.5 / 1000 = 9.5 kbps/s³`. (Units
matter: in TCP it's packets/RTT³; in our port it's kbps/s³.)

This is meaningful: **C calibrates "how impatient the controller is to
recover."** Lower C = lazier recovery; higher C = more aggressive
recovery. A scenario A run will tell us empirically whether 10 s is
too slow (channel under-used during the shaping window) or about right.

---

## 5. Evaluation Methodology (Section 6)

### Testbed
- Dumbbell topology, two dummynet routers, Dell Linux servers.
- Bottleneck bandwidth: typically 400 Mbps. Buffer 100 % BDP unless
  stated.
- Bottleneck RTT: varied 8 ms to 324 ms across experiments.
- Background traffic: ~15 % of bottleneck capacity, generated by a
  modified *Surge* web-traffic generator (cross-traffic).
- Comparison: standard TCP-SACK, HSTCP, BIC-TCP, CUBIC.

### Key experiments

**§6.2 — Intra-protocol fairness (same RTT, two flows):**
- Throughput ratio between competing same-RTT flows.
- CUBIC ≈ 0.95 across RTTs 16–324 ms — best of all tested protocols.
- Link utilisation: CUBIC > 90 % up to RTT 324 ms.

**§6.3 — Inter-RTT fairness (one flow 162 ms, other 16–162 ms):**
- CUBIC's throughput ratio between long/short RTT flow is linearly
  proportional to `1/RTT_ratio` (like TCP-SACK) — short RTT gets
  proportionally more, but the slope is "acceptable" (their wording).
- HSTCP gives short-RTT flow disproportionate share; CUBIC does not.

**§6.4 — Impact on standard TCP:**
- CUBIC steals less bandwidth from TCP-SACK than BIC-TCP or HSTCP at
  most operating points; behaves like TCP itself in TCP-friendly
  regions.

### Headline results (Figures 4, 5, 8, 9)

- **Two CUBIC flows on 400 Mbps × 240 ms RTT converge to fair share
  within 200 s** (Fig. 4). Convex-concave window curves visually
  resemble breathing — fast catch-up, plateau, slow exploration.
- **CUBIC + TCP-SACK on 400 Mbps × 82 ms RTT**: TCP-SACK fully under-
  utilises, CUBIC fills the rest. Fig. 5(b).
- **Link utilisation 90 %+ across all tested conditions** (Fig. 8(b)).

The key empirical finding: **CUBIC achieves high link utilisation
*and* fair sharing *and* RTT-independence simultaneously** — the three
goals that all earlier high-speed TCP variants had to trade off.

---

## 6. Implementation Evolution (Table 1)

CUBIC has been continuously refined in Linux. Notable upgrades:

| Version | Kernel | Change |
|---|---|---|
| 2.0-pre | 2.6.13 | First release |
| 2.0 | 2.6.15 | Officially included |
| 2.0 | 2.6.18 | **Becomes default TCP** (replaces BIC-TCP) |
| 2.0 | 2.6.21 | Cubic root: bisection → Newton-Raphson (10× faster) |
| 2.1 | 2.6.22 | **Removed window clamping (S_max inheritance from BIC-TCP)** — improves scalability in concave region |
| 2.1 | 2.6.22-rc4 | Improved slow-start |
| 2.2 | 2.6.25-rc3 | **Removed window clamping in convex phase too** — improves convergence speed while keeping fairness |

The arc of these updates is informative: the original CUBIC inherited
some BIC-TCP safety clamps that turned out to be over-cautious; the
Linux community gradually removed them as extensive lab testing
confirmed CUBIC was stable without them. For our port, we should
match the v2.2 behaviour (no clamping in either region).

---

## 7. Implications for Our TCC — What Changes

### 7.1 Replaces our hand-rolled two-phase increase

The current `bitrate_controller_t::on_sample` increase branch does:

```cpp
if (current_kbps < 0.9 * last_known_good)
    current_kbps *= gamma;       // phase 1: ×1.15 per tick
else
    current_kbps += step_kbps;   // phase 2: +500 kbps per tick
```

This is a discrete, tick-based, two-region approximation of what
CUBIC does continuously and analytically. The substitution is direct:

```cpp
double t_since_last_decrease = elapsed_seconds(last_decrease_time);
double target_kbps = C * pow(t_since_last_decrease - K, 3) + last_known_good;
current_kbps = clamp(target_kbps, min_kbps, effective_max_kbps);
```

Three benefits:
- **Time-based**, so the curve is unaffected if we change
  `decision_interval_ms`.
- **One function**, no `if`/`else` branching between phases.
- **Peer-reviewed parameter choices** (C, β) we can cite directly.

### 7.2 Replaces Idea 5 (`last_known_good` decay) with fast convergence

Our [[improvement-roadmap]] Idea 5 proposed slow time-decay of
`last_known_good`. CUBIC's fast-convergence mechanism (Eq. 3.7) does
the same job more cleanly: shrink `W_max` *exactly when evidence
arrives* that the previous ceiling was wrong (a second decrease before
recovery completes). Event-driven beats time-decay because it is
self-calibrating — it only acts when the network actually
contradicts our memory.

### 7.3 Complements Idea 1 (computed-drain step)

The two are orthogonal and combine cleanly:

- **Idea 1** fixes the *decrease size*: drop to `α · observed_rate`
  instead of `β · current_target`. Addresses both over- and
  under-drain failure modes from the β sweep.
- **CUBIC port** fixes the *increase shape*: smooth time-based
  cubic curve instead of two-phase γ + STEP. Addresses recovery
  speed and stability near the ceiling.

Combined, they correspond to one half of C³G's reactive-drain
([[alos2019]] §IV.A — the proper drain to `μ̄`) plus a CUBIC-shaped
substitute for C³G's proactive state dictionary
([[reactive-blind-spot]]).

### 7.4 Drop TCP-friendly mode entirely

The Eq. 4 fallback exists because TCP-CUBIC flows can share a
bottleneck with TCP-Reno flows that need protection. Sunshine sessions
do not share a bottleneck with TCP-Reno controllers; the home-network
contention pattern is "one big UDP stream vs maybe Netflix vs maybe
the laundry router." Even if there is TCP cross-traffic, it is *not
our flow* — we are not obligated to mimic TCP fairness. Dropping the
mode means we do not implement `W_tcp(t)` (Eq. 4) or
`cubic_tcp_friendliness()` from their Algorithm 1.

### 7.5 β stays a sweep parameter — but probably lower than CUBIC's 0.2

CUBIC's `β = 0.2` (retain 0.8) is paired with TCP's *loss-triggered*
decrease, where aggressive cuts destabilise throughput. Our trigger
is RTT inflation (earlier signal), where gentle cuts under-drain the
queue. The β sweep we just ran confirmed this: 0.85 (close to CUBIC's
0.8) under-drains; 0.5 over-drains; 0.7 is around the sweet spot.

If we also adopt Idea 1 (computed-drain step), β becomes a *safety
floor* on the decrease size rather than the primary lever — the
"how aggressively to fall back when we cannot estimate observed rate
confidently." A conservative floor of β = 0.5 to 0.7 paired with
Idea 1's data-driven cut is probably the right starting point.

---

## 8. Directly Reusable Elements for Sunshine TCC

| Element | How we adapt it |
|---|---|
| `W(t) = C·(t − K)³ + W_max` | Replace phase-1/phase-2 increase with cubic curve over wall-clock time since last decrease |
| `K = ∛(W_max · β / C)` | Recompute K every time we update `last_known_good` or change β |
| Fast convergence (Eq. 3.7) | On a second decrease while `current < last_known_good`, set `last_known_good ← current · (2−β)/2` |
| Time-based growth (not tick-based) | Decouple controller curve from `decision_interval_ms` |
| `C = 0.4` analytical justification (§5) | Use the inverted form `C = W_max · β / K³` with our chosen *recovery time* K (e.g., 10 s) instead of inheriting their TCP-tuned 0.4 |
| Removed window clamping (v2.2, kernel 2.6.25-rc3) | No artificial limit on per-tick window change; let the cubic curve self-pace |

## 9. What We Do *Not* Adopt

| Element | Reason for skipping |
|---|---|
| TCP-friendly mode (Eq. 4 + `cubic_tcp_friendliness()`) | No competing TCP flows in our setting |
| Newton-Raphson cubic root | User-space; `std::cbrt` is fine |
| Pluggable congestion module interface | Linux kernel API, not relevant in user-space |
| Slow-start / `ssthresh` transitions | Our controller starts at max-bitrate, not from zero |
| Multiplicative decrease at β = 0.2 specifically | Wrong number for our RTT-inflation trigger; keep β as a sweep parameter |
| `dMin` / `min_cwnd` plumbing | Specific to packet-window semantics |

---

## 10. Algorithmic Comparison Against the Surveyed Papers

| Paper | Decrease | Increase | Memory | Trigger signal |
|---|---|---|---|---|
| TCP Reno | `W · 0.5` | `+1/RTT` (linear in ACKs) | None | Packet loss |
| HSTCP | `W · β(W)` (window-dependent) | `+α(W)/RTT` (window-dependent) | None | Packet loss |
| BIC-TCP | `W · β` | Binary search to `W_max`, then linear, then max-probing | `W_max` | Packet loss |
| **CUBIC** | **`W · (1−β)`, β = 0.2** | **`W(t) = C(t−K)³ + W_max`** | **`W_max` + fast convergence** | **Packet loss** |
| GCC ([[gcc]]) | `W · α` (α = 0.85) | `× η` (η = 1.05) | None | Delay gradient `m(t)` |
| C³G ([[alos2019]]) | `λ_drain = μ̄ − qdData/Δt` | Proactive state-dictionary exploration | Network state dictionary | Per-frame RTVL > 100 ms |
| **Our TCC (current)** | **`current · β` (β swept)** | **×γ then +STEP** | **`last_known_good`** | **ENet RTT > 100 ms** |
| **Our TCC (with CUBIC port + Idea 1)** | **`α · observed_rate`** | **`B(t) = C(t−K)³ + last_known_good` + fast convergence** | **`last_known_good` (shrunk on repeated congestion)** | **ENet RTT + frame_send_ms** |

CUBIC's row is the direct predecessor in *shape* of our current
controller. The "with CUBIC port + Idea 1" row is the post-improvement
target — strictly more sophisticated than CUBIC because it adds
delay-based triggering (closer to GCC and C³G) on top of CUBIC's
time-based recovery curve.

---

## 11. The TCC Framing CUBIC Enables

CUBIC lets us position the work in a clean lineage:

> *"Our controller is a CUBIC-shaped AIMD applied to UDP-based cloud-
> gaming bitrate adaptation. The decrease is triggered by ENet RTT
> inflation rather than packet loss, allowing earlier response than
> TCP. The increase follows CUBIC's cubic-time curve (Ha et al., 2008),
> giving fast recovery toward the last known-good bitrate, a stable
> plateau there, and gentle exploration of capacity beyond. The fast-
> convergence mechanism shrinks the known-good ceiling on repeated
> congestion, replacing the proactive state-dictionary of Alós et al.
> (2019) with a substantially simpler event-driven rule."*

This framing:
- Anchors the work in the most-deployed congestion-control algorithm
  on the Internet.
- Gives a clean comparison axis against C³G (proactive state dictionary
  → CUBIC fast convergence: how much of C³G's gain does the simpler
  mechanism recover?).
- Justifies our parameter choices by reference to a peer-reviewed
  paper instead of hand-tuning.
- Makes future-work directions natural: "the next step would be
  CUBIC-Vegas style hybrid (combining cubic increase with our
  RTT-gradient trigger), or the C³G state-dictionary on top."

---

## Related
- [[alos2019]] — C³G; closest prior work; CUBIC supplies the proactive
  layer simplification their state-dictionary motivates
- [[gcc]] — Google Congestion Control; also AIMD-shaped; uses delay-
  gradient like our trigger but does not have CUBIC's time-based
  increase
- [[abragame]] — pure-linear increase that ABRAGame explicitly flagged
  as a limitation; CUBIC is the textbook solution to that limitation
- [[reactive-blind-spot]] — architectural floor; CUBIC's fast
  convergence partially mitigates it on the recovery side
- [[improvement-roadmap]] — the document this paper analysis informs;
  needs updating to replace Idea 5 with fast convergence and rewrite
  Idea 6 around the actual CUBIC algorithm
- [[idea-10-abr-comparison]] — TCC research idea; CUBIC framing
  strengthens its lineage story
- [[bitrate-control]] — Sunshine's current static bitrate flow
- [[related-work]] — paper survey synthesis

## Sources
- Ha, S.; Rhee, I.; Xu, L. *CUBIC: A New TCP-Friendly High-Speed TCP
  Variant*. ACM SIGOPS Operating Systems Review, Vol. 42, Issue 5,
  pp. 64–74, July 2008.
- Linux kernel source: `net/ipv4/tcp_cubic.c`
- CUBIC version-history table: their Table 1 (kernels 2.6.13–2.6.25).
- Pluggable congestion module interface (`tcp_congestion_ops`):
  Hemminger, S. *TCP infrastructure split out*, lwn.net/Articles/128626/,
  2005.
- BIC-TCP predecessor: Xu, L.; Harfoush, K.; Rhee, I. *Binary Increase
  Congestion Control for Fast Long-Distance Networks*. IEEE INFOCOM,
  2004.
