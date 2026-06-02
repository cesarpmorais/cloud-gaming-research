# Paper Analysis: An Overview of the Networking Issues of Cloud Gaming: A Literature Review
**Baldovino, 2022 — Journal of Innovation Information Technology and Application (JINITA)**

A **literature review** (not a primary contribution) covering 33 papers from
2017–2022 on cloud-gaming networking. Its value to our TCC is as a
**citation hub**: it surveys the design space, names threshold numbers that
have become folklore in the field, and points at the primary papers we
should chase if we want depth on any one sub-topic.

This file replaces the earlier paraphrase in [[related-work]] and corrects
two misattributions in our previous notes.

---

## 1. Problem Framing

Two research questions drive the review:

1. *What issues and challenges related to networking currently affect cloud
   gaming?*
2. *What solutions have been proposed or used to solve them?*

Method: Google Scholar search on `"cloud gaming"` and `"cloud-based game"`
in title, 2017–present, English only → 168+69 hits → 33 selected. Sources
weighted toward conference proceedings (ResearchGate 27%, organization
sites 45%, IEEE Xplore 9%).

---

## 2. Identified Challenges (with citation counts)

The survey clusters problems into seven buckets (Figure 2 of the paper):

| Challenge | Times cited in surveyed lit. | Most relevant to our TCC? |
|---|---|---|
| Latency | 10 | **Yes** — our primary concern |
| Delay (round-trip + response) | 10 | **Yes** — same axis as latency, broader |
| Bandwidth | 7 | **Yes** — the resource we adapt |
| QoS / QoE | 5 | **Yes** — what we optimize |
| Packet loss | 4 | Yes — guard signal (IDR rate) |
| Graphics quality | 4 | Indirectly — QoE proxy |
| Cost of providing service | 3 | No — we are not a cloud provider |
| Complexity (encoding, compression, content) | 4 | Indirectly — codec reconfig |

### Threshold numbers worth citing in the TCC

- **RTT < 70 ms** for general cloud-gaming playability — Baldovino attributes
  this to **Sužnjević and Homen 2020** (Baldovino's ref [22], *Use of
  Cloud Gaming in Education*, IntechOpen). This is the peer-reviewed
  benchmark we should cite when defining "degraded" in our scenarios.
- **~100 ms** input-to-response budget for action games, **~150 ms** for
  slow-paced games — Baldovino's ref [36], **Mossad et al.** (DeepGame).
- **1% packet loss makes cloud-based games unplayable** — Baldovino's
  refs [19] (Lindstrom et al., *Cloud Gaming: A QoE Study*) and [22]
  (Sužnjević & Homen).
- **MMORPGs tolerate up to ~100 ms** RTT (slower-paced category) —
  Baldovino's ref [26] (Jaya et al., *Rendering Server Allocation for
  MMORPG Players*).

These are the numbers we will cite as the "playability cliff" in the
methodology section of the TCC. None of them originate with Baldovino;
the survey just collects them.

---

## 3. Identified Solution Categories

The survey clusters solutions into seven buckets (Figure 3, Table 2 of
the paper):

| Solution | Solves | Relevance to our TCC |
|---|---|---|
| Lag / latency compensation | Latency, delay | Out of scope — client-side, modifies game logic (Time Warp [29]) |
| **Compression with encoding techniques** | Bandwidth, graphics quality, complexity | **Direct overlap** — our bitrate controller is this category |
| Client computing power (graphics streaming, hybrid rendering) | Graphics quality, QoE | Out of scope — needs Moonlight changes |
| Edge computing | Latency, bandwidth, delay, packet loss | Orthogonal — moves the server closer; we instead adapt the encoder |
| Machine learning | Latency, bandwidth, delay, complexity | Future work — RL controller dropped from our scope |
| Frame adaption (prediction, skipping) | Delay | Adjacent — alters framerate, not bitrate |
| GPU-based server selection | Cost | Out of scope — multi-tenant resource allocation |

