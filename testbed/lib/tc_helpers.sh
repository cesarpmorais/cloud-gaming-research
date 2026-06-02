#!/usr/bin/env bash
# Helpers for managing tc htb bandwidth-shaping qdiscs.
# Sourced by run_scenario.sh — not meant to run standalone.

set -euo pipefail

: "${IFACE:?IFACE must be set, e.g. export IFACE=eno1}"

# Rate for the "unshaped" / good (recovered) state. Far above the ~19 Mbps
# encoder target, so in this state the htb class never throttles the stream.
TC_UNSHAPED_RATE="${TC_UNSHAPED_RATE:-1000mbit}"

# Create the htb qdisc plus a single class, in the unshaped state.
# Called once at the start of a run; every later transition is a `tc class
# change` on this class — atomic, with no traffic interruption.
tc_setup() {
    sudo tc qdisc replace dev "$IFACE" root handle 1: htb default 1
    sudo tc class replace dev "$IFACE" parent 1: classid 1:1 htb rate "$TC_UNSHAPED_RATE"
}

# Enter a degraded state: cap the class at the given rate, in Mbit/s.
# Example: tc_cap 8  ->  8mbit. Queueing delay above this cap is the RTT
# inflation the controller reads as its congestion signal.
tc_cap() {
    local mbit="$1"
    sudo tc class change dev "$IFACE" parent 1: classid 1:1 htb rate "${mbit}mbit"
}

# Return to the unshaped (good) state.
tc_uncap() {
    sudo tc class change dev "$IFACE" parent 1: classid 1:1 htb rate "$TC_UNSHAPED_RATE"
}

# Remove any qdisc applied by us. Safe to call even if nothing is set.
tc_clear() {
    sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true
}

# Show current qdisc/class state for sanity checking.
tc_show() {
    tc -s qdisc show dev "$IFACE"
    tc -s class show dev "$IFACE"
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
