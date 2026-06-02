# Related Work — Adaptive Bitrate for Cloud Gaming

## What is it?
Survey of the papers most relevant to idea #10 (Fixed vs Rule-based adaptive bitrate in Sunshine). Covers what each contributes, what we reuse, and where our work goes further.

## Why it matters for Sunshine / TCC
These papers define the academic context for the TCC. They justify our algorithm choices, evaluation methodology, input signals, and positioning relative to prior work.

---

## Paper 1 — Thompson et al. (Adaptive Bitrate and AI Quality Scaling)

**Approach:** Hybrid server-side ABR (threshold + predictive) + client-side AI upscaling (CNN/GAN) to reconstruct lower-resolution frames.

**Useful framing:** Defines "good streaming" as **continuity of play** — avoiding artifacts during instability, not peak visual fidelity. This maps directly to our stability-focused evaluation.

**Not directly usable:** Client-side AI upscaling is out of scope (Moonlight-side change, massive complexity). Predictive modeling concept could inform RL state design.

---

## Paper 2 — Baldovino (Networking Issues of Cloud Gaming, literature review)

**Scope:** Literature review of 33 papers (2017–2022) on cloud-gaming
networking, JINITA Vol. 4 No. 2. Full analysis in [[baldovino2022]].

**Value to us as a citation hub** (not a primary contribution):
- **RTT < 70 ms** for cloud-gaming playability — Baldovino's ref [22]
  (Sužnjević & Homen 2020). Peer-reviewed benchmark to define "degraded
  state" in our evaluation.
- **~100 ms** input-to-response for action games, **~150 ms** for slow-paced
  — Baldovino's ref [36] (Mossad et al., DeepGame).
- **1% packet loss makes games unplayable** — Baldovino's refs [19], [22].
- **Solution taxonomy** (lag compensation / encoding adaptation / client
  computing / edge / ML / frame adaption / GPU server selection) gives us
  the vocabulary to position our work as "compression with encoding
  techniques" — the bucket the survey itself notes is "ineffective under
  excessive network congestion," which is precisely the gap our
  delay-driven controller addresses.

**Primary references unlocked for follow-on reading**:
- **Alos et al. 2019, IEEE Access** — *Congestion Control for Cloud Gaming
  Over UDP Based on Round-Trip Video Latency*. Round-trip video latency as
  control signal — functionally identical to our RTT-inflation approach.
  **Read.**
- **Slivar et al. 2018, ACM TOMM** — Game categorization for QoE-driven
  encoding strategy. Explicitly addresses *"configuring encoding parameters
  for game streaming when bandwidth is diverse."*
- **Mossad et al. DeepGame (ACM MM 2021)** — DNN-based attention-region
  encoding, 19–36% bandwidth reduction without QoE loss. Orthogonal to ABR.
- **Zhang et al. EdgeGame (IEEE Wireless Commun. 2019)** — edge-side deep
  learning for bitrate adaptation; 50% network delay reduction, 20% QoE
  improvement claimed.

**Corrections to earlier notes** (full detail in [[baldovino2022]]):
- **Themis** (ref [38], Li et al. ACM MM 2019) is RL for **server-side
  resource partitioning** (CPU/GPU allocation across colocated games), *not*
  RL for bitrate adaptation. The state/reward sketch we previously
  attributed to Themis was projection, not what the paper actually does.
  The 17–36% number is response-delay reduction from resource partitioning,
  not from any ABR mechanism. Drop Themis as an ABR reference.

**Key finding the surveyed papers converge on:** latency is the dominant
failure mode; VoD techniques (buffering, lookahead, retransmission) are
inapplicable to real-time gaming.

---

## Paper 3 — GCC: Carlucci et al. (2016, ACM MMSys)

**The canonical delay-gradient AIMD for WebRTC.** Full analysis in [[gcc]].
Summary:

**Algorithm:**
- Delay-based controller at the *receiver*: Kalman-filter the inter-frame
  one-way delay gradient `m(t)`; compare against an adaptive threshold `γ(t)`;
  over-use detector FSM drives a Decrease (α=0.85) / Hold / Increase (η=1.05)
  remote-rate FSM.
- Loss-based controller at the *sender*: multiplicative decrease when
  `f_l > 0.10`, multiplicative increase when `f_l < 0.02`.
- Encoder target = `min(A_r, A_s)`. Pacer drains at `1.5·A` with FEC padding.
- No clock sync needed — the delay *gradient* cancels the constant clock
  offset.

