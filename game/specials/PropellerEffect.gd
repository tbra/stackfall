class_name PropellerEffect
extends SpecialEffect
## Propeller special (spec 2.6: "stands where it lands, then lifts itself and
## blows for its duration"). docs/GIFT_EFFECTS_PLAN.md package D: Propeller is
## the Anvil in reverse. After landing (SpecialBehavior's LandedProbe, via
## needs_landing(); never Jolt `sleeping`) it runs DiscForce.apply(sign -1)
## every tick for `disc_force.duration_s`, raising the side it stands on, so
## the disc tilts the opposite way from an Anvil at the same point.
##
## DECISION (plan section 7): the literal body lift (`linear_velocity.y =
## lift_speed` every tick) is gone -- it fought Jolt and ejected/woke the
## carrier. The disc coupling is the effect; "lifts itself" survives as a
## visual-only rise of the gift model (`carrier_rise_m`), never a physics write.
##
## No per-block state lives on this shared Resource: elapsed time is
## SpecialBehavior.landed_age().

## Meta on the GiftVisual node holding its resting local Y.
const _BASE_Y_META: StringName = &"propeller_base_y"

## DiscForce tuning. `strength` is tilt impulse per metre of disc-local
## distance per second (DiscForce.apply with delta > 0); `duration_s` is how
## long the blow runs after landing.
##
## DECISION: strength 0.01 per metre per second for 3 s (0.03 per metre in
## total, 1.5x the Anvil's single 0.02-per-metre kick) because the tilt
## spring decays while a sustained push is still being applied; measured on
## the real Field the peak tilt is about 1.2x the Anvil's (0.02 gave 2.4x).
## test_propeller_effect.gd asserts it stays within 0.5x-2x.
@export var disc_force: DiscForceTuning = DiscForceTuning.new()

## Visual-only height (m) the gift model rises over the effect's duration,
## smoothstepped. Applied to the GiftVisual child only; 0 disables it.
@export var carrier_rise_m: float = 0.6


func needs_landing() -> bool:
	return true


func effect_lifetime_s() -> float:
	return disc_force.duration_s


## Raises the landing side while the effect window runs. Only called once the
## behaviour reports the carrier has landed (needs_landing()).
func physics_tick(block: Block, behavior: SpecialBehavior, delta: float) -> void:
	_apply_visual_rise(block, behavior.landed_age())
	DiscForce.apply(Match.field(), block.global_position, -1.0, disc_force, delta)


## Pure: the visual rise (m) `landed_age_s` seconds after landing.
func rise_at(landed_age_s: float) -> float:
	if disc_force.duration_s <= 0.0:
		return 0.0
	return carrier_rise_m * smoothstep(0.0, 1.0, landed_age_s / disc_force.duration_s)


## Vetoes the decel-based impact trigger entirely (Bontago-1en.22): a hard
## landing must not detonate (a no-op) before the effect ran. The end is
## time-driven (wants_early_trigger()) or a chain trigger.
func impact_triggers(_block: Block, _behavior: SpecialBehavior) -> bool:
	return false


## True once `disc_force.duration_s` has elapsed since landing.
func wants_early_trigger(_block: Block, behavior: SpecialBehavior) -> bool:
	return behavior.has_landed() and behavior.landed_age() >= disc_force.duration_s


## No-op: the blow already ran tick by tick in physics_tick().
func detonate(_block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	pass


## Moves the gift model up; the carrier body and collider are untouched.
func _apply_visual_rise(block: Block, landed_age_s: float) -> void:
	if carrier_rise_m == 0.0:
		return
	var visual: Node3D = block.get_node_or_null(NodePath(String(BlockFactory.GIFT_VISUAL_NODE))) as Node3D
	if visual == null:
		return
	if not visual.has_meta(_BASE_Y_META):
		visual.set_meta(_BASE_Y_META, visual.position.y)
	visual.position.y = float(visual.get_meta(_BASE_Y_META)) + rise_at(landed_age_s)
