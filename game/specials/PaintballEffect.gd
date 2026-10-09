class_name PaintballEffect
extends SpecialEffect
## The gift is the host-simulated glob. Its impact/fuse splashes a
## bounded sphere of real block colliders and converts each by net ID.
##
## Bontago-1pi.85.16 (owner answer 1pi.85.1): a Paintball is not thrown. When the intent carried
## a validated camera forward (MatchPlacement -> set_launch_direction) the glob flies a straight
## line along it at `flight_speed_mps` once armed and splashes on its first contact (probe, as
## RocketEffect). Without a direction (bots, plain drop) it behaves exactly as before: velocity
## drop impact or fuse.

@export_range(0.5, 20.0, 0.1) var splash_radius_m: float = 3.5

## Speed (m/s) of the aimed flight.
@export var flight_speed_mps: float = 60.0

## Gravity scale while in flight (Bontago-1pi.85.25: 0, straight line); the carrier's own scale
## is restored at the splash.
@export var flight_gravity_scale: float = 0.0

## Seconds after the launch during which the owner's own blocks within `own_block_clear_radius_m`
## of the launch point are collision exceptions (Bontago-1pi.85.37; see RocketEffect).
@export var own_block_grace_s: float = 0.4

## Radius (m) around the launch point whose own blocks the glob may leave through.
@export var own_block_clear_radius_m: float = 2.0

## Extra look-ahead (m) beyond one tick of travel for the contact probe.
@export var impact_probe_margin_m: float = 0.05

## Smallest direction length treated as a direction at all.
const MIN_DIRECTION_LENGTH: float = 0.001

const LAUNCH_DIRECTION_META: StringName = &"paintball_launch_direction"
const _LAUNCH_AGE_META: StringName = &"paintball_launch_age"
const _HIT_META: StringName = &"paintball_hit"
const _CARRIER_GRAVITY_META: StringName = &"paintball_carrier_gravity_scale"


## Host-side aimed-launch input for `block`; returns whether it was accepted. The upward part is
## dropped (same rule as the Rocket) and the rest normalised.
static func set_launch_direction(block: Block, direction: Vector3) -> bool:
	if block == null or not is_instance_valid(block):
		return false
	var clean: Vector3 = RocketEffect.sanitize_downward_direction(direction)
	if clean == Vector3.ZERO:
		return false
	block.set_meta(LAUNCH_DIRECTION_META, clean)
	return true


## A flying (aimed) Paintball ends by its own contact probe, not the velocity-drop test.
func impact_triggers(block: Block, _behavior: SpecialBehavior) -> bool:
	return not block.has_meta(LAUNCH_DIRECTION_META)


func physics_tick(block: Block, behavior: SpecialBehavior, delta: float) -> void:
	if not block.has_meta(LAUNCH_DIRECTION_META) or block.has_meta(_HIT_META):
		return
	if not block.has_meta(_LAUNCH_AGE_META):
		block.set_meta(_LAUNCH_AGE_META, behavior.age())
		block.set_meta(_CARRIER_GRAVITY_META, block.gravity_scale)
		block.wake_for_impulse()
		block.wake()
		RocketEffect.hold_own_exceptions(block, own_block_clear_radius_m)
	var direction: Vector3 = block.get_meta(LAUNCH_DIRECTION_META) as Vector3
	block.continuous_cd = true
	block.gravity_scale = flight_gravity_scale
	block.kick(direction * flight_speed_mps)
	block.angular_velocity = Vector3.ZERO
	var launched_at: float = float(block.get_meta(_LAUNCH_AGE_META))
	if behavior.age() - launched_at >= own_block_grace_s:
		RocketEffect.release_own_exceptions(block)
	var params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	params.from = block.global_transform
	params.motion = direction * (flight_speed_mps * delta + impact_probe_margin_m)
	params.exclude_bodies = RocketEffect.held_own_rids(block)
	var result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
	if PhysicsServer3D.body_test_motion(block.get_rid(), params, result):
		if behavior.impact_filter(result.get_collider(), launched_at):
			block.set_meta(_HIT_META, true)


func wants_early_trigger(block: Block, _behavior: SpecialBehavior) -> bool:
	return block.has_meta(_HIT_META)


func detonate(block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	if block != null:
		RocketEffect.release_own_exceptions(block)
	if block != null and block.has_meta(_CARRIER_GRAVITY_META):
		block.gravity_scale = float(block.get_meta(_CARRIER_GRAVITY_META))
	var ctx: MatchContext = MatchContext.current()
	if block == null or not ctx.has_authority() or ctx.state() != MatchPhase.State.PLAYING:
		return
	if block.owner_slot < 0 or block.owner_slot >= ctx.slot_count():
		return
	var hit_bodies: Array[RigidBody3D] = SpecialPhysics.query_bodies_in_range(
		block.get_world_3d().direct_space_state,
		block.global_position,
		splash_radius_m,
		[block.get_rid()]
	)
	for body: RigidBody3D in hit_bodies:
		var target: Block = body as Block
		if target != null:
			ctx.convert_block_owner(target, block.owner_slot)
