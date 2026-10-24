class_name SlotCursors
extends RefCounted
## Last ghost per slot and the host auto-drop pose (interface stub: bodies land with the MatchNet cut).

const NOT_IMPLEMENTED: String = "SlotCursors: not implemented"

## now_s is () -> float, monotonic seconds.
@warning_ignore("unused_parameter")
func _init(now_s: Callable, ghost: GhostTuning, beacon: BeaconVisualTuning, physics: PhysicsTuning) -> void:
	pass


## Refreshes the ref; KEEPS the stored cursors.
@warning_ignore("unused_parameter")
func bind(host: MatchHostPort) -> void:
	push_error(NOT_IMPLEMENTED)


@warning_ignore("unused_parameter")
func store(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	push_error(NOT_IMPLEMENTED)


## Shape unchanged from MatchNet.cursor_for_slot, including "age".
@warning_ignore("unused_parameter")
func for_slot(slot_id: int) -> Dictionary:
	push_error(NOT_IMPLEMENTED)
	return {}


@warning_ignore("unused_parameter")
func clear(slot_id: int) -> void:
	push_error(NOT_IMPLEMENTED)


## {"origin", "orientation_index", "free_quat"}: the stored cursor, else the raised home fallback.
@warning_ignore("unused_parameter")
func auto_drop_pose(slot_id: int) -> Dictionary:
	push_error(NOT_IMPLEMENTED)
	return {}


func reset() -> void:
	push_error(NOT_IMPLEMENTED)
