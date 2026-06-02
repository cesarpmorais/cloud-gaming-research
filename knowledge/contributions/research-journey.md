# Research Journey — How the Signal & Methodology Understanding Evolved

## What is it?
A chronological record of how this project's understanding of the **congestion
signal** and the **test methodology** changed while building PR #1. Each stage
states an assumption, what disproved it, and the correction it forced. It exists
so the TCC can narrate the *evolution* of the research — why the final design is
what it is — instead of presenting only the endpoint.

## Why it matters for Sunshine / TCC
- The thesis argument is stronger when each wrong turn visibly motivates the
  next decision; a reader sees reasoning, not just a result.
- It records dead ends so a future contributor does not repeat them.
- Stages 4–7 reshape the [[idea-10-abr-comparison]] plan: both the testbed
  impairment and the controller's input signal change as a result.

## Key Concepts

### Stage 0 — Assumption: Moonlight streams loss data continuously
Initial belief: a modern Moonlight client continuously reports packet-loss
statistics that Sunshine can read, so instrumenting the existing
`IDX_LOSS_STATS` handler would yield a loss signal for free. A first
implementation attempt was built directly on this assumption.

### Stage 1 — Correction: `IDX_LOSS_STATS` is dead code for Sunshine
`IDX_LOSS_STATS` (0x0201) is a legacy-GFE-only codepath, guarded by
`LC_ASSERT(!IS_SUNSHINE())`. A modern Moonlight↔Sunshine session never sends it,
so the handler is never reached. The first attempt failed because it
instrumented this dead path. The real per-frame loss packet is
`SS_FRAME_FEC_STATUS` (`SS_FRAME_FEC_PTYPE`, 0x5502) — which Sunshine had **no
handler for at all** and silently dropped.

### Stage 2 — Correction: the loss packet is event-driven, not periodic
`SS_FRAME_FEC_STATUS` is sent **only** on a loss or FEC-recovery condition. On a
clean network the server hears nothing. Consequence: CSV rows cannot be driven
by client packets (a clean run would produce an empty file). Rows must be
**server-paced** — written on a fixed 200 ms tick, with events accumulated into
whichever row is open.

### Stage 3 — Correction: the loss packet self-destructs under loss
`SS_FRAME_FEC_STATUS` is sent **unreliably** — `ENET_PACKET_FLAG_UNSEQUENCED`,
explicitly best-effort. It travels the same path it describes, so under netem
loss the report itself is dropped at the loss rate, with no retransmission.
Empirically it fired exactly **once** in a 71 s test (during startup, before
loss was applied) and never again. The pivot: stop relying on FEC status; use
**IDR-request rate** as the working server-observable loss signal.

### Stage 4 — Correction: IDR-request rate saturates
The 10% / 50% loss test showed IDR-request rate is a working *detector* but a
poor *gauge*. Per-tick magnitude barely changed between 10% and 50% (0–2
requests either way); only the **density** of active ticks rose (~half the rows
→ nearly all rows). A 5× change in loss moved the signal roughly 2×. It behaves
as a ~3-level indicator (clean / some loss / heavy loss), not a graded
congestion measure — and every CSV column is encoder-side *process* output, with
nothing describing the network or the client experience.

### Stage 5 — The pivotal correction: random loss is the wrong impairment
The deeper realization: an adaptive bitrate controller exists to **match the
send rate to available bandwidth**. Under uniform random packet loss, lowering
the bitrate barely helps — loss percentage is independent of send rate. The
regime where ABR actually wins is **bandwidth constriction**, where loss and
latency become a *function of* the bitrate.

The testbed (`testbed/scenarios.md`) had already documented *pivoting away from
bandwidth caps to packet loss* — because `tc netem rate` produced no FEC events.
That was the measurement limitation steering the methodology: the experiment was
reshaped around what the existing sensor could detect, not around what the
contribution is meant to fix. The correct response is not "use loss" but "add a
sensor that detects bandwidth constriction, then keep bandwidth-shaped
scenarios."

