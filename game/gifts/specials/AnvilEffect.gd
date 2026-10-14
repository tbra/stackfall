class_name AnvilEffect
extends SpecialEffect
## Anvil (spec 2.6: "applies weight to tilt the field", the JayIsGames review's
## "a tilting anvil" -- lands heavy, tilts the field toward where it lands).
## docs/GIFT_EFFECTS_PLAN.md package D: the tilt now goes through DiscForce
## (sign +1 dips the landing side) and "has it landed" is a LandedProbe, not
## Jolt's `sleeping` flag (an anvil on an awake island never slept, so the
## special only ever fired from the silent fuse).

## Mass this special's block is set to once armed (spec 2.6: mass 60,
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

## Landing-detection thresholds (replaces `block.sleeping`).
@export var landed: LandedTuning = LandedTuning.new()

## block.set_meta() key marking "mass already overridden for this block".
##
## DECISION: a SpecialDef's `effect` is one shared Resource instance reused by
## every block spawned with this special, so this effect carries no per-block
## mutable state of its own. Idempotency lives on the block via set_meta().
const _MASS_APPLIED_META: StringName = &"anvil_mass_applied"

## block.set_meta() key holding this block's own LandedProbe (a RefCounted),
## for the same shared-resource reason as above.
##
## DECISION: Anvil keeps its own probe instead of `needs_landing()`. The
## behaviour only ticks an effect after landing when needs_landing() is true,
## but the mass override must happen on the first armed tick (the anvil has
## to be heavy when it hits), so the effect polls the probe itself.
const _PROBE_META: StringName = &"anvil_landed_probe"


## One-shot mass override on the first armed tick (mid-fall mass changes do
## not alter the trajectory), then feeds this block's landing probe.
func physics_tick(block: Block, _behavior: SpecialBehavior, delta: float) -> void:
	if not block.has_meta(_MASS_APPLIED_META):
		block.mass = mass
		block.set_meta(_MASS_APPLIED_META, true)
	var probe: LandedProbe = _probe_for(block)
	probe.update(block, delta)


## Triggers once the anvil has actually landed (velocity/timeout probe, see
## LandedProbe), not on a timer. A hard landing satisfying
## SpecialBehavior's arm_impulse check can still trigger it earlier.
func wants_early_trigger(block: Block, _behavior: SpecialBehavior) -> bool:
	if block == null or not block.has_meta(_PROBE_META):
		return false
	return (block.get_meta(_PROBE_META) as LandedProbe).has_landed()


## Dips the disc at the point the anvil landed, via MatchContext.field() -- a
## SpecialEffect has no scene-tree handle of its own. DiscForce.apply() is a
## no-op at the exact disc centre and while the field's tilt is disabled.
func detonate(block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	DiscForce.apply(MatchContext.current().field(), block.global_position, 1.0, disc_force, 0.0)


func _probe_for(block: Block) -> LandedProbe:
	if block.has_meta(_PROBE_META):
		return block.get_meta(_PROBE_META) as LandedProbe
	var probe: LandedProbe = LandedProbe.new(landed)
	block.set_meta(_PROBE_META, probe)
	return probe
