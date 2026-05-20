# Bitrate Control in Sunshine

## What is it?
Bitrate is the number of bits transmitted per second. In game streaming, it is the primary lever controlling the trade-off between **visual quality** and **bandwidth consumption**.

- Higher bitrate → encoder uses more bits per frame → less compression artifacts → better image quality, but more bandwidth required
- Lower bitrate → more compression → blockiness/blurriness, but fits in a narrower pipe

Sunshine uses a **static constant-bitrate model**: bitrate is negotiated exactly once at session setup and never changes for the rest of the stream. There is no adaptive loop at runtime.

## Why it matters for Sunshine / TCC
- The static model is the gap that idea #10 (Fixed vs rule-based comparison) targets
- The only per-frame loss signal a modern Moonlight client sends (`SS_FRAME_FEC_STATUS`) is dropped unhandled by `stream.cpp` — adding that handler is the first step toward adaptive control
- Understanding the full bitrate flow is required before implementing any runtime adjustment

## Key Concepts

### The fundamental finding: Sunshine uses a static model

Bitrate is negotiated **exactly once**, at session setup, and **never changes for the rest of the stream**. There is no adaptive loop. Client feedback is received but ignored for bitrate purposes.

---

### Step 1 — Client declares its desired bitrate (RTSP SETUP)

When Moonlight connects, it sends an RTSP SETUP request containing:

```
x-nv-vqos[0].bw.maximumBitrateKbps = 20000
```

This is the client saying: "I want 20 Mbps." Sunshine receives this at `rtsp.cpp:993`.

---

### Step 2 — Sunshine adjusts the bitrate downward (once, forever)

`rtsp.cpp:1047-1071` performs three subtractions:

#### What is FEC?
**Forward Error Correction** — the sender transmits redundant data alongside the actual payload so the receiver can reconstruct lost packets without requesting a retransmission.

In game streaming, retransmission is too slow: by the time you detect a lost packet, request it, and receive it again, the frame is already late. FEC lets you absorb some loss silently with no round-trip delay.

Example: send 10 video packets + 2 FEC packets → receiver can recover any 2 lost packets from those 10 using the FEC data alone.

`config::stream.fec_percentage` defaults to 20 — meaning 20% of transmitted data is FEC overhead. So a 20 Mbps pipe has only 80% = 16 Mbps available for actual video. The bitrate adjustment below carves that space out before telling the encoder what it has to work with.

Tradeoff: higher FEC = more loss resilience but less video bandwidth. Lower FEC = better quality on clean networks but more visible degradation when packets drop.

```cpp
// 1. FEC overhead: if FEC is 20%, video gets 80% of the pipe
configuredBitrateKbps /= 100.f / (100 - config::stream.fec_percentage);

// 2. Audio bandwidth: reserve space for audio stream
auto audioBitrateAdjustment = (HIGH_QUALITY ? 256 : 96) * channels;
configuredBitrateKbps -= min(audioBitrateAdjustment, configuredBitrateKbps / 5);

// 3. Protocol overhead: 500 Kbps for headers, control data (max 10%)
configuredBitrateKbps -= min(500, configuredBitrateKbps / 10);
```

So 20,000 Kbps becomes roughly ~15,000 Kbps after adjustments. This number is written into `config.monitor.bitrate` and **never touched again**.

---

### Step 3 — Bitrate is passed to the encoder at session initialization

`video.cpp:1787-1819` takes the adjusted bitrate and configures the encoder:

```cpp
auto bitrate = min(config.bitrate, config::video.max_bitrate) * 1000; // to bits/sec

ctx->bit_rate       = bitrate;   // target
ctx->rc_max_rate    = bitrate;   // ceiling
ctx->rc_min_rate    = bitrate;   // floor (in CBR mode)
ctx->rc_buffer_size = bitrate / config.framerate;  // one frame of buffer
```

#### What each parameter means

**`ctx->bit_rate`** — the target bitrate. The encoder tries to hit this on average.

**`ctx->rc_max_rate`** — the ceiling. The encoder cannot exceed this even for a single complex frame. Setting it equal to `bit_rate` enforces CBR — no borrowing future bandwidth for hard scenes.

**`ctx->rc_min_rate`** — the floor. The encoder must produce at least this many bits per second even for a static scene, padding with filler if needed. Combined with `rc_max_rate = bit_rate`, this locks the encoder into a fixed rate.
> Only set when not in `CBR_WITH_VBR` mode. In that mode, `ctx->bit_rate` is decremented by 1 so that `rc_max_rate != bit_rate`, which some backends interpret as VBR mode.