**Our TCC sits squarely in "Compression with Encoding Techniques."**
The survey lists this bucket as solving bandwidth, graphics quality, and
complexity simultaneously — but warns: *"May be ineffective if there is
excessive network congestion."* That caveat is precisely the gap our
delay-driven controller addresses: prior compression-based work changes
*how* you encode, not *how much* you encode in response to *observed
congestion*.

---

## 4. Primary Papers Worth Pursuing Directly (via Baldovino)

The survey's biggest value to us is as a discovery layer. Below are
referenced primary papers that bear directly on idea #10 and that we
have not yet read:

| Ref | Paper | Why it matters |
|---|---|---|
| [20] | Doyle et al., **"Strife"** — *Cloud Strife: Expanding the Horizons of Cloud Gaming Services* (IEEE SERVICES 2017) | Adapts compression *type* per client; closest spirit to ABR at a coarser knob. Worth checking how they trigger adaptation. |
| [27] | Slivar et al., *Game Categorization for Deriving QoE-Driven Video Encoding Configuration Strategies for Cloud Gaming* (ACM TOMM 2018) | Explicitly identifies our exact problem: *"configuring encoding parameters for game streaming when bandwidth is diverse."* Likely a category-tree of recommended encoder settings per game genre. |
| [30] | Alos, Moran et al., **"Congestion Control for Cloud Gaming Over UDP Based on Round-Trip Video Latency"** (IEEE Access 2019) | **Top-priority read.** Round-trip video latency as a control signal is functionally identical to our RTT-inflation approach. Probably the closest non-ABRAGame algorithm prior art for us. |
| [31] | Zhang et al., **"EdgeGame"** — *Improving Cloud Gaming Experience through Mobile Edge Computing* (IEEE Wireless Commun. 2019) | Uses deep learning at the edge to adapt bitrate to network conditions. Edge-side, but the learned-controller framing is interesting. 50% network delay reduction, 20% QoE improvement claimed. |
| [36] | Mossad et al., **"DeepGame"** — *Efficient Video Encoding for Cloud Gaming* (ACM MM 2021) | Learns player's contextual interest via DNN; encodes attention zones at higher quality. Reduces bandwidth 19–36% without QoE loss. Orthogonal axis from bitrate ABR — could compose. |
| [38] | Li et al., **"Themis"** — *Efficient and Adaptive Resource Partitioning for Reducing Response Delay in Cloud Gaming* (ACM MM 2019) | **Correction to our prior notes:** Themis is **RL for server-side resource partitioning** (CPU/GPU allocation across colocated games), *not* RL for bitrate adaptation. Their 17–36% delay reduction is on response delay, not RTT. Less directly relevant than we assumed. |
| [46] | Anand & Wenren, **"CloudHide"** — Latency Hiding Techniques for Thin-Client Cloud Gaming (ACM MM 2017) | Predictive frame pre-generation to hide latency. Out of scope for us but interesting for "what would we do *after* adaptive bitrate?" |
| [47] | Nguyen et al. — Delay-Aware Adaptation Framework Under User-Device Computation Constraint (MMM 2020) | Frame skipping + discarding to balance buffering vs smoothness. Closest *frame-rate* adaptation paper for the joint (fps, bitrate) follow-on PR Hong2015 motivates. |

If we add only one paper to the next reading slot: **Alos et al. 2019
(IEEE Access ref [30])** — round-trip video latency as the congestion
signal. Same statistic as our RTT inflation; likely the closest
methodological prior art that exists.

---

## 5. Corrections to Our Previous Notes

The earlier `related-work.md` entry contained two overstatements that
trace back to a loose reading of this survey:

### Correction 1 — Themis state/reward design

**Previous (wrong):** *"RL state/reward design from Themis: state =
{latency, jitter, estBW}; reward = maximize bitrate while minimizing RTT
and IDR requests. Directly informs our RL controller design."*

