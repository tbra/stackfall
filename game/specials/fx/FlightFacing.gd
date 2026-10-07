class_name FlightFacing
extends RefCounted
## Bontago-1pi.85.49: turns a flying gift carrier so its model's nose axis points along its
## velocity. Shared by Rocket (every flight tick) and Magnet (while thrown). Pure helper plus one
## write; no state of its own beyond a block-meta flag marking the first write.

## nose_basis(): dot below which the direction counts as opposite to the nose, and the |x| above
## which the nose counts as lying along X (so another helper axis is used).
const ANTIPARALLEL_DOT: float = -0.9999
const NEAR_X_AXIS: float = 0.9

const FACED_META: StringName = &"flight_faced"


## A rotation taking the unit `nose` axis onto the unit `direction` (shortest arc). A direction
## opposite to the nose turns half a revolution about a perpendicular axis.
static func nose_basis(nose: Vector3, direction: Vector3) -> Basis:
	var from: Vector3 = nose.normalized()
	var to: Vector3 = direction.normalized()
	if from.dot(to) < ANTIPARALLEL_DOT:
		var side: Vector3 = Vector3.RIGHT if absf(from.x) < NEAR_X_AXIS else Vector3.UP
		return Basis(from.cross(side).normalized(), PI)
	return Basis(Quaternion(from, to))


## Faces `block` along its linear velocity; a no-op below `min_speed`. The first write resets
## physics interpolation so the model does not swing in from the spawn pose.
static func face_velocity(block: Block, nose: Vector3, min_speed: float) -> void:
	if block.linear_velocity.length() < min_speed:
		return
	face_direction(block, nose, block.linear_velocity)


## Faces `block` along an explicit `direction` (the rocket's fixed flight line).
static func face_direction(block: Block, nose: Vector3, direction: Vector3) -> void:
	var first: bool = not block.has_meta(FACED_META)
	block.global_transform = Transform3D(nose_basis(nose, direction), block.global_position)
	if first:
		block.set_meta(FACED_META, true)
		block.reset_physics_interpolation()
