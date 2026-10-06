class_name RocketEffect
extends SpecialEffect
## Rocket special. OWNER decision 2026-10-05 (docs/SPEC.md 2.6, Bontago-1pi.85, answer
## to plan question 1): on activation the Rocket launches in a STRAIGHT LINE along the
## activating player's camera direction (not thrown, not upward) and explodes on the
## first thing it touches (a block, the disc or map geometry); fuel running out is only
## a safety backstop. It no longer climbs 27 m and bursts in empty air.
##
## Flow: armed (arm_delay after the drop) -> physics_tick() launches it once, then every
## tick holds its velocity at `thrust_speed_mps` along the launch direction and probes the
## contact it is about to make; a contact the behaviour's impact_filter accepts sets a
## block-meta flag, wants_early_trigger() reports it, and detonate() blasts with ExplosionFx.
##
## DECISION (Bontago-1pi.85.10): impact is detected by this effect's own contact probe
## (a short body_test_motion along the flight line), not by SpecialBehavior's
## velocity-drop test, so triggers_on_impact() is false: the velocity-drop test cannot
## tell what was hit (needed for the owner-grace filter) and would also fire on the
## carrier's own landing before the launch. The probe runs after the velocity write and
## looks one tick of travel (plus `impact_probe_margin_m`) ahead, continuous_cd stays
## armed, so the blast is centred within about a third of a metre of the surface.
##
## DECISION (Bontago-1pi.85.10): the launch direction is host-side input, per block, in
## block meta: the shared SpecialEffect resource keeps no per-block state (the pattern
## every timed effect uses). The camera-direction wiring from the client (PlayerController
## intent -> MatchPlacement) is package I's; it calls
## `RocketEffect.set_launch_direction(block, camera_forward)` on the spawned carrier
## before its first physics tick. The host never trusts the value: it must be finite,
## its upward part is dropped ("not upward") and it is normalised; anything unusable
## keeps the default (see default_launch_direction()).

## Speed (m/s) the Rocket flies at along its launch direction (plan section 3: 14).
@export var thrust_speed_mps: float = 14.0

## Safety fuel: seconds after the launch before it explodes even if it touched nothing
## (plan section 3: 4.0).
@export var fuel_duration_s: float = 4.0

## Downward pitch (degrees) of the default launch direction used when no camera
## direction was supplied (bots, tests, a client that sent nothing usable).
@export var default_pitch_down_deg: float = 20.0

## Extra look-ahead (m) beyond one tick of travel for the impact probe.
@export var impact_probe_margin_m: float = 0.05

## Blast shape (plan section 3: radius 4.5 m, peak 10 m/s delta-v).
@export var blast: ExplosionTuning = ExplosionTuning.new()

## Smallest horizontal-plus-downward direction length treated as a direction at all.
const MIN_DIRECTION_LENGTH: float = 0.001

## block.set_meta() key: the host-side launch direction input (Vector3, unit length).
const LAUNCH_DIRECTION_META: StringName = &"rocket_launch_direction"

## block.set_meta() keys for the per-block flight state (the effect resource is shared).
const _LAUNCH_AGE_META: StringName = &"rocket_launch_age"
const _FLIGHT_DIRECTION_META: StringName = &"rocket_flight_direction"
const _HIT_META: StringName = &"rocket_hit"


## Host-side launch-direction input for `block` (a Rocket carrier). Returns whether it was
## accepted; a rejected value leaves any earlier one (or the default) in place.
static func set_launch_direction(block: Block, direction: Vector3) -> bool:
	if block == null or not is_instance_valid(block):
		return false
	var clean: Vector3 = sanitize_launch_direction(direction)
	if clean == Vector3.ZERO:
		return false
	block.set_meta(LAUNCH_DIRECTION_META, clean)
	return true


## Pure: the direction the host will actually fly. Non-finite or degenerate input gives
## Vector3.ZERO (rejected); an upward component is removed (owner: "not upward").
static func sanitize_launch_direction(direction: Vector3) -> Vector3:
	if not direction.is_finite():
		return Vector3.ZERO
	var not_upward: Vector3 = Vector3(direction.x, minf(direction.y, 0.0), direction.z)
	if not_upward.length() < MIN_DIRECTION_LENGTH:
		return Vector3.ZERO
	return not_upward.normalized()


