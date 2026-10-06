class_name MagnetEffect
extends SpecialEffect
## Magnet special (docs/SPEC.md ~line 252: "Pulls enemy blocks within 8 m
## toward itself for 3 s"; docs/M8_PLAN.md P1 package). Follows the
## "timed-effect pattern" established by PropellerEffect.gd/VolcanoEffect.gd:
## physics_tick() runs the pull every armed tick from the moment it arms,
## before triggering; impact_triggers() vetoes the magnet's own landing
## impact so the pull window always gets to run at least once; wants_early_
## trigger() flips once pull_duration_s has elapsed since arming; detonate()
## is a no-op because the pull already ran tick by tick.
##
## DECISION (game/specials/MagnetEffect.gd, matches PropellerEffect.gd's own
## DECISION): a SpecialDef's `effect` is one shared Resource instance reused
## by every block spawned with this special during a match (autoload/match/
## MatchPlacement.gd's _attach_pending_special() binds the same cached,
## un-duplicated def to a fresh SpecialBehavior each time) -- so this effect
## keeps NO mutable per-block state on itself. "behavior.age() at first armed
## tick" lives in block.set_meta()/get_meta(), keyed by a unique StringName,
## exactly the seam PropellerEffect.gd/VolcanoEffect.gd already use.

## Pull strength and reach (Bontago-1pi.85.13). RadialPull applies a
## mass-independent acceleration (accel_mps2 * falloff) plus friction_compensation,
## so an 8 kg tetromino on the 0.85-friction disc really slides toward the magnet.
## radius_m is docs/SPEC.md's "within 8 m"; Magnet has no capture.
@export var pull: RadialPullTuning = RadialPullTuning.new()

## Seconds the pull runs, from the first armed tick, before this special
## force-triggers on its own. docs/SPEC.md: "for 3 s".
@export var pull_duration_s: float = 3.0

## @export var tuning ... mirrors BombEffect.gd:18's preload pattern so every
## SpecialEffect subclass follows the same "has its own SpecialTuning
## fallback" shape sibling effects (Bomb/Rocket/Volcano) already establish.
## Not actually read by this effect's own logic below -- no tunable Magnet
## needs belongs on the shared SpecialTuning resource; pull/
## pull_duration_s above are all Magnet-specific and live on this
## subclass, exactly like PropellerEffect's lift_speed/lift_duration_s/
## tilt_strength do.
@export var tuning: SpecialTuning = preload("res://config/special_tuning.tres")

## block.set_meta() key: behavior.age() at the tick this block first armed --
## the timed-effect pattern's own "<key>_start_age", seeded once, read every
## tick after via elapsed = age() - start_age.
const _START_AGE_META: StringName = &"magnet_start_age"


## Pulls every enemy Block within pull.radius_m toward this block's own
## position, every armed tick, for pull_duration_s seconds starting the very
## first tick this runs (no "settle" gate, unlike Propeller -- neither
## docs/SPEC.md nor docs/M8_PLAN.md ask the magnet itself to land first, and
## SpecialBehavior only calls physics_tick() once armed regardless).
func physics_tick(block: Block, behavior: SpecialBehavior, delta: float) -> void:
	if not block.has_meta(_START_AGE_META):
		block.set_meta(_START_AGE_META, behavior.age())

	var world: World3D = block.get_world_3d()
	if world == null:
		return  # no live physics world registered (e.g. an isolated unit test)
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var mover_owner_slot: int = block.owner_slot
	# DECISION (game/specials/MagnetEffect.gd): the enemy-only filter also
	# drops any non-Block body (candidate == null) -- SpecialPhysics stays
	# Block-agnostic by design (its own top-of-file DECISION), so "skip
	# non-Block bodies" is this caller's job, exactly like
	# query_bodies_in_range()'s own doc comment expects of the Magnet/Glue/
	# Gravity well callers.
	var enemy_only_filter: Callable = func(body: RigidBody3D) -> bool:
		var candidate: Block = body as Block
		return candidate != null and candidate.owner_slot != mover_owner_slot

	var exclude: Array[RID] = [block.get_rid()]
	# DECISION (Bontago-1pi.85.13): query through RadialPull (ExplosionFx.query_bodies)
	# instead of SpecialPhysics.query_bodies_in_range, which misses blocks near the
	# concave disc floor (one hit per triangle, capped).
	RadialPull.pull(space_state, block.global_position, pull, exclude, enemy_only_filter, delta)


## FIX pattern (matches PropellerEffect.gd/VolcanoEffect.gd's own
## impact_triggers() override, Bontago-1en.22): vetoes the decel-based impact
## trigger entirely so the magnet's own landing impact right as it arms can't
## trigger() (a no-op detonate()) before physics_tick() has run even once,
## which would skip the whole pull window -- the exact bug class Bontago-
## 1en.22 fixed for Propeller/Jumping Bean/Earthquake/Volcano.
func impact_triggers(_block: Block, _behavior: SpecialBehavior) -> bool:
	return false


## True once elapsed-since-first-armed-tick reaches pull_duration_s.
func wants_early_trigger(block: Block, behavior: SpecialBehavior) -> bool:
	if not block.has_meta(_START_AGE_META):
		return false
	var elapsed: float = behavior.age() - float(block.get_meta(_START_AGE_META))
	return elapsed >= pull_duration_s


## No-op: the pull already ran, tick by tick, in physics_tick() above --
## matches the timed-effect pattern's own note that detonate() becomes a
## no-op for every timed-effect special.
func detonate(_block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	pass


## The pull window is the effect's lifetime (SpecialBehavior derives the fuse backstop
## from it instead of the blanket arm_delay + fuse_timeout_s).
func effect_lifetime_s() -> float:
	return pull_duration_s
