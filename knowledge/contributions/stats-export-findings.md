# Streaming Stats Export — Development Findings

## What is it?
Notes from building PR #1 of the TCC: a per-session CSV export of server-side
streaming statistics in Sunshine, plus a new handler for Moonlight's per-frame
FEC status packet. This file records what was discovered while implementing and
testing it — several points contradict earlier assumptions in [[bitrate-control]]
and [[idea-10-abr-comparison]].

The export is gated by a `stats_export_path` config option (empty = disabled).
When set, Sunshine writes one CSV row per fixed 200 ms interval for each
streaming session.

## Why it matters for Sunshine / TCC
- PR #1 is the instrumentation layer that every later step of
  [[idea-10-abr-comparison]] depends on.
- The empirical results reshape the adaptive controller's signal design: the
  loss signal we planned to build on barely exists in practice.
- Documents the protocol reality so a future contributor — or the thesis
  reader — does not repeat the dead-end.

## Key Concepts

### IDX_LOSS_STATS is dead code for Sunshine
Moonlight only sends `IDX_LOSS_STATS` (0x0201) to legacy GFE servers; the
codepath is guarded by `LC_ASSERT(!IS_SUNSHINE())`. The handler in `stream.cpp`
is never reached by a modern Moonlight ↔ Sunshine session. An earlier
implementation attempt failed because it instrumented this dead handler.

### SS_FRAME_FEC_STATUS (0x5502) is the real per-frame loss packet
- Modern Moonlight reports loss via `SS_FRAME_FEC_STATUS` on packet type
  `SS_FRAME_FEC_PTYPE` (0x5502), big-endian, 21 bytes.
- It is **event-driven**: sent only on a loss or FEC-recovery condition (three
  send sites in `RtpVideoQueue.c`). A cleanly received frame produces nothing.
- It is sent **unreliably** — `sendMessageEnet(..., ENET_PACKET_FLAG_UNSEQUENCED)`
  (`ControlStream.c:1329`), and `connectionSendFrameFecStatus` marks it
  "best-effort only". No retransmit, no ordering. The report rides the very path
  it describes, so under loss the report itself is dropped at the loss rate.
- Sunshine had **no handler** for incoming 0x5502 — the packets were dropped.
  PR #1 adds `server->map(0x5502, ...)`.
- 0x5502 is also Sunshine's outgoing `IDX_SET_RGB_LED`; there is no conflict
  because `server->map` only dispatches inbound packets.
- Apollo does not handle it either — the contribution space is open.

### Empirical: FEC status barely fires under netem random loss
- Test: netem 10% then 50% packet loss, ~71 s session, RTX 4070 + Moonlight
  Android client.
- `SS_FRAME_FEC_STATUS` arrived **once** (during connection startup). Across
  both deliberate-loss windows: **zero events**.
- The handler is proven correct — it recorded that one startup event — so the
  packets simply are not arriving during loss.
- Now explained: the lone event landed during connection startup, *before*
  `packetloss init` was run, so its unreliable report had a clean path. Every
  later report was sent into active netem loss and dropped (see the unreliable
  transport above). The signal self-destructs exactly when its condition holds.

### IDR-request rate is the loss signal that actually works
- Under loss the client responds with an **IDR-request storm**: `idr_requests`
  jumps from 0 to ~5–10/s, the encoder emits back-to-back keyframes, and the
  delivered bitrate *inflates* (~2.5 Mbps → ~8 Mbps) instead of dropping.
- IDR-request density even distinguishes severity: 10% loss leaves gaps between
  active rows; 50% loss shows IDR activity in essentially every 200 ms row.
- Conclusion: the server-observable congestion signal to build the controller
  on is **IDR-request rate** (plus bitrate inflation), not FEC status. This
  inverts the plan in [[idea-10-abr-comparison]], which treated FEC status as
  the primary trigger and IDR requests as a lagging confirmation.
- `IDX_INVALIDATE_REF_FRAMES` (RFI) requests are also counted (`rfi_requests`
  column) as a second candidate loss signal.
- **Caveat (later finding):** IDR-request rate is a working *detector* but it
  **saturates** — 10% vs 50% loss barely changes the per-tick magnitude, only
  the density of active ticks. It is a ~3-level indicator, not a graded
  congestion gauge. More fundamentally, random loss is not the impairment an
  adaptive bitrate controller can fix; RTT under bandwidth constriction is the
  signal to build on. See [[research-journey]] (Stages 4–6).

