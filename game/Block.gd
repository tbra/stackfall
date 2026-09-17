class_name Block
extends RigidBody3D
## A placed or falling block (spec 2.4, 3.6). Built by BlockFactory from a
## BlockShape; carries just enough identity for M1 (which shape it is and how
## many cubes it has). Ownership, influence, and special behavior arrive in
## later milestones.

@export var shape_id: StringName = &""
@export var cube_count: int = 0
