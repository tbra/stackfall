class_name FlightFacing
extends RefCounted
## Bontago-1pi.85.49: turns a flying gift carrier so its model's nose axis points along its
## velocity. Shared by Rocket (every flight tick) and Magnet (while thrown). Pure helper plus one
## write; no state of its own beyond a block-meta flag marking the first write.

## nose_basis(): dot below which the direction counts as opposite to the nose, and the |x| above
## which the nose counts as lying along X (so another helper axis is used).
const ANTIPARALLEL_DOT: float = -0.9999
const NEAR_X_AXIS: float = 0.9

## upright_nose_basis(): |direction.y| above which the direction counts as vertical.
const UPRIGHT_VERTICAL_DOT: float = 0.999

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


## Like nose_basis(), but the model keeps its world up (a yaw then a pitch, never a roll): the
## unit `nose` axis (horizontal in the model) points along `direction` and the model's +Y stays
## pointing up. For a model with a fixed "front" that must not turn upside down, e.g. the
## slingshot (Bontago-1pi.85.79). A vertical direction falls back to the world Z as its up hint.
static func upright_nose_basis(nose: Vector3, direction: Vector3) -> Basis:
	var to: Vector3 = direction.normalized()
	var up_hint: Vector3 = Vector3.UP
	if absf(to.dot(Vector3.UP)) > UPRIGHT_VERTICAL_DOT:
		up_hint = Vector3.BACK
	var look: Basis = Basis.looking_at(to, up_hint)
	return look * nose_basis(nose, Vector3.FORWARD)


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
