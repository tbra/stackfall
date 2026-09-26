class_name GlueJoint
extends Node
## Owns one Generic6DOFJoint3D formed by GlueEffect.gd and the "breakable"
## behaviour spec 2.6's Glue row asks for (docs/M8_PLAN.md P3-GLUE package).
##
## DECISION (game/specials/GlueJoint.gd, docs/M8_PLAN.md P3): Godot's
## Joint3D types have no built-in break force, so breakability is
## approximated here by sampling, every physics tick, the two connected
## bodies' relative linear ACCELERATION (change in relative velocity over
## delta) times their combined mass -- a rough proxy for the jolt a rigid
## joint would feel from its two bodies suddenly diverging, in the same
## force-like units (kg * m/s^2 = N) spec 2.6's "break force 40" implies.
## Exceeding `break_force` frees the joint and this node. The Generic6DOF
## joint is this node's own child (not the block's), so freeing this node
## also frees the joint as part of the normal scene-tree cleanup -- no
## separate `queue_free()` call is strictly required for it, but one is made
## explicitly below anyway so the joint disappears from physics on the very
## same frame this node is told to break, rather than waiting on Godot's
## child-then-parent free ordering.

var _joint: Generic6DOFJoint3D = null
var _body_a: RigidBody3D = null
var _body_b: RigidBody3D = null
var _break_force: float = 40.0
var _prev_velocity_a: Vector3 = Vector3.ZERO
var _prev_velocity_b: Vector3 = Vector3.ZERO
var _bound: bool = false


## Wires this node to the joint it owns and the two bodies it connects.
## `joint` must already be a child of this node (GlueEffect._glue_pair()'s own
## build order) so freeing this node frees the joint too.
func bind(
	joint: Generic6DOFJoint3D, body_a: RigidBody3D, body_b: RigidBody3D, break_force_value: float
) -> void:
	_joint = joint
	_body_a = body_a
	_body_b = body_b
	_break_force = break_force_value
	_prev_velocity_a = body_a.linear_velocity
	_prev_velocity_b = body_b.linear_velocity
	_bound = true


func _physics_process(delta: float) -> void:
	advance(delta)


## Runs one stress sample. Split out from `_physics_process()` so a test can
## drive it directly with a controlled `delta`, mirroring
## SpecialBehavior.advance()'s own directly-testable seam.
func advance(delta: float) -> void:
	if not _bound:
		return
	if not is_instance_valid(_body_a) or not is_instance_valid(_body_b):
		_break()
		return
	if delta <= 0.0:
		return

	var accel_a: Vector3 = (_body_a.linear_velocity - _prev_velocity_a) / delta
	var accel_b: Vector3 = (_body_b.linear_velocity - _prev_velocity_b) / delta
	_prev_velocity_a = _body_a.linear_velocity
	_prev_velocity_b = _body_b.linear_velocity

	var combined_mass: float = _body_a.mass + _body_b.mass
	var stress: float = (accel_a - accel_b).length() * combined_mass
	apply_stress_sample(stress)


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
	if _joint != null and is_instance_valid(_joint):
		_joint.queue_free()
	queue_free()
