class_name BlockFactory
extends RefCounted
## Builds a Block (RigidBody3D) from a BlockShape resource (spec 3.6, 2.4):
## a compound of BoxShape3D per cube (ConvexPolygonShape3D for any
## `sloped_cells`), mass = cube count * cube_mass, and a generated mesh.
##
## Lives in game/, not core/, because it creates scene-tree nodes
## (RigidBody3D, CollisionShape3D, MeshInstance3D); CLAUDE.md keeps core/free
## of scene-tree dependence.
##
## DECISION (game/BlockFactory.gd, Bontago-mv0.17 item 2 -- owner feel report
## "remove the wedge block"): config/blocks/wedge.tres is deleted (it was the
## only shape ever setting `sloped_cells`), but the sloped-cell branch below
## (`_make_collision_shape`/`_make_visual_mesh`) stays. It is dead code today,
## not load-bearing for anything shipped, but it is generic per-cell geometry
## with no wedge-specific assumptions baked in, so keeping it costs nothing
## and preserves the ramp capability for a future shape/special without
## redoing this convex-hull math. Deleting it was not required to remove the
## wedge shape itself.
##
## Bontago-xtq.3 (owner feel report "our blocks are made up of many smaller
## blocks, is that necessary? the original just has solid shapes"): the
## visual side of build()/build_visual_only() below now adds exactly one
## MeshInstance3D per block/ghost, built by core/blocks/BlockMeshBuilder.gd
## from the shape's own cells with interior faces removed, instead of one
## MeshInstance3D (and visible seam) per cell. Collision is unchanged -- still
## one CollisionShape3D per cell, a compound of boxes -- since the physics
## shape was never the thing the owner was seeing.

const BLOCK_SCENE: PackedScene = preload("res://game/Block.tscn")

## Bontago-mv0.11 (owner-reported playability): one StandardMaterial3D per
## owner colour, shared by every mesh of every block that colour ever builds,
## instead of a new material per block. Keyed by the Color itself (Godot's
## Dictionary supports Color keys directly); never cleared, since the whole
## project palette is MatchConfig.player_colors' fixed 8 entries plus
## Color.WHITE for the M1/no-owner call sites -- at most 9 materials for the
## life of the process.
static var _materials_by_color: Dictionary = {}


## `owner_slot` defaults to -1 so M1's call sites (no player slots yet) keep
## compiling unchanged; M2's Match.request_place is the first caller to pass
## a real slot id (spec 2.2 "height credit"). `color` defaults to white for
## the same reason -- a block built with no colour looks exactly as it did
## before Bontago-mv0.11.
static func build(shape: BlockShape, tuning: PhysicsTuning, owner_slot: int = -1, color: Color = Color.WHITE) -> Block:
	var block: Block = BLOCK_SCENE.instantiate()
	block.shape_id = shape.id
	block.cube_count = shape.cells.size()
	block.owner_slot = owner_slot

	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.friction = tuning.block_friction
	material.bounce = tuning.block_bounce
	block.physics_material_override = material
	block.mass = tuning.cube_mass * maxf(float(shape.cells.size()), 1.0)
	# DECISION (game/BlockFactory.gd): RigidBody3D's damp modes default to
	# COMBINE, which ADDS the body's value to physics/3d/default_linear_damp.
	# REPLACE makes the PhysicsTuning number the actual damping, so the
	# terminal fall velocity quoted in PhysicsTuning.gd (g / damp) is the real
	# one and doesn't silently change if a project default is edited.
	block.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	block.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	block.linear_damp = tuning.block_linear_damp
	block.angular_damp = tuning.block_angular_damp
	# Bontago-mv0.18 (in-game tuning panel, spec 2.8 "Gravity 0.5x-2x"): a
	# per-body multiplier rather than PhysicsServer3D.area_set_param() on the
	# world's default gravity area -- gravity_scale is a plain RigidBody3D
	# property this factory already owns end to end, needs no World3D/space
	# lookup, and covers every future spawn automatically since every block
	# reads the same shared `tuning` instance ui/TuningPanel.gd edits live (see
	# Block.apply_physics_tuning() for the matching live-apply path on blocks
	# that already exist).
	block.gravity_scale = tuning.gravity_multiplier

	var visual_material: StandardMaterial3D = _material_for_color(color)
	var half_size: float = (tuning.cube_size - tuning.cube_margin) * 0.5
	# Bontago-mv0.17 item 3 (was Bontago-mv0.12's geometric centre): cells are
	# built around the shape's bottom-centre, not raw cell (0, 0, 0) -- see
	# BlockShape.bottom_center()'s own doc comment. This is what makes the
	# body's own local origin (0, 0, 0) coincide with the shape's own bottom
	# face, matching the ghost's visual (build_visual_only() below) and the
	# pivot autoload/Match.gd's request_place() now spawns at.
	var pivot: Vector3 = shape.bottom_center()
	for cell: Vector3i in shape.cells:
		var local_pos: Vector3 = (Vector3(cell) - pivot) * tuning.cube_size
		var is_sloped: bool = shape.sloped_cells.has(cell)

		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = _make_collision_shape(half_size, is_sloped)
		collision.position = local_pos
		block.add_child(collision)

	_add_shape_visual(block, shape, tuning, visual_material)

	return block


