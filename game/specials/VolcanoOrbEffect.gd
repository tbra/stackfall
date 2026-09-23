class_name VolcanoOrbEffect
extends SpecialEffect
## The tiny explosion a single Volcano lava orb runs on impact (spec 2.6's
## Volcano row: "erupts, launching a spray of small lava-orb blocks that each
## explode"). docs/M4_SPECIALS_PACKAGES.md's P4-VOLCANO package.
##
## DECISION (game/specials/VolcanoOrbEffect.gd, docs/M4_SPECIALS_PACKAGES.md
## P4-VOLCANO): duplicates BombEffect.gd's ~5-line detonate() shape on
## purpose (the package's own explicit DECISION) rather than depending on
## P3-BOMB, so Volcano stays parallel-dispatchable against Bomb/Rocket. One
## instance is built once by VolcanoEffect.gd (see that file's
## `_orb_special_def()`) and shared by every orb that volcano spawns during
## the match -- an orb never keeps per-block state on this effect itself
## (its own arm/age/trigger state already lives on the SpecialBehavior each
## spawned orb gets, exactly like every other special).

## Reaches config/special_tuning.tres the same way BombEffect.gd/
## RocketEffect.gd do -- see BombEffect.gd's own field comment for the full
## DECISION. Overwritten by VolcanoEffect._orb_special_def() with its own
## `tuning` export (the volcano's, not necessarily the preloaded default) the
## instant this effect is built, so this preload only matters if some other
## caller ever constructs a VolcanoOrbEffect directly.
@export var tuning: SpecialTuning = preload("res://config/special_tuning.tres")

## Explosion radius in meters -- set by VolcanoEffect from its own
## `orb_explosion_radius` export (docs/M4_SPECIALS_PACKAGES.md tunables
## table: 1.5, NEW).
@export var explosion_radius: float = 1.5

## Explosion impulse magnitude fed into SpecialPhysics.explode()'s falloff,
## before tuning.max_explosion_impulse's clamp -- set by VolcanoEffect from
## `orb_impulse * orb_explosion_impulse_fraction` (see that file's own
## DECISION on what "the volcano's own explosion_impulse-equivalent" means).
@export var explosion_impulse: float = 3.0


## The moment this orb's own SpecialBehavior triggers (impact or fuse
## timeout), push every real RigidBody3D within explosion_radius, excluding
## the orb's own body, then chain into any other armed special within the
## same radius one depth deeper -- BombEffect.detonate()'s identical shape.
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
