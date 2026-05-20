# Sunshine ABRAGame Testbed

Automation for running the 6 ABRAGame network scenarios + a clean baseline against a Sunshine ↔ Moonlight session, scaled to a realistic 20 Mbps cloud-gaming target.

## What's here

| Path | Purpose |
|------|---------|
| `scenarios.md` | Definition of the 7 scenarios (clean, A–F) with bandwidth/latency profiles |
| `run_scenario.sh` | Main entry — runs one scenario, one repetition |
| `lib/tc_helpers.sh` | `tc netem` setup/teardown wrappers |
| `lib/scenarios.sh` | Time-scheduled `tc` changes per scenario |
| `results/baseline/` | CSVs + `.notes.txt` from fixed-bitrate baseline runs |
| `results/adaptive/` | (Future) results from adaptive bitrate runs (PR #2) |

## Prerequisites

1. **Sunshine binary built** with our PR #1 changes (`metrics_path` config option supported).
2. **Sunshine config** (`~/.config/sunshine/sunshine.conf`):
   ```
   metrics_path = /home/cesarpmorais/code/ufmg/tcc/data/metrics
   ```
3. **Moonlight Android** paired and configured for **20 Mbps at 1080p60**.
4. **`iproute-tc`** installed (`sudo dnf install iproute-tc`).
5. **Sudo for `tc`** — `tc qdisc` requires root.
6. **Background apps closed** on the host: Discord, Steam, browser, OS updates, etc.

## One-time setup

```bash
chmod +x testbed/run_scenario.sh testbed/lib/*.sh
export IFACE=eno1   # confirm with: ip route show default
```

## **Operational protocol — read carefully**

Sunshine writes one CSV per session (lazy on first FEC event). The script identifies the new CSV by diffing the staging directory before/after the run. **For this to work, every run must be a fresh session.**

### Per-session setup (start of bench day)

1. Confirm Moonlight Android is on **20 Mbps, 1080p60**.
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

[6/6] Locating new CSV ...
      note saved: /.../A_run1_20260510-180230.notes.txt
      csv saved:  /.../A_run1_20260510-180230.csv
      events: 87
Done.
```

## Sanity checking after a run

```bash
# Quick stats
awk -F, 'NR>1 {n++; m+=$5; t+=$6; idr+=$11} END {
  printf "events=%d  missing_avg=%.2f  total_data_avg=%.2f  idr_total=%d\n",
         n, m/n, t/n, idr
}' results/baseline/A_run1_*.csv

# Verify tc was actually applied (run during a "bad phase")
tc qdisc show dev eno1
```

Expected ranges per scenario are in `scenarios.md` ("Per-scenario expected behavior").

## Troubleshooting

| Symptom | Cause / Fix |
|---------|-------------|
| Script says "no new CSV found" after run | (1) `clean` produced 0 events — expected. (2) Forgot to disconnect/reconnect Moonlight — the run's events went into the previous session's file. (3) Sunshine `metrics_path` misconfigured. |
| `tc: Operation not permitted` | Need sudo. The script invokes `sudo tc` internally; you'll be prompted. |
| `RTNETLINK answers: File exists` | Stale tc qdisc from a prior crashed run. Run `sudo tc qdisc del dev $IFACE root` and retry. The script's cleanup trap should prevent this. |
| All scenarios look identical | tc isn't actually being applied. Verify with `tc qdisc show dev eno1` during a run; should show netem with the expected rate/delay. Check that `IFACE` matches the wired interface, and that Wi-Fi is off (or that the stream actually routes through the wired iface). |
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
