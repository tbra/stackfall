class_name MatchReplicaPort
extends RefCounted
## Typed adapter over the Match autoload: the client-side
## mirror writes (`apply_replicated_*`) that net/MatchEventApplier and
## net/MatchNet make when the host's answers arrive. Reads and the host-side
## rule entry points live on MatchHostPort; this port only mirrors.
##
## DECISION: see SessionPort for why this is an adapter holding the autoload with a
## runtime is_valid() instead of an assert. Signatures are copied from autoload/Match.gd,
## which is not edited. The feed / lifecycle entries are no-ops when the port adapts
## nothing (the spies, which override every mirror write).
## SHORTCUT: dynamic calls on the RefCounted feed/lifecycle controllers, upgrade when P7 lets the autoload closure name MatchFeed/MatchLifecycle (V1 typing)

var _match: MatchAutoload = null
var _valid: bool = false


## A real Match (the autoload or any MatchAutoload instance); null leaves the port
## invalid (spies and the invalid-port case).
func _init(match_node: MatchAutoload = null) -> void:
	_match = match_node
	_valid = match_node != null


## True when the port adapts a Match.
func is_valid() -> bool:
	return _valid


func apply_replicated_state_change(new_state: int) -> void:
	_match.apply_replicated_state_change(new_state)


func apply_replicated_countdown(seconds_left: int) -> void:
	_match.apply_replicated_countdown(seconds_left)


func apply_replicated_feed(
	slot_id: int,
	shape_id: StringName,
	next_shape_id: StringName,
	host_feed_seq: int,
	host_feed_time_left: float = -1.0,
	host_is_locked: bool = false
) -> void:
	_match.apply_replicated_feed(slot_id, shape_id, next_shape_id, host_feed_seq, host_feed_time_left, host_is_locked)


func apply_replicated_turn(slot_id: int) -> void:
	_match.apply_replicated_turn(slot_id)


func apply_replicated_elimination(slot_id: int, by_slot: int = -1) -> void:
	_match.apply_replicated_elimination(slot_id, by_slot)


func apply_replicated_mode_state(mode_state: Dictionary) -> void:
	_match.apply_replicated_mode_state(mode_state)


func apply_replicated_gift_spawned(gift_id: int, position: Vector2) -> void:
	_match.apply_replicated_gift_spawned(gift_id, position)


func apply_replicated_gift_flight(gift_id: int, origin: Vector3, landing: Vector3) -> void:
	_match.apply_replicated_gift_flight(gift_id, origin, landing)


func apply_replicated_gift_landed(gift_id: int, landing: Vector3) -> void:
	_match.apply_replicated_gift_landed(gift_id, landing)


func apply_replicated_gift_claimed(gift_id: int, slot_id: int, special_id: StringName) -> void:
	_match.apply_replicated_gift_claimed(gift_id, slot_id, special_id)


func apply_replicated_gift_expired(gift_id: int) -> void:
	_match.apply_replicated_gift_expired(gift_id)


func apply_replicated_gift_slot(slot_id: int, contents: Array, activated: StringName, carrier_id: StringName) -> void:
	_match.apply_replicated_gift_slot(slot_id, contents, activated, carrier_id)


func apply_replicated_qol(slot_id: int, backlog: int, paused: bool) -> void:
	_match.apply_replicated_qol(slot_id, backlog, paused)


func apply_replicated_special_consumed(slot_id: int, special_id: StringName) -> void:
	_match.apply_replicated_special_consumed(slot_id, special_id)


func apply_replicated_territory(
	cells: PackedInt32Array,
	owners: PackedByteArray,
	states: PackedByteArray,
	full: bool,
	circle_xs: PackedFloat32Array = PackedFloat32Array(),
	circle_zs: PackedFloat32Array = PackedFloat32Array(),
	circle_radii: PackedFloat32Array = PackedFloat32Array(),
	circle_teams: PackedInt32Array = PackedInt32Array(),
	goal_positions: PackedVector2Array = PackedVector2Array(),
	goal_radii: PackedFloat32Array = PackedFloat32Array(),
	argmax_mode: bool = false
) -> void:
	_match.apply_replicated_territory(cells, owners, states, full, circle_xs, circle_zs, circle_radii, circle_teams, goal_positions, goal_radii, argmax_mode)


func apply_replicated_glue_charges(slot_id: int, count: int, revision: int) -> bool:
	return _match.apply_replicated_glue_charges(slot_id, count, revision)


func apply_replicated_block_owner(net_id: int, new_slot: int) -> bool:
	return _match.apply_replicated_block_owner(net_id, new_slot)


func apply_replicated_cat_start(id: int, slot_id: int, position: Vector3, duration: float) -> bool:
	return _match.apply_replicated_cat_start(id, slot_id, position, duration)


func apply_replicated_cat_state(id: int, position: Vector3, velocity: Vector3, point: Vector3, remaining: float) -> void:
	_match.apply_replicated_cat_state(id, position, velocity, point, remaining)


## The host ended cat `id` (MatchWireEvents.CAT_ENDED); Match ignores a stale id.
func end_cat(id: int) -> void:
	_match.end_cat(id)


# --- Feed / lifecycle controllers (dynamic calls on Match.feed() / Match.lifecycle()) -----

## MatchFeed.apply_replicated_next_gift(). No-op without a feed.
func apply_replicated_next_gift(slot_id: int, shape_id: StringName) -> void:
	var feed: RefCounted = _match.feed() if _match != null else null
	if feed != null:
		feed.call(&"apply_replicated_next_gift", slot_id, shape_id)


## MatchFeed.apply_replicated_staged_gift(). No-op without a feed.
func apply_replicated_staged_gift(slot_id: int, shape_id: StringName) -> void:
	var feed: RefCounted = _match.feed() if _match != null else null
	if feed != null:
		feed.call(&"apply_replicated_staged_gift", slot_id, shape_id)


## Writes the host's match clock into MatchLifecycle (MatchWireEvents.MATCH_CLOCK).
## No-op without a lifecycle.
func apply_replicated_match_timer(seconds_left: float) -> void:
	var lifecycle: RefCounted = _match.lifecycle() if _match != null else null
	if lifecycle != null:
		lifecycle.apply_replicated_match_timer(seconds_left)
