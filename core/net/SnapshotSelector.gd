class_name SnapshotSelector
extends RefCounted
## Host-side resend decision for sleeping bodies: a body is drift-tested only
## when it was never sent, its sleeping flag flipped, or the disc moved this
## tick. Pure rule logic with no scene tree.

var _config: NetConfig = null


func _init(net_config: NetConfig = null) -> void:
	_config = net_config


## Starts a tick. `disc` is compared exactly with the previous call's disc; the
## first call after construction or reset() counts as changed.
func begin_tick(_disc: Transform3D) -> void:
	push_error("SnapshotSelector.begin_tick: not implemented")


## True when this body must be drift-tested this tick.
func needs_check(_net_id: int, _sleeping: bool) -> bool:
	push_error("SnapshotSelector.needs_check: not implemented")
	return true


## True when the pose passed the resend epsilon against the last SENT pose.
func moved_since_sent(_net_id: int, _position: Vector3, _rotation: Quaternion) -> bool:
	push_error("SnapshotSelector.moved_since_sent: not implemented")
	return true


func remember_sent(_net_id: int, _position: Vector3, _rotation: Quaternion, _sleeping: bool) -> void:
	push_error("SnapshotSelector.remember_sent: not implemented")


func forget(_net_id: int) -> void:
	push_error("SnapshotSelector.forget: not implemented")


func reset() -> void:
	push_error("SnapshotSelector.reset: not implemented")
