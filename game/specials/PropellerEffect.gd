class_name PropellerEffect
extends SpecialEffect
## Propeller special (spec 2.6: "stands where it lands, then lifts itself and
## blows for its duration" -- replaces the old "Fan" wind-field idea; see
## docs/M4_SPECIALS_PACKAGES.md's P5-PROPELLER package, which supersedes
## spec's older "pushes nearby blocks sideways" framing). Follows that doc's
## "timed-effect pattern" -- physics_tick() runs the lift+tilt every armed
## tick once settled, before triggering; wants_early_trigger() flips once
## lift_duration_s has elapsed since settling; detonate() is a no-op because
## the effect already ran.
##
## DECISION (game/specials/PropellerEffect.gd, docs/M4_SPECIALS_PACKAGES.md
## P5-PROPELLER): a SpecialDef's `effect` is one shared Resource instance
## reused by every block spawned with this special during a match
## (autoload/match/MatchPlacement.gd's _attach_pending_special() binds the
## same cached, un-duplicated def to a fresh SpecialBehavior each time) -- so
## this effect keeps NO mutable per-block state on itself. "Has it settled
## yet" and "seconds since settling" both live in block.set_meta()/
## get_meta(), keyed by unique StringNames, exactly the seam
## EarthquakeEffect.gd/AnvilEffect.gd already use. Two blocks sharing this
## very instance therefore keep fully independent settle flags and elapsed
## timers, one per block.

## Vertical speed (m/s) this block's body is held at, every armed tick, once
## it has settled -- spec 2.6's Propeller row; no explicit number given,
## OPEN, provisional (docs/M4_SPECIALS_PACKAGES.md's tunables table).
@export var lift_speed: float = 4.0

## Seconds the lift+tilt runs, once settled, before this special
## force-triggers on its own. NEW, OPEN in spec.
@export var lift_duration_s: float = 3.0

## Tilt-impulse magnitude (Field.apply_tilt_impulse()'s velocity-kick units,
## see game/Field.gd) applied per second while lifting, pushing the disk down
## on the OPPOSITE side from where this block sits -- so the block's own
## corner rises and the disc tilts away from the propeller.
##
## DECISION (game/specials/PropellerEffect.gd, matches
## docs/M4_SPECIALS_PACKAGES.md's own P5-PROPELLER pseudocode): the direction
## fed to apply_tilt_impulse() is the NEGATED disk-local XZ position of the
## block (not the raw position) -- apply_tilt_impulse(dir, mag)'s own contract
## (game/Field.gd) pushes the disk DOWN at the side named by `dir`, so naming
## the block's own position would dip the disk toward the propeller, the
## opposite of spec 2.6's "stands where it lands, then lifts itself" reading
## (the propeller's own footprint rising, not sinking). This is a genuine
## disk-local XZ *position* (normalized), the same space AnvilEffect.gd
## passes -- unaffected by the Earthquake worker's rotation-space correction
## (docs/M4_SPECIALS_PACKAGES.md's "Orchestrator decisions" item 5), which
## only applies to a `tilt_vector()`-space input like EarthquakeEffect.gd's
## leveling term.
@export var tilt_strength: float = 0.3

## block.set_meta() key marking "this block has settled once" (first tick
## where block.sleeping read true while armed) -- gates the whole lift+tilt
## pattern until then, per spec 2.6's "stands where it lands" ordering.
const _SETTLED_META: StringName = &"propeller_settled"

## block.set_meta() key: behavior.age() at the tick this block first settled
## -- the timed-effect pattern's "<key>_start_age", seeded once, read every
## tick after via elapsed = age() - start_age.
const _START_AGE_META: StringName = &"propeller_start_age"


