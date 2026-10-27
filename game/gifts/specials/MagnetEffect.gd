class_name MagnetEffect
extends SpecialEffect
## Magnet special (docs/SPEC.md: "Pulls enemy blocks within 8 m toward itself for 3 s").
## Timed-effect pattern: physics_tick() runs the pull every armed tick; impact_triggers()
## vetoes the magnet's own landing impact so the pull window runs at least once;
## wants_early_trigger() flips once pull_duration_s has elapsed since arming; detonate()
## is a no-op because the pull already ran tick by tick.
##
## A SpecialDef's `effect` is one shared Resource reused by every block with this special, so
## this effect keeps NO mutable per-block state; it lives in MagnetState (SpecialBehavior.state()).

## Pull strength and reach. RadialPull applies a mass-independent acceleration (accel_mps2 * falloff) plus friction_compensation,
## so an 8 kg tetromino on the 0.85-friction disc really slides toward the magnet.
## radius_m is docs/SPEC.md's "within 8 m"; Magnet has no capture.
@export var pull: RadialPullTuning = RadialPullTuning.new()

## Seconds the pull runs, from the first armed tick, before this special
## force-triggers on its own. docs/SPEC.md: "for 3 s".
@export var pull_duration_s: float = 6.0

## The model's "nose" in the carrier's local frame: magnet_v1.glb's pole tips sit at +Y. While
## thrown (airborne, before the pull starts) the carrier turns so this axis leads along its
## velocity (FlightFacing).
@export var model_nose_axis: Vector3 = Vector3(0.0, 1.0, 0.0)

## Seconds after the throw before the pull starts. The def's arm_delay is 0 so
## physics_tick() runs, and the carrier faces its velocity, from the first tick; the pull
## itself waits this long.
@export var pull_start_delay_s: float = 0.0

## Below this speed (m/s) the thrown magnet keeps its pose instead of facing its velocity.
@export var face_min_speed_mps: float = 1.0

## Shared SpecialTuning fallback, as on the sibling effects. Not read by this effect:
## the Magnet-specific tunables live on this class.
@export var tuning: SpecialTuning = preload("res://config/gifts/special_tuning.tres")

## Per-activation state (SpecialBehavior.state()): the shared effect Resource keeps none.
class MagnetState extends EffectState:
	## behavior.age() at the tick this block first armed; negative until seeded.
	var start_age: float = -1.0
	## Set once the thrown magnet has slowed below face_min_speed_mps (landed); from then on it
	## keeps its resting pose instead of turning toward a slide or wobble.
	var facing_done: bool = false

	func started() -> bool:
		return start_age >= 0.0


func new_state() -> EffectState:
	return MagnetState.new()


## A thrown magnet spawns with its pole tips along the throw velocity.
func faces_launch(mode: GiftThrow.Mode, _aim_direction: Vector3, throw_velocity: Vector3) -> bool:
	return mode == GiftThrow.Mode.THROW and throw_velocity.length() > 0.0


func launch_facing(_mode: GiftThrow.Mode, _aim_direction: Vector3, throw_velocity: Vector3) -> Basis:
	return FlightFacing.nose_basis(model_nose_axis, throw_velocity)


## Pulls every enemy Block within pull.radius_m toward this block's own position, every
## armed tick after landing (a thrown magnet) for pull_duration_s seconds from the first tick this runs.
func physics_tick(block: Block, behavior: SpecialBehavior, delta: float) -> void:
	var state: MagnetState = behavior.state() as MagnetState
	if not state.started():
		state.start_age = behavior.age()
	_face_while_airborne(block, state)  # a dropped magnet turns here; a thrown one in flight_tick()
	if behavior.age() - state.start_age < pull_start_delay_s:
		return

	var world: World3D = block.get_world_3d()
	if world == null:
		return  # no live physics world registered (e.g. an isolated unit test)
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var mover_owner_slot: int = block.owner_slot
	# DECISION: the enemy-only filter also drops any non-Block body (candidate == null):
	# SpecialPhysics stays Block-agnostic, so skipping non-Block bodies is this caller's job.
	var enemy_only_filter: Callable = func(body: RigidBody3D) -> bool:
		var candidate: Block = body as Block
		return candidate != null and candidate.owner_slot != mover_owner_slot

	var exclude: Array[RID] = [block.get_rid()]
	# DECISION: query through RadialPull (ExplosionFx.query_bodies)
	# instead of SpecialPhysics.query_bodies_in_range, which misses blocks near the
	# concave disc floor (one hit per triangle, capped).
	RadialPull.pull(space_state, block.global_position, pull, exclude, enemy_only_filter, delta)


## The thrown magnet turns along its path while in flight; the pull itself waits for landing
## (SpecialBehavior.starts_on_landing).
func flight_tick(block: Block, behavior: SpecialBehavior, _delta: float) -> void:
	_face_while_airborne(block, behavior.state() as MagnetState)


## While the thrown magnet is still travelling it turns so the pole tips lead along its
## velocity (FlightFacing); once it slows below `face_min_speed_mps` it has landed and
## keeps that pose for good. Runs from flight_tick() (magnet.tres arm_delay is 0).
func _face_while_airborne(block: Block, state: MagnetState) -> void:
	if state.facing_done:
		return
	if block.linear_velocity.length() < face_min_speed_mps:
		if block.has_meta(FlightFacing.FACED_META):
			state.facing_done = true
		return
	block.angular_velocity = Vector3.ZERO
	FlightFacing.face_velocity(block, model_nose_axis, face_min_speed_mps)


## Vetoes the decel-based impact trigger so the magnet's own landing impact as it arms
## cannot trigger() (a no-op detonate()) before physics_tick() has run, which would skip
## the whole pull window.
func impact_triggers(_block: Block, _behavior: SpecialBehavior) -> bool:
	return false


## True once elapsed-since-first-armed-tick reaches pull_duration_s.
func wants_early_trigger(_block: Block, behavior: SpecialBehavior) -> bool:
	var state: MagnetState = behavior.state() as MagnetState
	if not state.started():
		return false
	var elapsed: float = behavior.age() - state.start_age
	return elapsed >= pull_start_delay_s + pull_duration_s


## No-op: the pull already ran, tick by tick, in physics_tick() above.
func detonate(_block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	pass


## The pull window is the effect's lifetime (SpecialBehavior derives the fuse backstop
## from it instead of the blanket arm_delay + fuse_timeout_s).
func effect_lifetime_s() -> float:
	return pull_start_delay_s + pull_duration_s
