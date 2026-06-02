#!/usr/bin/env bash
# run_scenario.sh — orchestrates a single scenario run.
#
# Usage:
#   IFACE=eno1 ./run_scenario.sh <scenario> <run_number> [--mode baseline|adaptive]
#
# Examples:
#   IFACE=eno1 ./run_scenario.sh A 1
#   IFACE=eno1 ./run_scenario.sh clean 2 --mode baseline
#   IFACE=eno1 ./run_scenario.sh test 1
#
# Prerequisites — see testbed/README.md for full operational protocol. Brief:
#   - Sunshine running with stats_export_path = ~/code/ufmg/tcc/data/metrics
#   - Moonlight bitrate slider set to 25 Mbps, 1080p60 (negotiates ~19 Mbps)
#   - Moonlight session DISCONNECTED before each run, then RECONNECTED right
#     before pressing ENTER, so each run streams a fresh single-run session.
#   - Background apps closed (Discord, Steam, browser, OS updates, etc.)
#
# What it does:
#   1. Validates inputs.
#   2. Clears any stale tc qdisc on $IFACE and installs the htb shaper.
#   3. Waits for operator to confirm Moonlight session is fresh and stable.
#   4. Runs the scenario function (applies tc bandwidth caps over time).
#   5. Tears down tc.
#   6. Prompts for gameplay-experience ratings and notes.
#   7. Locates the session CSV, copies it (renamed) into results; saves the
#      note alongside. The original CSV is kept in the staging dir.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="$SCRIPT_DIR/lib"
RESULTS_DIR="$SCRIPT_DIR/results"

usage() {
    cat <<EOF >&2
Usage: IFACE=<interface> $0 <scenario> <run_number> [--mode baseline|adaptive]

  scenario    one of: clean test A B C D E F
  run_number  positive integer (1, 2, 3, ...) used in output filename
  --mode      results subdir; defaults to "baseline"

Required env: IFACE (network interface to shape, e.g. eno1)
Optional env: SCENARIO_DURATION (override default duration)
              METRICS_STAGING_DIR (where Sunshine writes; default ~/code/ufmg/tcc/data/metrics)
EOF
    exit 64
}

[ "$#" -ge 2 ] || usage

SCENARIO="$1"
RUN_NUMBER="$2"
shift 2

MODE="baseline"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode) MODE="$2"; shift 2;;
        *) echo "Unknown arg: $1" >&2; usage;;
    esac
done

case "$SCENARIO" in
    clean|test|A|B|C|D|E|F) ;;
    *) echo "Invalid scenario: $SCENARIO" >&2; usage;;
esac

[[ "$RUN_NUMBER" =~ ^[1-9][0-9]*$|^0$ ]] || {
    echo "run_number must be a non-negative integer" >&2
    usage
}

: "${IFACE:?IFACE must be set, e.g. export IFACE=eno1}"
METRICS_STAGING_DIR="${METRICS_STAGING_DIR:-$HOME/code/ufmg/tcc/data/metrics}"

# The test scenario is a fixed ~60 s pipeline check, not a 240 s campaign run.
if [ "$SCENARIO" = "test" ]; then
    SCENARIO_DURATION="${SCENARIO_DURATION:-60}"
    export SCENARIO_DURATION
fi

OUTPUT_DIR="$RESULTS_DIR/$MODE"
mkdir -p "$OUTPUT_DIR"

# shellcheck source=lib/tc_helpers.sh
source "$LIB_DIR/tc_helpers.sh"

# shellcheck source=lib/scenarios.sh
source "$LIB_DIR/scenarios.sh"

cleanup() {
    tc_clear
}
trap cleanup EXIT INT TERM

echo "================================================================"
echo " Scenario: $SCENARIO  Run: $RUN_NUMBER  Mode: $MODE"
echo " Interface: $IFACE   Duration: ${SCENARIO_DURATION:-240}s"
echo " Results: $OUTPUT_DIR"
echo "================================================================"

echo "[1/6] Resetting tc on $IFACE (clear + htb shaper setup) ..."
tc_clear
tc_setup

echo "[2/6] Sanity ping ..."
if tc_ping_check; then
    echo "      ping OK"
else
    echo "      ping FAILED — aborting (network not reachable)" >&2
    exit 1
fi

cat <<EOF
[3/6] PROTOCOL CHECKLIST before starting this run:
      - Moonlight session was DISCONNECTED and RECONNECTED since the previous run
      - The stream looks stable on the client
      - You have an in-game scene loaded (not a menu)
      - All non-essential apps closed on the host

      Press ENTER when ready, or Ctrl-C to abort.
EOF

read -r

echo "[4/6] Running scenario $SCENARIO ..."
START_TS=$(date +%s)
START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')