## No-op until the block has settled once (Jolt's own `sleeping` flag, same
## settle test AnvilEffect.gd's wants_early_trigger() uses) -- spec 2.6:
## "stands where it lands" before it does anything else.
##
## Review fix (Bontago-1en.6): `block.sleeping` only gates the FIRST settle,
## not every subsequent tick. The very first lift tick below writes
## `block.linear_velocity.y = lift_speed`, and Jolt wakes a sleeping body the
## instant its velocity is written to (any RigidBody3D motion clears
## `sleeping`), so a `if not block.sleeping: return` guard re-checked every
## tick would see `sleeping == false` again from the second tick onward and
## bail out forever -- the lift becomes a one-tick kick and the tilt fires
## exactly once instead of running for the whole `lift_duration_s` window.
## Neither Block nor SpecialBehavior expose a sturdier "has landed" flag than
## `sleeping` (AnvilEffect.gd's wants_early_trigger() reads the same flag, but
## Anvil never writes velocity itself, so it never re-wakes what it just
## read); the fix is to seed `_SETTLED_META`/`_START_AGE_META` only once, the
## first time this block is observed sleeping, and run the lift+tilt every
## armed tick after that regardless of the current `sleeping` value, exactly
## like `_START_AGE_META` already being present is treated as "settled" by
## wants_early_trigger() below.
func physics_tick(block: Block, behavior: SpecialBehavior, delta: float) -> void:
	if not block.has_meta(_SETTLED_META):
		if not block.sleeping:
			return
		block.set_meta(_SETTLED_META, true)
		block.set_meta(_START_AGE_META, behavior.age())
	block.linear_velocity.y = lift_speed
	var field: Field = Match.field()
	# No live Field registered (e.g. an isolated unit test that never called
	# Match.register_world()): the lift itself and the elapsed-time
	# bookkeeping above still run so wants_early_trigger() below stays
	# correct, but there is nothing to tilt.
	if field == null:
		return
	var local: Vector2 = field.disk_local_from_world(block.global_position)
	if local == Vector2.ZERO:
		# Exactly centred: no side to name for "away from itself" to mean
		# anything -- same "distance 0, no impulse" call AnvilEffect.gd's
		# detonate() makes, rather than relying on apply_tilt_impulse()'s
		# own zero-vector guard so a test can tell the two no-op reasons
		# apart if it ever needs to.
		return
	field.apply_tilt_impulse(-local.normalized(), tilt_strength * delta)


## FIX (game/specials/PropellerEffect.gd, Bontago-1en.22): vetoes the decel-
## based impact trigger entirely -- see SpecialEffect.impact_triggers()'s own
## doc comment. A hard-thrown/dropped propeller that lands right as it arms
## used to satisfy arm_impulse on that very landing and detonate (a no-op
## detonate()) before physics_tick() ever ran once, so the lift+tilt never
## started. This effect's own end is entirely time-driven
## (wants_early_trigger() below) or a chain trigger from a nearby special
## (SpecialBehavior.trigger_others_in_range(), unaffected by this hook).
func impact_triggers(_block: Block, _behavior: SpecialBehavior) -> bool:
	return false


## True once elapsed-since-first-settled reaches lift_duration_s. False
## while still airborne (never settled, no start-age meta yet) -- an impact
## strong enough to satisfy SpecialBehavior's own arm_impulse check can still
## trigger this earlier, same as every other special.
##
## Bontago-1en.22 amendment: "an impact ... can still trigger this earlier"
## above described the pre-fix decel path, now vetoed by impact_triggers()
## above -- an early trigger for this effect is only ever the fuse timeout
## or a chain trigger from a nearby special now.
func wants_early_trigger(block: Block, behavior: SpecialBehavior) -> bool:
	if not block.has_meta(_START_AGE_META):
		return false
	var elapsed: float = behavior.age() - float(block.get_meta(_START_AGE_META))
	return elapsed >= lift_duration_s


## No-op: the lift+tilt already ran, tick by tick, in physics_tick() above --
## docs/M4_SPECIALS_PACKAGES.md's timed-effect pattern note ("detonate()
## becomes a no-op for every P5 special"). Kept for SpecialEffect's contract.
func detonate(_block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	pass
