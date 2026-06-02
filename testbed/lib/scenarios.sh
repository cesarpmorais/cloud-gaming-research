#!/usr/bin/env bash
# Scenario runners. Each function implements one of the ABRAGame profiles
# adapted to bandwidth-limited impairment (tc htb caps).
# Sourced by run_scenario.sh.
#
# Each runner blocks for ~240 s while applying tc changes on a schedule.
# All times are seconds from session start (t=0).
# Profiles match testbed/scenarios.md.
#
# Impairment model: bandwidth caps via `tc htb`, not packet loss. An adaptive
# bitrate controller exists to match the send rate to available bandwidth, so
# bandwidth constriction — not random loss — is the impairment it is designed
# to handle. Under an htb cap the bottleneck queue fills and inflates RTT (the
# controller's signal); under random loss RTT stays calm. See
# testbed/scenarios.md and knowledge/contributions/research-journey.md (Stage 5).
#
# tc_setup (htb qdisc + unshaped class) is run by run_scenario.sh before the
# runner starts, so each runner begins in the unshaped state. Runners only call
# tc_cap / tc_uncap — atomic `tc class change` calls. Unshaped is the "good" /
# recovered state; a cap is a degraded state.

# Helper: sleep until the given absolute timestamp (seconds since epoch).
# Avoids drift that accumulates with sequential `sleep` calls.
sleep_until() {
    local target="$1"
    local now
    now=$(date +%s)
    local delta=$(( target - now ))
    if [ "$delta" -gt 0 ]; then sleep "$delta"; fi
}

# Scenarios run for SCENARIO_DURATION seconds (default 240; run_scenario.sh
# overrides it to 60 for the `test` scenario).
SCENARIO_DURATION="${SCENARIO_DURATION:-240}"

scenario_clean() {
    # No impairment at all — true baseline. Used to verify the controller
    # (PR #2) does not produce false-positive bitrate drops in good
    # conditions. Expected: stable RTT, no IDR storm.
    local t0=$(date +%s)
    sleep_until $(( t0 + SCENARIO_DURATION ))
}

scenario_A() {
    # Abrupt drop + rapid recovery: unshaped -> 8 Mbps (80-160s) -> unshaped.
    local t0=$(date +%s)
    sleep_until $(( t0 + 80 ));  tc_cap 8
    sleep_until $(( t0 + 160 )); tc_uncap
    sleep_until $(( t0 + SCENARIO_DURATION ))
}

scenario_B() {
    # Gradual decline + fast recovery: step ramp 16 -> 12 -> 8 Mbps
    # (60-160s) -> unshaped. Worst cap (8 Mbps) is active 120-160s.
    local t0=$(date +%s)
    sleep_until $(( t0 + 60 ));  tc_cap 16
    sleep_until $(( t0 + 90 ));  tc_cap 12
    sleep_until $(( t0 + 120 )); tc_cap 8
    sleep_until $(( t0 + 160 )); tc_uncap
    sleep_until $(( t0 + SCENARIO_DURATION ))
}

scenario_C() {
    # Slow decline + fast recovery: step ramp 14 -> 10 Mbps (40-200s) -> unshaped.
    local t0=$(date +%s)
    sleep_until $(( t0 + 40 ));  tc_cap 14
    sleep_until $(( t0 + 120 )); tc_cap 10
    sleep_until $(( t0 + 200 )); tc_uncap
    sleep_until $(( t0 + SCENARIO_DURATION ))
}

scenario_D() {
    # Intermittent fluctuations: toggle unshaped / 10 Mbps every 30s,
    # starting with an unshaped phase.
    local t0=$(date +%s)
    local s=0
    while [ "$s" -lt "$SCENARIO_DURATION" ]; do
        # unshaped phase (already unshaped from setup / previous tc_uncap)
        sleep_until $(( t0 + s + 30 ))
        s=$(( s + 30 ))
        [ "$s" -ge "$SCENARIO_DURATION" ] && break
        # capped phase
        tc_cap 10
        sleep_until $(( t0 + s + 30 ))
        tc_uncap
        s=$(( s + 30 ))
    done
}

scenario_E() {
    # Long heavy constriction + abrupt recovery: unshaped -> 4 Mbps
    # (40-200s) -> unshaped. Worst case. Under fixed bitrate the session may
    # disconnect during the 4 Mbps phase — expected and informative for the
    # baseline. Partial CSV is acceptable; run_scenario.sh auto-marks the
    # filename with _partial-Ns when actual duration is short of target.
    local t0=$(date +%s)
    sleep_until $(( t0 + 40 ));  tc_cap 4
    sleep_until $(( t0 + 200 )); tc_uncap
    sleep_until $(( t0 + SCENARIO_DURATION ))
}

scenario_F() {
    # Low start + late improvement: 6 Mbps (0-160s) -> unshaped (160-240s).
    local t0=$(date +%s)
    tc_cap 6
    sleep_until $(( t0 + 160 )); tc_uncap
    sleep_until $(( t0 + SCENARIO_DURATION ))
}

scenario_test() {
    # Quick validation (~60s): unshaped -> 5 Mbps (15-45s) -> unshaped.
    # Confirms the full pipeline end-to-end — tc transitions, CSV collection,
    # and that a bandwidth cap actually inflates rtt_ms — before committing to
    # a full campaign. run_scenario.sh sets SCENARIO_DURATION=60 for `test`.
    local t0=$(date +%s)
    sleep_until $(( t0 + 15 )); tc_cap 5
    sleep_until $(( t0 + 45 )); tc_uncap
    sleep_until $(( t0 + 60 ))
}
