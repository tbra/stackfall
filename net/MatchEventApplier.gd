extends Node
## Client-side apply of host -> client match events.
##
## A child of the MatchNet autoload, built by MatchNet.late_activate() so the validation and
## dispatch below are compiled after the first frame instead of with the autoload. The RPC entry
## point stays MatchNet.net_match_event() (path /root/MatchNet unchanged, protocol unchanged); it
## forwards here after its own awaiting-world gate. No RPC lives on this node.
##
## apply_event() is a table: the argument shape of the event first (MatchWireEvents.shape_of
## through WireLimits.args_shape_ok), then one handler per MatchWireEvents name. A handler
## validates the values the shape cannot (ranges, ids, ownership, match state) and then makes
## its writes through the typed MatchReplicaPort. Every handler answers whether it applied.

## MatchWireEvents.SPECIAL_TRIGGERED's chain_depth wire bound (SpecialTuning.max_chain_depth): the config is
## architecture-fixed for the build, so it is preloaded rather than read from the running match.
var _special_tuning: SpecialTuning = preload("res://config/gifts/special_tuning.tres")
## The fade length a client reports with a replicated dissolve start (the shipped resource the
## host's HoleDissolver reads).
var _hole_dissolve_tuning: HoleDissolveTuning = preload("res://config/blocks/tuning/hole_dissolve_tuning.tres")

var _session: SessionPort = null
var _host: MatchHostPort = null
var _replica: MatchReplicaPort = null
var _config: NetConfig = null
var _gifts: GiftWireGuard = null
var _handlers: Dictionary = {}


## Binds the ports, the wire config and the gift wire state; MatchNet calls it again on every
## rebind (this node holds no state beyond these refs). Until it is bound every event is refused.
func bind(session: SessionPort, host: MatchHostPort, replica: MatchReplicaPort, config: NetConfig, gifts: GiftWireGuard) -> void:
	_session = session
	_host = host
	_replica = replica
	_config = config
	_gifts = gifts


## Validates and applies one host-authored match event. False when the event is unknown, its
## arguments do not have the wire shape, or its handler refused the values.
func apply_event(event: StringName, args: Array) -> bool:
	var shape: Array = MatchWireEvents.shape_of(event)
	if shape.is_empty() or not WireLimits.args_shape_ok(args, shape):
		return false
	if _replica == null or not _replica.is_valid():
		return false
	if _handlers.is_empty():
		_build_handlers()
	return bool((_handlers[event] as Callable).call(args))


func _build_handlers() -> void:
	_handlers = {
		MatchWireEvents.STATE_CHANGED: _on_state_changed,
		MatchWireEvents.COUNTDOWN: _on_countdown,
		MatchWireEvents.TURN_CHANGED: _on_turn_changed,
		MatchWireEvents.FEED_ISSUED: _on_feed_issued,
		MatchWireEvents.FEED_EXPIRED: _on_feed_expired,
		MatchWireEvents.QOL_FEED: _on_qol_feed,
		MatchWireEvents.GIFT_SLOT: _on_gift_slot,
		MatchWireEvents.PLACEMENT_REJECTED: _on_placement_rejected,
		MatchWireEvents.PLACEMENT_RELOCATED: _on_placement_relocated,
		MatchWireEvents.PLAYER_ELIMINATED: _on_player_eliminated,
		MatchWireEvents.MATCH_WON: _on_match_won,
		MatchWireEvents.MODE_STATE: _on_mode_state,
		MatchWireEvents.MATCH_RESULTS: _on_match_results,
		MatchWireEvents.GIFT_FLIGHT: _on_gift_flight,
		MatchWireEvents.GIFT_LANDED: _on_gift_landed,
		MatchWireEvents.GIFT_SPAWNED: _on_gift_spawned,
		MatchWireEvents.GIFT_CLAIMED: _on_gift_claimed,
		MatchWireEvents.GIFT_EXPIRED: _on_gift_expired,
		MatchWireEvents.SPECIAL_TRIGGERED: _on_special_triggered,
		MatchWireEvents.SPECIAL_CONSUMED: _on_special_consumed,
		MatchWireEvents.GLUE_CHARGES: _on_glue_charges,
		MatchWireEvents.BLOCK_GLUED: _on_block_glued,
		MatchWireEvents.BLOCK_OWNER_CHANGED: _on_block_owner_changed,
		MatchWireEvents.BLOCK_FROZEN: _on_block_frozen,
		MatchWireEvents.CAT_STARTED: _on_cat_started,
		MatchWireEvents.CAT_ENDED: _on_cat_ended,
		MatchWireEvents.BLOCK_DISSOLVE_STARTED: _on_block_dissolve_started,
		MatchWireEvents.SLOT_REPLAY: _on_slot_replay,
		MatchWireEvents.MATCH_CLOCK: _on_match_clock,
		MatchWireEvents.LOADING_GATE: _on_loading_gate,
		MatchWireEvents.LIVE_SCORES: _on_live_scores,
	}


