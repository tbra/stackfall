class_name EarthquakeEffect
extends SpecialEffect
## Earthquake special (spec 1.6): "shakes the field, tilts randomly, helps
## level existing tilt." It runs through DiscForce.shake. Follows the "timed-effect pattern": physics_tick() shakes every
## armed tick; wants_early_trigger() flips once `disc_force.duration_s` has
## elapsed; detonate() is a no-op because the effect already ran.
##
## DECISION: SpecialDef.effect is a single Resource instance shared by every
## block that draws this special, so this effect keeps NO mutable per-block
## state; "seconds since armed" lives in the EffectState from new_state(), so two
## Earthquake blocks keep independent timers.
class State:
	extends EffectState
	## False until the first armed tick records `start_age`.
	var started: bool = false
	var start_age: float = 0.0

	func elapsed(age: float) -> float:
		return age - start_age


## DiscForce tuning: `duration_s` is the seconds the shake runs before this
## special force-triggers on its own (spec 1.6's Earthquake row; no explicit
## number given -- provisional), `shake_amplitude_m` the tilt impulse units per
## second of the kick and `shake_tilt_deg` how fast its axis sweeps around the
## disc.
##
## DECISION: spec 1.6 pairs a linear amplitude (0.25 m) with an
## angular one (2.5 deg); Field.gd exposes no vertical-bounce entry point, so
## both fold onto the one tilt-impulse tunable.
@export var disc_force: DiscForceTuning = DiscForceTuning.new()

## Fraction of the field's current |tilt_vector()| fed back as an impulse
## opposing the tilt each armed tick -- spec 1.6: Earthquake "helps level
## existing tilt." Not given a number in the spec.
@export var leveling_strength: float = 0.5


func effect_lifetime_s() -> float:
	return disc_force.duration_s


func new_state() -> EffectState:
	return State.new()


func physics_tick(_block: Block, behavior: SpecialBehavior, delta: float) -> void:
	var state: State = behavior.state() as State
	if not state.started:
		state.started = true
		state.start_age = behavior.age()
	var field: FieldBody = MatchContext.current().field()
	# No live Field registered (e.g. an isolated unit test that never called
	# the Match autoload registering a world): the elapsed-time bookkeeping above still runs
	# so wants_early_trigger() below stays correct, but there is nothing to
	# shake.
	if field == null:
		return
	# Sweeping kick; a no-op once `disc_force.duration_s` has passed.
	var elapsed: float = state.elapsed(behavior.age())
	DiscForce.shake(field, disc_force, elapsed, delta)
	# Field.apply_tilt_impulse() already no-ops while tilt is disabled
	# (PHYSICAL_BALANCE/OFF match config, or before any match wires tilt on
	# at all), so this effect needs no separate MatchConfig.tilt_mode guard.
	var tilt: Vector2 = field.tilt_vector()
	if tilt != Vector2.ZERO:
		# DECISION: NOT `apply_tilt_impulse(-tilt.normalized(), ...)`. apply_tilt_impulse()'s `direction` is a disk-local
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


## Vetoes the decel-based impact trigger entirely -- see
## SpecialEffect.impact_triggers()'s own doc comment. This effect's own end is
## time-driven (wants_early_trigger() below) or a chain trigger from a nearby
## special (SpecialBehavior.trigger_others_in_range(), unaffected).
func impact_triggers(_block: Block, _behavior: SpecialBehavior) -> bool:
	return false


func wants_early_trigger(_block: Block, behavior: SpecialBehavior) -> bool:
	var state: State = behavior.state() as State
	return state.started and state.elapsed(behavior.age()) >= disc_force.duration_s


## No-op: the shake already ran, tick by tick, in physics_tick() above.
func detonate(_block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	pass
