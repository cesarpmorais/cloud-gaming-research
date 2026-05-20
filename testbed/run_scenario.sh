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
#   - Sunshine running with metrics_path = ~/code/ufmg/tcc/data/metrics
#   - Moonlight bitrate set to 20 Mbps, 1080p60
#   - Moonlight session DISCONNECTED before each run, then RECONNECTED right
#     before pressing ENTER. Sunshine writes one CSV per session, so without
#     a fresh session the script cannot identify the new file.
#   - Background apps closed (Discord, Steam, browser, OS updates, etc.)
#
# What it does:
#   1. Validates inputs.
#   2. Clears any stale tc qdisc on $IFACE.
#   3. Waits for operator to confirm Moonlight session is fresh and stable.
#   4. Runs the scenario function (applies tc changes over time).
#   5. Tears down tc.
#   6. Prompts for gameplay-experience ratings and notes.
#   7. Locates the new CSV, renames + moves it; saves the note alongside.

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

OUTPUT_DIR="$RESULTS_DIR/$MODE"
mkdir -p "$OUTPUT_DIR"

# Snapshot of CSVs already present so we can identify the new one later.
mapfile -t PRE_RUN_CSVS < <(
    find "$METRICS_STAGING_DIR" -maxdepth 1 -name '*.csv' 2>/dev/null | sort
)

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

echo "[1/6] Clearing any existing tc qdisc on $IFACE ..."
tc_clear

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

echo "[6/6] Locating new CSV ..."

mapfile -t POST_RUN_CSVS < <(
    find "$METRICS_STAGING_DIR" -maxdepth 1 -name '*.csv' 2>/dev/null | sort
)

NEW_CSV=""

for f in "${POST_RUN_CSVS[@]}"; do
    found=0

    for g in "${PRE_RUN_CSVS[@]}"; do
        if [ "$f" = "$g" ]; then
            found=1
            break
        fi
    done

    if [ "$found" -eq 0 ]; then
        NEW_CSV="$f"
        break
    fi
done

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
    echo "      WARNING: no new CSV found in $METRICS_STAGING_DIR" >&2
    echo "      Possible causes:" >&2
    echo "        - clean network produced 0 events (expected for 'clean' scenario)" >&2
    echo "        - Sunshine wasn't started with metrics_path pointing here" >&2
    echo "        - Moonlight session was not freshly reconnected before this run" >&2
    echo "        - the session disconnected before any FEC event fired" >&2
    echo "      Note file is still saved for record-keeping." >&2
    exit 0
fi

CSV_DEST="$OUTPUT_DIR/${BASE}.csv"

mv "$NEW_CSV" "$CSV_DEST"

LINES=$(wc -l < "$CSV_DEST")
EVENTS=$(( LINES - 1 ))

echo "      csv saved: $CSV_DEST"
echo "      events: $EVENTS"

echo "Done."