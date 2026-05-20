# Paper Analysis: ABRAGame — Automatic Bit Rate Adjustment for Cloud Gaming  
**Armendariz & Joskowicz, 2025 — Multimedia Tools and Applications**

---

## 1. Problem Framing
ABRAGame optimizes for **playability maintenance under network degradation**. Their definition of "good" streaming is the absence of visual degradations caused by frame loss — specifically, frozen screens and visual artifacts that occur when P-frame packets arrive late or are lost entirely.  

The optimization priority is clearly **stability over quality**: they explicitly accept reduced video resolution/quality (via lower bitrate) in exchange for uninterrupted gameplay. They are not optimizing for maximum visual quality or minimum latency per se, but rather for preventing catastrophic failures (frame freezes, long recovery times, session loss) that destroy the gaming experience.  

A secondary goal is **fast recovery** — once network conditions improve, the bitrate should ramp back up to restore visual quality.

---

## 2. Input Signals
The algorithm uses three main metrics, all computed client-side every 20 ms:

- **Average Network Latency (AvgNetLat):**  
  One-way delay from server to client, calculated as the mean packet delay within each 20 ms measurement window. Requires clock synchronization between client and server.

- **Estimated Bandwidth (estBW):**  
  Sum of all received bits divided by the measurement window duration. Represents actual received throughput (not channel capacity).

- **Average Bit Rate (AvgBitRate):**  
  The server's current encoding rate, sent to the client to indicate the current operating point.

### Derived Signal
- **Cumulative latency over a 500 ms sliding window**
  - Latency sampled every 20 ms
  - Sum over 500 ms window
  - Threshold: **2000**
  - Equivalent to sustained latency ≈ **80 ms for 500 ms**
  - Exceeding threshold triggers a **degradation alarm**

**Not used:**
- Packet loss rate  
- Jitter  
- Buffer occupancy  
- Video quality metrics (PSNR, SSIM)

---

## 3. Algorithm / Approach

### Core Mechanism
Rule-based threshold system with two components:

### Prediction Component
- Sliding window (500 ms) accumulates latency
- If cumulative latency > 2000 → trigger alarm

**Rationale:**
- Avoids slope-based false positives (e.g., C3G, GCC)
- Transient spikes do not trigger alarms unless persistent

---

### Bitrate Decrease
- On alarm:
  ```
  new bitrate = estBW − BWmargin
  ```
- **BWmargin:** 1.5 Mbps  
- **Step size (BWstep):** 0.5 Mbps  
- Response time: ~500 ms  

---

### Bitrate Increase
- After a prediction event:
  - Start **20-second timer**
  - If no new alarm:
    - Increase bitrate by 0.5 Mbps
    - Restart timer
  - If alarm occurs:
    - Apply decrease logic

**Note:** Conservative linear increase (authors suggest exponential as future work)

---

### Architecture
- Entirely client-side
- Reads logs from client app
- Runs as separate process
- Sends bitrate commands via control channel
- **No server modifications required**

---

## 4. Evaluation Methodology

### Platform
- Real cloud gaming platform (ABYA Go)

### Network Emulation
- Linux bridge (Ubuntu 20.04)
- NetEm for traffic shaping
- Wired Ethernet setup (no Wi-Fi variability)

### Network Scenarios (240 s each)
- **A:** Abrupt drop + rapid recovery  
- **B:** Gradual drop + fast recovery  
- **C:** Slow drop + fast recovery  
- **D:** Intermittent fluctuations  
- **E:** Long drop + abrupt recovery  
- **F:** Low start + late improvement  

### Latency Conditions
- Low: ~7 ms  
- High: +50 ms  

### Games Tested
- 15 games
- Genres: FPS, Racing, RPG, Fighting
- Sessions:
  - 183 (prediction)
  - 182 (bitrate adjustment)

### Baselines
- Slope-based algorithm (C3G-like)
- Qualitative comparison with:
  - Stadia
  - GeForce Now
  - PS Now
  - xCloud

### Metrics
- Prediction accuracy  
- False positives  
- Unpredicted degradations  
- Effective loss cancellation rate  
- Recovery time  
- Qualitative playability  

---

## 5. Key Results

### Prediction Performance
- **100% detection** (0 missed events out of 269)
- **10.3% false positives** (31 / 300)
- vs slope-based:
  - 56% false positives
  - 11% missed degradations

---

### Bitrate Adjustment
- **85.9% effective loss cancellation** (324 / 377)
- Failed cases:
  - Avg interruption: **4.5 seconds**
  - Without system: 20+ seconds or session loss

---

### Comparison with Platforms (Literature)
- Stadia:
  - ~80 s to stabilize
  - >200 s transient phase
- PS Now:
  - ~20 s recovery
  - Initial stall
- ABRAGame:
  - **4.5 s worst-case recovery**

---

### Worst Conditions
- 14.1% failure cases not deeply analyzed
- Racing games had most failures:
  - 25 / 154

---

## 6. Game Streaming Specifics

### Design Assumptions
- No buffering or retransmission
- Strict latency constraints

### Encoding
- **Infinite GOP (H.264)**
  - One I-frame at start
  - Only P-frames afterward
  - Loss causes cascading corruption

### Transport
- RTP over UDP (custom)

### Latency Sensitivity
- FPS: ~100 ms  
- RPG: ~500 ms  
- RTS: ~1 s  

### Interactivity
- Uplink uncongested
- Control signals reliably reach server

---

## 7. Gaps and Limitations

### Acknowledged
- Limited analysis of false positives  
- Linear increase is conservative  
- No formal QoE testing (ITU-T P.809)  
- No QoE model comparison (e.g., G.1072)  

---

### Implicit Limitations
- Fixed empirical thresholds  
- Requires clock synchronization  
- No packet loss input  
- Limited bandwidth range (3–15 Mbps)  
- No resolution/framerate adaptation  
- Platform-specific instrumentation  

---

## 8. Directly Reusable Elements for Sunshine TCC

| Element | How to Adapt |
|--------|-------------|
| NetEm testbed | Reproduce Linux bridge + NetEm setup |
| Latency accumulation | Use as congestion signal |
| BWmargin / BWstep | Map to AIMD tuning parameters |
| 20s recovery timer | Baseline for additive increase |
| Evaluation metrics | Use same stability metrics |
| Genre testing | Maintain cross-genre evaluation |
| Comparison framing | Use external platform benchmarks |
| AIMD structure | Core design alignment |

---

### Key Insight
ABRAGame is effectively an **AIMD controller**:
- Decrease: throughput − margin (multiplicative-ish)
- Increase: fixed additive steps

**Main distinction:**  
Triggers on **predicted congestion (latency accumulation)** rather than observed loss.
```