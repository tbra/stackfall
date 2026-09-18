#!/usr/bin/env bash
# M3a local acceptance harness (docs/M3a_PLAN.md P4, "Testing without a
# second PC"). The .sh twin of run_m3a_local.ps1 for a Bash environment
# (Git Bash / WSL / Linux CI). Launches 1 headless host + (PEERS - 1)
# headless clients on 127.0.0.1, running tests/bench/m3a_acceptance.tscn,
# and aggregates their exit codes. Client 1 gets --sim-lag/--sim-loss,
# defaulting to spec Part 4 M3's acceptance condition itself: "a client with
# 100 ms of simulated lag and 2% packet loss sees smooth towers."
#
# Must run the scene, not a -s script (commit 12d2ec2's gotcha: autoload
# identifiers do not resolve under -s's bare SceneTree).
#
# Usage:
#   tools/run_m3a_local.sh
#   PEERS=4 SIM_LAG=100 SIM_LOSS=0.02 tools/run_m3a_local.sh
#
# Exit code: 0 if every instance exited 0; 1 otherwise. An instance exiting 2
# means it hit the "layer is still a stub" guard in m3a_acceptance.gd rather
# than actually failing an assertion — see that script's header.

set -u

PEERS="${PEERS:-4}"
PORT="${PORT:-47778}"
SIM_LAG="${SIM_LAG:-100}"
SIM_LOSS="${SIM_LOSS:-0.02}"
GODOT="${GODOT:-godot}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCENE_PATH="res://tests/bench/m3a_acceptance.tscn"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/m3a_local.XXXXXX")"
echo "M3A harness: logs in $LOG_DIR"

declare -a PIDS=()
declare -a NAMES=()
declare -a WATCHDOG_PIDS=()

start_instance() {
	local name="$1"
	shift
	"$GODOT" --headless --path "$REPO_ROOT" "$SCENE_PATH" -- "$@" \
		> "$LOG_DIR/$name.out.log" 2> "$LOG_DIR/$name.err.log" &
	PIDS+=("$!")
	NAMES+=("$name")
}

# DECISION (tools/run_m3a_local.sh): m3a_acceptance.gd's own --expect-peers
# defaults to 1, so without it here the host proceeded with a 2-player
# MatchConfig (MatchConfig.PLAYER_COUNT_MIN) while PEERS real peers had
# actually joined -- slot_of_peer() collisions in the host's per-slot
# counters then masqueraded as duplicate/lost placements. The host must be
# told how many peers this run is actually bringing.
start_instance "host" --headless-host --port="$PORT" --expect-peers="$PEERS"

# The host needs a moment to bind and start advertising before a client
# dials in directly.
sleep 2

for ((i = 1; i < PEERS; i++)); do
	if [ "$i" -eq 1 ]; then
		start_instance "client$i" --join="127.0.0.1:$PORT" --sim-lag="$SIM_LAG" --sim-loss="$SIM_LOSS"
	else
		start_instance "client$i" --join="127.0.0.1:$PORT"
	fi
done

# A watchdog per instance rather than a GNU-specific `timeout`/`tail --pid`
# combination, so this runs the same under Git Bash on Windows as under a
# real Linux shell.
for pid in "${PIDS[@]}"; do
	( sleep "$TIMEOUT_SECONDS"; kill "$pid" 2>/dev/null ) &
	WATCHDOG_PIDS+=("$!")
done

overall_status=0
for idx in "${!PIDS[@]}"; do
	pid="${PIDS[$idx]}"
	name="${NAMES[$idx]}"
	wait "$pid"
	code=$?
	echo "--- $name (exit $code) ---"
	grep "M3A_ACCEPT" "$LOG_DIR/$name.out.log" || true
	if [ -s "$LOG_DIR/$name.err.log" ]; then
		echo "  (stderr, see $LOG_DIR/$name.err.log)"
	fi
	if [ "$code" -ne 0 ]; then
		overall_status=1
	fi
done
for watchdog in "${WATCHDOG_PIDS[@]:-}"; do
	kill "$watchdog" 2>/dev/null || true
done

if [ "$overall_status" -ne 0 ]; then
	echo "M3A harness FAILED. Full logs in $LOG_DIR"
else
	echo "M3A harness PASSED ($PEERS instances). Full logs in $LOG_DIR"
fi
exit "$overall_status"