**`ctx->rc_buffer_size = bitrate / framerate`** — the **VBV buffer** (Video Buffering Verifier, also called HRD buffer in H.264). Models the decoder's receive buffer. The encoder can temporarily draw down the buffer for hard frames and refill it on simple ones, but it can never overflow (decoder drops frames) or underrun (stream stalls). Sized to exactly one frame of data — intentionally small to minimize decoder latency.

#### What is CBR?

**Constant Bitrate** — the encoder produces a fixed number of bits per second regardless of what's on screen. The opposite is **VBR (Variable Bitrate)**, which uses more bits for complex scenes and fewer for simple ones.

```
Scene:        [explosion] [pause menu] [fast movement] [static UI]

CBR output:   15 Mbps     15 Mbps       15 Mbps         15 Mbps
VBR output:   22 Mbps      4 Mbps       20 Mbps          3 Mbps
```

VBR is more quality-efficient but unpredictable. CBR is predictable — the receiver always knows how much data is coming.

**Why Sunshine uses CBR:**
1. **Network planning** — client negotiates a fixed budget at setup; a spike to 3x the agreed rate would cause drops
2. **Latency** — VBR requires lookahead or buffering to allocate bits; lookahead is impossible in live game streaming (the next frame doesn't exist yet)
3. **Simplicity** — maps cleanly to the RTSP bitrate negotiation

**The downside:** a static menu gets the same bitrate as a firefight. The menu wastes bits on filler; the firefight gets blocky because the ceiling won't allow more. This is part of why adaptive bitrate matters — even a smarter CBR that adjusts its target rate based on network conditions would be a significant improvement over the current static setup.

#### Encoders

Each encoder backend gets the same number in different forms:

| Backend | File | Line | Parameter | Mode |
|---|---|---|---|---|
| FFmpeg (software) | `video.cpp` | 1789 | `ctx->bit_rate` | CBR |
| NVENC | `nvenc_base.cpp` | 253 | `rcParams.averageBitRate` | `NV_ENC_PARAMS_RC_CBR` |
| VAAPI | `vaapi.cpp` | 283-303 | `ctx->bit_rate` | VBR preferred, CBR fallback, CQP last resort |

All backends also configure a **VBV/HRD buffer** sized to one frame worth of data (`bitrate / framerate`).

For a full breakdown of all encoder backends, why there are multiple, the selection logic, and the implications for runtime reconfiguration, see [[encoders]].

---

### Step 4 — Every frame is encoded at that fixed bitrate forever

The encoding loop (`video.cpp:1434` for AVCodec, `1508` for NVENC) sends frames to the encoder with the bitrate already baked into the codec context. There is no per-frame or per-second bitrate update.

---

### Step 5 — Client feedback arrives… and is ignored for bitrate

A **modern Moonlight client connected to Sunshine** sends the following on the control channel:

| Message | Type | Handler | What Sunshine does | Bitrate effect |
|---|---|---|---|---|
| Periodic ping | `0x0200` | `stream.cpp:924` | Logs; keeps RTT measurement warm | **None** |
| IDR frame request | `0x0302` | `stream.cpp:952` | Signals encoder to produce an IDR frame | **None** |
| Ref frame invalidation | `0x0301` | `stream.cpp:958` | Updates encoder's reference frame predictions | **None** |
| Per-frame FEC status | `0x5502` | **none — dropped** | Nothing; Sunshine has no incoming handler | **None** |

**Critical correction:** modern Moonlight does **not** send `IDX_LOSS_STATS` (0x0201) to Sunshine. That packet and the handler at `stream.cpp:936` exist only for legacy GFE clients — Moonlight's loss-stats thread explicitly asserts `!IS_SUNSHINE()` before using that codepath (`moonlight-common-c/src/ControlStream.c:1370`). For a Sunshine session that handler is **dead code**.

Instead, modern Moonlight reports loss through `SS_FRAME_FEC_STATUS` (packet type `0x5502`), and **only when a loss or FEC-recovery condition occurs** — there are exactly three send sites in `RtpVideoQueue.c` (lines 344, 596, 640), all on loss paths. A fully-received frame produces no packet. On a clean network Sunshine receives zero of these. It *is* sent when FEC successfully recovered a frame, so "FEC had to work" arrives slightly before "frame actually lost".

**Sunshine currently has no handler for incoming `0x5502`**, so even this signal is dropped. (`0x5502` appears in Sunshine's `packetTypes[]` only as the *outgoing* `IDX_SET_RGB_LED` — same number, opposite direction, no wire conflict.)

The `SS_FRAME_FEC_STATUS` payload (big-endian) carries per-frame FEC detail: `frameIndex`, `highestReceivedSequenceNumber`, `nextContiguousSequenceNumber`, `missingPacketsBeforeHighestReceived`, `totalDataPackets`, `totalParityPackets`, `receivedDataPackets`, `receivedParityPackets`, `fecPercentage`, and multi-FEC block index/count.

---

### Complete data flow diagram

```
Moonlight                          Sunshine
─────────                          ────────
RTSP SETUP ──────────────────────► rtsp.cpp:993
  bw = 20,000 Kbps                   Extract client bitrate

                                    rtsp.cpp:1047-1071
                                    Subtract FEC + audio + overhead
                                    → adjusted = ~15,000 Kbps
                                    → config.monitor.bitrate = 15000
                                    [NEVER CHANGES AGAIN]

                                    video.cpp:1787-1819
                                    encoder initialized:
                                      ctx->bit_rate = 15,000,000 bps

                                    ┌─ encode frame ─┐
Streaming ◄──────────────────────── │ encode frame   │ (loop forever)
                                    │ encode frame   │
                                    └────────────────┘

FEC status (0x5502) ─ ─ ─ ─ ─ ─ ─► (no handler — packet dropped)
  only on loss/FEC-recovery          Moonlight's real loss signal,
  per-frame, big-endian              currently unused

IDR request ─────────────────────► stream.cpp:952
                                    video.idr_events->raise(true)
                                    ← frame type changes, bitrate doesn't
```

---

### Configuration options affecting bitrate

| Config variable | File | Default | Effect |
|---|---|---|---|
| `config::video.max_bitrate` | `config.h:143` | 0 (no limit) | Server-side bitrate ceiling |
| `config::stream.fec_percentage` | `config.cpp:523` | 20 | Drives FEC overhead reduction at setup |
| `config::video.nv_legacy.vbv_percentage_increase` | `nvenc_base.cpp:257` | 0 | Increases NVENC VBV buffer by % |
| `config::video.vaapi.strict_rc_buffer` | `vaapi.cpp:283` | false | Forces single-frame VBV on VAAPI |

---

### The gap for idea #10

Sunshine has no adaptive control. Three pieces are missing:

1. **A loss signal that's actually captured.** The only loss feedback a modern Moonlight client sends is `SS_FRAME_FEC_STATUS` (0x5502), and Sunshine drops it. The first step is adding a `server->map(0x5502, ...)` handler in `controlBroadcastThread`. This signal is **event-driven** — sent only on loss/FEC-recovery, not periodically — so a clean network produces silence; any sliding window over it must be time-based and server-paced.
2. **A bitrate decision function** (rule-based or RL) that consumes accumulated loss events.
3. **A mechanism to reconfigure the running encoder mid-session** — does not currently exist and is the key technical challenge.

## Related
- [[architecture]] — overall pipeline; `stream.cpp` and `video.cpp` roles
- [[frame-types]] — IDR requests as a signal of network degradation
- [[idea-10-abr-comparison]] — the TCC contribution targeting this gap

## Sources
- `src/rtsp.cpp:993` — client bitrate reception
- `src/rtsp.cpp:1047-1071` — one-time session bitrate adjustment
- `src/video.cpp:1787-1819` — encoder initialization with bitrate
- `src/video.cpp:1434-1526` — encoding loop (fixed bitrate per frame)
- `src/stream.cpp:924-969` — client feedback handlers (periodic ping, legacy loss stats, IDR, ref frame invalidation)
- `moonlight-common-c/src/ControlStream.c:1309` — Moonlight's loss-stats thread: Sunshine branch (`usePeriodicPing`) vs legacy GFE branch
- `moonlight-common-c/src/RtpVideoQueue.c:92` — `SS_FRAME_FEC_STATUS` construction; three loss-only send sites at lines 344, 596, 640
- `src/nvenc/nvenc_base.cpp:244-260` — NVENC rate control config
- `src/platform/linux/vaapi.cpp:283-303` — VAAPI rate control config
