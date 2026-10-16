extends GutTest
## Checks BlockFactory's output shape (mass, collision/mesh count) against
## the numbers in spec 1.4 and config/physics/physics_tuning.tres.

var _tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")


func test_cube_mass_and_shape_count() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	assert_eq(block.cube_count, 1)
	assert_almost_eq(block.mass, _tuning.cube_mass * 1.0, 0.0001)
	assert_eq(_count_children_of_type(block, "CollisionShape3D"), 1)
	# the outline is a next_pass on the BlockMesh material.
	assert_eq(_count_children_of_type(block, "MeshInstance3D"), 1)


func test_bar4_mass_and_shape_count() -> void:
	var shape: BlockShape = load("res://config/blocks/bar4.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	assert_eq(block.cube_count, 4)
	assert_almost_eq(block.mass, _tuning.cube_mass * 4.0, 0.0001)
	assert_eq(_count_children_of_type(block, "CollisionShape3D"), 4)
	# one solid mesh for the whole shape, not one per cell --
	# see game/blocks/BlockFactory.gd's DECISION and core/blocks/BlockMeshBuilder.gd.
	# the outline is a next_pass on that mesh's material,
	# not a second MeshInstance3D.
	assert_eq(_count_children_of_type(block, "MeshInstance3D"), 1)


## Requirement: "our blocks are made up of many smaller
## blocks, is that necessary? the original just has solid shapes": every
## multi-cube shape now renders as exactly one solid MeshInstance3D, whatever
## its cube_count, both for a spawned Block and for the ghost-only visual.
## a spawned Block's solid mesh additionally gets its own
## outline MeshInstance3D (sharing that same one solid ArrayMesh, see
## game/blocks/BlockFactory.gd's own DECISION comment) -- the ghost-only visual does
## not, so it stays at exactly one.
func test_every_shape_builds_exactly_one_mesh_instance_regardless_of_cube_count() -> void:
	for shape: BlockShape in BlockShape.load_all_shapes():
		var block: Block = autofree(BlockFactory.build(shape, _tuning))
		assert_eq(
			_count_children_of_type(block, "MeshInstance3D"), 1,
			"%s (cube_count=%d) should build exactly one MeshInstance3D (outline is a next_pass)." % [shape.id, shape.cells.size()]
		)
		assert_eq(_count_children_of_type(block, "CollisionShape3D"), shape.cells.size())
		var visual: Node3D = autofree(BlockFactory.build_visual_only(shape, _tuning))
		assert_eq(_count_children_of_type(visual, "MeshInstance3D"), 1, "%s ghost visual" % shape.id)


func test_boxes_are_shrunk_by_the_margin() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	var collision: CollisionShape3D = null
	for child: Node in block.get_children():
		if child is CollisionShape3D:
			collision = child
			break
	assert_not_null(collision)
	var box: BoxShape3D = collision.shape as BoxShape3D
	assert_not_null(box, "cube.tres should collide with a BoxShape3D.")
	var expected_edge: float = _tuning.cube_size - _tuning.cube_margin
	assert_almost_eq(box.size.x, expected_edge, 0.0001)
	assert_almost_eq(box.size.y, expected_edge, 0.0001)
	assert_almost_eq(box.size.z, expected_edge, 0.0001)


func test_physics_material_matches_tuning() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	assert_almost_eq(block.physics_material_override.friction, _tuning.block_friction, 0.0001)
	assert_almost_eq(block.physics_material_override.bounce, _tuning.block_bounce, 0.0001)


# --- (in-game tuning panel, spec 1.9 "Gravity 0.5x-2x") -------


# --- rebound damping: BlockFactory wires its own tuning ----


## A dedicated PhysicsTuning instance, not the shared preloaded resource (see
## test_playercontroller_mouse.gd's matching CameraTuning comment on why),
## since this test's whole point is a *non-default* multiplier.
func test_gravity_scale_follows_a_custom_multiplier() -> void:
	var custom_tuning: PhysicsTuning = PhysicsTuning.new()
	custom_tuning.gravity_multiplier = 1.6
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, custom_tuning))
	assert_almost_eq(block.gravity_scale, 1.6, 0.0001)


func _count_children_of_type(node: Node, type_name: String) -> int:
	var count: int = 0
	for child: Node in node.get_children():
		if child.get_class() == type_name:
			count += 1
	return count


# --- player-coloured blocks -----


# --- fix round (review MAJOR): the "contributing to territory --
# --- influence" glow seam now lives on Block itself, not written directly ---
# --- from inside BlockFactory.build() -----------------------------------------


# --- pivot is the shape's --
# --- geometric centre, not cell (0, 0, 0) ------------------------------------

