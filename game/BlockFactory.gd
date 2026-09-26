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
##
## Bontago-xtq.27 (M7 P2, spec 2.10 as amended, owner decision 2026-09-26
## Bontago-5h7 Q1/Q2): a real spawned block now carries a *second*
## MeshInstance3D (named "BlockOutline") sharing that exact same ArrayMesh --
## an inverted-hull outline pass, shaders/block_outline.gdshader -- in
## addition to the primary one (named "BlockMesh"), whose material is now
## shaders/block_cell_grid.gdshader (toon-banded diffuse + UV-edge cell-grid
## lines + a per-instance "contributing" glow toggle). The mesh geometry
## itself, and the ghost-only ("BlockOutline"-less) path through
## build_visual_only(), are unchanged -- see _add_shape_visual()'s own
## DECISION comment for why the outline is gated to real blocks only.

const BLOCK_SCENE: PackedScene = preload("res://game/Block.tscn")
const CELL_GRID_SHADER: Shader = preload("res://shaders/block_cell_grid.gdshader")
const OUTLINE_SHADER: Shader = preload("res://shaders/block_outline.gdshader")
const VISUAL_TUNING: BlockVisualTuning = preload("res://config/block_visual_tuning.tres")

## Bontago-mv0.11 (owner-reported playability), extended by Bontago-xtq.27:
## one ShaderMaterial (shaders/block_cell_grid.gdshader) per owner colour,
## shared by every mesh of every block that colour ever builds, instead of a
## new material per block. Keyed by the Color itself (Godot's Dictionary
## supports Color keys directly); never cleared, since the whole project
## palette is MatchConfig.player_colors' fixed 8 entries plus Color.WHITE for
## the M1/no-owner call sites -- at most 9 materials for the life of the
## process.
static var _materials_by_color: Dictionary = {}

## Bontago-xtq.27: the outline pass's own ShaderMaterial never varies by
## owner colour (outline_color/outline_width_m are both plain
## BlockVisualTuning fields, not per-player), so exactly one instance is ever
## built, lazily, the first time a real block spawns.
static var _outline_material: ShaderMaterial = null


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
	# Review fix (Bontago-xtq.17 SHOULD-FIX 3): wires `tuning` onto the Block
	# itself so Block._integrate_forces() reads THIS build's own instance
	# (a non-singleton tuning a test hands in, e.g.) instead of always
	# falling back to the shared preloaded config/physics_tuning.tres --
	# Block._ready()'s own null-check fallback stays, for a Block built
	# without going through this factory at all.
	block.tuning = tuning

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

	var visual_material: ShaderMaterial = _material_for_color(color)
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

	# Bontago-xtq.27 (M7 P2, docs/M7_PLAN.md P2's own DECISION): "contributing
	# to territory influence" has no dedicated solver signal yet this
	# milestone, so a settled/resting block reads as contributing and an
	# in-flight one doesn't -- RigidBody3D's own built-in sleeping state is the
	# proxy. Fix round (review MAJOR): this only ever reflects reality on
	# whichever peer is this body's physics authority -- a client's synced
	# blocks are frozen kinematic (net/SnapshotSync.gd's freeze_body()) and
	# never sleep for real, so client_tick() drives the same
	# Block.set_contributing_visual() seam from the wire's `sleeping` flag
	# instead (net/SnapshotSync.gd, net/Interpolator.gd). Connected
	# unconditionally rather than gated on host/authority: a client's own
	# sleeping_state_changed is simply inert (a frozen kinematic body never
	# fires it for real), so it cannot race or conflict with the wire-driven
	# call. A no-op on a ghost (build_visual_only() never calls this).
	block.set_contributing_visual(block.sleeping)
	block.sleeping_state_changed.connect(
		func() -> void: block.set_contributing_visual(block.sleeping)
	)

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
## (Bontago-xtq.3, outline added by Bontago-xtq.27): one MeshInstance3D named
## "BlockMesh" holding a BlockMeshBuilder-generated mesh for the whole shape,
## with interior faces already removed; when `material` is non-null (a real
## spawned block, never build_visual_only()'s ghost -- see that function's own
## doc comment) a second MeshInstance3D named "BlockOutline" is added sharing
## that exact same mesh resource, with the shared inverted-hull outline
## ShaderMaterial. Falls back to the pre-existing one-mesh-per-cell path
## (`material` per cell, no face culling, no outline) only for a shape
## BlockMeshBuilder.build_mesh() refuses -- see its own doc comment for
## exactly when that is (sloped_cells or a custom shape.mesh, neither used by
## any shipped shape today, so the outline pass was not extended to it).
static func _add_shape_visual(
	parent: Node3D, shape: BlockShape, tuning: PhysicsTuning, material: ShaderMaterial
) -> void:
	var combined_mesh: ArrayMesh = BlockMeshBuilder.build_mesh(shape, tuning.cube_size, tuning.cube_margin)
	if combined_mesh != null:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.name = &"BlockMesh"
		mesh_instance.mesh = combined_mesh
		mesh_instance.material_override = material
		parent.add_child(mesh_instance)

		# DECISION (game/BlockFactory.gd, Bontago-xtq.27, docs/M7_PLAN.md P2):
		# a second MeshInstance3D sharing this same ArrayMesh, not a
		# next_pass material on the primary one. next_pass still costs
		# Godot a full second render pass per block either way, but chains
		# both shaders onto ONE surface's render_mode -- the cell-grid pass
		# needs cull_back (normal) while the outline needs cull_front
		# (inverted hull); a second MeshInstance3D keeps each shader's own
		# render_mode simple and independent instead of fighting over one
		# surface's cull state. Only added for a real spawned block
		# (`material` non-null); build_visual_only()'s ghost stays at
		# exactly one MeshInstance3D so GhostPreview's own tint logic
		# (_apply_material_to_visual(), which overwrites every
		# MeshInstance3D child's material_override with one plain tint)
		# keeps working unmodified instead of stomping the outline's
		# ShaderMaterial.
		if material != null:
			var outline_instance: MeshInstance3D = MeshInstance3D.new()
			outline_instance.name = &"BlockOutline"
			outline_instance.mesh = combined_mesh
			outline_instance.material_override = _outline_material_singleton()
			outline_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(outline_instance)
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


static func _material_for_color(color: Color) -> ShaderMaterial:
	if _materials_by_color.has(color):
		return _materials_by_color[color]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = CELL_GRID_SHADER
	material.set_shader_parameter(&"albedo_color", color)
	material.set_shader_parameter(&"toon_band_count", VISUAL_TUNING.toon_band_count)
	material.set_shader_parameter(&"grid_line_width_px", VISUAL_TUNING.grid_line_width_px)
	material.set_shader_parameter(&"grid_line_color", VISUAL_TUNING.grid_line_color)
	material.set_shader_parameter(&"grid_line_glow_color", VISUAL_TUNING.grid_line_glow_color)
	material.set_shader_parameter(&"grid_line_glow_strength", VISUAL_TUNING.grid_line_glow_strength)
	_materials_by_color[color] = material
	return material


static func _outline_material_singleton() -> ShaderMaterial:
	if _outline_material == null:
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = OUTLINE_SHADER
		material.set_shader_parameter(&"outline_width_m", VISUAL_TUNING.outline_width_m)
		material.set_shader_parameter(&"outline_color", VISUAL_TUNING.outline_color)
		_outline_material = material
	return _outline_material


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
