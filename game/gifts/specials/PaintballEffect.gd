class_name PaintballEffect
extends SpecialEffect
## The gift is the host-simulated glob. Its impact/fuse splashes a
## bounded sphere of real block colliders and converts each by net ID.
##
## Aimed launch: when the intent carries a validated camera forward (MatchPlacement ->
## set_launch_direction) the glob flies a straight line along it at `flight_speed_mps`
## once armed and splashes on its first contact (probe, as RocketEffect). Without a
## direction (bots, plain drop) it splashes on a velocity-drop impact or the fuse.

@export_range(0.5, 20.0, 0.1) var splash_radius_m: float = 3.5

## Speed (m/s) of the aimed flight.
@export var flight_speed_mps: float = 60.0

## Gravity scale while in flight (0, straight line); the carrier's own scale
## is restored at the splash.
@export var flight_gravity_scale: float = 0.0

## Seconds after the launch during which the player's own blocks within `own_block_clear_radius_m`
## of the launch point are collision exceptions (see RocketEffect).
@export var own_block_grace_s: float = 0.4

## Radius (m) around the launch point whose own blocks the glob may leave through.
@export var own_block_clear_radius_m: float = 2.0

## Extra look-ahead (m) beyond one tick of travel for the contact probe.
@export var impact_probe_margin_m: float = 0.05

## The slingshot model's firing axis in the carrier's local frame (paintball_v3.glb: pouch drawn
## back toward -Z, so it fires along +Z). The held model and the spawned body both turn it onto the
## aim, the same way the Rocket does with its nose.
@export var model_nose_axis: Vector3 = Vector3(0.0, 0.0, 1.0)

## Name of the glob node in the gift model (paintball.glb 'Blob pivot'): the only part that flies.
@export var glob_node_name: StringName = &"Blob pivot"

## Model clip played on the slingshot copy left at the launch point (band snaps forward).
@export var release_animation: StringName = &"fire_500ms"

## Seconds the slingshot copy stays after its release clip before it fades.
@export_range(0.0, 5.0, 0.05) var sling_hold_s: float = 0.15

## Seconds the slingshot copy takes to shrink and fade out.
@export_range(0.0, 5.0, 0.05) var sling_fade_s: float = 0.35

## Smallest direction length treated as a direction at all.
const MIN_DIRECTION_LENGTH: float = 0.001

const LAUNCH_DIRECTION_META: StringName = &"paintball_launch_direction"


## Per-activation flight state (SpecialBehavior.state()): the shared effect Resource keeps none.
class PaintballState extends EffectState:
	## behavior.age() at the first flying tick; negative until the glob has launched.
	var launch_age: float = -1.0
	var hit: bool = false
	var carrier_gravity_scale: float = 1.0

	func launched() -> bool:
		return launch_age >= 0.0


## Host-side aimed-launch input for `block`; returns whether it was accepted. The upward part is
## dropped (same rule as the Rocket) and the rest normalised.
static func set_launch_direction(block: Block, direction: Vector3) -> bool:
	if block == null or not is_instance_valid(block):
		return false
	var clean: Vector3 = GiftAim.sanitize_downward_direction(direction)
	if clean == Vector3.ZERO:
		return false
	block.set_meta(LAUNCH_DIRECTION_META, clean)
	return true


func new_state() -> EffectState:
	return PaintballState.new()


## The slingshot spawns facing its shot, upright, as the held model does.
func faces_launch(mode: GiftThrow.Mode, aim_direction: Vector3, _throw_velocity: Vector3) -> bool:
	return mode == GiftThrow.Mode.AIMED and GiftAim.sanitize_downward_direction(aim_direction) != Vector3.ZERO


func launch_facing(_mode: GiftThrow.Mode, aim_direction: Vector3, _throw_velocity: Vector3) -> Basis:
	return FlightFacing.upright_nose_basis(model_nose_axis, GiftAim.sanitize_downward_direction(aim_direction))


func apply_launch(block: Block, direction: Vector3) -> void:
	set_launch_direction(block, direction)


func effect_radius_m() -> float:
	return splash_radius_m


## Expanding colour shell tinted by the thrower's slot.
func build_client_fx(ctx: MatchContext, block: Block, position: Vector3, _owner_slot: int) -> void:
	var parent: Node3D = ctx.blocks_parent()
	if parent == null or block == null or block.owner_slot < 0 or block.owner_slot >= ctx.slot_count():
		return
	var splash: PaintballSplash = PaintballSplash.new()
	splash.bind_to_match = true
	DiscAnchor.attach(splash, position, parent)
	splash.setup(ctx.slot(block.owner_slot).color)


## A flying (aimed) Paintball ends by its own contact probe, not the velocity-drop test.
func impact_triggers(block: Block, _behavior: SpecialBehavior) -> bool:
	return not block.has_meta(LAUNCH_DIRECTION_META)


func physics_tick(block: Block, behavior: SpecialBehavior, delta: float) -> void:
	var state: PaintballState = behavior.state() as PaintballState
	if not block.has_meta(LAUNCH_DIRECTION_META) or state.hit:
		return
	if not state.launched():
		state.launch_age = behavior.age()
		state.carrier_gravity_scale = block.gravity_scale
		block.wake_for_impulse()
		block.wake()
		RocketEffect.hold_own_exceptions(block, own_block_clear_radius_m)
	var direction: Vector3 = block.get_meta(LAUNCH_DIRECTION_META) as Vector3
	block.continuous_cd = true
	block.gravity_scale = flight_gravity_scale
	block.kick(direction * flight_speed_mps)
	block.angular_velocity = Vector3.ZERO
	var launched_at: float = state.launch_age
	if behavior.age() - launched_at >= own_block_grace_s:
		RocketEffect.release_own_exceptions(block)
	var params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	params.from = block.global_transform
	params.motion = direction * (flight_speed_mps * delta + impact_probe_margin_m)
	params.exclude_bodies = RocketEffect.held_own_rids(block)
	var result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
	if PhysicsServer3D.body_test_motion(block.get_rid(), params, result):
		if behavior.impact_filter(result.get_collider(), launched_at):
			state.hit = true


func wants_early_trigger(_block: Block, behavior: SpecialBehavior) -> bool:
	return (behavior.state() as PaintballState).hit


func detonate(block: Block, behavior: SpecialBehavior, _chain_depth: int) -> void:
	var state: PaintballState = behavior.state() as PaintballState if behavior != null else null
	if block != null:
		RocketEffect.release_own_exceptions(block)
	if block != null and state != null and state.launched():
		block.gravity_scale = state.carrier_gravity_scale
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
		if body.has_method(&"members_in_sphere"):
			# Glue fusion: the group is one body (FusedBody, duck-typed for the layer lint), but
			# only members inside the splash change.
			var inside: Array[Block] = []
			inside.assign(body.call(&"members_in_sphere", block.global_position, splash_radius_m) as Array)
			for member: Block in inside:
				ctx.convert_block_owner(member, block.owner_slot)
			if body.has_method(&"refresh_owner"):
				body.call(&"refresh_owner")  # carrier owner_slot follows its converted members
			continue
		var target: Block = body as Block
		if target != null:
			ctx.convert_block_owner(target, block.owner_slot)
