# Sunshine ABRAGame Testbed

Automation for running the 6 ABRAGame network scenarios + a clean baseline against a Sunshine ↔ Moonlight session. Impairment is bandwidth shaping (`tc htb`); the encoder target is ~19 Mbps (negotiated from a 25 Mbps client slider).

## What's here

| Path | Purpose |
|------|---------|
| `scenarios.md` | Definition of the 7 scenarios (clean, A–F) with bandwidth profiles |
| `run_scenario.sh` | Main entry — runs one scenario, one repetition |
| `lib/tc_helpers.sh` | `tc htb` shaper setup/teardown wrappers |
| `lib/scenarios.sh` | Time-scheduled `tc` bandwidth caps per scenario |
| `results/baseline/` | CSVs + `.notes.txt` from fixed-bitrate baseline runs |
| `results/adaptive/` | (Future) results from adaptive bitrate runs (PR #2) |

## Prerequisites

1. **Sunshine binary built** with our PR #1 changes (`stats_export_path` config option supported).
2. **Sunshine config** (`~/.config/sunshine/sunshine.conf`):
   ```
   stats_export_path = /home/cesarpmorais/code/ufmg/tcc/data/metrics
   ```
3. **Moonlight Android** paired with the bitrate slider at **25 Mbps, 1080p60** (Sunshine negotiates a ~19 Mbps / 18988 kbps on-the-wire target from it).
4. **`iproute-tc`** installed (`sudo dnf install iproute-tc`).
5. **Sudo for `tc`** — `tc qdisc` requires root.
6. **Background apps closed** on the host: Discord, Steam, browser, OS updates, etc.

## One-time setup

```bash
chmod +x testbed/run_scenario.sh testbed/lib/*.sh
export IFACE=eno1   # confirm with: ip route show default
```

## **Operational protocol — read carefully**

Sunshine writes one CSV per session, created the moment the session starts (header first, then one row per 200 ms tick). The script identifies this run's CSV as the staging-dir file with the newest modification time — a live session is still being appended to, so it always wins. The original is left in place and a renamed copy is placed in `results/`. **Still, run every scenario on a fresh session** (disconnect/reconnect Moonlight between runs) so each CSV holds exactly one run.

### Per-session setup (start of bench day)

1. Confirm the Moonlight Android bitrate slider is on **25 Mbps, 1080p60**.
2. Close all non-essential apps on the host.
3. Start Sunshine: `./Sunshine/build/sunshine` (leave running for the whole bench session).
4. Open Moonlight on the Android device.

### Per-run protocol (every single run)

1. **Disconnect** the Moonlight session if it's connected (back out of the stream view).
2. **Reconnect** to the host in Moonlight — wait for the desktop to appear and the stream to feel responsive.
3. **Load an in-game scene** (not a menu) that has visible motion.
4. In the host terminal: `./testbed/run_scenario.sh <scenario> <run_number>`
5. Script clears tc, pings the gateway, then prompts you with a checklist.
6. Press **ENTER** when ready. The 240 s window starts immediately.
7. **Play** during the 240 s — keep the camera moving so the encoder has dynamic content.
8. After the script reports "done", it prompts you to write a **gameplay note** (1–3 lines describing your subjective experience). End the note with a blank line.
9. The script saves `<scenario>_run<N>_<timestamp>.csv` and `.notes.txt` next to it.
10. Move to the next run — **always go back to step 1 (disconnect/reconnect)**.

### If the session disconnects mid-run

For scenario E especially, Moonlight may drop the connection during the heavy 4 Mbps phase. **This is expected.**

- Let the script finish (it will detect a shorter actual duration)
- It will still prompt for the gameplay note
- The CSV (if any) gets `_partial-Ns` appended to the filename
- Reconnect and proceed to the next run

## Full baseline campaign

7 scenarios × 3 runs = **21 runs** ≈ 84 min of streaming + ~30 min disconnect/reconnect overhead + notes. Plan a **2–3 hour bench session**.

Suggested order (alternates light/heavy on the network):

```
clean-1  A-1  E-1  D-1  B-1  F-1  C-1
clean-2  A-2  E-2  D-2  B-2  F-2  C-2
clean-3  A-3  E-3  D-3  B-3  F-3  C-3
```

## Single-run example

```bash
$ IFACE=eno1 ./testbed/run_scenario.sh A 1

================================================================
 Scenario: A  Run: 1  Mode: baseline
 Interface: eno1   Duration: 240s
 Results: /.../testbed/results/baseline
================================================================
[1/6] Clearing any existing tc qdisc on eno1 ...
[2/6] Sanity ping ...
      ping OK
[3/6] PROTOCOL CHECKLIST before starting this run:
      - Moonlight session was DISCONNECTED and RECONNECTED since the previous run
      ...
      Press ENTER when ready, or Ctrl-C to abort.

[4/6] Running scenario A ...
      done in 240s

[5/6] Gameplay-experience note for this run.
      Write 1-3 lines describing your subjective experience...
      Type your note (blank line ends):
> Smooth until ~80s, then strong stutter for 4-5 seconds.
> Recovered to playable around 100s but with visible blocking.
> Clean again after 160s, didn't notice anything else.
>

[6/6] Locating the session CSV ...
      note saved:   /.../results/baseline/A_run1_20260510-180230.notes.txt
      csv copied:   /.../results/baseline/A_run1_20260510-180230.csv
      source kept:  /.../data/metrics/sunshine-stats-20260510-175958.csv
      rows (200ms ticks): 1187
Done.
```

## Sanity checking after a run

```bash
# Quick stats (column indices match the 18-column Tier 1 CSV)
awk -F, 'NR>1 {n++; rtt+=$11; bps+=$4; st+=$9; idr+=$17} END {
  printf "rows=%d  rtt_avg=%.1fms  bitrate_avg=%.0fkbps  stalls=%d  idr_requests=%d\n",
         n, rtt/n, bps/n, st, idr
}' results/baseline/A_run1_*.csv

# Verify the cap was actually applied (run during a "bad phase")
tc -s class show dev eno1   # the htb class rate should match the scenario's cap
```

Expected ranges per scenario are in `scenarios.md` ("Per-scenario expected behavior").

## Troubleshooting

| Symptom | Cause / Fix |
|---------|-------------|
| Script says "no CSV written during this run" | A live session appends a row every 200 ms, so nothing written is a setup fault: (1) Sunshine `stats_export_path` misconfigured, or Sunshine not running; (2) the session never started (pairing / app-launch failure); (3) the session died before the run began. |
| Copied CSV has far more rows than expected (~1200 for a 240 s run) | You forgot to disconnect/reconnect Moonlight, so this run streamed into the previous session's still-open CSV. The copy now spans multiple runs — slice by `elapsed_ms`, or just re-run on a fresh session. |
| `tc: Operation not permitted` | Need sudo. The script invokes `sudo tc` internally; you'll be prompted. |
| `RTNETLINK answers: File exists` | Stale tc qdisc from a prior crashed run. Run `sudo tc qdisc del dev $IFACE root` and retry. The script's cleanup trap should prevent this. |
| All scenarios look identical | The cap isn't being applied. Verify with `tc -s class show dev eno1` during a run; the htb class rate should match the scenario's current cap. Check that `IFACE` matches the wired interface, and that Wi-Fi is off (or that the stream actually routes through the wired iface). |
| Smooth gameplay during scenario E | Either (a) you got lucky and Moonlight survived the 4 Mbps phase, or (b) tc isn't being applied. Check #2 above. |
| `clean` looks unstable | Probably not the testbed — check Sunshine encoder choice, GPU pinning, network routes. Don't run the campaign until clean is actually clean. |

## Smoke test before campaign

Run two throwaways before the real campaign to validate the setup end-to-end:

```bash
./testbed/run_scenario.sh clean 0   # expect: smooth gameplay, ~0 events
./testbed/run_scenario.sh A 0       # expect: stutter at ~80s, many events
```

(Use `0` as the run number — these aren't real runs, just smoke tests. Delete the resulting files before starting the real campaign with `1/2/3`.)

If both behave as expected, proceed. If `clean` is unstable or `A` produces no events, **stop and debug** — running the full campaign on a broken setup wastes 2-3 hours.
