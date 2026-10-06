class_name EarthquakeEffect
extends SpecialEffect
## Earthquake special (spec 2.6): "shakes the field, tilts randomly, helps
## level existing tilt." docs/M4_SPECIALS_PACKAGES.md P5-EARTHQUAKE, moved onto
## DiscForce.shake by docs/GIFT_EFFECTS_PLAN.md package D (behaviour
## unchanged). Follows the "timed-effect pattern": physics_tick() shakes every
## armed tick; wants_early_trigger() flips once `disc_force.duration_s` has
## elapsed; detonate() is a no-op because the effect already ran.
##
## DECISION: SpecialDef.effect is a single Resource instance shared by every
## block that draws this special, so this effect keeps NO mutable per-block
## state (no `var elapsed`). "Seconds since armed" lives in block meta, keyed
## by START_AGE_META, so two Earthquake blocks keep independent timers.
const START_AGE_META: StringName = &"earthquake_start_age"

## DiscForce tuning: `duration_s` is the seconds the shake runs before this
## special force-triggers on its own (spec 2.6's Earthquake row; no explicit
## number given -- provisional), `shake_amplitude_m` the tilt impulse units per
## second of the kick and `shake_tilt_deg` how fast its axis sweeps around the
## disc.
##
## DECISION (carried over): spec 2.6 pairs a linear amplitude (0.25 m) with an
## angular one (2.5 deg); Field.gd exposes no vertical-bounce entry point, so
## both fold onto the one tilt-impulse tunable. 3.0 per second equals the old
## 0.05 per tick at 60 Hz.
@export var disc_force: DiscForceTuning = DiscForceTuning.new()

## Fraction of the field's current |tilt_vector()| fed back as an impulse
## opposing the tilt each armed tick -- spec 2.6: Earthquake "helps level
## existing tilt." NEW, OPEN in spec.
@export var leveling_strength: float = 0.5


func effect_lifetime_s() -> float:
	return disc_force.duration_s


func physics_tick(block: Block, behavior: SpecialBehavior, delta: float) -> void:
	if not block.has_meta(START_AGE_META):
		block.set_meta(START_AGE_META, behavior.age())
	var field: Field = Match.field()
	# No live Field registered (e.g. an isolated unit test that never called
	# Match.register_world()): the elapsed-time bookkeeping above still runs
	# so wants_early_trigger() below stays correct, but there is nothing to
	# shake.
	if field == null:
		return
	# Sweeping kick; a no-op once `disc_force.duration_s` has passed.
	var elapsed: float = behavior.age() - float(block.get_meta(START_AGE_META))
	DiscForce.shake(field, disc_force, elapsed, delta)
	# Field.apply_tilt_impulse() already no-ops while tilt is disabled
	# (PHYSICAL_BALANCE/OFF match config, or before any match wires tilt on
	# at all), so this effect needs no separate MatchConfig.tilt_mode guard.
	var tilt: Vector2 = field.tilt_vector()
	if tilt != Vector2.ZERO:
		# DECISION: NOT `apply_tilt_impulse(-tilt.normalized(), ...)` as
		# docs/M4_SPECIALS_PACKAGES.md's P5-EARTHQUAKE pseudocode literally
		# reads -- verified against Field.gd's own contract and a failing
		# regression test. apply_tilt_impulse()'s `direction` is a disk-local
		# XZ *position* to push down on, converted into a velocity kick via
		# the perpendicular map Vector2(dz, -dx). `tilt_vector()` is a
		# ROTATION-space vector, not a disk position, so feeding
		# `-tilt.normalized()` straight in runs that perpendicular map again
		# and the kick lands orthogonal to the tilt instead of opposing it.
		# Composing the map TWICE -- `Vector2(tilt_normalized.y,
		# -tilt_normalized.x)` -- cancels out to a true
		# `-leveling_strength * tilt` contribution (two -90 deg turns = 180
		# deg), which is what "helps level existing tilt" actually needs.
		var tilt_normalized: Vector2 = tilt.normalized()
		var cancel_direction: Vector2 = Vector2(tilt_normalized.y, -tilt_normalized.x)
		field.apply_tilt_impulse(cancel_direction, leveling_strength * tilt.length())


## FIX (Bontago-1en.22): vetoes the decel-based impact trigger entirely -- see
## SpecialEffect.impact_triggers()'s own doc comment. This effect's own end is
## time-driven (wants_early_trigger() below) or a chain trigger from a nearby
## special (SpecialBehavior.trigger_others_in_range(), unaffected).
func impact_triggers(_block: Block, _behavior: SpecialBehavior) -> bool:
	return false


func wants_early_trigger(block: Block, behavior: SpecialBehavior) -> bool:
	if not block.has_meta(START_AGE_META):
		return false
	var elapsed: float = behavior.age() - float(block.get_meta(START_AGE_META))
	return elapsed >= disc_force.duration_s


## No-op: the shake already ran, tick by tick, in physics_tick() above.
func detonate(_block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	pass
