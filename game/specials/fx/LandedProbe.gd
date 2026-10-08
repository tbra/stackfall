class_name LandedProbe
extends RefCounted
## Landing detection probe for timed effects (Jumping Bean, Propeller, Anvil, Magnet).
##
## Replaces the unreliable Jolt `sleeping` check with a velocity-based detector.
## A block is considered "landed" when linear speed falls below `t.landed_speed_mps`
## for `t.landed_hold_s` seconds, OR once `t.landed_timeout_s` has elapsed since the
## first contact (whichever comes first). Tracks elapsed time since landing via `landed_age()`.
##
## Speed is measured RELATIVE to the supporting surface (the tilting disc's point velocity
## under the carrier, or the velocity of the block it rests on), so a gift riding a moving
## disc settles promptly instead of waiting for the timeout (Bontago-1pi.85.67).
##
## Depends on: LandedTuning, Block

## Tuning; defaults apply when none is supplied.
var tuning: LandedTuning = LandedTuning.new()

var _landed: bool = false
var _landed_age_s: float = 0.0
var _slow_s: float = 0.0
var _contact_s: float = -1.0
## Previous-tick global transforms of non-rigid supports, keyed by instance id.
var _support_prev: Dictionary = {}


func _init(landed_tuning: LandedTuning = null) -> void:
	if landed_tuning != null:
		tuning = landed_tuning


## Updates probe state each physics tick. Call once per tick while the block is active.
func update(block: Block, delta: float) -> void:
	if _landed:
		_landed_age_s += delta
		return
	if block == null or not is_instance_valid(block) or not block.is_inside_tree():
		return
	var support_velocity: Vector3 = Vector3.ZERO
	var touching: bool = false
	var hit: Dictionary = _probe_contact(block, delta)
	if not hit.is_empty():
		touching = true
		support_velocity = hit["velocity"] as Vector3
	if touching and _contact_s < 0.0:
		_contact_s = 0.0
	elif _contact_s >= 0.0:
		_contact_s += delta
	# Only count slow ticks while touching something, so the apex of a throw is not "landed".
	if touching and (block.linear_velocity - support_velocity).length() < tuning.landed_speed_mps:
		_slow_s += delta
	else:
		_slow_s = 0.0
	if _slow_s >= tuning.landed_hold_s or (_contact_s >= 0.0 and _contact_s >= tuning.landed_timeout_s):
		_landed = true
		_landed_age_s = 0.0


## Returns true if the block has landed according to the tuned criteria.
func has_landed() -> bool:
	return _landed


## Returns seconds elapsed since the block was first detected as landed.
## Returns 0.0 if not yet landed.
func landed_age() -> float:
	return _landed_age_s if _landed else 0.0


## Blocks run without contact_monitor (see Block.gd), so contact is a short downward
## body test-motion against the block's own shapes. Returns {} when not touching, else
## {"velocity": Vector3} = the supporting surface's world velocity at the carrier.
func _probe_contact(block: Block, delta: float) -> Dictionary:
	var params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	params.from = block.global_transform
	params.motion = Vector3.DOWN * tuning.contact_probe_m
	var result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(block.get_rid(), params, result):
		return {}
	var collider: Object = result.get_collider()
	var velocity: Vector3 = Vector3.ZERO
	if collider is RigidBody3D:
		velocity = result.get_collider_velocity()
	elif collider is Node3D and delta > 0.0:
		# Kinematic support (the disc): point velocity from its transform delta per tick.
		var support: Node3D = collider as Node3D
		var id: int = support.get_instance_id()
		var now: Transform3D = support.global_transform
		if _support_prev.has(id):
			var prev: Transform3D = _support_prev[id] as Transform3D
			var point: Vector3 = block.global_position
			var moved: Vector3 = now * (prev.affine_inverse() * point)
			velocity = (moved - point) / delta
		_support_prev[id] = now
	return {"velocity": velocity}
