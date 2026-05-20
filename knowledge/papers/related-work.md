# Related Work — Adaptive Bitrate for Cloud Gaming

## What is it?
Survey of the three papers most relevant to idea #10 (Fixed vs Rule-based vs RL adaptive bitrate in Sunshine). Covers what each contributes, what we reuse, and where our work goes further.

## Why it matters for Sunshine / TCC
These papers define the academic context for the TCC. They justify our algorithm choices, evaluation methodology, input signals, and positioning relative to prior work.

---

## Paper 1 — Thompson et al. (Adaptive Bitrate and AI Quality Scaling)

**Approach:** Hybrid server-side ABR (threshold + predictive) + client-side AI upscaling (CNN/GAN) to reconstruct lower-resolution frames.

**Useful framing:** Defines "good streaming" as **continuity of play** — avoiding artifacts during instability, not peak visual fidelity. This maps directly to our stability-focused evaluation.

**Not directly usable:** Client-side AI upscaling is out of scope (Moonlight-side change, massive complexity). Predictive modeling concept could inform RL state design.

---

## Paper 2 — Baldovino (Networking Issues of Cloud Gaming, literature review)

**Scope:** Systematic review of 33 papers (2017–2022) on cloud gaming QoS/QoE.

**Directly reusable:**
- **70ms RTT threshold** for general playability — a peer-reviewed benchmark to define "degraded state" in our evaluation. Consistent with ABRAGame's ~80ms cumulative latency trigger.
- **RL state/reward design from Themis:** state = {latency, jitter, estBW}; reward = maximize bitrate while minimizing RTT and IDR requests. Directly informs our RL controller design.
- **Themis result:** 17–36% reduction in response delay — gives us a target range for what RL can achieve.

**Key finding:** All reviewed papers agree that latency is the primary killer of game streaming and that VoD techniques (buffering, lookahead) are inapplicable.

---

## Paper 3 — ABRAGame: Armendariz & Joskowicz (2025, Multimedia Tools and Applications)

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

**Where all three agree:**
- Latency is the primary failure mode in game streaming
- VoD techniques (buffering, lookahead, retransmission) are inapplicable
- Wi-Fi / wireless is the main source of instability
- Stability matters more than peak quality during degradation

**Where they differ:**
- Where intelligence lives: Thompson (server+client hybrid), Baldovino/Themis (server-side RL), ABRAGame (client-side rule-based)
- Input signals: latency (ABRAGame), throughput + latency + jitter (Themis), all of the above (Thompson)

**Our positioning:**
Server-side, open-source, rule-based vs RL comparison, using server-observable signals (IDR rate, packet loss, estBW). Extends ABRAGame with server integration, exponential increase, and a learned controller. Applies Themis-style RL reward design to Sunshine's specific signal set.

## Related
- [[abragame]] — full ABRAGame paper analysis
- [[idea-10-abr-comparison]] — how these papers inform the TCC design
- [[bitrate-control]] — Sunshine's current static bitrate model (the gap we're filling)
- [[frame-types]] — IDR requests as a congestion signal

## Sources
- Thompson et al. — Adaptive Bitrate and AI Quality Scaling (cloud gaming)
- Baldovino — Networking Issues of Cloud Gaming (2017–2022 literature review)
- Armendariz & Joskowicz — ABRAGame: Automatic Bit Rate Adjustment for Cloud Gaming, Multimedia Tools and Applications, 2025
