class_name GlueJoint
extends Node
## Owns one breakable joint made by a charged GlueDrops block on contact.
##
## DECISION (Bontago-1pi.85.13, docs/GIFT_EFFECTS_PLAN.md section 3 Glue): Godot's
## Joint3D types have no built-in break force. The old per-tick relative
## acceleration * mass "stress" exceeded its threshold from ordinary contact
## settling, so bonds snapped on the first jostle. A bond now breaks only when it
## is really being torn apart: the bodies' relative pose drifts more than
## `break_separation_m` from the pose captured at bind time, or their relative
## linear speed exceeds `break_speed_mps`, or either body's one-tick velocity change
## exceeds `break_shock_mps` (a blast). `apply_stress_sample()` stays
## as a direct test seam against `break_force`. The Generic6DOF joint is this
## node's own child, so freeing this node frees the joint with it.

var _joint: Generic6DOFJoint3D = null
var _body_a: PhysicsBody3D = null
var _body_b: PhysicsBody3D = null
var _break_force: float = 600.0
var _break_separation_m: float = 0.15
var _break_speed_mps: float = 6.0
var _break_shock_mps: float = 2.5
var _prev_velocity_a: Vector3 = Vector3.ZERO
var _prev_velocity_b: Vector3 = Vector3.ZERO
## Body B's transform in body A's frame at bind time (the pose the joint holds).
var _rest_relative: Transform3D = Transform3D.IDENTITY
var _bound: bool = false


## Wires this node to the joint it owns and the two bodies it connects.
## `joint` must already be a child of this node (GlueDrops.try_bond()'s build
## order) so freeing this node frees the joint too. The disc is not a rigid
## body, so its velocity in the stress estimate is treated as zero.
func bind(
	joint: Generic6DOFJoint3D,
	body_a: PhysicsBody3D,
	body_b: PhysicsBody3D,
	break_force_value: float,
	break_separation_value: float = 0.15,
	break_speed_value: float = 6.0,
	break_shock_value: float = 2.5
) -> void:
	_joint = joint
	_body_a = body_a
	_body_b = body_b
	_break_force = break_force_value
	_break_separation_m = break_separation_value
	_break_speed_mps = break_speed_value
	_break_shock_mps = break_shock_value
	_prev_velocity_a = _velocity(body_a)
	_prev_velocity_b = _velocity(body_b)
	_rest_relative = body_a.global_transform.affine_inverse() * body_b.global_transform
	_bound = true


func bodies_match(a: PhysicsBody3D, b: PhysicsBody3D) -> bool:
	return (_body_a == a and _body_b == b) or (_body_a == b and _body_b == a)


func _velocity(body: PhysicsBody3D) -> Vector3:
	return (body as RigidBody3D).linear_velocity if body is RigidBody3D else Vector3.ZERO


func _physics_process(delta: float) -> void:
	advance(delta)


## Runs one break test. Split out from `_physics_process()` so a test can
## drive it directly with a controlled `delta`, mirroring
## SpecialBehavior.advance()'s own directly-testable seam.
func advance(delta: float) -> void:
	if not _bound:
		return
	if not is_instance_valid(_body_a) or not is_instance_valid(_body_b):
		_break()
		return
	if separation_m() > _break_separation_m:
		_break()
		return
	var velocity_a: Vector3 = _velocity(_body_a)
	var velocity_b: Vector3 = _velocity(_body_b)
	# A blast hands a rigid pair one sudden velocity change that the joint solver
	# absorbs within the tick (relative speed and separation stay ~0), so the
	# one-tick velocity change of either body is the blast signature. Tilt, sliding
	# and a block landing on the pair change a bonded body's velocity far less.
	var shock: float = maxf(
		(velocity_a - _prev_velocity_a).length(), (velocity_b - _prev_velocity_b).length()
	)
	_prev_velocity_a = velocity_a
	_prev_velocity_b = velocity_b
	if shock > _break_shock_mps or (velocity_a - velocity_b).length() > _break_speed_mps:
		_break()


## Distance between body B's current origin and where the bind-time relative pose
## says it should be, given body A's current transform.
func separation_m() -> float:
	if not is_instance_valid(_body_a) or not is_instance_valid(_body_b):
		return 0.0
	var expected: Transform3D = _body_a.global_transform * _rest_relative
	return expected.origin.distance_to(_body_b.global_transform.origin)


## Public test seam (docs/M8_PLAN.md P3 acceptance: "a GlueJoint given a
## synthetic stress sample above/below break_force frees/keeps itself and its
## joint"): breaks the joint once `stress` exceeds `break_force`, bypassing
## the velocity-delta computation above entirely so a test can assert the
## break/keep decision directly against a chosen number.
func apply_stress_sample(stress: float) -> void:
	if stress > _break_force:
		_break()


## Frees the joint (explicitly, so it leaves the physics world this same
## frame) and then this node itself.
func _break() -> void:
	_bound = false
	if _joint != null and is_instance_valid(_joint):
		_joint.queue_free()
	queue_free()
