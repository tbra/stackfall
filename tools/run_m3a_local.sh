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
#   PEERS=2 THROW_PASS=1 tools/run_m3a_local.sh   # + the M4 P2c-ii throw phase
#   PEERS=2 RECONNECT_PASS=1 tools/run_m3a_local.sh   # + the fca.30 drop/rejoin phase
#   PEERS=2 LATE_JOIN_AFTER=5 tools/run_m3a_local.sh  # + the 8or.11 late joiner
#
# Exit code: 0 if every instance exited 0; 1 otherwise. An instance exiting 2
# means it hit the "layer is still a stub" guard in m3a_acceptance.gd rather
# than actually failing an assertion — see that script's header. THROW_PASS=1
# passes tests/bench/m3a_acceptance.gd's own --throw-pass flag to every
# instance; a throw-phase failure there already makes that instance exit 1
# (m3a_acceptance.gd's _ready()), so the existing non-zero-exit check below
# already fails this script on a throw failure too.

set -u

PEERS="${PEERS:-4}"
PORT="${PORT:-47778}"
SIM_LAG="${SIM_LAG:-100}"
SIM_LOSS="${SIM_LOSS:-0.02}"
GODOT="${GODOT:-godot}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"
THROW_PASS="${THROW_PASS:-0}"
RECONNECT_PASS="${RECONNECT_PASS:-0}"
LATE_JOIN_AFTER="${LATE_JOIN_AFTER:-0}"

if [ "$PEERS" -lt 1 ]; then
	echo "Peers must be at least 1 (the host)." >&2
	exit 1
fi
echo "M3A harness: hard timeout set to $TIMEOUT_SECONDS seconds"

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
# Bontago-8or.11: a late-join run expects one extra client after match start.
EXPECTED_PEERS="$PEERS"
if [ "$LATE_JOIN_AFTER" -gt 0 ]; then
	EXPECTED_PEERS=$((PEERS + 1))
fi

declare -a THROW_ARGS=()
if [ "$THROW_PASS" != "0" ]; then
	THROW_ARGS+=(--throw-pass)
fi
# Bontago-fca.30: a real mid-match drop + rejoin of the slot-1 client.
declare -a RECONNECT_ARGS=()
if [ "$RECONNECT_PASS" != "0" ]; then
	RECONNECT_ARGS+=(--reconnect-pass)
fi
declare -a LATE_ARGS=()
if [ "$LATE_JOIN_AFTER" -gt 0 ]; then
	LATE_ARGS+=(--late-join-after="$LATE_JOIN_AFTER")
fi

start_instance "host" --headless-host --port="$PORT" --expect-peers="$EXPECTED_PEERS" 	${THROW_ARGS[@]+"${THROW_ARGS[@]}"} ${LATE_ARGS[@]+"${LATE_ARGS[@]}"} ${RECONNECT_ARGS[@]+"${RECONNECT_ARGS[@]}"}

# The host needs a moment to bind and start advertising before a client
# dials in directly.
sleep 2

for ((i = 1; i < PEERS; i++)); do
	declare -a CLIENT_ARGS=(--join="127.0.0.1:$PORT")
	if [ "$i" -eq 1 ]; then
		CLIENT_ARGS+=(--sim-lag="$SIM_LAG" --sim-loss="$SIM_LOSS")
	fi
	start_instance "client$i" "${CLIENT_ARGS[@]}" 		${THROW_ARGS[@]+"${THROW_ARGS[@]}"} ${RECONNECT_ARGS[@]+"${RECONNECT_ARGS[@]}"} ${LATE_ARGS[@]+"${LATE_ARGS[@]}"}
	unset CLIENT_ARGS
done

# Bontago-8or.11: late-join scenario -- one extra client (no reconnect flag).
if [ "$LATE_JOIN_AFTER" -gt 0 ]; then
	echo "M3A harness: waiting 2.5 seconds before starting late-join client"
	sleep 2.5
	start_instance "client_late" --join="127.0.0.1:$PORT" --late-join --sim-lag="$SIM_LAG" --sim-loss="$SIM_LOSS" 		${THROW_ARGS[@]+"${THROW_ARGS[@]}"}
fi

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
	grep -E "M3A_ACCEPT|M3A_THROW" "$LOG_DIR/$name.out.log" || true
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

# Bontago-fca.30: a reconnect run must also be clean of engine errors/warnings
# in every instance's logs. The quit-time "ObjectDB instances were leaked at
# exit" line is excluded (same as the .ps1).
LOG_PROBLEMS=()
if [ "$RECONNECT_PASS" != "0" ]; then
	for name in "${NAMES[@]}"; do
		for log in "$LOG_DIR/$name.out.log" "$LOG_DIR/$name.err.log"; do
			[ -f "$log" ] || continue
			while IFS= read -r line; do
				LOG_PROBLEMS+=("$name: $line")
			done < <(grep -E "ERROR:|SCRIPT ERROR|WARNING:|leaked|orphan" "$log" | grep -v "M3A_ACCEPT" | grep -v "ObjectDB instances were leaked at exit" || true)
		done
	done
	if [ "${#LOG_PROBLEMS[@]}" -gt 0 ]; then
		echo "M3A harness: reconnect pass found ${#LOG_PROBLEMS[@]} error/warning log line(s):"
		for ((k = 0; k < ${#LOG_PROBLEMS[@]} && k < 10; k++)); do
			echo "  ${LOG_PROBLEMS[$k]}"
		done
	fi
fi

if [ "$overall_status" -ne 0 ]; then
	echo "M3A harness FAILED: an instance exited non-zero. Full logs in $LOG_DIR"
	exit 1
fi
if [ "${#LOG_PROBLEMS[@]}" -gt 0 ]; then
	echo "M3A harness FAILED: engine errors/warnings in logs. Full logs in $LOG_DIR"
	exit 1
fi
echo "M3A harness PASSED (${#PIDS[@]} instances). Full logs in $LOG_DIR"
exit 0
