class_name SlotCursors
extends RefCounted
## Last ghost per slot and the host auto-drop pose. On the host the stored cursor is what spec
## 2.5's auto-drop fires from; on every instance it is what game/player/RemoteCursors.gd draws.

var _now_s: Callable
var _ghost: GhostTuning
var _beacon: BeaconVisualTuning
var _physics: PhysicsTuning
var _host: MatchHostPort = null
## slot_id -> {"origin": Vector3, "orientation_index": int, "free_quat": Quaternion, "time": float}
var _cursors: Dictionary = {}


## now_s is () -> float, monotonic seconds. The tunings are the shipped resources PlayerController
## reads for the player's first-block hover, so the no-cursor fallback clears the home beacon by
## the identical rule.
func _init(now_s: Callable, ghost: GhostTuning, beacon: BeaconVisualTuning, physics: PhysicsTuning) -> void:
	_now_s = now_s
	_ghost = ghost
	_beacon = beacon
	_physics = physics


## Refreshes the ref; KEEPS the stored cursors.
func bind(host: MatchHostPort) -> void:
	_host = host


func store(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	if slot_id < 0:
		return
	_cursors[slot_id] = {
		"origin": origin,
		"orientation_index": orientation_index,
		"free_quat": free_quat,
		"time": float(_now_s.call()),
	}


## {"origin", "orientation_index", "free_quat", "age"} of the last cursor for `slot_id`, or {}.
func for_slot(slot_id: int) -> Dictionary:
	var stored: Dictionary = _cursors.get(slot_id, {})
	if stored.is_empty():
		return {}
	return {
		"origin": stored["origin"],
		"orientation_index": stored["orientation_index"],
		"free_quat": stored["free_quat"],
		"age": float(_now_s.call()) - float(stored["time"]),
	}


func clear(slot_id: int) -> void:
	_cursors.erase(slot_id)


## {"origin", "orientation_index", "free_quat"}: the stored cursor, else the raised home fallback.
## A client intent or stored cursor is already a pose the peer's own ghost produced and is never
## raised. The fallback is the home flag at disc level, which is inside the beacon's socket and
## crystal, so it rises by GhostTuning.home_spawn_pivot_height() (orientation 0 / identity is what
## that height assumes).
## DECISION: world UP, not field-local up, matching PlayerController's own hover; tilt modes rotate
## the Field by a few degrees, which still leaves the block well clear of the beacon.
func auto_drop_pose(slot_id: int) -> Dictionary:
	var cursor: Dictionary = for_slot(slot_id)
	if cursor.has("origin"):
		return {
			"origin": cursor["origin"],
			"orientation_index": int(cursor["orientation_index"]),
			"free_quat": cursor["free_quat"],
		}
	var home: Vector3 = _host.default_ghost_origin(slot_id)
	return {
		"origin": home + Vector3.UP * _ghost.home_spawn_pivot_height(_beacon, _physics),
		"orientation_index": 0,
		"free_quat": Quaternion.IDENTITY,
	}


func reset() -> void:
	_cursors.clear()