### Stage 6 — Resolution: RTT is server-observable without clock sync
[[idea-10-abr-comparison]] had dismissed latency as a signal because *one-way*
latency needs client/server clock synchronization. But **round-trip time needs
no clock sync** — both ENet peers derive it from ACK timing on their own clock,
and RTT *trend* (rise above a per-session baseline) is a valid congestion
signal. Sunshine's control channel is ENet; ENet maintains `peer->roundTripTime`
for free, kept fresh by Moonlight's **reliable** periodic ping. Sunshine simply
never reads it (the periodic-ping handler is empty).

Resolution / current plan of record:
1. Add an `rtt_ms` column to the CSV (read `peer->roundTripTime`).
2. Return to bandwidth-shaped test scenarios (`tc` rate caps), keeping loss
   scenarios only as secondary.
3. Verify RTT grades the scenarios where loss/IDR-rate did not.
4. Only then build the adaptive controller (the mid-stream bitrate
   reconfiguration path does not yet exist in Sunshine).

### Stage 7 — RTT validated empirically; random loss vs bandwidth contrast
Steps 1–3 of the Stage 6 plan were carried out.

**Tier 1 instrumentation shipped.** The CSV gained `rtt_ms`, `rtt_var_ms`,
`avg_send_ms`, `target_kbps`, `packets_sent`, plus `stalls` / `stall_ms`
(broadcast stalls — gaps ≥ 100 ms between dispatched frames). 18 columns total.

**RTT works.** A bandwidth-limited test (`tc htb` capped at 5 Mbps —
`data/metrics/sunshine-stats-20260520-193640.csv`) showed `rtt_ms` inflate from
~5 ms to **1600 ms** as the `htb` queue filled, then decay back once the cap was
lifted. The rise is **graded and monotonic** (classic bufferbloat) — exactly the
continuous congestion signal that loss/IDR-rate failed to provide.

**Random loss and bandwidth limiting have opposite signatures**, and together
they confirm the choice of signal:
- Random loss → IDR-request storm, FEC silent, RTT calm.
- Bandwidth limiting → RTT explodes (bufferbloat), IDR/FEC near-zero — the queue
  *delays* packets instead of dropping them.
Since ABR adapts to bandwidth, RTT is the correct signal — now proven on both
ends.

**`avg_send_ms` turned out weak.** It stayed ~0 almost throughout (the send
socket absorbs without blocking) and only spiked (~230–290 ms) on full
kernel-buffer saturation, coinciding with ~1.7 s freezes of the
`videoBroadcastThread`. It is a late, binary "fully choked" indicator; the
`stalls` / `stall_ms` columns capture those freezes directly.

The "verify RTT" step is ✅. Remaining: build the adaptive controller (PR #2).

## Related
- [[stats-export-findings]] — current-state findings of PR #1
- [[loss-recovery]] — FEC / RFI / IDR escalation ladder
- [[idea-10-abr-comparison]] — the ABR plan reshaped by Stages 5–6
- [[bitrate-control]] — bitrate flow; the missing runtime-reconfiguration path

## Sources
- `moonlight-common-c/src/ControlStream.c` — `IDX_LOSS_STATS` GFE-only branch;
  FEC status sent unreliably (`:1329`); reliable periodic ping (`:1351`) that
  keeps ENet RTT fresh
- `moonlight-common-c/src/RtpVideoQueue.c` — `SS_FRAME_FEC_STATUS` trigger sites
- `Sunshine/src/network.{h,cpp}` — ENet host/peer; `ENetPeer` carries
  `roundTripTime`
- `Sunshine/src/stream.cpp:950` — empty `IDX_PERIODIC_PING` handler
- `Sunshine/src/video.cpp:1863` — bitrate set once at encoder init; no
  mid-stream reconfiguration
- `data/metrics/sunshine-stats-20260519-203714.csv` — the 10% / 50% loss run
- `data/metrics/sunshine-stats-20260520-193640.csv` — the 5 Mbps bandwidth-limit run (RTT validation)
- `Sunshine/src/stat_trackers.{h,cpp}` — the `csv_stats_logger` with Tier 1 columns
- `testbed/scenarios.md` — bandwidth-shaped scenarios (Stages 5–7)
