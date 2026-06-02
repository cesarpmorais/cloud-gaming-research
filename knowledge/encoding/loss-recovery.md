# Loss Recovery: FEC, RFI, and IDR

## What is it?
Three mechanisms a low-latency video stream uses to survive packet loss. They
sit at three different layers and form an **escalation ladder** — from cheap and
automatic to expensive and manual:

1. **FEC** — preventive redundancy; recovers small loss locally, no feedback.
2. **RFI** — surgical reference repair; one round trip, cheap.
3. **IDR request** — full decoder reset; one round trip, expensive.

Each rung is used only when the rung below it fails.

## Why it matters for Sunshine / TCC
- All three are visible to Sunshine as control-channel feedback and are exported
  by PR #1's CSV (`fec_events`, `missing_packets`, `unrecoverable_frames`,
  `rfi_requests`, `idr_requests`).
- The adaptive controller in [[idea-10-abr-comparison]] is built on reading this
  feedback. Knowing which rung the client actually uses under loss decides which
  column is the usable congestion signal.
- Empirically (see [[stats-export-findings]]), under netem loss Moonlight skips
  the RFI rung and storms straight to IDR requests — so **IDR-request rate**, not
  FEC status, is the loss signal that survives to the server.

## Key Concepts

### FEC — Forward Error Correction
- **Layer:** packet. **Direction:** proactive. **Feedback:** none.
- The sender adds redundant Reed-Solomon **parity packets** to every frame
  *before* any loss happens ("forward" = correction data sent ahead of need).
- If a few of a frame's packets drop, the client rebuilds them locally from
  parity — no request, no round trip, no visible glitch.
- **Cost:** constant bandwidth overhead (the parity packets).
- **Limit:** recovers only *within a single frame*, and only while losses stay
  under the parity budget. Beyond that the frame is **unrecoverable** and
  recovery must escalate to a feedback-based rung.
- In Moonlight↔Sunshine, the client reports FEC outcomes back via
  `SS_FRAME_FEC_STATUS` (packet type `SS_FRAME_FEC_PTYPE`, 0x5502) — but only on
  a loss/recovery event, and sent **unreliably** (best-effort), so it is a poor
  signal under loss. See [[stats-export-findings]].

### RFI — Reference Frame Invalidation
- **Layer:** frame reference. **Direction:** reactive. **Feedback:** 1 round trip.
- *The scalpel.* When a frame is lost, every following P-frame that references
  it decodes wrong (corruption / smearing).
- Instead of demanding a full keyframe, the client tells the server *"frames
  X..Y are bad — stop using them as references."* The encoder codes the next
  frame against an older **known-good** reference, yielding a near-normal,
  decodable P-frame.
- **Cost:** small — a slightly larger P-frame, not a keyframe.
- **Needs:** encoder support for long-term / explicit reference selection.
- Sunshine packet: `IDX_INVALIDATE_REF_FRAMES`. The repaired frame carries the
  `after_ref_frame_invalidation` flag.

### IDR request — Instantaneous Decoder Refresh
- **Layer:** decoder reset. **Direction:** reactive. **Feedback:** 1 round trip.
- *The sledgehammer.* The client gives up on patching and asks for a full
  **intra-coded keyframe**: it depends on nothing, resets the decoder entirely,
  and guarantees recovery.
- **Cost:** large — an IDR is often 5–10x the size of a P-frame, so a burst of
  IDR requests **inflates** delivered bitrate (the ~2.5 → ~8 Mbps spike seen in
  the loss-test CSV).
- Sunshine packet: `IDX_REQUEST_IDR_FRAME`. See [[frame-types]] for I-frame vs
  IDR (an IDR additionally resets the reference buffer).

### The escalation ladder
```
small loss  ──►  FEC absorbs it silently        (no feedback, automatic)
FEC fails   ──►  RFI repairs the reference chain (1 RTT, cheap)
RFI can't   ──►  IDR request resets the decoder  (1 RTT, expensive, bitrate spike)
```
RFI "can't help" when too much is lost, no good reference frame is available, or
the encoder lacks long-term-reference support.

## Related
- [[frame-types]] — I/P/B/IDR frame types; I-frame vs IDR distinction
- [[stats-export-findings]] — why FEC status is unusable as a loss signal, and
  why IDR-request rate is the working one
- [[idea-10-abr-comparison]] — the adaptive controller built on this feedback
- [[bitrate-control]] — full bitrate flow and client-feedback handling
- [[architecture]] — `stream.cpp` control-channel handlers

## Sources
- `Sunshine/src/stream.cpp` — `IDX_REQUEST_IDR_FRAME`, `IDX_INVALIDATE_REF_FRAMES`,
  and the `SS_FRAME_FEC_PTYPE` (0x5502) handlers
- `moonlight-common-c/src/RtpVideoQueue.c` — FEC recovery and the
  `reportFinalFrameFecStatus` trigger sites (lines 344, 596, 640)
- `moonlight-common-c/src/ControlStream.c` — FEC status sent unreliably
  (`ENET_PACKET_FLAG_UNSEQUENCED`, line 1329); `connectionSendFrameFecStatus`
  marked best-effort (line 415)
- H.264 spec — IDR NAL unit; long-term reference frames