**Results:** 84% link utilization with 20 ms median queuing delay on a
variable-capacity link; intra-protocol fairness 0.93 across 3 GCC flows;
adaptive threshold cuts p95 RTT from 187 → 130 ms vs. static.

**What we reuse:**
- Signal philosophy — delay *gradient* (not absolute delay, not loss) as the
  primary trigger. Our RTT-inflation signal is the server-side / round-trip
  analog of `m(t)`.
- AIMD shape with multiplicative decrease — validates our `BETA = 0.7` choice
  as the same algorithm family.
- Channel utilization `U = R_r / C` as a first-class evaluation metric to
  pair with queuing-delay percentiles.
- "Loss as confirmation, not trigger" — same role IDR-request rate plays in
  our design.

**What we cannot reuse:**
- Receiver-side controller: we cannot modify Moonlight, so all estimation
  has to live on the server. Forces us to use round-trip instead of one-way.
- Per-frame (~30 Hz) control loop: Linux NVENC reconfiguration cost
  (AVCodecContext rebuild + IDR) precludes this; our controller runs on a
  ~1 s window.
- Pacer + FEC padding layer: Sunshine ships whatever NVENC emits.

**Where it positions our work:** GCC is the upper bound on what receiver-side,
per-frame, delay-gradient ABR can achieve. ABRAGame and our TCC sit further
down the constraint axis (no client mods, server-only, coarser cadence) but
recover the same core algorithm with simpler signals.

---

## Paper 4 — Hong et al. (2015, IEEE TCSVT) — GamingAnywhere reconfiguration

**The implementation prior art.** Full analysis in [[hong2015]]. Summary:

**Contributions:**
- Crowdsourced MOS study (101 subjects, 3020 sessions, 132 h) on
  GamingAnywhere → per-game quadratic MOS model in `(fps, bitrate)`.
- Runtime codec reconfiguration in GA: migrated ffmpeg → live555,
  added `ioctl` interface between RTSP server and codec modules,
  implemented soft reconfiguration for libx264 (CRF + `vbv-maxrate`),
  Freescale VPU, and Intel QSV.
- Optimal + efficient bandwidth-allocation algorithms across concurrent
  gamers sharing a datacenter uplink (EFF_avg / EFF_mm), up to 46%
  worst-MOS improvement over equal-share.

**Why it matters:** Hong2015 is the closest **implementation-level** prior
work to our PR #2a. They hit the same fundamental constraint we did
(*"the bitrate cannot be changed once the encoder is initialized"* — for
libx264 ABR in 2015, for ffmpeg avcodec NVENC on Linux in 2026) and landed
on the same architectural pattern: decouple session lifecycle from encoder
lifecycle via an event/ioctl channel. We re-did this work for Sunshine +
NVENC; the contribution is the modern port, not the original idea.

**What we reuse:**
- The architectural pattern (event-driven encoder reconfig, decoupled from
  RTSP) — already implemented.
- The 2 Mbps MOS-saturation finding as justification for our bitrate range.
- The crowdsourced MOS protocol (1–7 scale, three sub-scores) if our
  blind-MOS evaluation scales.
- Efficiency `= MOS / Mbps` as a derived metric for fixed-vs-adaptive
  comparison.
- The lesson that **framerate is the other knob** — under-bitrate
  conditions, lowering fps and raising per-frame bits can beat lowering
  bitrate at constant fps. Out of scope for our TCC but is the natural
  follow-on PR.

**What we cannot reuse:**
- Client-side bandwidth estimation via WBest-style packet dispersion.
- MOS model as the online optimization objective (we use delay, not MOS).
- Multi-gamer resource allocation (Sunshine is single-tenant).
- Their fitted MOS coefficients (libx264, 720p, 2014).

---

## Paper 5 — C³G: Alós et al. (2019, IEEE Access) — server-side RTT-based CG ABR

**The closest prior work to our TCC.** Full analysis in [[alos2019]].
Summary:

**Algorithm:**
- Defines **RTVL** (Round-Trip Video Latency): per-frame round-trip
  delay measured **at the server**, from when the raw frame is sent to
  the encoder until the client's frame-ACK arrives.
- Three-phase congestion model (sub-OOP / congestion / bufferbloat)
  inherited from BBR/Kleinrock, applied at the application layer over UDP.
