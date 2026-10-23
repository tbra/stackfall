class_name MatchEventMirror
extends RefCounted
## Host-side Events subscribers that mirror match-flow events to net_match_event, one
## on_<event> per Events-driven MatchWireEvents name. Every handler is host-only and sends
## the exact payload MatchWireEvents.shape_of describes. The replay-only events
## (slot_replay, match_clock, loading_gate) are built by MatchWorldReplay and have no
## live subscriber here.


var _session: SessionPort = null
var _host: MatchHostPort = null
var _seams: MatchIntentGateway.Seams = null
## Host: net ids of blocks currently fused into a FusedBody.
var _fused_ids: Dictionary = {}
## net ids of charged glue drops coated at spawn (cleared when their last bond ends, as that is
## when the coat is removed).
var _glue_charged_ids: Dictionary = {}


## `seams` is the same shape the intent gateway takes (production wiring MatchNet binds; a test
## binds spies): the mirror uses `broadcast` and `send_to_peer`.
func _init(seams: MatchIntentGateway.Seams) -> void:
	_seams = seams


## (Re)binds the session and Match reads. MatchNet calls it whenever its providers change; the
## session needs is_host, is_local_slot and peer_of_slot, the host eliminated_by, feed_seq,
## feed_time_left, is_release_locked, feed_claim_carrier_shape_id, feed_note_special_triggered and
## is_starting_match.
func bind_ports(session: SessionPort, host: MatchHostPort) -> void:
	_session = session
	_host = host


## Connects the subscribers that only mirror. The ones MatchNet also needs a side effect from
## (state, feed expiry, refusals, glue, dissolve) are connected by MatchNet, which calls the same
## on_<event> methods.
func bind(events_source: Node) -> void:
	events_source.connect(&"countdown_tick", on_countdown)
	events_source.connect(&"turn_changed", on_turn_changed)
	events_source.connect(&"feed_block_issued", on_feed_issued)
	events_source.connect(&"qol_feed_changed", on_qol_feed)
	events_source.connect(&"gift_slot_changed", on_gift_slot)
	events_source.connect(&"player_eliminated", on_player_eliminated)
	events_source.connect(&"match_won", on_match_won)
	events_source.connect(&"mode_state_changed", on_mode_state)
	events_source.connect(&"match_results_ready", on_match_results)
	events_source.connect(&"gift_flight_spawned", on_gift_flight)
	events_source.connect(&"gift_landed", on_gift_landed)
	events_source.connect(&"gift_spawned", on_gift_spawned)
	events_source.connect(&"gift_claimed", on_gift_claimed)
	events_source.connect(&"gift_expired", on_gift_expired)
	events_source.connect(&"special_triggered", on_special_triggered)
	events_source.connect(&"special_consumed", on_special_consumed)
	events_source.connect(&"glue_charges_changed", on_glue_charges)
	events_source.connect(&"block_owner_changed", on_block_owner_changed)
	events_source.connect(&"block_frozen_changed", on_block_frozen)
	events_source.connect(&"cat_started", on_cat_started)
	events_source.connect(&"cat_ended", on_cat_ended)
	events_source.connect(&"blocks_fused", on_blocks_fused)
	events_source.connect(&"fused_member_released", on_fused_member_released)
	events_source.connect(&"glue_drop_charged", on_glue_drop_charged)


## The LOADING/COUNTDOWN states a start_match() runs through are carried by net_match_start.
func on_state_changed(_from_state: int, to_state: int) -> void:
	if _session.is_host() and not _host.is_starting_match():
		_send(MatchWireEvents.STATE_CHANGED, [to_state])


func on_countdown(seconds_left: int) -> void:
	_send(MatchWireEvents.COUNTDOWN, [seconds_left])


func on_turn_changed(slot_id: int) -> void:
	_send(MatchWireEvents.TURN_CHANGED, [slot_id])


## The host's feed sequence, timer and release lock ride with the block they belong to, read at
## the moment Match emits (after the placement that triggered it).
func on_feed_issued(slot_id: int, shape_id: StringName, next_shape_id: StringName) -> void:
	if _session.is_host():
		_send(MatchWireEvents.FEED_ISSUED, [
			slot_id, shape_id, next_shape_id, _host.feed_seq(slot_id),
			_host.feed_time_left(slot_id), _host.is_release_locked(slot_id),
		])