## Builds just the visuals for a shape (no RigidBody3D, no collision) as a
## plain Node3D with one MeshInstance3D for the whole shape (Bontago-xtq.3).
## Used by GhostPreview so the held block's look matches the real one without
## simulating physics for it. Offset by the shape's bottom-centre exactly
## like build() above, so the ghost's visual and the spawned body agree on
## where the shape's bottom face sits relative to this node's own origin
## (Bontago-mv0.17 item 3, was Bontago-mv0.12's geometric centre);
## GhostPreview's own tint material is applied by the caller
## (_apply_material_to_visual()), never here, per this package's "keep the
## ghost's own tint logic untouched" -- it still works unchanged because it
## walks every MeshInstance3D child, and there is now just one.
static func build_visual_only(shape: BlockShape, tuning: PhysicsTuning) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "ShapeVisual"
	_add_shape_visual(root, shape, tuning, null)
	return root


## Adds the visual MeshInstance3D(s) for `shape` to `parent`. The common path
## (Bontago-xtq.3): one MeshInstance3D holding a BlockMeshBuilder-generated
## mesh for the whole shape, with interior faces already removed. Falls back
## to the pre-existing one-mesh-per-cell path (`material` per cell, no face
## culling) only for a shape BlockMeshBuilder.build_mesh() refuses -- see its
## own doc comment for exactly when that is (sloped_cells or a custom
## shape.mesh, neither used by any shipped shape today).
static func _add_shape_visual(
	parent: Node3D, shape: BlockShape, tuning: PhysicsTuning, material: StandardMaterial3D
) -> void:
	var combined_mesh: ArrayMesh = BlockMeshBuilder.build_mesh(shape, tuning.cube_size, tuning.cube_margin)
	if combined_mesh != null:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = combined_mesh
		mesh_instance.material_override = material
		parent.add_child(mesh_instance)
		return

	var half_size: float = (tuning.cube_size - tuning.cube_margin) * 0.5
	var pivot: Vector3 = shape.bottom_center()
	for cell: Vector3i in shape.cells:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		var is_sloped: bool = shape.sloped_cells.has(cell)
		var mesh: Mesh = shape.mesh if shape.mesh != null else _make_visual_mesh(half_size, is_sloped)
		mesh_instance.mesh = mesh
		mesh_instance.material_override = material
		mesh_instance.position = (Vector3(cell) - pivot) * tuning.cube_size
		parent.add_child(mesh_instance)


static func _material_for_color(color: Color) -> StandardMaterial3D:
	if _materials_by_color.has(color):
		return _materials_by_color[color]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	_materials_by_color[color] = material
	return material


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