func _slot_ok(slot_id: int) -> bool:
	return slot_id >= 0 and slot_id < _host.slot_count()


func _block_for(net_id: int) -> BlockBody:
	if not Quantize.is_wire_id(net_id):
		return null
	var registry: Node = _host.registry()
	if registry == null:
		return null
	var block: BlockBody = registry.block_for_net_id(net_id)
	return block if block != null and is_instance_valid(block) else null


func _on_state_changed(args: Array) -> bool:
	_replica.apply_replicated_state_change(args[0])
	return true


func _on_countdown(args: Array) -> bool:
	_replica.apply_replicated_countdown(args[0])
	Events.countdown_tick.emit(args[0])
	return true


## DECISION: in turn-based play, Events.turn_changed means "it is this slot's turn". In
## real-time play there are no turns (every slot plays at once), and what the signal
## does on a receiving instance is point the HUD and the ghost at the controls that are live
## here, which is always your own slot. Mirroring the host's value verbatim would aim this
## client's whole UI at another player, so outside turn-based play a client substitutes its own
## slot. Turn-based mirrors the host's slot verbatim.
func _on_turn_changed(args: Array) -> bool:
	var turn_slot: int = args[0]
	var running: MatchConfig = _host.config()
	if running != null and not running.turn_based:
		turn_slot = _session.local_slot()
	if turn_slot < 0:
		return false
	_replica.apply_replicated_turn(turn_slot)
	Events.turn_changed.emit(turn_slot)
	return true


func _on_feed_issued(args: Array) -> bool:
	_replica.apply_replicated_feed(args[0], args[1], args[2], args[3], args[4], args[5])
	Events.feed_block_issued.emit(args[0], args[1], args[2])
	return true


func _on_feed_expired(args: Array) -> bool:
	Events.feed_timer_expired.emit(args[0])
	return true


func _on_gift_slot(args: Array) -> bool:
	if _session.is_host() or not _slot_ok(args[0]):
		return false
	var contents: Array = args[1]
	if contents.size() > QolExperiments.GIFT_SLOT_CAPACITY_CEILING:
		return false
	var slot_contents: Array[StringName] = []
	for entry: Variant in contents:
		if not (entry is String or entry is StringName) or not _gifts.special_id_ok(StringName(entry)):
			return false
		slot_contents.append(StringName(entry))
	var activated_special: StringName = args[2]
	var carrier_id: StringName = args[3]
	if activated_special != &"" and (not _gifts.special_id_ok(activated_special) or not _host.feed_knows_shape(carrier_id)):
		return false
	_replica.apply_replicated_gift_slot(args[0], slot_contents, activated_special, carrier_id)
	return true


func _on_qol_feed(args: Array) -> bool:
	if _session.is_host() or not _slot_ok(args[0]):
		return false
	_replica.apply_replicated_qol(args[0], args[1], args[2])
	Events.qol_feed_changed.emit(args[0], args[1], args[2])
	return true


## An input boundary like every other wire payload; a refusal is the refused player's own
## feedback, so anything naming a slot this instance does not drive (including the host's own
## seat) is dropped rather than sounded.
func _on_placement_rejected(args: Array) -> bool:
	var rejected_slot: int = args[0]
	var reason: String = String(args[1])
	if _session.is_host() or not _slot_ok(rejected_slot):
		return false
	if WireLimits.reject_reason_clamped(reason, _config) != reason:
		return false
	if not _session.is_local_slot(rejected_slot):
		return false
	Events.placement_rejected.emit(rejected_slot, StringName(reason))
	return true


