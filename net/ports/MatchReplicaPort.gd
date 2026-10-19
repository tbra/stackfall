class_name MatchReplicaPort
extends RefCounted
## Typed adapter over the Match autoload (or a test double): the client-side
## mirror writes (`apply_replicated_*`) that net/MatchEventApplier and
## net/MatchNet make when the host's answers arrive. Reads and the host-side
## rule entry points live on MatchHostPort; this port only mirrors.
##
## DECISION: see SessionPort for why this is an adapter holding the autoload
## (one dynamic call per method) with a runtime is_valid() instead of an assert.
## Signatures are copied from autoload/Match.gd, which is not edited. The
## TRANSITIONAL entries forward to Match's private `_feed` / `_lifecycle`
## collaborators and are no-ops when the adapted object has none (the doubles).

## Every mirror write a real Match answers.
const REQUIRED_METHODS: Array[StringName] = [
	&"apply_replicated_state_change",
	&"apply_replicated_countdown",
	&"apply_replicated_feed",
	&"apply_replicated_turn",
	&"apply_replicated_elimination",
	&"apply_replicated_mode_state",
	&"apply_replicated_gift_spawned",
	&"apply_replicated_gift_flight",
	&"apply_replicated_gift_landed",
	&"apply_replicated_gift_claimed",
	&"apply_replicated_gift_expired",
	&"apply_replicated_gift_slot",
	&"apply_replicated_qol",
	&"apply_replicated_special_consumed",
	&"apply_replicated_territory",
	&"apply_replicated_glue_charges",
	&"apply_replicated_block_owner",
	&"apply_replicated_cat_start",
	&"apply_replicated_cat_state",
	&"end_cat",
]

const FEED_PROPERTY: StringName = &"_feed"
const LIFECYCLE_PROPERTY: StringName = &"_lifecycle"
const MATCH_TIMER_PROPERTY: StringName = &"_match_timer_left"

var _match: Object = null
var _valid: bool = false


func _init(match_node: Object) -> void:
	_match = match_node
	if match_node == null:
		push_error("MatchReplicaPort: the adapted match object is null")
		return
	var missing: Array[StringName] = []
	for method_name: StringName in REQUIRED_METHODS:
		if not match_node.has_method(method_name):
			missing.append(method_name)
	if not missing.is_empty():
		push_error("MatchReplicaPort: %s lacks %s" % [_describe(match_node), missing])
		return
	_valid = true


## True when the adapted object has every REQUIRED_METHODS entry.
func is_valid() -> bool:
	return _valid


func apply_replicated_state_change(new_state: int) -> void:
	_match.call(&"apply_replicated_state_change", new_state)


func apply_replicated_countdown(seconds_left: int) -> void:
	_match.call(&"apply_replicated_countdown", seconds_left)


func apply_replicated_feed(
	slot_id: int,
	shape_id: StringName,
	next_shape_id: StringName,
	host_feed_seq: int,
	host_feed_time_left: float = -1.0,
	host_is_locked: bool = false
) -> void:
	_match.call(&"apply_replicated_feed", slot_id, shape_id, next_shape_id, host_feed_seq, host_feed_time_left, host_is_locked)


func apply_replicated_turn(slot_id: int) -> void:
	_match.call(&"apply_replicated_turn", slot_id)


func apply_replicated_elimination(slot_id: int, by_slot: int = -1) -> void:
	_match.call(&"apply_replicated_elimination", slot_id, by_slot)


func apply_replicated_mode_state(mode_state: Dictionary) -> void:
	_match.call(&"apply_replicated_mode_state", mode_state)


func apply_replicated_gift_spawned(gift_id: int, position: Vector2) -> void:
	_match.call(&"apply_replicated_gift_spawned", gift_id, position)


func apply_replicated_gift_flight(gift_id: int, origin: Vector3, landing: Vector3) -> void:
	_match.call(&"apply_replicated_gift_flight", gift_id, origin, landing)


func apply_replicated_gift_landed(gift_id: int, landing: Vector3) -> void:
	_match.call(&"apply_replicated_gift_landed", gift_id, landing)


func apply_replicated_gift_claimed(gift_id: int, slot_id: int, special_id: StringName) -> void:
	_match.call(&"apply_replicated_gift_claimed", gift_id, slot_id, special_id)


func apply_replicated_gift_expired(gift_id: int) -> void:
	_match.call(&"apply_replicated_gift_expired", gift_id)


func apply_replicated_gift_slot(slot_id: int, contents: Array, activated: StringName, carrier_id: StringName) -> void:
	_match.call(&"apply_replicated_gift_slot", slot_id, contents, activated, carrier_id)


func apply_replicated_qol(slot_id: int, backlog: int, paused: bool) -> void:
	_match.call(&"apply_replicated_qol", slot_id, backlog, paused)


func apply_replicated_special_consumed(slot_id: int, special_id: StringName) -> void:
	_match.call(&"apply_replicated_special_consumed", slot_id, special_id)


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
	_match.call(
		&"apply_replicated_territory",
		cells, owners, states, full,
		circle_xs, circle_zs, circle_radii, circle_teams,
		goal_positions, goal_radii, argmax_mode
	)


func apply_replicated_glue_charges(slot_id: int, count: int, revision: int) -> bool:
	return bool(_match.call(&"apply_replicated_glue_charges", slot_id, count, revision))


func apply_replicated_block_owner(net_id: int, new_slot: int) -> bool:
	return bool(_match.call(&"apply_replicated_block_owner", net_id, new_slot))


func apply_replicated_cat_start(id: int, slot_id: int, position: Vector3, duration: float) -> bool:
	return bool(_match.call(&"apply_replicated_cat_start", id, slot_id, position, duration))


func apply_replicated_cat_state(id: int, position: Vector3, velocity: Vector3, point: Vector3, remaining: float) -> void:
	_match.call(&"apply_replicated_cat_state", id, position, velocity, point, remaining)


## The host ended cat `id` (EVENT_CAT_ENDED); Match ignores a stale id.
func end_cat(id: int) -> void:
	_match.call(&"end_cat", id)


# --- TRANSITIONAL: Match's private feed / lifecycle collaborators -----------------

## MatchFeed.apply_replicated_next_gift(). No-op without a feed.
func apply_replicated_next_gift(slot_id: int, shape_id: StringName) -> void:
	var feed: Object = _collaborator(FEED_PROPERTY)
	if feed != null:
		feed.call(&"apply_replicated_next_gift", slot_id, shape_id)


## MatchFeed.apply_replicated_staged_gift(). No-op without a feed.
func apply_replicated_staged_gift(slot_id: int, shape_id: StringName) -> void:
	var feed: Object = _collaborator(FEED_PROPERTY)
	if feed != null:
		feed.call(&"apply_replicated_staged_gift", slot_id, shape_id)


## Writes the host's match clock into MatchLifecycle (EVENT_MATCH_CLOCK).
## No-op without a lifecycle.
func apply_replicated_match_timer(seconds_left: float) -> void:
	var lifecycle: Object = _collaborator(LIFECYCLE_PROPERTY)
	if lifecycle != null:
		lifecycle.set(MATCH_TIMER_PROPERTY, seconds_left)


func _collaborator(property_name: StringName) -> Object:
	return _match.get(property_name) as Object


static func _describe(node: Object) -> String:
	var script: Script = node.get_script() as Script
	if script != null and not script.resource_path.is_empty():
		return script.resource_path
	return node.get_class()
