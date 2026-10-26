class_name AnvilEffect
extends SpecialEffect
## Anvil (spec 1.6: "applies weight to tilt the field": lands heavy, tilts the
## field toward where it lands).
## The tilt goes through DiscForce
## (sign +1 dips the landing side) and "has it landed" is a LandedProbe, not
## Jolt's `sleeping` flag (an anvil on an awake island never slept, so the
## special only ever fired from the silent fuse).

## Mass this special's block is set to once armed (spec 1.6: mass 60,
## provisional -- the number itself is OPEN, only that it is heavy). Higher
## than any ordinary block's mass so the anvil's own weight, not an
## incidental knock from something else, is what settles it and what a
## later impact against it registers as substantial.
@export var mass: float = 60.0

## DiscForce tuning for the landing kick. `strength` is the tilt impulse
## (Field.apply_tilt_impulse() velocity-kick units) per metre of the landing
## point from the disc centre: 0.02, picked so a rim landing alone reaches
## roughly half of TiltTuning.max_tilt_deg (spec's own constant is OPEN).
@export var disc_force: DiscForceTuning = DiscForceTuning.new()

## Landing-detection thresholds.
@export var landed: LandedTuning = LandedTuning.new()

## Per-activation state, kept on the SpecialBehavior (the effect resource is shared by
## every block spawned with this special).
##
## DECISION: Anvil keeps its own probe instead of `needs_landing()`. The behaviour only
## ticks an effect after landing when needs_landing() is true, but the mass override must
## happen on the first armed tick (the anvil has to be heavy when it hits), so the effect
## polls the probe itself.
class AnvilState extends EffectState:
	## True once the block's mass was overridden.
	var mass_applied: bool = false
	var probe: LandedProbe


## Fresh state with a probe on this anvil's landing thresholds.
func new_state() -> EffectState:
	var state: AnvilState = AnvilState.new()
	state.probe = LandedProbe.new(landed)
	return state


## One-shot mass override on the first armed tick (mid-fall mass changes do
## not alter the trajectory), then feeds this block's landing probe.
func physics_tick(block: Block, behavior: SpecialBehavior, delta: float) -> void:
	var state: AnvilState = behavior.state() as AnvilState
	if not state.mass_applied:
		block.mass = mass
		state.mass_applied = true
	state.probe.update(block, delta)


## Triggers once the anvil has actually landed (velocity/timeout probe, see
## LandedProbe), not on a timer. A hard landing satisfying
## SpecialBehavior's arm_impulse check can still trigger it earlier.
func wants_early_trigger(_block: Block, behavior: SpecialBehavior) -> bool:
	var state: AnvilState = behavior.state() as AnvilState
	return state != null and state.probe.has_landed()


## Dips the disc at the point the anvil landed, via MatchContext.field() -- a
## SpecialEffect has no scene-tree handle of its own. DiscForce.apply() is a
## no-op at the exact disc centre and while the field's tilt is disabled.
func detonate(block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	DiscForce.apply(MatchContext.current().field(), block.global_position, 1.0, disc_force, 0.0)
