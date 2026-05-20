# Idea: ML-Based Adaptive Bitrate (ABR) Controller

Status: 💡 raw

## Description
Replace or augment Sunshine's bitrate adaptation logic with a machine learning model that learns to pick optimal streaming parameters based on observed network state.

The agent would observe:
- Recent packet loss rate and RTT (from control channel)
- Current bitrate and FPS
- FEC usage rate
- Delivered vs target bitrate ratio

And output: target bitrate adjustment for the next interval.

The model could be pre-trained offline (using data collected via idea #7) and deployed as a lightweight inference module inside Sunshine, or run as a sidecar process.

## ⚠️ Starting Point: Find the Actual State of the Art

Before developing this idea further, a literature search is required. Key questions:

1. What is the current (2023–2025) state of the art for **interactive/game streaming** ABR — not video-on-demand?
2. Do recent papers use RL, transformers, or other approaches?
3. What datasets and metrics do they evaluate on?
4. Is there open-source code to build on?

Suggested search terms (Google Scholar):
- "adaptive bitrate game streaming 2024"
- "interactive video streaming reinforcement learning 2024"
- "low latency adaptive streaming deep learning 2023 2024"
- "real-time video streaming quality adaptation neural"

Known starting references (foundational, not necessarily current):
- **Pensieve** (Mao et al., SIGCOMM 2017) — RL for ABR; designed for VoD, not game streaming
- **Salsify** (Fouladi et al., NSDI 2018) — joint encoder+transport co-design; more relevant to interactive streaming
- **BOLA** (Spiteri et al., 2016) — buffer-based optimization baseline

Note: Pensieve is the most cited paper but is from 2017 and targets chunk-based VoD. Game streaming (no buffer, frame-by-frame, <100ms latency) has different constraints. The real state of the art for this use case may be significantly different.

## Why it matters for TCC
- **Academic angle**: connects to state-of-the-art streaming research
- **Novel**: no ML-based ABR exists in Sunshine or any Moonlight fork
- **Data pipeline**: idea #7 (stats export) provides training data; idea #8 (adaptive streaming) is the rule-based baseline to beat
- The TCC narrative becomes: baseline → rule-based ABR → ML ABR → evaluation

## Related Ideas
- [[idea-07-stats-export]] — training data source
- [[idea-08-adaptive-streaming]] — rule-based baseline this would improve upon

## Related Knowledge
- [[architecture]] — bitrate control in `src/video.cpp` and `src/stream.cpp`