## Same own-seat-only rule: a malformed or out-of-disk point, or another seat's relocation,
## never reaches the cursor/camera jump.
func _on_placement_relocated(args: Array) -> bool:
	var relocated_slot: int = args[0]
	var relocated_point: Vector2 = args[1]
	if _session.is_host() or _host.config() == null or not _slot_ok(relocated_slot):
		return false
	var point_bound: float = _host.circle_wire_xz_bound()
	if not relocated_point.is_finite() or absf(relocated_point.x) > point_bound or absf(relocated_point.y) > point_bound:
		return false
	if not _session.is_local_slot(relocated_slot):
		return false
	Events.placement_relocated.emit(relocated_slot, relocated_point)
	return true


func _on_player_eliminated(args: Array) -> bool:
	var by_slot: int = args[2]
	if by_slot < -1 or by_slot >= _host.slot_count():
		by_slot = -1
	_replica.apply_replicated_elimination(args[0], by_slot)
	Events.player_eliminated.emit(args[0], args[1])
	return true


func _on_match_won(args: Array) -> bool:
	Events.match_won.emit(args[0])
	return true


## Display-only mirror; a client never derives an outcome from it. Malformed payloads are
## dropped, not defaulted.
func _on_mode_state(args: Array) -> bool:
	var mode_state: Dictionary = ResultsValidation.validate_mode_state(args[0])
	if mode_state.is_empty():
		return false
	_replica.apply_replicated_mode_state(mode_state)
	return true


## A malformed or truncated payload must not reach a results-screen consumer half-typed (see
## ResultsValidation.validate_results_payload for why this rejects rather than defaults).
func _on_match_results(args: Array) -> bool:
	var validated: Dictionary = ResultsValidation.validate_results_payload(args[0])
	if validated.is_empty():
		return false
	Events.match_results_ready.emit(validated)
	return true


func _on_live_scores(args: Array) -> bool:
	if _session.is_host():
		return false
	var live: Dictionary = ResultsValidation.validate_results_payload(args[0])
	var stats: MatchStats = _host.stats() as MatchStats
	if live.is_empty() or stats == null:
		return false
	stats.apply_live_snapshot(live)
	return true


func _on_gift_flight(args: Array) -> bool:
	var gift_id: int = args[0]
	var origin: Vector3 = args[1]
	var landing: Vector3 = args[2]
	if gift_id < 0 or not origin.is_finite() or not landing.is_finite():
		return false
	if not is_finite(origin.distance_to(landing)) or origin.y < landing.y:
		return false
	if not _gifts.begin_flight(gift_id):
		return false
	_replica.apply_replicated_gift_flight(gift_id, origin, landing)
	Events.gift_flight_spawned.emit(gift_id, origin, landing)
	return true


func _on_gift_landed(args: Array) -> bool:
	var gift_id: int = args[0]
	var landing: Vector3 = args[1]
	if gift_id < 0 or not landing.is_finite():
		return false
	var state: Dictionary = _host.gift_state(gift_id)
	if state.is_empty() or not landing.is_equal_approx(state["landing"]) or not _gifts.land(gift_id):
		return false
	_replica.apply_replicated_gift_landed(gift_id, landing)
	Events.gift_landed.emit(gift_id, landing)
	return true


func _on_gift_spawned(args: Array) -> bool:
	var gift_id: int = args[0]
	var position: Vector2 = args[1]
	if not _gifts.note_spawn(gift_id, position):
		return false
	_replica.apply_replicated_gift_spawned(gift_id, position)
	Events.gift_spawned.emit(gift_id, position)
	return true


func _on_gift_claimed(args: Array) -> bool:
	var gift_id: int = args[0]
	var slot_id: int = args[1]
	var special_id: StringName = args[2]
	var gift_shape_id: StringName = args[3]
	# Bounds-check the slot before it reaches MatchGifts.apply_replicated_claim() or the Events bus.
	if not _slot_ok(slot_id) or not _gifts.special_id_ok(special_id) or not _host.feed_knows_shape(gift_shape_id):
		return false
	if not _gifts.remove(gift_id):
		return false
	if _host.gift_slot_enabled():
		# The gift went to the slot (MatchWireEvents.GIFT_SLOT), not the block queue; only the crate
		# visual is retired here.
		_replica.apply_replicated_gift_expired(gift_id)
	else:
		_replica.apply_replicated_gift_claimed(gift_id, slot_id, special_id)
		if _host.feed_gift_after_next_active():
			_replica.apply_replicated_staged_gift(slot_id, gift_shape_id)
		else:
			_replica.apply_replicated_next_gift(slot_id, gift_shape_id)
	Events.gift_claimed.emit(gift_id, slot_id, special_id)
	return true