- **Reactive decrease**: when `qdData > 0` AND RTVL trending up, predict
  next-step RTVL; if it would exceed `RTVL_th = 100 ms`, launch a drain
  sequence — hold rate at `λ_drain = μ̄ − qdData/Δt` for `T_drain` seconds,
  then jump up to `λ_OOP = μ̄`.
- **Proactive increase**: maintain a "network state dictionary" of
  recently-explored bitrates and their network ratings; choose next
  candidate (up / hold / down) by historical rating; modulate step size
  and period via an exploration gain that learns from outcomes.

**Results (vs BBR-on-UDP, on PlayGiga, real WAN ~30 km, TBF-shaped):**
- **Loss-free for capacity drops up to ~42%** (`α_c < 1.75`).
- **AP 0.4–0.8 s vs BBR >1 s** (adaptation period after capacity drop).
- **Effective channel use 93–96% vs BBR 87–93%** in stable conditions.
- **RTVL kept below 100 ms** for steady bandwidth limitations.
- Trades 4× slower exploration recovery (EP ~36 s vs BBR ~8 s) for
  loss-free reactive behavior — explicit design priority.

**What we directly borrow:**
- **`RTVL_th = 100 ms` as playability threshold** — supersedes the
  generic Baldovino-cited 70 ms RTT for action-game framing.
- **AP / RTVL_peak / L_AP triple** as our reactive-performance metric set.
- **Effective channel use `λ̄/c_btl`** as a stable-window metric (target ≥
  90% for both fixed and adaptive).
- **42% loss-free drop bound** as a quantitative comparison point.
- The `(c_btl,lim × α_c)` test grid concept (5/7/9 Mb/s × 1.25–2.5
  drop ratios) — partially adopted into our 7-scenario design.

**What this paper means for our positioning:**
The framing "server-side, RTT-based ABR for cloud gaming" is **not novel
as of 2019** — Alos et al. already published it on PlayGiga. The novelty
of our TCC sharpens to:
1. **Open-source instantiation** on Sunshine (PlayGiga is proprietary,
   unreproducible).
2. **No client modification** — even C³G requires per-frame frame-ACKs
   from the CG client. We use ENet's `peer->roundTripTime`, which
   Moonlight already maintains for its own keep-alive, so the signal is
   free.
3. **Hardware-encoder pipeline** (NVENC via avcodec on Linux) — the
   `AVCodecContext` rebuild reality that software encoders sidestep.
4. **Simpler policy** — AIMD vs reactive-drain + proactive-state-dictionary.
   Our research question becomes *"how much of C³G's policy complexity
   is necessary on a Sunshine-class platform?"* — a legitimate
   reproducibility / Pareto question.

**Architectural positioning we should adopt in the TCC text:**
> *Alos et al. demonstrated on the proprietary PlayGiga platform that a
> server-side, RTT-driven adaptive bitrate controller can keep cloud
> gaming latency below 100 ms and avoid packet losses for capacity drops
> up to ~42%. Their algorithm requires per-frame client ACKs and a
> learned network state dictionary. We ask whether the same outcome is
> achievable on the open-source Sunshine platform with (i) no client
> modification and (ii) a plain AIMD policy driven by ENet's existing
> round-trip time measurement.*

---

## Paper 6 — ABRAGame: Armendariz & Joskowicz (2025, Multimedia Tools and Applications)

**The closest prior work.** Full analysis in [[abragame]]. Summary:

**Algorithm:**
- Congestion signal: cumulative one-way latency over 500ms sliding window (threshold: 2000, ≈ sustained 80ms)
- Decrease: `new_bitrate = estBW − 1.5 Mbps`
- Increase: `+0.5 Mbps` every 20 seconds of stability (linear; authors suggest exponential as future work)
- Architecture: client-side, separate process, no server modifications

**Results:**
- 100% degradation detection, 10.3% false positives
- 85.9% effective frame loss cancellation
- Recovery time: 4.5s vs 20–200s in commercial platforms (Stadia, PS Now, GeForce Now)

**Testbed:** Linux bridge + NetEm, 6 network scenarios (A–F), 240s each, real gaming platform.

**What we reuse directly:**
- NetEm testbed design and 6 scenario types (directly reproducible)
- Evaluation metrics (loss cancellation rate, recovery time, false positive rate)
- 20-second stability timer as starting parameter
- Cumulative signal over sliding window as congestion trigger concept
- `estBW - margin` decrease logic

**What we adapt:**
- Congestion signal: one-way latency → IDR request rate + packet loss (server-observable, no clock sync)
- estBW: client-side computation → server-side `encoded_bits_sent / window`
- Architecture: client-side → server-side, integrated into Sunshine via NVENC reconfiguration