**Correction:** Baldovino describes Themis as *"reinforcement learning to
adaptively partition resources for reducing delay in cloud gaming"* —
i.e., **server-side CPU/GPU resource allocation across colocated games,
not bitrate adaptation.** The state/reward sketch above was projection,
not what the Themis paper actually does. Since we dropped RL from the
TCC, the correction is moot for our final scope, but the file should not
misattribute the algorithm.

### Correction 2 — "17–36% reduction in response delay" as an RL/ABR target

**Previous (wrong):** *"Themis result: 17–36% reduction in response delay
— gives us a target range for what RL can achieve."*

**Correction:** This number is response delay reduction from **resource
partitioning**, not from any bitrate or encoding adaptation. It is not a
comparable target for a delay-based ABR controller. The analogous number
from this survey is **Zhang et al. EdgeGame's claimed 50% network delay
reduction and 20% QoE improvement** — both via *edge offloading*, also
not directly comparable to in-codec ABR but at least operating in the
same problem space.

---

## 6. What the Survey Confirms Across All 33 Papers

These are the points where the surveyed literature converges, and which
are therefore safe to assert in the TCC without citing any one specific
paper:

- **Latency is the dominant failure mode** in cloud gaming. Cited in 10/33
  surveyed papers as the primary concern.
- **VoD-style buffering / retransmission cannot be applied** to real-time
  gaming. Cited repeatedly as a constraint that distinguishes cloud
  gaming from Netflix-style streaming.
- **Packet loss above ~1% degrades playability rapidly.** Multiple
  papers converge on this threshold.
- **Different game genres have different tolerances** — FPS (~100 ms),
  RPG (~500 ms), RTS (~1 s) — and so a single configuration cannot serve
  all games. This motivates per-game tuning (Slivar et al. [27]) or
  adaptive control that is genre-agnostic (what we do).
- **Wireless / Wi-Fi is the dominant source of instability** in
  consumer-side deployments.

---

## 7. Limitations of the Survey Itself

- **Indonesian undergraduate-tier journal** (JINITA, ISSN 2715-9248);
  not peer-reviewed at the level of TCSVT/ACM TOMM. Use it as a
  reading-list pointer, not as a load-bearing citation.
- **Five-year window** (2017–2022) misses both the foundational papers
  (ABRAGame is 2025, GCC is 2016, Hong2015 is 2015) and the most recent
  developments.
- **Only 33 papers** — the 7 challenges / 7 solutions clustering is
  shallow; some papers fit several buckets and get arbitrarily assigned.
- **No depth on individual algorithms** — most entries are 1–3 sentence
  paraphrases. We have to read the primary papers to do anything with the
  pointers.

---

## 8. How We Use This Paper in the TCC

- Cite for the **70 ms RTT playability threshold** (via Sužnjević & Homen).
- Cite for the **100 / 150 ms input-to-response budgets** (via Mossad et al.).
- Cite for the **1% packet loss unplayability threshold** (via Lindstrom
  et al. / Sužnjević & Homen).
- Cite as the source of the **"compression with encoding techniques" /
  "edge computing" / "frame adaption" / "ML"** taxonomy when positioning
  our work in the literature landscape.
- Use the references list as a discovery hub for the **Alos et al. 2019**
  paper (round-trip video latency, IEEE Access) and **Slivar et al. 2018**
  (game categorization for encoding strategy) — both directly relevant
  primary sources we have not yet read.

---

## Related
- [[abragame]] — algorithm prior art (post-dates this survey)
- [[gcc]] — receiver-side delay-gradient ABR (pre-dates this survey;
  cited as comparison baseline by ABRAGame but not surveyed here)
- [[hong2015]] — implementation prior art (pre-dates this survey)
- [[related-work]] — synthesis across all surveyed papers
- [[idea-10-abr-comparison]] — our controller plan

## Sources
- Baldovino, B. *An Overview of the Networking Issues of Cloud Gaming:
  A Literature Review*. Journal of Innovation Information Technology and
  Application (JINITA), Vol. 4, No. 2, pp. 120–132, December 2022.
  DOI: 10.35970/jinita.v4i2.1581.
