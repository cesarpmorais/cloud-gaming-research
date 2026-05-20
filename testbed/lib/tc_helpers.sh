#!/usr/bin/env bash
# Helpers for managing tc netem qdiscs.
# Sourced by run_scenario.sh — not meant to run standalone.

set -euo pipefail

: "${IFACE:?IFACE must be set, e.g. export IFACE=eno1}"

# Apply a packet-loss qdisc with the given loss percentage (integer or decimal).
# Optional delay in ms can be passed as the second argument (defaults to 0 — i.e.
# no extra delay added).
#
# Why loss instead of rate: FEC events (our metric source) are loss-triggered,
# not throughput-triggered. `tc netem rate` causes queueing delay but does not
# reliably produce loss until the qdisc queue overflows, which is unpredictable
# and may not happen at all before Moonlight disconnects. `tc netem loss X%`
# drops X% of packets directly, producing deterministic FEC event signal.
tc_loss() {
    local loss_pct="$1"
    local delay_ms="${2:-0}"
    if [ "$delay_ms" -gt 0 ]; then
        sudo tc qdisc replace dev "$IFACE" root netem loss "${loss_pct}%" delay "${delay_ms}ms"
    else
        sudo tc qdisc replace dev "$IFACE" root netem loss "${loss_pct}%"
    fi
}

# Remove any qdisc applied by us. Safe to call even if nothing is set.
tc_clear() {
    sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true
}

# Show current qdisc for sanity checking.
tc_show() {
    tc qdisc show dev "$IFACE"
}

# Quick connectivity sanity check — assumes a known reachable IP via this iface.
# Defaults to the gateway. Returns 0 if at least one of 3 pings succeeds.
tc_ping_check() {
    local target="${1:-$(ip route show default | awk '/^default/ {print $3; exit}')}"
    if [ -z "$target" ]; then
        echo "[tc_helpers] no default gateway found; skipping ping check" >&2
        return 0
    fi
    ping -c 3 -W 2 -I "$IFACE" "$target" >/dev/null 2>&1
}
