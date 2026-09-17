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