func _combined_local_aabb(root: Node3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	for child: Node in root.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var mesh_aabb: AABB = mesh_instance.mesh.get_aabb()
		mesh_aabb.position += mesh_instance.position
		if first:
			result = mesh_aabb
			first = false
		else:
			result = result.merge(mesh_aabb)
	return result


## Every BlockShape whose cells don't straddle the origin symmetrically (bar3,
## domino, L3, L4, T4, S4, pillar...) used to hang off the cursor and rotate
## about the wrong point, because build_visual_only() placed
## cell (0, 0, 0) at this node's own origin instead of the shape's centre.
##
## The pivot moved from the shape's geometric centre to
## its bottom-centre (half the block used to sink below
## the cursor point), so this node's own origin (0, 0, 0) must now be the
## visual AABB's x/z centre AND its bottom face -- not its full 3D centre.
## GhostPreview.update_placement() positions this node's origin at the
## (rotation-compensated) cursor height; see BlockShape.bottom_center()'s own
## doc comment for why.
func test_ghost_visual_bottom_sits_at_this_nodes_own_origin_for_every_shape() -> void:
	for shape: BlockShape in BlockShape.load_all_shapes():
		var visual: Node3D = autofree(BlockFactory.build_visual_only(shape, _tuning))
		var aabb: AABB = _combined_local_aabb(visual)
		var bottom_center_xz: Vector2 = Vector2(
			aabb.position.x + aabb.size.x * 0.5, aabb.position.z + aabb.size.z * 0.5
		)
		assert_true(
			bottom_center_xz.is_equal_approx(Vector2.ZERO),
			"%s's visual AABB should be x/z-centred on this node's own origin, got %s" % [shape.id, bottom_center_xz]
		)
		# the collision/visual box is shrunk by cube_margin
		# (spec 1.4's "so neighboring blocks don't jam"), so the bottom face
		# sits half that margin above y = 0, not exactly on it -- see
		# BlockFactory.build()'s half_size math. The tolerance is exactly
		# that half-margin, not a loose fudge factor.
		assert_almost_eq(
			aabb.position.y, 0.0, _tuning.cube_margin * 0.5 + 0.0001,
			"%s's visual AABB bottom should sit at this node's own origin y = 0, got %s" % [shape.id, aabb.position.y]
		)


## The spawned body must land exactly where the ghost showed: BlockFactory.
## build() offsets every cell by the same shape.bottom_center() as
## build_visual_only() above, so a real block's per-cell local offsets match
## its ghost's, cell for cell, for every shape in the project.
func test_built_blocks_use_the_same_cell_offsets_as_their_ghost_visual() -> void:
	for shape: BlockShape in BlockShape.load_all_shapes():
		var block: Block = autofree(BlockFactory.build(shape, _tuning))
		var visual: Node3D = autofree(BlockFactory.build_visual_only(shape, _tuning))

		var block_positions: Array[Vector3] = []
		for child: Node in block.get_children():
			# "BlockOutline" is excluded -- it is a rendering-
			# only outline pass sharing the exact same ArrayMesh (and the exact
			# same node position) as "BlockMesh", not a distinct cell placement,
			# so it must not be double-counted against the ghost's one entry.
			if child is MeshInstance3D:
				block_positions.append((child as MeshInstance3D).position)
		var visual_positions: Array[Vector3] = []
		for child: Node in visual.get_children():
			visual_positions.append((child as MeshInstance3D).position)

		assert_eq(block_positions.size(), visual_positions.size(), "%s" % shape.id)
		for pos: Vector3 in visual_positions:
			assert_true(
				block_positions.any(func(p: Vector3) -> bool: return p.is_equal_approx(pos)),
				"%s: the built block is missing the ghost's cell offset %s" % [shape.id, pos]
			)


## item 3: autoload/Match.gd's request_place() spawns every
## block with `block.global_transform = Transform3D(basis, world_origin)`,
## where world_origin is the ghost's own (bottom-pivoted) position -- so a
## real spawned body's AABB bottom must land at exactly that requested
## height, for every shape, the same way the ghost visual's does above.
func test_body_aabb_bottom_matches_the_requested_spawn_height() -> void:
	var spawn_origin: Vector3 = Vector3(3.0, 7.0, -2.0)
	for shape: BlockShape in BlockShape.load_all_shapes():
		var block: Block = autofree(BlockFactory.build(shape, _tuning))
		block.global_transform = Transform3D(Basis.IDENTITY, spawn_origin)
		var aabb: AABB = _combined_local_aabb(block)
		var world_bottom_y: float = spawn_origin.y + aabb.position.y
		assert_almost_eq(
			world_bottom_y, spawn_origin.y, _tuning.cube_margin * 0.5 + 0.0001,
			(
				"%s: spawning at y = %s should put its AABB bottom at (within margin of) that same height, got %s"
				% [shape.id, spawn_origin.y, world_bottom_y]
			)
		)