## Default launch direction without camera input: toward the middle of the field (the
## world origin, where game/Field.gd sits) pitched `default_pitch_down_deg` below
## horizontal, so a Rocket dropped on a stack heads inward and down into the pile.
func default_launch_direction(block: Block) -> Vector3:
	var inward: Vector3 = Vector3(-block.global_position.x, 0.0, -block.global_position.z)
	if inward.length() < MIN_DIRECTION_LENGTH:
		inward = Vector3.FORWARD
	var pitch: float = deg_to_rad(default_pitch_down_deg)
	return (inward.normalized() * cos(pitch) + Vector3.DOWN * sin(pitch)).normalized()


## The direction `block` will launch along: the host-side input when one was set,
## otherwise default_launch_direction().
func launch_direction_for(block: Block) -> Vector3:
	# has_meta first: get_meta() with a null default still errors on a missing key.
	if block.has_meta(LAUNCH_DIRECTION_META):
		var raw: Variant = block.get_meta(LAUNCH_DIRECTION_META)
		if raw is Vector3:
			var stored: Vector3 = sanitize_launch_direction(raw)
			if stored != Vector3.ZERO:
				return stored
	return default_launch_direction(block)


## Impacts are detected by the contact probe below, not by the velocity-drop test.
func triggers_on_impact() -> bool:
	return false


## The action (flight) lasts at most `fuel_duration_s`; SpecialBehavior derives its fuse
## backstop from this.
func effect_lifetime_s() -> float:
	return fuel_duration_s


## DECISION (Bontago-1pi.85.10): the spent Rocket is removed at its explosion (no 0.75 s
## linger), same as the Bomb.
func detaches() -> bool:
	return true


## Every armed tick: launch once, hold the straight-line velocity, probe for contact.
## Written with kick() so the thrust is exempt from rebound damping (Bontago-xtq.17).
func physics_tick(block: Block, behavior: SpecialBehavior, delta: float) -> void:
	if block.has_meta(_HIT_META):
		return
	if not block.has_meta(_LAUNCH_AGE_META):
		_launch(block, behavior)
	var direction: Vector3 = block.get_meta(_FLIGHT_DIRECTION_META) as Vector3
	block.continuous_cd = true
	block.kick(direction * thrust_speed_mps)
	block.angular_velocity = Vector3.ZERO
	var launched_at: float = float(block.get_meta(_LAUNCH_AGE_META))
	if _contact_ahead(block, behavior, direction, delta, launched_at):
		block.set_meta(_HIT_META, true)


## True once the Rocket touched something (impact) or its safety fuel is spent.
func wants_early_trigger(block: Block, behavior: SpecialBehavior) -> bool:
	if block.has_meta(_HIT_META):
		return true
	if not block.has_meta(_LAUNCH_AGE_META):
		return false
	return behavior.age() - float(block.get_meta(_LAUNCH_AGE_META)) >= fuel_duration_s


## Blast every real RigidBody3D within `blast.radius_m` (the Rocket's own body excluded),
## then chain into any other special in range one depth deeper.
func detonate(block: Block, behavior: SpecialBehavior, chain_depth: int) -> void:
	var center: Vector3 = block.global_position
	ExplosionFx.blast(block.get_world_3d().direct_space_state, center, blast, [block.get_rid()])
	ExplosionFx.chain(behavior, center, blast.radius_m, chain_depth)


## First armed tick: fix the flight direction and wake the body (a long-stable carrier is
## STATIC-frozen by StableBlockManager and would ignore the velocity write).
func _launch(block: Block, behavior: SpecialBehavior) -> void:
	block.set_meta(_LAUNCH_AGE_META, behavior.age())
	block.set_meta(_FLIGHT_DIRECTION_META, launch_direction_for(block))
	block.wake_for_impulse()
	block.wake()


## Whether the body would touch something accepted by the behaviour's impact_filter within
## the next tick of travel (plus the margin). Disc and map geometry are not Blocks, so the
## filter always accepts them; only the owner's own blocks are ignored during the grace.
func _contact_ahead(
	block: Block, behavior: SpecialBehavior, direction: Vector3, delta: float, launched_at: float
) -> bool:
	var params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	params.from = block.global_transform
	params.motion = direction * (thrust_speed_mps * delta + impact_probe_margin_m)
	var result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(block.get_rid(), params, result):
		return false
	var collider: Object = result.get_collider()
	return behavior.impact_filter(collider, launched_at)
