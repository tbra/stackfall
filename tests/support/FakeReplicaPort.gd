class_name FakeReplicaPort
extends MatchReplicaPort
## Spy for MatchReplicaPort: answers every mirror write a consumer (MatchEventApplier,
## MatchNet) makes, records it in `calls` and returns the neutral answer, so a test asserts
## what the consumer asked the replica to do without a Match. It adapts nothing (super(null)),
## so a port method added without an override here falls through to the null adapter and
## fails the test loudly instead of reaching the real autoload; test_replica_port.gd's
## conformance test fails first. A test needing another answer extends this class and
## overrides that one method.

## One entry per call, in order: {"method": StringName, "args": Array}.
var calls: Array[Dictionary] = []


func _init() -> void:
	super(null)


func is_valid() -> bool:
	return true


## The argument lists of every call to `method_name`, in order.
func calls_to(method_name: StringName) -> Array[Array]:
	var found: Array[Array] = []
	for call: Dictionary in calls:
		if call["method"] == method_name:
			found.append(call["args"] as Array)
	return found


func _note(method_name: StringName, args: Array) -> void:
	calls.append({"method": method_name, "args": args})


func apply_replicated_state_change(new_state: int) -> void:
	_note(&"apply_replicated_state_change", [new_state])


func apply_replicated_countdown(seconds_left: int) -> void:
	_note(&"apply_replicated_countdown", [seconds_left])


func apply_replicated_feed(
	slot_id: int,
	shape_id: StringName,
	next_shape_id: StringName,
	host_feed_seq: int,
	host_feed_time_left: float = -1.0,
	host_is_locked: bool = false
) -> void:
	_note(&"apply_replicated_feed", [slot_id, shape_id, next_shape_id, host_feed_seq, host_feed_time_left, host_is_locked])


func apply_replicated_turn(slot_id: int) -> void:
	_note(&"apply_replicated_turn", [slot_id])


func apply_replicated_elimination(slot_id: int, by_slot: int = -1) -> void:
	_note(&"apply_replicated_elimination", [slot_id, by_slot])


func apply_replicated_mode_state(mode_state: Dictionary) -> void:
	_note(&"apply_replicated_mode_state", [mode_state])


func apply_replicated_gift_spawned(gift_id: int, position: Vector2) -> void:
	_note(&"apply_replicated_gift_spawned", [gift_id, position])


func apply_replicated_gift_flight(gift_id: int, origin: Vector3, landing: Vector3) -> void:
	_note(&"apply_replicated_gift_flight", [gift_id, origin, landing])


func apply_replicated_gift_landed(gift_id: int, landing: Vector3) -> void:
	_note(&"apply_replicated_gift_landed", [gift_id, landing])


func apply_replicated_gift_claimed(gift_id: int, slot_id: int, special_id: StringName) -> void:
	_note(&"apply_replicated_gift_claimed", [gift_id, slot_id, special_id])


func apply_replicated_gift_expired(gift_id: int) -> void:
	_note(&"apply_replicated_gift_expired", [gift_id])


func apply_replicated_gift_slot(slot_id: int, contents: Array, activated: StringName, carrier_id: StringName) -> void:
	_note(&"apply_replicated_gift_slot", [slot_id, contents, activated, carrier_id])


func apply_replicated_qol(slot_id: int, backlog: int, paused: bool) -> void:
	_note(&"apply_replicated_qol", [slot_id, backlog, paused])


func apply_replicated_special_consumed(slot_id: int, special_id: StringName) -> void:
	_note(&"apply_replicated_special_consumed", [slot_id, special_id])


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
	_note(&"apply_replicated_territory", [
		cells, owners, states, full, circle_xs, circle_zs, circle_radii, circle_teams,
		goal_positions, goal_radii, argmax_mode,
	])


func apply_replicated_glue_charges(slot_id: int, count: int, revision: int) -> bool:
	_note(&"apply_replicated_glue_charges", [slot_id, count, revision])
	return false


func apply_replicated_block_owner(net_id: int, new_slot: int) -> bool:
	_note(&"apply_replicated_block_owner", [net_id, new_slot])
	return false


func apply_replicated_cat_start(id: int, slot_id: int, position: Vector3, duration: float) -> bool:
	_note(&"apply_replicated_cat_start", [id, slot_id, position, duration])
	return false


func apply_replicated_cat_state(id: int, position: Vector3, velocity: Vector3, point: Vector3, remaining: float) -> void:
	_note(&"apply_replicated_cat_state", [id, position, velocity, point, remaining])


func end_cat(id: int) -> void:
	_note(&"end_cat", [id])


func apply_replicated_next_gift(slot_id: int, shape_id: StringName) -> void:
	_note(&"apply_replicated_next_gift", [slot_id, shape_id])


# apply_replicated_staged_gift is deliberately not spied: a same-named method here makes lint_dead
# read MatchFeed.apply_replicated_staged_gift as name-ambiguous. A test that
# needs it uses MatchReplicaPort over a real Match (test_replica_port.gd).


func apply_replicated_match_timer(seconds_left: float) -> void:
	_note(&"apply_replicated_match_timer", [seconds_left])
