class_name BlockFactory
extends RefCounted
## Builds a Block (RigidBody3D) from a BlockShape resource (spec 3.6, 2.4):
## a compound of BoxShape3D per cube (ConvexPolygonShape3D for the wedge's
## sloped cells), mass = cube count * cube_mass, and a generated mesh.
##
## Lives in game/, not core/, because it creates scene-tree nodes
## (RigidBody3D, CollisionShape3D, MeshInstance3D); CLAUDE.md keeps core/free
## of scene-tree dependence.

const BLOCK_SCENE: PackedScene = preload("res://game/Block.tscn")


static func build(shape: BlockShape, tuning: PhysicsTuning) -> Block:
	var block: Block = BLOCK_SCENE.instantiate()
	block.shape_id = shape.id
	block.cube_count = shape.cells.size()

	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.friction = tuning.block_friction
	material.bounce = tuning.block_bounce
	block.physics_material_override = material
	block.mass = tuning.cube_mass * maxf(float(shape.cells.size()), 1.0)

	var half_size: float = (tuning.cube_size - tuning.cube_margin) * 0.5
	for cell: Vector3i in shape.cells:
		var local_pos: Vector3 = Vector3(cell) * tuning.cube_size
		var is_sloped: bool = shape.sloped_cells.has(cell)

		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = _make_collision_shape(half_size, is_sloped)
		collision.position = local_pos
		block.add_child(collision)

		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		var mesh: Mesh = shape.mesh if shape.mesh != null else _make_visual_mesh(half_size, is_sloped)
		mesh_instance.mesh = mesh
		mesh_instance.position = local_pos
		block.add_child(mesh_instance)

	return block


static func _make_collision_shape(half_size: float, sloped: bool) -> Shape3D:
	if not sloped:
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3.ONE * (half_size * 2.0)
		return box

	# A right-triangular prism: full height at -Z, sloping down to zero
	# height at +Z. The physics engine builds the convex hull from these
	# 6 points, so this is a proper sloped collision shape (spec 2.4).
	var s: float = half_size
	var points: PackedVector3Array = PackedVector3Array([
		Vector3(-s, -s, -s), Vector3(s, -s, -s), Vector3(s, -s, s), Vector3(-s, -s, s),
		Vector3(-s, s, -s), Vector3(s, s, -s),
	])
	var convex: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	convex.points = points
	return convex


static func _make_visual_mesh(half_size: float, sloped: bool) -> Mesh:
	var size: Vector3 = Vector3.ONE * (half_size * 2.0)
	if not sloped:
		var box_mesh: BoxMesh = BoxMesh.new()
		box_mesh.size = size
		return box_mesh

	# DECISION (game/BlockFactory.gd): Godot's built-in PrismMesh approximates
	# the wedge's slope visually. Its axis convention isn't guaranteed to line
	# up exactly with the hand-built ConvexPolygonShape3D above, but M1 only
	# needs correct wedge physics, not pixel-accurate wedge art.
	var prism: PrismMesh = PrismMesh.new()
	prism.size = size
	return prism
