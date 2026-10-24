class_name FakeHostPort
extends MatchHostPort
## Spy for MatchHostPort: answers every rule entry point and read a consumer (MatchNet, WeatherNet,
## SnowNet, BreezeNet, MatchEventApplier) makes, records it in `calls` and returns the neutral
## answer (accepted intents, empty reads, no Match), so a test asserts what the consumer asked the
## host to do without a Match. It adapts no Match (null), so a port method added without an
## override here hits the null adapter, which errors and fails the test loudly instead of reaching
## the real autoload; test_host_port.gd's conformance test fails first. A test needing another
## answer extends this class and overrides that one method.
## loading_gate_replay_args is deliberately not overridden: an override makes lint_dead read the real
## lifecycle method as reached only through a name-ambiguous call; through the spy it answers [].

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


func set_replicator(replicator: Variant) -> void:
	_note(&"set_replicator", [replicator])


func release_replicator(replicator: Variant) -> void:
	_note(&"release_replicator", [replicator])


func default_ghost_origin(slot_id: int) -> Vector3:
	_note(&"default_ghost_origin", [slot_id])
	return Vector3.ZERO


func on_peer_left(slot_id: int) -> void:
	_note(&"on_peer_left", [slot_id])


func disconnect_grace_left(slot_id: int) -> float:
	_note(&"disconnect_grace_left", [slot_id])
	return -1.0


func held_shape(slot_id: int) -> BlockShape:
	_note(&"held_shape", [slot_id])
	return null


func next_shape(slot_id: int) -> BlockShape:
	_note(&"next_shape", [slot_id])
	return null


func held_special(slot_id: int) -> StringName:
	_note(&"held_special", [slot_id])
	return &""


func next_special(slot_id: int) -> StringName:
	_note(&"next_special", [slot_id])
	return &""


func after_next_special(slot_id: int) -> StringName:
	_note(&"after_next_special", [slot_id])
	return &""


func config() -> MatchConfig:
	_note(&"config", [])
	return null


func state() -> int:
	_note(&"state", [])
	return 0


func slot_count() -> int:
	_note(&"slot_count", [])
	return 0


func slot(slot_id: int) -> PlayerSlot:
	_note(&"slot", [slot_id])
	return null


func request_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq_value: int
) -> StringName:
	_note(&"request_place", [slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq_value])
	return PlacementRules.REASON_OK


func request_throw(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq_value: int
) -> StringName:
	_note(&"request_throw", [slot_id, origin, orientation_index, free_quat, velocity, feed_seq_value])
	return PlacementRules.REASON_OK


func request_use_gift_slot(slot_id: int) -> bool:
	_note(&"request_use_gift_slot", [slot_id])
	return false


func set_cat_target(slot_id: int, point: Vector3) -> bool:
	_note(&"set_cat_target", [slot_id, point])
	return false


func note_aim(slot_id: int, aim: Vector3) -> void:
	_note(&"note_aim", [slot_id, aim])


func is_pose_well_formed(origin: Vector3, orientation_index: int, free_quat: Quaternion) -> bool:
	_note(&"is_pose_well_formed", [origin, orientation_index, free_quat])
	return false


func feed_seq(slot_id: int) -> int:
	_note(&"feed_seq", [slot_id])
	return 0


func on_peer_rejoined(slot_id: int) -> void:
	_note(&"on_peer_rejoined", [slot_id])


func abort_match() -> void:
	_note(&"abort_match", [])


func start_match(match_config: MatchConfig) -> void:
	_note(&"start_match", [match_config])


func active_cat() -> RigidBody3D:
	_note(&"active_cat", [])
	return null


func active_slot() -> int:
	_note(&"active_slot", [])
	return -1


func blocks_parent() -> Node3D:
	_note(&"blocks_parent", [])
	return null


func circle_render_arrays() -> Dictionary:
	_note(&"circle_render_arrays", [])
	return {}


func circle_wire_radius_max() -> float:
	_note(&"circle_wire_radius_max", [])
	return 0.0


func circle_wire_xz_bound() -> float:
	_note(&"circle_wire_xz_bound", [])
	return 0.0


func countdown_remaining() -> float:
	_note(&"countdown_remaining", [])
	return 0.0


func eliminated_by(slot_id: int) -> int:
	_note(&"eliminated_by", [slot_id])
	return -1


func feed_time_left(slot_id: int) -> float:
	_note(&"feed_time_left", [slot_id])
	return 0.0


func field() -> FieldBody:
	_note(&"field", [])
	return null


func gift_slot_contents(slot_id: int) -> Array[StringName]:
	_note(&"gift_slot_contents", [slot_id])
	return [] as Array[StringName]


func gift_slot_enabled() -> bool:
	_note(&"gift_slot_enabled", [])
	return false


func gift_state(gift_id: int) -> Dictionary:
	_note(&"gift_state", [gift_id])
	return {}


func gift_states() -> Array[Dictionary]:
	_note(&"gift_states", [])
	return [] as Array[Dictionary]


func glue_drops_left(slot_id: int) -> int:
	_note(&"glue_drops_left", [slot_id])
	return 0


func glue_revision(slot_id: int) -> int:
	_note(&"glue_revision", [slot_id])
	return 0


func is_release_locked(slot_id: int) -> bool:
	_note(&"is_release_locked", [slot_id])
	return false


func match_timer_left() -> float:
	_note(&"match_timer_left", [])
	return 0.0


func mode_state_snapshot() -> Dictionary:
	_note(&"mode_state_snapshot", [])
	return {}


func qol_backlog_count(slot_id: int) -> int:
	_note(&"qol_backlog_count", [slot_id])
	return 0


func qol_timer_paused(slot_id: int) -> bool:
	_note(&"qol_timer_paused", [slot_id])
	return false


func raster() -> TerritoryRaster:
	_note(&"raster", [])
	return null


func registry() -> Node:
	_note(&"registry", [])
	return null


func stats() -> RefCounted:
	_note(&"stats", [])
	return null


func territory_share(team_id: int) -> float:
	_note(&"territory_share", [team_id])
	return 0.0


func weather() -> RefCounted:
	_note(&"weather", [])
	return null


func feed_knows_shape(shape_id: StringName) -> bool:
	_note(&"feed_knows_shape", [shape_id])
	return false


func feed_claim_carrier_shape_id(slot_id: int) -> StringName:
	_note(&"feed_claim_carrier_shape_id", [slot_id])
	return &""


func feed_gift_after_next_active() -> bool:
	_note(&"feed_gift_after_next_active", [])
	return false


func feed_staged_gift_shape_id(slot_id: int) -> StringName:
	_note(&"feed_staged_gift_shape_id", [slot_id])
	return &""


func feed_note_special_triggered() -> void:
	_note(&"feed_note_special_triggered", [])


func is_starting_match() -> bool:
	_note(&"is_starting_match", [])
	return false