func _on_gift_expired(args: Array) -> bool:
	var gift_id: int = args[0]
	if not _gifts.remove(gift_id):
		return false
	_replica.apply_replicated_gift_expired(gift_id)
	Events.gift_expired.emit(gift_id)
	return true


## Mirrors a special's trigger to every client. A client runs no SpecialBehavior of its own, so
## this is the only place it learns a special fired; it is an effects signal, never fed back
## into Match.
func _on_special_triggered(args: Array) -> bool:
	var net_id: int = args[0]
	var def_id: StringName = args[1]
	var position: Vector3 = args[2]
	var chain_depth: int = args[3]
	if net_id < 0 or not WireLimits.special_id_ok(def_id, _config) or not position.is_finite():
		return false
	if chain_depth < 0 or chain_depth > _special_tuning.max_chain_depth:
		return false
	Events.special_triggered.emit(net_id, def_id, position, chain_depth)
	return true


## DECISION: unlike most cases, this one guards is_host() itself rather than relying only on
## net_match_event's @rpc("authority", ...): a well-behaved client never sends this RPC, so a
## host-side call is a stale duplicate or spoofed, and popping the host's own queue twice would
## silently desync it from every client's mirror.
func _on_special_consumed(args: Array) -> bool:
	if _session.is_host() or not _slot_ok(args[0]):
		return false
	# Only the syntactic shape check, not the roster-membership tightening: a special already
	# popped on the host was roster-checked when it was queued.
	if not WireLimits.special_id_ok(args[1], _config):
		return false
	_replica.apply_replicated_special_consumed(args[0], args[1])
	Events.special_consumed.emit(args[0], args[1])
	return true


func _on_glue_charges(args: Array) -> bool:
	if _session.is_host() or not _slot_ok(args[0]):
		return false
	if args[1] < 0 or args[1] > 100 or args[2] <= 0:
		return false
	_replica.apply_replicated_glue_charges(args[0], args[1], args[2])
	return true


## Presentation only. An unknown id (a spawn the client never built) or a malformed payload is
## dropped.
func _on_block_dissolve_started(args: Array) -> bool:
	if _session.is_host():
		return false
	var dissolving: BlockBody = _block_for(args[0])
	if dissolving == null:
		return false
	Events.block_dissolve_started.emit(dissolving, args[0], _hole_dissolve_tuning.dissolve_delay_s)
	return true


## SLOT_REPLAY's argument positions (the MatchWireEvents row).
enum ReplayArg { SLOT, HELD, NEXT, FEED_SEQ, TIME_LEFT, LOCKED, HELD_SPECIAL, NEXT_SPECIAL, AFTER_SPECIAL, AFTER_CARRIER }


