class_name Block
extends RigidBody3D
## A placed or falling block (spec 2.4, 3.6). Built by BlockFactory from a
## BlockShape; carries just enough identity for M1 (which shape it is and how
## many cubes it has). Ownership, influence, and special behavior arrive in
## later milestones.

@export var shape_id: StringName = &""
@export var cube_count: int = 0

## M2 (spec 2.2 "height credit", 3.4): which PlayerSlot placed this block,
## permanently — territory influence and multiplayer attribution both key off
## this. -1 means "no owner", e.g. M1's placements before slots existed.
@export var owner_slot: int = -1

## M3's network id, assigned by game/BlockRegistry.gd when the block is
## registered. -1 until then.
@export var net_id: int = -1

## Bontago-mv0.18 (in-game tuning panel): every Block adds itself to this
## group in _ready() so ui/TuningPanel.gd can push a PhysicsTuning edit onto
## every block already standing, not just the next one BlockFactory builds
## (get_tree().get_nodes_in_group(TUNING_GROUP), never a game/BlockRegistry.gd
## change -- that file belongs to a different package).
const TUNING_GROUP: StringName = &"tuning_blocks"


func _ready() -> void:
	add_to_group(TUNING_GROUP)


## Re-applies every PhysicsTuning number a live body would otherwise only
## ever read once, at BlockFactory.build() time: damping, the friction/bounce
## material, and gravity_scale (spec 2.8 "Gravity 0.5x-2x" -- BlockFactory.
## build() sets gravity_scale from this same field for every new spawn;
## rewriting it here on an already-falling body only changes the acceleration
## RigidBody3D integrates on the *next* physics step, not any velocity it has
## already accumulated, so there is no visible "kick", just a smooth change in
## how fast it keeps falling from here.
func apply_physics_tuning(tuning: PhysicsTuning) -> void:
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = tuning.block_linear_damp
	angular_damp = tuning.block_angular_damp
	gravity_scale = tuning.gravity_multiplier
	var material: PhysicsMaterial = physics_material_override
	if material == null:
		material = PhysicsMaterial.new()
		physics_material_override = material
	material.friction = tuning.block_friction
	material.bounce = tuning.block_bounce
