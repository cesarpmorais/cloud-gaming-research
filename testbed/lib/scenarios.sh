#!/usr/bin/env bash
# Scenario runners. Each function implements one of the ABRAGame profiles
# adapted to packet-loss-based impairment (instead of bandwidth-based).
# Sourced by run_scenario.sh.
#
# Each runner blocks for ~240 s while applying tc changes on a schedule.
# All times are seconds from session start (t=0).
# Profiles match testbed/scenarios.md.
#
# Design choice (May 2026): we use `tc netem loss X%` instead of `tc netem rate`.
# Rationale: our PR #1 captures SS_FRAME_FEC_STATUS events, which are triggered
# by packet loss (FEC recovery, frame drops). Bandwidth caps cause queueing
# delay but only produce loss when the qdisc queue overflows — unreliable for
# our signal. Loss-based scenarios deterministically generate FEC events.
# Temporal shapes are preserved from the ABRAGame paper.

# Helper: sleep until the given absolute timestamp (seconds since epoch).
# Avoids drift that accumulates with sequential `sleep` calls.
sleep_until() {
    local target="$1"
    local now
    now=$(date +%s)
    local delta=$(( target - now ))
    if [ "$delta" -gt 0 ]; then sleep "$delta"; fi
}

# scenarios run for SCENARIO_DURATION seconds (default 240).
SCENARIO_DURATION="${SCENARIO_DURATION:-240}"

scenario_clean() {
    # No impairment at all — true baseline. Used to verify the controller
    # (PR #2) does not produce false positives in good conditions. Expected:
    # zero or near-zero FEC events.
    local t0=$(date +%s)
    tc_clear
    sleep_until $(( t0 + SCENARIO_DURATION ))
}

scenario_A() {
    # Abrupt spike + rapid recovery: 0% → 5% loss (80-160s) → 0%
    local t0=$(date +%s)
    tc_clear
    sleep_until $(( t0 + 80 ));  tc_loss 5
    sleep_until $(( t0 + 160 )); tc_clear
    sleep_until $(( t0 + SCENARIO_DURATION ))
}

scenario_B() {
    # Gradual rise + fast recovery: step ramp 0→1→2→3→5% (60-160s) → 0%
    local t0=$(date +%s)
    tc_clear
    sleep_until $(( t0 + 60 ));  tc_loss 1
    sleep_until $(( t0 + 80 ));  tc_loss 2
    sleep_until $(( t0 + 100 )); tc_loss 3
    sleep_until $(( t0 + 120 )); tc_loss 5
    sleep_until $(( t0 + 160 )); tc_clear
    sleep_until $(( t0 + SCENARIO_DURATION ))
}

scenario_C() {
    # Slow rise + fast recovery: step ramp 0→1→2→3% (40-200s) → 0%
    local t0=$(date +%s)
    tc_clear
    sleep_until $(( t0 + 40 ));  tc_loss 1
    sleep_until $(( t0 + 100 )); tc_loss 2
    sleep_until $(( t0 + 160 )); tc_loss 3
    sleep_until $(( t0 + 200 )); tc_clear
    sleep_until $(( t0 + SCENARIO_DURATION ))
}

scenario_D() {
    # Intermittent: alternate clean / 3% loss every 30s.
    local t0=$(date +%s)
    local s=0
    while [ "$s" -lt "$SCENARIO_DURATION" ]; do
        tc_clear
        sleep_until $(( t0 + s + 30 ))
        s=$(( s + 30 ))
        [ "$s" -ge "$SCENARIO_DURATION" ] && break
        tc_loss 3
        sleep_until $(( t0 + s + 30 ))
        s=$(( s + 30 ))
    done
}

scenario_E() {
    # Long heavy loss period + abrupt recovery: 0% → 7% (40-200s) → 0%.
    # Most aggressive scenario. Moonlight may disconnect during the long phase
    # under fixed bitrate — that is expected and informative for the baseline.
    # Partial CSV is acceptable; the script auto-marks the filename with
    # _partial-Ns when actual duration is short of target.
    local t0=$(date +%s)
    tc_clear
    sleep_until $(( t0 + 40 ));  tc_loss 7
    sleep_until $(( t0 + 200 )); tc_clear
    sleep_until $(( t0 + SCENARIO_DURATION ))
}

scenario_F() {
    # High-loss start + late improvement: 5% (0-160s) → 0% (160-240s).
    local t0=$(date +%s)
    tc_loss 5
    sleep_until $(( t0 + 160 )); tc_clear
    sleep_until $(( t0 + SCENARIO_DURATION ))
}

scenario_test() {
    # Quick validation scenario (~60s total).
    # Uses heavy 10% loss to guarantee FEC events fire — used to verify the
    # full pipeline (tc changes, CSV collection, FEC event logging) end-to-end
    # before committing to a full campaign.

    local t0=$(date +%s)

    tc_clear
    sleep_until $(( t0 + 15 ))

    tc_loss 10
    sleep_until $(( t0 + 45 ))

    tc_clear
    sleep_until $(( t0 + 60 ))
}