## Client side of SLOT_REPLAY. The wire is validated in full before any of it is applied (the same
## "drop, never default" rule as every other event): a malformed slot replay changes nothing. The
## argument types are already enforced by the MatchWireEvents shape.
##
## Gifts are rebuilt through the same replica calls a live claim uses, in the order a seated client
## would have seen them: the held gift is queued and marked as the next carrier, the feed event
## activates it, then the queued next gift is queued behind it.
func _on_slot_replay(args: Array) -> bool:
	if _session.is_host():
		return false
	var slot_id: int = args[ReplayArg.SLOT]
	var held_id: StringName = args[ReplayArg.HELD]
	var next_id: StringName = args[ReplayArg.NEXT]
	var feed_seq: int = args[ReplayArg.FEED_SEQ]
	var time_left: float = float(args[ReplayArg.TIME_LEFT])
	var locked: bool = args[ReplayArg.LOCKED]
	var held_special: StringName = args[ReplayArg.HELD_SPECIAL]
	var next_special: StringName = args[ReplayArg.NEXT_SPECIAL]
	var after_special: StringName = args[ReplayArg.AFTER_SPECIAL]
	var after_carrier: StringName = args[ReplayArg.AFTER_CARRIER]
	if _host.config() == null or not _slot_ok(slot_id):
		return false
	if feed_seq < 0 or not is_finite(time_left) or time_left < 0.0 or time_left > MatchConfig.BLOCK_TIMER_MAX:
		return false
	if not _host.feed_knows_shape(held_id):
		return false
	if next_id != &"" and not _host.feed_knows_shape(next_id):
		return false
	if held_special != &"" and not _gifts.special_id_ok(held_special):
		return false
	if next_special != &"" and (next_id == &"" or not _gifts.special_id_ok(next_special)):
		return false
	if after_special != &"" and (not _gifts.special_id_ok(after_special) or not _host.feed_knows_shape(after_carrier)):
		return false
	if held_special != &"":
		_replica.apply_replicated_gift_claimed(-1, slot_id, held_special)
		_replica.apply_replicated_next_gift(slot_id, held_id)
	_replica.apply_replicated_feed(slot_id, held_id, next_id, feed_seq, time_left, locked)
	if next_special != &"":
		_replica.apply_replicated_gift_claimed(-1, slot_id, next_special)
		_replica.apply_replicated_next_gift(slot_id, next_id)
	if after_special != &"":
		_replica.apply_replicated_gift_claimed(-1, slot_id, after_special)
		_replica.apply_replicated_staged_gift(slot_id, after_carrier)
	Events.feed_block_issued.emit(slot_id, held_id, next_id)
	return true


## The client's read model of the match timer is written directly; a client never ticks it.
## Timed modes keep it current through MatchWireEvents.MODE_STATE.
func _on_match_clock(args: Array) -> bool:
	var clock: float = args[0]
	if _session.is_host() or not is_finite(clock) or clock < 0.0:
		return false
	_replica.apply_replicated_match_timer(clock)
	return true


func _on_block_owner_changed(args: Array) -> bool:
	if _session.is_host() or not Quantize.is_wire_id(args[0]) or not _slot_ok(args[1]):
		return false
	_replica.apply_replicated_block_owner(args[0], args[1])
	return true


func _on_block_glued(args: Array) -> bool:
	if _session.is_host():
		return false
	var block: BlockBody = _block_for(args[0])
	if block == null:
		return false
	MatchEventMirror.set_block_coated(block, args[1])
	return true


func _on_block_frozen(args: Array) -> bool:
	if _session.is_host():
		return false
	var block: BlockBody = _block_for(args[0])
	if block == null:
		return false
	if block.is_frozen_visual() != args[1]:
		block.set_frozen_visual(args[1])
		Events.block_frozen_changed.emit(args[0], args[1])
	return true


func _on_cat_started(args: Array) -> bool:
	var cat_id: int = args[0]
	var cat_slot: int = args[1]
	var position: Vector3 = args[2]
	var duration: float = args[3]
	if _session.is_host() or not Quantize.is_wire_id(cat_id) or not _slot_ok(cat_slot):
		return false
	# A duration the clamp would change (over the cap, or not finite) is not from this build's host.
	if not position.is_finite() or duration <= 0.0 or WireLimits.cat_duration_clamped(duration, _config) != duration:
		return false
	_replica.apply_replicated_cat_start(cat_id, cat_slot, position, duration)
	return true


func _on_cat_ended(args: Array) -> bool:
	if _session.is_host() or not Quantize.is_wire_id(args[0]):
		return false
	_replica.end_cat(args[0])
	return true


## The replayed loading-gate snapshot [ready_ids, required_ids, open], applied through the same
## Events a live broadcast uses (the lifecycle's mirror and the loading screen listen to those).
## Host-authored only; every field is validated like Net._rpc_loading_ready_state.
func _on_loading_gate(args: Array) -> bool:
	if _session.is_host():
		return false
	var ready_ids: PackedInt32Array = args[0]
	var required_ids: PackedInt32Array = args[1]
	var max_peers: int = _config.max_peers
	if ready_ids.size() > max_peers or required_ids.size() > max_peers:
		return false
	for peer_id: int in ready_ids:
		if peer_id < Net.HOST_PEER_ID:
			return false
	for peer_id: int in required_ids:
		if peer_id < Net.HOST_PEER_ID:
			return false
	Events.loading_ready_changed.emit(ready_ids, required_ids)
	if bool(args[2]):
		Events.loading_gate_opened.emit()
	return true
