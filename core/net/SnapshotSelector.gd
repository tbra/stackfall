class_name SnapshotSelector
extends RefCounted
## Host-side resend decision for sleeping bodies: a body is drift-tested only
## when it was never sent, its sleeping flag flipped, or the disc moved this
## tick. Pure rule logic with no scene tree.

var _config: NetConfig = null
## net_id -> SentState, the last SENT pose and sleeping flag.
var _sent: Dictionary = {}
var _disc: Transform3D = Transform3D.IDENTITY
var _has_disc: bool = false
var _disc_changed: bool = true


class SentState:
	var position: Vector3 = Vector3.ZERO
	var rotation: Quaternion = Quaternion.IDENTITY
	var sleeping: bool = false


func _init(net_config: NetConfig = null) -> void:
	_config = net_config if net_config != null else NetConfig.new()


## Starts a tick. `disc` is compared exactly with the previous call's disc; the
## first call after construction or reset() counts as changed.
func begin_tick(disc: Transform3D) -> void:
	_disc_changed = not _has_disc or disc != _disc
	_disc = disc
	_has_disc = true


## True when this body must be drift-tested this tick: never sent, its sleeping
## flag differs from the last sent one, or the disc moved this tick.
func needs_check(net_id: int, sleeping: bool) -> bool:
	var state: SentState = _sent.get(net_id) as SentState
	return state == null or state.sleeping != sleeping or _disc_changed


## True when the pose passed the resend epsilon against the last SENT pose
## (never sent counts as moved).
func moved_since_sent(net_id: int, position: Vector3, rotation: Quaternion) -> bool:
	var state: SentState = _sent.get(net_id) as SentState
	if state == null:
		return true
	if position.distance_to(state.position) > _config.resend_position_epsilon:
		return true
	return rad_to_deg(rotation.angle_to(state.rotation)) > _config.resend_angle_epsilon


func remember_sent(net_id: int, position: Vector3, rotation: Quaternion, sleeping: bool) -> void:
	var state: SentState = _sent.get(net_id) as SentState
	if state == null:
		state = SentState.new()
		_sent[net_id] = state
	state.position = position
	state.rotation = rotation
	state.sleeping = sleeping


func forget(net_id: int) -> void:
	_sent.erase(net_id)


func reset() -> void:
	_sent.clear()
	_has_disc = false
	_disc_changed = true