### The CSV must be server-paced
Because the loss packet is event-driven, CSV rows cannot be triggered by client
packets — a clean network would yield an empty file. Rows are written on a
fixed server-side tick (200 ms) driven by the video broadcast loop; FEC events
are accumulated into whichever row is currently open.

### Resolved: why FEC status does not survive loss
Earlier this was an open question — "lost in transit" vs "never generated". The
source settles it: FEC status is sent **unreliably and best-effort**
(`ENET_PACKET_FLAG_UNSEQUENCED`), so loss in transit is the *expected, designed*
behaviour — not a Sunshine dispatch bug. There is nothing to "fix": the packet
is structurally unusable as a loss signal under the loss it reports.

The Moonlight Android logcat (`adb logcat -s moonlight-common-c`, `Unrecoverable
frame` lines) is now only a secondary check on *how many* FEC events the client
generates — useful for the thesis writeup, not a blocker for PR #1.

### Tier 1: server-side network metrics added to the CSV
After the random-loss findings above, the CSV was extended with server-side
network columns (18 total): `rtt_ms` / `rtt_var_ms` (ENet `peer->roundTripTime`),
`avg_send_ms` (per-frame dispatch time), `target_kbps` (negotiated encoder
target), `packets_sent`, and `stalls` / `stall_ms` (gaps ≥ 100 ms between
dispatched frames — `videoBroadcastThread` freezes).

Note: `target_kbps` is the *negotiated* target, not the client's bitrate slider.
Moonlight transforms the slider before the RTSP handshake (observed: a 25 Mbps
slider negotiates 18988 kbps), consistent with reserving ~20% for FEC overhead.

### Bandwidth limiting and random loss have opposite signatures
A `tc htb` test capped at 5 Mbps
(`data/metrics/sunshine-stats-20260520-193640.csv`):

| Impairment | RTT | IDR-request rate | FEC events |
|---|---|---|---|
| Random loss (`netem loss`) | calm | storm | ~zero (unreliable transport) |
| Bandwidth limit (`tc htb`) | inflates ~5 → 1600 ms | near-zero | near-zero |

Under a bandwidth cap the `htb` queue **delays** packets rather than dropping
them, so RTT inflates **monotonically** (bufferbloat) while the loss-recovery
machinery stays quiet; RTT decays back once the cap is lifted. This is the
graded congestion signal the controller needs — and, since ABR adapts to
*bandwidth*, it is the correct one. See [[research-journey]] Stage 7.

### `avg_send_ms` is a weak signal
It stays ~0 most of the time (the send socket absorbs without blocking) and only
spikes (~230–290 ms) on full kernel send-buffer saturation, coinciding with
~1.7 s `videoBroadcastThread` freezes. A late, binary indicator — the `stalls`
columns capture the freezes more directly.

## Related
- [[loss-recovery]] — FEC/RFI/IDR escalation ladder; the concepts behind these findings
- [[bitrate-control]] — full bitrate flow; Step 5 corrected with these findings
- [[idea-10-abr-comparison]] — signal design; its "Input signals" section is
  superseded by the IDR-rate finding here
- [[idea-07-stats-export]] — original scope of the CSV export idea
- [[frame-types]] — IDR frames, and why an IDR storm inflates bitrate

## Sources
- `Sunshine/src/stat_trackers.{h,cpp}` — `csv_stats_logger`
- `Sunshine/src/stream.cpp` — 0x5502 handler, IDR/RFI counters, frame recording
- `Sunshine/src/config.{h,cpp}` — `stats_export_path` option
- `moonlight-common-c/src/RtpVideoQueue.c:92` — `SS_FRAME_FEC_STATUS` build and the loss-only send sites
- `moonlight-common-c/src/ControlStream.c` — loss-stats thread (`:1309`, Sunshine vs legacy GFE branch); FEC status sent unreliably (`:1329`, `ENET_PACKET_FLAG_UNSEQUENCED`); `connectionSendFrameFecStatus` best-effort (`:415`)
- `data/metrics/sunshine-stats-20260519-203714.csv` — the 10% / 50% loss test run
- `data/metrics/sunshine-stats-20260520-193640.csv` — the 5 Mbps bandwidth-limit test run
- `testbed/scenarios.md` — bandwidth-shaped test scenarios
