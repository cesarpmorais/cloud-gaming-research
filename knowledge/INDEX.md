# TCC Knowledge Base

Project: Open-source contribution to [Sunshine](https://github.com/LizardByte/Sunshine) game streaming server.
Goal: Get a PR merged as part of a Brazilian undergrad thesis (TCC).

---

## Protocols
- [[upnp]] — UPnP NAT traversal, port mapping, Sunshine's required ports for internet streaming

## Video Encoding
- [[frame-types]] — I, P, B, and IDR frames; why IDR is needed for recovery in game streaming
- [[loss-recovery]] — FEC, RFI, and IDR as a packet-loss recovery escalation ladder
- [[vulkan-encoder]] — Vulkan video encoder backend (added May 2026); cross-vendor, Linux-only

## Sunshine Internals
- [[architecture]] — full pipeline overview (capture → encode → stream → network), key files, platform abstraction, and per-idea file map
- [[dev-workflow]] — build, run, test, format, common errors and fixes
- [[nvfbc]] — NVFBC capture API and CUDA dependency; capture backend overview
- [[capture-backends]] — all Linux capture backends (post-May 2026 refactor), selection logic, current 10-bit format coverage
- [[xdgportal-pipewire-migration]] — May 2026 split of portalgrab → portalgrab + pipewire + kwingrab; what moved where
- [[bitrate-control]] — full bitrate flow: RTSP negotiation, one-time adjustment, encoder config, client feedback handling, and the gap for adaptive control
- [[encoders]] — all encoder backends (NVENC, VAAPI, AMF, Vulkan, software, VideoToolbox), selection logic, the Linux/Windows NVENC code-path split (avcodec wrapper vs standalone SDK), and per-backend runtime reconfigure support

## Linux Subsystems
- [[wayland-vs-x11]] — X11 vs Wayland architecture, how each affects screen capture
- [[dmabuf]] — DMA-BUF GPU memory sharing, DMA-BUF vs MemPtr paths in portalgrab, why drm_format=0 breaks both
- [[pipewire]] — Linux multimedia server; handles screen capture brokering on Wayland via xdg-desktop-portal

## Contributions
- [[contributing-guidelines]] — PR rules, semantic commit format, clang-format, gtest, Codecov, localization
- [[sunshine-ci-pipeline]] — what runs on a PR, SonarCloud thresholds (lambda 20 lines, params 7), gh-pages flake, first-PR maintainer approval
- [[stats-export-findings]] — PR #1 dev notes: dead IDX_LOSS_STATS, FEC-status reality, and the empirical finding that IDR-request rate is the working loss signal
- [[reactive-blind-spot]] — architectural property of reactive ABR controllers: ~2–3 s detection floor that produces the initial RTT spike; what GCC, ABRAGame, and C³G each do about it
- [[results-beta-0.7]] — first-round campaign results (baseline vs adaptive at β=0.7): 7×–33× p95 RTT cuts on 5/6 degraded scenarios, scenario E as failure mode, channel-use gap vs C³G, plus ready-to-paste TCC paragraphs
- [[research-journey]] — chronological evolution of the signal & methodology understanding (Stages 0–7); TCC narrative source material

## Papers
- [[related-work]] — synthesis of surveyed ABR papers: Thompson (hybrid AI), Baldovino (literature review), ABRAGame, GCC; what we reuse and where we go further
- [[abragame]] — full analysis of ABRAGame (Armendariz & Joskowicz, 2025); closest prior work; algorithm, testbed, results, and adaptation plan
- [[gcc]] — Google Congestion Control (Carlucci et al., MMSys'16); canonical delay-gradient AIMD for WebRTC; validates our signal philosophy, defers the per-frame loop and adaptive threshold as future work
- [[hong2015]] — Enabling Adaptive Cloud Gaming in an Open-Source Cloud Gaming Platform (Hong et al., IEEE TCSVT 2015); the *implementation* prior art — GA's runtime codec reconfiguration, the 2 Mbps MOS saturation finding, and crowdsourced MOS methodology
- [[baldovino2022]] — An Overview of the Networking Issues of Cloud Gaming (Baldovino, JINITA 2022); 33-paper literature review; useful as a *citation hub* for the 70 ms RTT / 1% loss / 100–150 ms response thresholds and as a pointer to Alos et al. 2019 (RTT-based congestion control)
- [[alos2019]] — **Congestion Control for Cloud Gaming Over UDP Based on Round-Trip Video Latency (C³G)** (Alós et al., IEEE Access 2019); the closest prior work to our TCC — server-side, RTT-based ABR on the PlayGiga CG platform, BBR-inspired, with a reactive drain + proactive state-dictionary policy

## Tasks
- [[fix-10bit-portal/plan]] — 🟡 partially solved upstream after May 2026 refactor; needs re-evaluation on current codebase
