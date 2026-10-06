class_name VolcanoOrbEffect
extends SpecialEffect
## The small blast one Volcano lava orb runs on impact (spec 2.6: "launching a
## spray of small lava-orb blocks that each explode"). Bontago-1pi.85.14 moved it
## onto ExplosionFx (mass-independent delta-v) with an ExplosionTuning (plan
## section 3: radius 1.5, peak 4 m/s), replacing the kg*m/s SpecialPhysics.explode.
##
## DECISION (Bontago-1pi.85.14): BlockSpawner.spawn() (the module the plan names for
## VolcanoStructure) takes no SpecialDef, so structure blocks are plain cubes today
## and nothing arms this effect yet. It stays a ready, tested building block: wiring
## it needs an optional def/tuning pair on BlockSpawner.spawn (reported to the
## orchestrator, BlockSpawner is package A2's file).

## Blast shape of one orb (radius, peak delta-v, falloff, upward bias, cap); VolcanoEffect.orb_blast hands its own in.
@export var blast: ExplosionTuning = ExplosionTuning.new()


## Blast every real RigidBody3D in range (the orb's own body excluded), then chain
## into any other armed special in range one depth deeper.
func detonate(block: Block, behavior: SpecialBehavior, chain_depth: int) -> void:
	var center: Vector3 = block.global_position
	ExplosionFx.blast(block.get_world_3d().direct_space_state, center, blast, [block.get_rid()])
	ExplosionFx.chain(behavior, center, blast.radius_m, chain_depth)