func on_feed_expired(slot_id: int) -> void:
	_send(MatchWireEvents.FEED_EXPIRED, [slot_id])


func on_qol_feed(slot_id: int, backlog: int, paused: bool) -> void:
	_send(MatchWireEvents.QOL_FEED, [slot_id, backlog, paused])


func on_gift_slot(slot_id: int, contents: Array, activated: StringName, carrier_id: StringName) -> void:
	_send(MatchWireEvents.GIFT_SLOT, [slot_id, contents, activated, carrier_id])


## A refusal is the refused player's own feedback: it goes to the owning peer alone. True when
## it was sent (the caller then suppresses its own tail reply for the same intent).
func on_placement_rejected(slot_id: int, reason: StringName) -> bool:
	return _reply_to_owner(slot_id, MatchWireEvents.PLACEMENT_REJECTED, [slot_id, reason])


## The owning seat's cursor and camera jump to where an auto-dropped block landed.
func on_placement_relocated(slot_id: int, point: Vector2) -> void:
	_reply_to_owner(slot_id, MatchWireEvents.PLACEMENT_RELOCATED, [slot_id, point])


## The third argument is the eliminator slot (-1 unknown).
func on_player_eliminated(slot_id: int, team_id: int) -> void:
	if _session.is_host():
		_send(MatchWireEvents.PLAYER_ELIMINATED, [slot_id, team_id, _host.eliminated_by(slot_id)])


func on_match_won(team_id: int) -> void:
	_send(MatchWireEvents.MATCH_WON, [team_id])


func on_mode_state(state: Dictionary) -> void:
	_send(MatchWireEvents.MODE_STATE, [state])


func on_match_results(results: Dictionary) -> void:
	_send(MatchWireEvents.MATCH_RESULTS, [results])


func on_gift_flight(gift_id: int, origin: Vector3, landing: Vector3) -> void:
	_send(MatchWireEvents.GIFT_FLIGHT, [gift_id, origin, landing])


func on_gift_landed(gift_id: int, landing: Vector3) -> void:
	_send(MatchWireEvents.GIFT_LANDED, [gift_id, landing])


func on_gift_spawned(gift_id: int, position: Vector2) -> void:
	_send(MatchWireEvents.GIFT_SPAWNED, [gift_id, position])


## In the after-next trial the carrier is the staged shape, not the next piece.
func on_gift_claimed(gift_id: int, slot_id: int, special_id: StringName) -> void:
	if _session.is_host():
		_send(MatchWireEvents.GIFT_CLAIMED, [gift_id, slot_id, special_id, _host.feed_claim_carrier_shape_id(slot_id)])


func on_gift_expired(gift_id: int) -> void:
	_send(MatchWireEvents.GIFT_EXPIRED, [gift_id])


## QoL: a triggered special freezes block timers for a while.
func on_special_triggered(net_id: int, def_id: StringName, position: Vector3, chain_depth: int) -> void:
	if _session.is_host():
		_host.feed_note_special_triggered()
		_send(MatchWireEvents.SPECIAL_TRIGGERED, [net_id, def_id, position, chain_depth])


func on_special_consumed(slot_id: int, special_id: StringName) -> void:
	_send(MatchWireEvents.SPECIAL_CONSUMED, [slot_id, special_id])


func on_glue_charges(slot_id: int, charges: int, revision: int) -> void:
	_send(MatchWireEvents.GLUE_CHARGES, [slot_id, charges, revision])


func on_block_glued(net_id: int, glued: bool) -> void:
	_send(MatchWireEvents.BLOCK_GLUED, [net_id, glued])


## Host: members newly fused into a FusedBody join the glued set; the coat event fires only for
## ids that were not already coated (a charged drop is coated at spawn).
func on_blocks_fused(_carrier: Node, members: Array) -> void:
	if not _session.is_host():
		return
	for member: Variant in members:
		var block: BlockBody = member as BlockBody
		if block == null or not Quantize.is_wire_id(block.net_id):
			continue
		var was_coated: bool = _fused_ids.has(block.net_id) or _glue_charged_ids.has(block.net_id)
		_fused_ids[block.net_id] = true
		if not was_coated:
			set_block_coated(block, true)
			on_block_glued(block.net_id, true)


