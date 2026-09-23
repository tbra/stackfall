class_name EarthquakeEffect
extends SpecialEffect
## Earthquake special (spec 2.6): "shakes the field, tilts randomly, helps
## level existing tilt." docs/M4_SPECIALS_PACKAGES.md P5-EARTHQUAKE. Follows
## that doc's "timed-effect pattern" -- physics_tick() runs the shake every
## armed tick, before triggering; wants_early_trigger() flips once
## shake_duration_s has elapsed; detonate() is a no-op because the effect
## already ran.
##
## DECISION (game/specials/EarthquakeEffect.gd): SpecialDef.effect is a
## single Resource instance, preloaded once by SpecialDef.load_all_specials()
## and shared by every block that draws this special --
## config/specials/SpecialDef.gd's own `@export var effect` doc and
## autoload/match/MatchPlacement.gd's _attach_pending_special() (which binds
## the SAME def/effect to a new SpecialBehavior each time, never duplicating
## either) both confirm this. So this effect keeps NO mutable per-block state
## on itself (no `var elapsed` field) -- "seconds since armed" instead lives
## in `block.set_meta()/get_meta()`, keyed by START_AGE_META, exactly the
## pattern docs/M4_SPECIALS_PACKAGES.md's "timed-effect pattern" section
## prescribes. Two blocks that both drew Earthquake (sharing this very
## instance) therefore keep fully independent elapsed timers, one per block.
const START_AGE_META: StringName = &"earthquake_start_age"

## Seconds the shake runs before this special force-triggers on its own
## (spec 2.6's Earthquake row; no explicit number given -- provisional).
@export var shake_duration_s: float = 4.0

## Impulse magnitude (Field.apply_tilt_impulse's "unit mass" velocity-kick
## units, not meters/degrees) fed into a random disk-local direction every
## armed tick -- the shake itself.
##
## DECISION (game/specials/EarthquakeEffect.gd, matches
## docs/M4_SPECIALS_PACKAGES.md's own P5-EARTHQUAKE decision): spec 2.6 pairs
## a linear amplitude (0.25 m) with an angular one (2.5 deg) for Earthquake's
## "bounce"; Field.gd exposes no literal vertical-bounce entry point (Open
## question 3, decided in place: ship without it), so both fold onto this one
## tilt-impulse tunable instead of a separate Y-offset system.
@export var shake_magnitude: float = 0.05

## Fraction of the field's current |tilt_vector()| fed back as an impulse
## opposing the tilt each armed tick -- spec 2.6: Earthquake "helps level
## existing tilt." NEW, OPEN in spec.
@export var leveling_strength: float = 0.5

## Shared across every block using this effect instance (see the DECISION
## above) -- fine, since it only ever picks a fresh random direction each
## tick and carries no per-block state.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func physics_tick(block: Block, behavior: SpecialBehavior, _delta: float) -> void:
	if not block.has_meta(START_AGE_META):
		block.set_meta(START_AGE_META, behavior.age())
	var field: Field = Match.field()
	# No live Field registered (e.g. an isolated unit test that never called
	# Match.register_world()): the elapsed-time bookkeeping above still runs
	# so wants_early_trigger() below stays correct, but there is nothing to
	# shake.
	if field == null:
		return
	# A random disk-local unit vector (Vector2.from_angle() is unit-length by
	# construction, so this is never the zero vector apply_tilt_impulse()
	# would otherwise no-op on).
	var shake_dir: Vector2 = Vector2.from_angle(_rng.randf_range(0.0, TAU))
	field.apply_tilt_impulse(shake_dir, shake_magnitude)
	# Field.apply_tilt_impulse() already no-ops while tilt is disabled
	# (PHYSICAL_BALANCE/OFF match config, or before any match wires tilt on
	# at all -- game/Field.gd:260-266), so this effect needs no separate
	# MatchConfig.tilt_mode guard of its own; verified by reading that
	# function directly rather than assumed.
	var tilt: Vector2 = field.tilt_vector()
	if tilt != Vector2.ZERO:
			# DECISION (game/specials/EarthquakeEffect.gd): NOT
			# `apply_tilt_impulse(-tilt.normalized(), ...)` as
			# docs/M4_SPECIALS_PACKAGES.md's P5-EARTHQUAKE pseudocode literally
			# reads -- verified against Field.gd:260-266's own contract and a
			# failing regression test (tests/unit/test_earthquake_effect.gd)
			# showing a "leveled" field ending up MORE tilted than an
			# unleveled control field kicked identically.
			# apply_tilt_impulse()'s `direction` is a disk-local XZ *position*
			# to push down on, converted into a velocity kick via the
			# perpendicular map Vector2(dz, -dx) (Field.gd's own DECISION on
			# that function). `tilt_vector()` is a ROTATION-space vector, not
			# a disk position (Field.gd:116-120's own doc: "chosen to read
			# the same way disk-local (x, z) already does ... NOT because it
			# is a literal disk-local point"), so feeding `-tilt.normalized()`
			# straight in as `direction` runs that same perpendicular map
			# again -- the resulting velocity kick lands orthogonal to the
			# tilt vector (a torque that rotates it) rather than opposing it:
			# apply_tilt_impulse(d, m) adds Vector2(d.y, -d.x) * m to the
			# tilt velocity, so d = -tilt.normalized() always yields a kick
			# perpendicular to `tilt`, never a `-tilt`-directed one (their dot
			# product is zero by construction). Composing the map TWICE --
			# `direction = Vector2(tilt_normalized.y, -tilt_normalized.x)` --
			# cancels out to a true `-leveling_strength * tilt` velocity
			# contribution (two -90 deg turns = 180 deg = negation), which is
			# what "helps level existing tilt" (spec 2.6) actually needs: a
			# kick working directly against the current lean, not a
			# perpendicular nudge the spring's own dynamics can turn into
			# *more* tilt.
			var tilt_normalized: Vector2 = tilt.normalized()
			var cancel_direction: Vector2 = Vector2(tilt_normalized.y, -tilt_normalized.x)
			field.apply_tilt_impulse(cancel_direction, leveling_strength * tilt.length())


func wants_early_trigger(block: Block, behavior: SpecialBehavior) -> bool:
	if not block.has_meta(START_AGE_META):
		return false
	var elapsed: float = behavior.age() - float(block.get_meta(START_AGE_META))
	return elapsed >= shake_duration_s


## No-op: the shake already ran, tick by tick, in physics_tick() above --
## docs/M4_SPECIALS_PACKAGES.md's timed-effect pattern note ("detonate()
## becomes a no-op for every P5 special"). Kept for SpecialEffect's contract.
func detonate(_block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	pass