"scenario_$SCENARIO"

END_TS=$(date +%s)
ACTUAL_DURATION=$(( END_TS - START_TS ))

echo "      done in ${ACTUAL_DURATION}s"

read_rating() {
    # Reads an integer 1-5 from stdin. Re-prompts until valid.
    # Prompt and validation messages go to stderr so command substitution
    # captures only the validated response on stdout.

    local prompt="$1"
    local response

    while true; do
        printf "  %s " "$prompt" >&2
        read -r response

        if [[ "$response" =~ ^[1-5]$ ]]; then
            printf '%s' "$response"
            return
        fi

        echo "  (must be 1-5, try again)" >&2
    done
}

cat <<'EOF'

[5/6] Gameplay-experience ratings (3 separate ratings, each 1-5).
      Type a number after each prompt and press ENTER.
EOF

LATENCY_RATING=$(read_rating  "Latency perception   (1=imperceptible, 5=unplayable):")
QUALITY_RATING=$(read_rating  "Visual quality       (1=crisp,         5=many artifacts):")
STABILITY_RATING=$(read_rating "Stability            (1=rock solid,    5=constant freezes):")

cat <<'EOF'

      Free-text note: 1-3 lines describing what you observed.
      End with a blank line.

      Type your note:
EOF

NOTE_LINES=()

while IFS= read -r line; do
    [ -z "$line" ] && break
    NOTE_LINES+=("$line")
done

echo "[6/6] Locating the session CSV ..."

# Sunshine appends a row every 200 ms for the whole session, so this run's CSV
# is the staging-dir file with the newest mtime — provided it was still being
# written during the run (mtime at or after START_TS). Picking by mtime (not a
# before/after diff) works even though the session, and thus its CSV, is
# created before this script starts.
NEW_CSV=""
NEW_CSV_MTIME=0

while IFS=' ' read -r mtime path; do
    mtime=${mtime%.*}
    if [ "$mtime" -ge "$START_TS" ] && [ "$mtime" -ge "$NEW_CSV_MTIME" ]; then
        NEW_CSV="$path"
        NEW_CSV_MTIME="$mtime"
    fi
done < <(find "$METRICS_STAGING_DIR" -maxdepth 1 -name '*.csv' -printf '%T@ %p\n' 2>/dev/null)

# Build basename. Mark partial if duration was significantly under target.
BASE="${SCENARIO}_run${RUN_NUMBER}_$(date -d "@$START_TS" +%Y%m%d-%H%M%S)"

if [ "$ACTUAL_DURATION" -lt $(( ${SCENARIO_DURATION:-240} - 10 )) ]; then
    BASE="${BASE}_partial-${ACTUAL_DURATION}s"
fi

NOTE_PATH="$OUTPUT_DIR/${BASE}.notes.txt"

{
    echo "scenario: $SCENARIO"
    echo "run: $RUN_NUMBER"
    echo "mode: $MODE"
    echo "started: $START_HUMAN"
    echo "duration_actual_s: $ACTUAL_DURATION"
    echo "duration_target_s: ${SCENARIO_DURATION:-240}"
    echo "rating_latency: $LATENCY_RATING"
    echo "rating_quality: $QUALITY_RATING"
    echo "rating_stability: $STABILITY_RATING"
    echo ""
    echo "# Gameplay note"

    if [ "${#NOTE_LINES[@]}" -eq 0 ]; then
        echo "(no note provided)"
    else
        for line in "${NOTE_LINES[@]}"; do
            echo "$line"
        done
    fi
} > "$NOTE_PATH"

echo "      note saved: $NOTE_PATH"

if [ -z "$NEW_CSV" ]; then
    echo "      WARNING: no CSV written during this run in $METRICS_STAGING_DIR" >&2
    echo "      A live session appends a CSV row every 200 ms, so nothing" >&2
    echo "      written points to a setup problem:" >&2
    echo "        - Sunshine wasn't started with stats_export_path pointing here" >&2
    echo "        - the session never started (pairing / app-launch failure)" >&2
    echo "        - the session died before the run began" >&2
    echo "      Note file is still saved for record-keeping." >&2
    exit 0
fi

CSV_DEST="$OUTPUT_DIR/${BASE}.csv"

# Copy, not move: the original stays in the staging dir; results/ gets a
# renamed copy sitting next to its .notes.txt.
cp "$NEW_CSV" "$CSV_DEST"

LINES=$(wc -l < "$CSV_DEST")
ROWS=$(( LINES - 1 ))

echo "      csv copied:  $CSV_DEST"
echo "      source kept: $NEW_CSV"
echo "      rows (200ms ticks): $ROWS"

echo "Done."