**Where we go further:**

| ABRAGame limitation | Our response |
|---|---|
| Client-side, requires clock sync | Server-side, no clock sync needed |
| Fixed empirical thresholds | RL controller learns thresholds implicitly |
| Linear increase only | Linear + exponential variant (their suggested future work) |
| No learned controller | RL as third comparison point |
| Proprietary platform | Open-source Sunshine — fully reproducible |
| No comparison to learned approach | Our core contribution |

---

## Cross-paper synthesis

**Where they all agree:**
- Latency is the primary failure mode in game streaming
- VoD techniques (buffering, lookahead, retransmission) are inapplicable
- Wi-Fi / wireless is the main source of instability
- Stability matters more than peak quality during degradation

**Where they differ:**
- Where intelligence lives: Thompson (server+client hybrid), ABRAGame (client-side rule-based), GCC (receiver-side delay-gradient), Hong2015 (server-side MOS optimization on client-measured bandwidth), **C³G (server-side RTVL with state-dictionary exploration)**, our TCC (server-side delay-based AIMD)
- Input signals: one-way latency (ABRAGame), one-way delay *gradient* via Kalman filter (GCC), measured throughput + MOS model (Hong2015), **per-frame RTVL with `qdData` (C³G)**, round-trip RTT inflation (us)
- Control cadence: per-frame ~30 Hz (GCC), per-window ~1 s (us, ABRAGame, Hong2015, C³G)

**Cross-paper algorithmic convergence:**
GCC, ABRAGame, C³G, and our TCC all reduce to the same skeleton —
*estimate a delay statistic, threshold it, AIMD-like the rate*.
The differences are in **where the estimate is computed** (receiver vs.
server vs. client), **what statistic** (one-way gradient vs. one-way
cumulative vs. round-trip vs. per-frame RTVL with explicit `qdData`),
and **how the increase phase decides what to try next** (fixed gain vs.
learned state dictionary vs. flat additive step). Hong2015 sits outside
this skeleton: it uses **measured bandwidth → MOS optimization** rather
than delay-based AIMD — but provides the implementation pattern
(event-driven codec reconfig) that every paper above also needs and
rarely documents.

**The C³G ↔ our-TCC axis is the load-bearing comparison.**
Both are server-side, RTT-flavored, UDP-native, cloud-gaming-specific.
The differences are the contribution of the TCC: open-source platform,
no client cooperation, hardware-encoder pipeline, simpler policy.

**Two distinct prior-art axes:**
- *Algorithm* prior art: GCC, ABRAGame — what to compute and decide.
- *Implementation* prior art: Hong2015 — how to actually rebuild an
  encoder mid-session in an open-source platform.

**Our positioning:**
Server-side, open-source, rule-based vs fixed-bitrate comparison, using
server-observable signals (RTT inflation, frame send latency, IDR rate as
backstop). The most constrained but most portable point in the design space:
no client modification, no clock synchronization, integrates into Sunshine's
existing encoder reconfiguration path. Extends ABRAGame's signal choice
(round-trip instead of one-way → no clock sync) and validates the AIMD
family against GCC's canonical delay-gradient formulation.

## Related
- [[abragame]] — full ABRAGame paper analysis
- [[gcc]] — full Google Congestion Control paper analysis
- [[idea-10-abr-comparison]] — how these papers inform the TCC design
- [[bitrate-control]] — Sunshine's current static bitrate model (the gap we're filling)
- [[frame-types]] — IDR requests as a congestion signal

## Sources
- Thompson et al. — Adaptive Bitrate and AI Quality Scaling (cloud gaming)
- Baldovino — Networking Issues of Cloud Gaming (2017–2022 literature review)
- Armendariz & Joskowicz — ABRAGame: Automatic Bit Rate Adjustment for Cloud Gaming, Multimedia Tools and Applications, 2025
- Carlucci, De Cicco, Holmer, Mascolo — Analysis and Design of the Google Congestion Control for WebRTC, ACM MMSys'16
- Hong, Hsu, Tsai, Huang, Chen, Hsu — Enabling Adaptive Cloud Gaming in an Open-Source Cloud Gaming Platform, IEEE TCSVT, 2015
- Alós, Morán, Carballeira, Berjón, García — Congestion Control for Cloud Gaming Over UDP Based on Round-Trip Video Latency (C³G), IEEE Access, 2019
