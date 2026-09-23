class_name RocketEffect
extends SpecialEffect
## Rocket special (spec 2.6: "launches straight up, explodes when its fuel
## runs out" -- no homing, spec's own §2.6 explicitly drops that). See
## docs/M4_SPECIALS_PACKAGES.md's P3-ROCKET package. Follows that doc's
## "timed-effect pattern" for the fuel countdown (physics_tick()/
## wants_early_trigger() gated on elapsed-since-armed), but unlike the P5
## effects this one's physics_tick() actually moves the body (continuous
## thrust) rather than shaking/tilting the field, and detonate() is a real
## explosion (Bomb's own shape), not a no-op.
##
## DECISION (game/specials/RocketEffect.gd, docs/M4_SPECIALS_PACKAGES.md
## P3-ROCKET): `physics_tick()` writes `block.linear_velocity =
## Vector3.UP * launch_speed` every armed tick rather than a one-shot launch
## impulse at spawn -- spec 2.6 leaves the trajectory OPEN, and continuous
## thrust makes "fuel exhausted" a literal, testable condition (the velocity
## write itself, not an arbitrary timer racing an independent launch impulse)
## without fighting SpecialBehavior._check_impact()'s own decel read (constant
## frame-to-frame velocity, absent a real collision, never looks like an
## impact).
##
## DECISION (game/specials/RocketEffect.gd): a SpecialDef's `effect` is one
## shared Resource instance reused by every block spawned with this special
## during a match (autoload/match/MatchPlacement.gd's _attach_pending_special()
## binds the same cached, un-duplicated def/effect to a fresh SpecialBehavior
## each time) -- so this effect keeps NO mutable per-block state on itself.
## "Seconds since armed" lives in block.set_meta()/get_meta(), exactly the
## timed-effect pattern's own seam (EarthquakeEffect.gd/PropellerEffect.gd).
## Two blocks sharing this very instance therefore keep fully independent
## fuel timers, one per block.

## Reaches config/special_tuning.tres the same way game/Field.gd reaches
## PhysicsTuning -- see BombEffect.gd's identical field for the full DECISION;
## mirrored verbatim here since Rocket also explodes.
@export var tuning: SpecialTuning = preload("res://config/special_tuning.tres")

## Vertical thrust speed (m/s) this block's body is held at, every armed
## tick, until its fuel runs out (spec 2.6's Rocket row; provisional).
@export var launch_speed: float = 18.0

## Seconds of thrust before this special force-triggers (explodes) on its
## own. NEW, spec's fuel duration left OPEN.
@export var fuel_duration_s: float = 1.5

## Explosion radius in meters once the fuel runs out (or an early impact
## triggers it) -- tunables table: 3.0, provisional.
@export var explosion_radius: float = 3.0

## Explosion impulse magnitude fed into SpecialPhysics.explode()'s falloff,
## before tuning.max_explosion_impulse's clamp -- tunables table: 14.0,
## provisional.
@export var explosion_impulse: float = 14.0

## block.set_meta() key: behavior.age() at the tick this block first armed --
## the timed-effect pattern's "<key>_start_age", seeded once on the first
## armed tick, read every tick after via elapsed = age() - start_age.
const _START_AGE_META: StringName = &"rocket_start_age"


## Every armed tick: continuous upward thrust plus continuous collision
## detection (spec 3.5: "any body moving faster than 15 m/s uses
## continuous_cd" -- launch_speed's default of 18.0 always qualifies, and a
## tuned-down value might not, so this sets it explicitly every tick rather
## than assuming the spawn path already did). Seeds _START_AGE_META on the
## very first armed tick, same as every other timed-effect pattern user.
##
## Review-precedent guard (mirrors PropellerEffect.gd's own fix, Bontago-1en.6):
## never gates on `block.sleeping` after writing velocity here -- a rocket
## under continuous thrust never actually sleeps, but wants_early_trigger()
## below reads elapsed-since-armed from meta, not from any sleep flag, so
## there is nothing here to regress the same way in the first place.
func physics_tick(block: Block, behavior: SpecialBehavior, _delta: float) -> void:
	if not block.has_meta(_START_AGE_META):
		block.set_meta(_START_AGE_META, behavior.age())
	block.continuous_cd = true
	block.linear_velocity = Vector3.UP * launch_speed


## True once elapsed-since-armed reaches fuel_duration_s. An impact strong
## enough to satisfy SpecialBehavior's own arm_impulse check can still
## trigger this earlier, same as every other special.
func wants_early_trigger(block: Block, behavior: SpecialBehavior) -> bool:
	if not block.has_meta(_START_AGE_META):
		return false
	var elapsed: float = behavior.age() - float(block.get_meta(_START_AGE_META))
	return elapsed >= fuel_duration_s


## The moment SpecialBehavior triggers this special (fuel exhausted or an
## early impact), explode exactly like BombEffect.detonate() with Rocket's
## own numbers.
func detonate(block: Block, behavior: SpecialBehavior, chain_depth: int) -> void:
	SpecialPhysics.explode(
		block.get_world_3d().direct_space_state,
		block.global_position,
		explosion_radius,
		explosion_impulse,
		tuning.max_explosion_impulse,
		[block.get_rid()]
	)
	behavior.trigger_others_in_range(block.global_position, explosion_radius, chain_depth)