## Host: a member left its group alive (the survivor of a collapse); it uncoats. Members that were
## removed (hole, kill plane) are handled by forget_glued.
func on_fused_member_released(member: Node) -> void:
	var block: BlockBody = member as BlockBody
	if not _session.is_host() or block == null or not Quantize.is_wire_id(block.net_id):
		return
	var was_fused: bool = _fused_ids.erase(block.net_id)
	var was_charged: bool = _glue_charged_ids.erase(block.net_id)
	if was_fused or was_charged:
		set_block_coated(block, false)
		on_block_glued(block.net_id, false)


## Host: a charged glue drop is coated (and the coat replicated) at spawn, so it wears the jelly
## while falling. DECISION: a never-bonded charged block stays coated; the existing 1 -> 0 bond
## transition already only fires for blocks that bonded.
func on_glue_drop_charged(body: Node) -> void:
	var block: BlockBody = body as BlockBody
	if not _session.is_host() or block == null or not Quantize.is_wire_id(block.net_id):
		return
	_glue_charged_ids[block.net_id] = true
	set_block_coated(block, true)
	on_block_glued(block.net_id, true)


## A removed block leaves the glued set (its despawn tells clients; no uncoat event).
func forget_glued(net_id: int) -> void:
	_fused_ids.erase(net_id)
	_glue_charged_ids.erase(net_id)


## Net ids of blocks fused into a FusedBody or coated by a glue drop, ascending.
func glued_ids() -> Array:
	var ids: Array = _fused_ids.keys()
	for charged_id: int in _glue_charged_ids:
		if not ids.has(charged_id):
			ids.append(charged_id)
	ids.sort()
	return ids


func reset_glue() -> void:
	_fused_ids.clear()
	_glue_charged_ids.clear()


func on_block_owner_changed(net_id: int, owner_slot: int) -> void:
	_send(MatchWireEvents.BLOCK_OWNER_CHANGED, [net_id, owner_slot])


func on_block_frozen(net_id: int, frozen: bool) -> void:
	_send(MatchWireEvents.BLOCK_FROZEN, [net_id, frozen])


func on_cat_started(id: int, slot_id: int, position: Vector3, duration: float) -> void:
	_send(MatchWireEvents.CAT_STARTED, [id, slot_id, position, duration])


func on_cat_ended(id: int) -> void:
	_send(MatchWireEvents.CAT_ENDED, [id])


## A body without a wire id never reached a client, so its dissolve is not mirrored.
func on_block_dissolve_started(_block: RigidBody3D, net_id: int, _duration_s: float) -> void:
	if Quantize.is_wire_id(net_id):
		_send(MatchWireEvents.BLOCK_DISSOLVE_STARTED, [net_id])


func on_live_scores(scores: Dictionary) -> void:
	_send(MatchWireEvents.LIVE_SCORES, [scores])


## The one coat write: the mirror calls it on the host path, the event applier on a client.
static func set_block_coated(block: BlockBody, coated: bool) -> void:
	LateScripts.script(LateScripts.HONEY_COAT).call(&"set_coated", block, coated)


func _send(event: StringName, args: Array) -> void:
	if _session.is_host():
		_seams.broadcast.call(&"net_match_event", [event, args])


## The remote peer that holds `slot_id`, or -1 when nobody remote does: the listen-server's own
## seat (it reacts to Match's local emit), a bot, an empty or vacated seat, a bad slot.
func _remote_peer_of_slot(slot_id: int) -> int:
	if slot_id < 0 or _session.is_local_slot(slot_id):
		return -1
	var peer_id: int = _session.peer_of_slot(slot_id)
	if peer_id <= 0 or peer_id == Net.HOST_PEER_ID:
		return -1
	return peer_id


func _reply_to_owner(slot_id: int, event: StringName, args: Array) -> bool:
	if not _session.is_host():
		return false
	var owner_peer: int = _remote_peer_of_slot(slot_id)
	if owner_peer < 0:
		return false
	return bool(_seams.send_to_peer.call(owner_peer, &"net_match_event", [event, args]))
