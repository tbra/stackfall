class_name HandshakePolicy
extends RefCounted
## Pure join decision for a handshake: accept, refuse with a JoinError, reclaim a
## reserved slot, or drop it without a reply. No scene tree, no clock, no
## MultiplayerAPI: the roster (net/session/NetRoster.gd) snapshots its state into
## `host_state` and applies the answer.
##
## The checks run in the order the old Net._rpc_handshake ran them, so a
## handshake that failed two checks gets the same answer it always did.

## Net.JoinError values this policy answers with. Core code cannot name the Net
## autoload; test_handshake_policy pins each to the enum so they cannot drift.
const ERROR_VERSION_MISMATCH: int = 2
const ERROR_SERVER_FULL: int = 3
const ERROR_MATCH_IN_PROGRESS: int = 4

## Why a DROP was dropped (Decision.drop_reason).
const DROP_NOT_HOST: StringName = &"not_host"
const DROP_OVERSIZE: StringName = &"oversize"
const DROP_DUPLICATE: StringName = &"duplicate"
const DROP_FLOOD: StringName = &"flood"


class Decision extends RefCounted:
	## DROP is a silent ignore: no refusal reply (a reply to a hostile sender is
	## an amplification) and no kick.
	enum Kind { ACCEPT, REFUSE, RECLAIM, DROP }
	var kind: int = Kind.ACCEPT
	## JoinError when REFUSE.
	var error: int = 0
	## Slot to seat in: the seat for ACCEPT (-1 = spectator), the slot given
	## back for RECLAIM.
	var slot_id: int = -1
	## Why, when DROP (the DROP_* names above).
	var drop_reason: StringName = &""


## request: {sender, build, name, token, already_seated}.
## host_state: {is_host, host_build, joins_open, match_in_progress, free_capacity,
## reservations: token -> slot, held_slots: slot -> true (live peers),
## can_reclaim_seat: Callable(slot) -> bool, pick_open_seat: Callable() -> int,
## max_build_len, max_name_len, max_token_len}.
## Order of checks follows the old Net._rpc_handshake.
static func decide(request: Dictionary, host_state: Dictionary) -> Decision:
	if not bool(host_state.get("is_host", false)):
		return _drop(DROP_NOT_HOST)
	# Before anything reads the strings: an oversize field is hostile, not a
	# version mismatch, and gets no reply.
	if not within_caps(request, host_state):
		return _drop(DROP_OVERSIZE)
	if bool(request.get("already_seated", false)):
		return _drop(DROP_DUPLICATE)
	if String(request.get("build", "")) != String(host_state.get("host_build", "")):
		return _refuse(ERROR_VERSION_MISMATCH)
	var reservations: Dictionary = host_state.get("reservations", {}) as Dictionary
	var held: Dictionary = host_state.get("held_slots", {}) as Dictionary
	if bool(host_state.get("match_in_progress", false)):
		# A token naming a slot that is still reclaimable wins first and skips the
		# joins-open and capacity checks: its own departure freed the room.
		var reclaimed: int = reclaimable_slot(String(request.get("token", "")), host_state)
		if reclaimed >= 0:
			var back: Decision = Decision.new()
			back.kind = Decision.Kind.RECLAIM
			back.slot_id = reclaimed
			return back
	if not bool(host_state.get("joins_open", false)):
		return _refuse(ERROR_MATCH_IN_PROGRESS)
	if int(host_state.get("free_capacity", 0)) <= 0:
		return _refuse(ERROR_SERVER_FULL)
	var seated: Decision = Decision.new()
	if bool(host_state.get("match_in_progress", false)):
		seated.slot_id = _open_seat(host_state, held, reservations)
	else:
		seated.slot_id = lowest_free_slot(held, reservations.values())
	return seated


## True when the raw build, name and token strings are all within their caps.
## The roster checks this on its own, ahead of the flood bucket, so an oversize
## handshake never costs a token.
static func within_caps(request: Dictionary, host_state: Dictionary) -> bool:
	return (
		String(request.get("build", "")).length() <= int(host_state.get("max_build_len", 0))
		and String(request.get("name", "")).length() <= int(host_state.get("max_name_len", 0))
		and String(request.get("token", "")).length() <= int(host_state.get("max_token_len", 0))
	)


## The lowest slot id >= 0 that no live peer (`held`: slot -> true) holds and no
## rejoin reservation (`reserved`: Array of slot ids) names.
static func lowest_free_slot(held: Dictionary, reserved: Array) -> int:
	var taken: Dictionary = held.duplicate()
	for slot: Variant in reserved:
		taken[int(slot)] = true
	var slot_id: int = 0
	while taken.has(slot_id):
		slot_id += 1
	return slot_id


## The slot `token` reserves when the seat policy still lets it be reclaimed and
## no live peer holds it; -1 otherwise (an unknown token, or a new joiner's "").
static func reclaimable_slot(token: String, host_state: Dictionary) -> int:
	var reservations: Dictionary = host_state.get("reservations", {}) as Dictionary
	if token.is_empty() or not reservations.has(token):
		return -1
	var held: Dictionary = host_state.get("held_slots", {}) as Dictionary
	var slot_id: int = int(reservations[token])
	if slot_id < 0 or held.has(slot_id):
		return -1
	var can_reclaim: Variant = host_state.get("can_reclaim_seat")
	if typeof(can_reclaim) != TYPE_CALLABLE or not (can_reclaim as Callable).is_valid():
		return -1
	if not bool((can_reclaim as Callable).call(slot_id)):
		return -1
	return slot_id


## The seat the gameplay policy offers a mid-match joiner, or -1 (spectator).
## A seat a live peer holds or a departed peer reserved is never handed out.
static func _open_seat(host_state: Dictionary, held: Dictionary, reservations: Dictionary) -> int:
	var pick: Variant = host_state.get("pick_open_seat")
	if typeof(pick) != TYPE_CALLABLE or not (pick as Callable).is_valid():
		return -1
	var seat: int = int((pick as Callable).call())
	if seat >= 0 and (held.has(seat) or reservations.values().has(seat)):
		return -1
	return seat


static func _refuse(error: int) -> Decision:
	var decision: Decision = Decision.new()
	decision.kind = Decision.Kind.REFUSE
	decision.error = error
	return decision


static func _drop(reason: StringName) -> Decision:
	var decision: Decision = Decision.new()
	decision.kind = Decision.Kind.DROP
	decision.drop_reason = reason
	return decision
