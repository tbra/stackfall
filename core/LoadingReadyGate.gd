class_name LoadingReadyGate
extends RefCounted
## Bontago-1pi.32 (owner playtest 2026-10-03: "The loading screen is too fast
## now, add a minimum of 5s that it is displayed and require each player to
## click a start button (A on gamepad) to indicate that they are ready; when
## every player is ready the game starts.").
##
## The pure rule behind the loading-screen ready gate: no scene tree, no Net,
## no Match. autoload/match/MatchLifecycle.gd owns one per match, ticks it from
## the host's countdown tick and feeds it the *current* set of required peers
## (every connected peer that holds a human slot; bots never appear in it).
##
## The gate opens once BOTH hold:
##   1. min_display_s has elapsed since begin(), and
##   2. every required peer is ready -- or max_wait_s has elapsed, the safety
##      cap that keeps an AFK/frozen player from blocking everyone forever.
## The required set is passed in on every call rather than stored, so a peer
## that disconnects drops out of it at once and one that joins is waited for.
## Readiness is keyed by peer id, never by anything a peer could claim about
## itself, and recording it is idempotent.

var _min_display_s: float = 0.0
var _max_wait_s: float = 0.0
var _elapsed_s: float = 0.0
var _open: bool = false
var _timed_out: bool = false
## peer_id -> true for every peer that pressed ready this match.
var _ready: Dictionary = {}


func begin(min_display_s: float, max_wait_s: float) -> void:
	_min_display_s = maxf(min_display_s, 0.0)
	_max_wait_s = maxf(max_wait_s, 0.0)
	_elapsed_s = 0.0
	_open = false
	_timed_out = false
	_ready.clear()


func is_open() -> bool:
	return _open


## True when the gate opened because max_wait_s ran out, not because everyone
## was ready.
func opened_by_timeout() -> bool:
	return _timed_out


func elapsed_s() -> float:
	return _elapsed_s


## Seconds until min_display_s has elapsed; 0.0 once it has.
func min_display_remaining_s() -> float:
	return maxf(_min_display_s - _elapsed_s, 0.0)


## Records `peer_id` as ready. Returns true only when this changed something:
## a peer outside `required` (a spoofed id, a spectator, a bot's seat, a peer
## that already left) and a repeat press are both refused with false, and an
## already-open gate takes no more intents.
func mark_ready(peer_id: int, required: PackedInt32Array) -> bool:
	if _open or not required.has(peer_id) or _ready.has(peer_id):
		return false
	_ready[peer_id] = true
	return true


func is_ready(peer_id: int) -> bool:
	return _ready.has(peer_id)


## The ready peers that are still required, in `required`'s order.
func ready_ids(required: PackedInt32Array) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	for peer_id: int in required:
		if _ready.has(peer_id):
			result.append(peer_id)
	return result


## True when every required peer is ready (vacuously true for an empty set:
## an all-bot match has nobody to wait for).
func all_ready(required: PackedInt32Array) -> bool:
	for peer_id: int in required:
		if not _ready.has(peer_id):
			return false
	return true


## Advances the clock and opens the gate when the rule above is met. Returns
## true exactly once, on the call that opens it.
func tick(delta: float, required: PackedInt32Array) -> bool:
	if _open:
		return false
	_elapsed_s += maxf(delta, 0.0)
	if _elapsed_s < _min_display_s:
		return false
	var cap_reached: bool = _elapsed_s >= _max_wait_s
	if not all_ready(required) and not cap_reached:
		return false
	_timed_out = cap_reached and not all_ready(required)
	_open = true
	return true
