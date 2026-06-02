# Video Frame Types: I, P, B, and IDR

## What is it?
In video encoding, not every frame is stored independently. Encoders exploit temporal redundancy — the fact that consecutive frames are usually very similar — to reduce bandwidth. Different frame types encode different amounts of information.

## Why it matters for Sunshine / TCC
Game streaming uses these frame types constantly. Understanding them is essential for:
- Understanding why IDR requests happen during packet loss (adaptive streaming, idea #8)
- Understanding latency trade-offs (more I-frames = more bandwidth but better recovery)
- Reading Sunshine's stream logs and feedback signals in `stream.cpp`

## Key Concepts

### Frame types

**I-frame (Intra-coded frame / keyframe)**
- A complete, self-contained image — no dependency on other frames
- Can be decoded alone
- Large (high bandwidth cost)
- The decoder's reference buffer is **not** reset — P-frames after it can still reference frames from before it

**P-frame (Predictive frame)**
- Only stores what *changed* since the last reference frame
- Much smaller than an I-frame
- Depends on the previous frame — if that frame is lost, this one can't be decoded

**B-frame (Bidirectional frame)**
- Depends on both the previous and next frames
- Smallest of the three
- Rarely used in game streaming — they introduce latency because you need a future frame to decode the current one

**IDR frame (Instantaneous Decoder Refresh)**
- A special I-frame that also **resets the decoder's reference buffer**
- After an IDR, nothing can reference any frame before it — hard boundary
- Used in game streaming as a recovery mechanism: when the client loses packets and can't decode, it requests an IDR to get a guaranteed clean slate

### I-frame vs IDR — the key difference

| | I-frame | IDR |
|--|---------|-----|
| Contains full image | ✅ | ✅ |
| Resets reference buffer | ❌ | ✅ |
| P-frames after can reference before | ✅ | ❌ |
| Used for recovery after packet loss | ❌ insufficient | ✅ |

A regular I-frame isn't enough for recovery after packet loss — the reference buffer may still be corrupted. Only an IDR guarantees a clean slate.

### Typical stream structure
```
IDR → P → P → P → P → I → P → P → IDR → P → P ...
 ↑                      ↑            ↑
hard reset           full image   hard reset
                   (soft keyframe)  (on client request
                                     or interval)
```

### IDR requests in game streaming
When Moonlight loses packets and FEC can't recover them, it can't decode subsequent P-frames. It sends an **IDR request** to Sunshine via the control channel (`stream.cpp`). Sunshine responds by encoding the next frame as an IDR.

Frequent IDR requests = symptom of bad network conditions. Used as an input signal for adaptive streaming (idea #8) alongside packet loss rate and FEC usage.

### Why B-frames are avoided in game streaming
B-frames require a future frame to decode the current one — meaning you have to delay output until you receive the next frame. In game streaming, where every frame must be displayed immediately, this latency is unacceptable.

## Related
- [[loss-recovery]] — FEC/RFI/IDR escalation ladder; IDR as the last-resort rung
- [[architecture]] — stream.cpp handles IDR requests from Moonlight
- [[idea-08-adaptive-streaming]] — IDR request rate as input signal

## Sources
- Sunshine source: `src/stream.cpp` — `IDX_REQUEST_IDR_FRAME` packet type
- H.264 spec: IDR NAL unit type
