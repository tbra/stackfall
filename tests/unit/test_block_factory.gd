extends GutTest
## Checks BlockFactory's output shape (mass, collision/mesh count) against
## the numbers in spec 2.4 and config/physics_tuning.tres.

var _tuning: PhysicsTuning = load("res://config/physics_tuning.tres")


func test_cube_mass_and_shape_count() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	assert_eq(block.cube_count, 1)
	assert_almost_eq(block.mass, _tuning.cube_mass * 1.0, 0.0001)
	assert_eq(_count_children_of_type(block, "CollisionShape3D"), 1)
	# Bontago-xtq.27: a real spawned block now carries a second MeshInstance3D
	# ("BlockOutline", inverted-hull outline pass) alongside the primary
	# ("BlockMesh") one -- see game/BlockFactory.gd's own DECISION comment.
	assert_eq(_count_children_of_type(block, "MeshInstance3D"), 2)


func test_bar4_mass_and_shape_count() -> void:
	var shape: BlockShape = load("res://config/blocks/bar4.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	assert_eq(block.cube_count, 4)
	assert_almost_eq(block.mass, _tuning.cube_mass * 4.0, 0.0001)
	assert_eq(_count_children_of_type(block, "CollisionShape3D"), 4)
	# Bontago-xtq.3: one solid mesh for the whole shape, not one per cell --
	# see game/BlockFactory.gd's DECISION and core/blocks/BlockMeshBuilder.gd.
	# Bontago-xtq.27 adds a second MeshInstance3D (the outline pass) on top of
	# that single solid mesh -- see game/BlockFactory.gd's own DECISION comment.
	assert_eq(_count_children_of_type(block, "MeshInstance3D"), 2)


## Bontago-xtq.3 (owner feel report "our blocks are made up of many smaller
## blocks, is that necessary? the original just has solid shapes"): every
## multi-cube shape now renders as exactly one solid MeshInstance3D, whatever
## its cube_count, both for a spawned Block and for the ghost-only visual.
## Bontago-xtq.27: a spawned Block's solid mesh additionally gets its own
## outline MeshInstance3D (sharing that same one solid ArrayMesh, see
## game/BlockFactory.gd's own DECISION comment) -- the ghost-only visual does
## not, so it stays at exactly one.
func test_every_shape_builds_exactly_one_mesh_instance_regardless_of_cube_count() -> void:
	for shape: BlockShape in BlockShape.load_all_shapes():
		var block: Block = autofree(BlockFactory.build(shape, _tuning))
		assert_eq(
			_count_children_of_type(block, "MeshInstance3D"), 2,
			"%s (cube_count=%d) should build exactly one solid MeshInstance3D plus its outline pass." % [shape.id, shape.cells.size()]
		)
		assert_eq(_count_children_of_type(block, "CollisionShape3D"), shape.cells.size())
		var visual: Node3D = autofree(BlockFactory.build_visual_only(shape, _tuning))
		assert_eq(_count_children_of_type(visual, "MeshInstance3D"), 1, "%s ghost visual" % shape.id)


func test_slab6_mass_and_shape_count() -> void:
	var shape: BlockShape = load("res://config/blocks/slab6.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	assert_eq(block.cube_count, 6)
	assert_almost_eq(block.mass, _tuning.cube_mass * 6.0, 0.0001)


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


# --- Bontago-mv0.18 (in-game tuning panel, spec 2.8 "Gravity 0.5x-2x") -------

func test_gravity_scale_matches_the_shared_tunings_multiplier() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	assert_almost_eq(block.gravity_scale, _tuning.gravity_multiplier, 0.0001)


# --- Bontago-xtq.17 (rebound damping): BlockFactory wires its own tuning ----

## Review fix (SHOULD-FIX 3): BlockFactory.build() sets `block.tuning =
## tuning` itself, so a non-singleton PhysicsTuning instance (not the shared
## preloaded config/physics_tuning.tres) is honored by Block._integrate_
## forces()'s rebound-damping read from the moment build() returns -- before
## the block ever joins the tree/runs _ready() at all.
func test_block_factory_build_wires_its_own_tuning_parameter_immediately() -> void:
	var custom_tuning: PhysicsTuning = PhysicsTuning.new()
	custom_tuning.rebound_damping = 0.4
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, custom_tuning))
	assert_same(
		block.tuning, custom_tuning,
		"BlockFactory.build() must wire its own tuning parameter onto the Block, not leave it null until _ready()."
	)


## The shared preloaded config/physics_tuning.tres instance every real spawn
## path uses is what build() wires on (test's own `_tuning` is `load()`ed
## from the same path, and Godot caches a Resource by path within one
## process -- ui/TuningPanel.gd's own class doc relies on the same fact) --
## _ready()'s own null-check fallback (see Block.gd) never even needs to run
## for this, since `tuning` is already non-null by the time build() returns.
func test_block_ready_wires_the_shared_physics_tuning_singleton() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	add_child_autofree(block)  # runs _ready()
	assert_same(block.tuning, load("res://config/physics_tuning.tres"))


func test_block_ready_does_not_overwrite_a_tuning_set_before_it_joined_the_tree() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	var custom_tuning: PhysicsTuning = PhysicsTuning.new()
	block.tuning = custom_tuning
	add_child_autofree(block)  # runs _ready()
	assert_same(block.tuning, custom_tuning)


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


func _first_mesh_instance(node: Node) -> MeshInstance3D:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			return child
	return null


# --- Bontago-mv0.11 (owner-reported playability): owner-coloured blocks -----

## Bontago-xtq.27: the primary mesh's material_override is now a ShaderMaterial
## (shaders/block_cell_grid.gdshader) rather than a StandardMaterial3D, so the
## owner colour lives in its "albedo_color" shader parameter instead of
## `.albedo_color` -- see game/BlockFactory.gd's `_material_for_color()`.
func test_block_mesh_material_matches_the_requested_color() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var color: Color = Color(0.9, 0.25, 0.25)
	var block: Block = autofree(BlockFactory.build(shape, _tuning, 0, color))
	var mesh_instance: MeshInstance3D = _first_mesh_instance(block)
	assert_not_null(mesh_instance)
	var material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	assert_not_null(material, "every mesh should carry an owner-coloured material override.")
	var albedo: Color = material.get_shader_parameter(&"albedo_color")
	assert_true(albedo.is_equal_approx(color))


func test_default_color_is_white_for_call_sites_that_dont_pass_one() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	var material: ShaderMaterial = _first_mesh_instance(block).material_override as ShaderMaterial
	assert_not_null(material)
	var albedo: Color = material.get_shader_parameter(&"albedo_color")
	assert_eq(albedo, Color.WHITE, "M1's no-owner call sites keep looking exactly as before.")


func test_two_blocks_of_the_same_slot_color_share_one_cached_material() -> void:
	var color: Color = Color(0.25, 0.55, 0.95)
	var block_a: Block = autofree(BlockFactory.build(load("res://config/blocks/cube.tres"), _tuning, 0, color))
	var block_b: Block = autofree(BlockFactory.build(load("res://config/blocks/bar4.tres"), _tuning, 1, color))

	var material_a: Material = _first_mesh_instance(block_a).material_override
	var material_b: Material = _first_mesh_instance(block_b).material_override

	assert_not_null(material_a)
	assert_eq(material_a, material_b, "one cached ShaderMaterial per colour, never one per block.")

	# Every *solid* mesh within one multi-cube block shares it too, not just
	# the first -- but Bontago-xtq.27's outline pass ("BlockOutline") is its
	# own separately-cached shared ShaderMaterial (never colour-keyed, see
	# _outline_material_singleton()), so it is excluded here and checked on
	# its own below instead.
	for child: Node in block_b.get_children():
		if child is MeshInstance3D and child.name == &"BlockMesh":
			assert_eq((child as MeshInstance3D).material_override, material_a)

	var outline_a: Material = (block_a.get_node(^"BlockOutline") as MeshInstance3D).material_override
	var outline_b: Material = (block_b.get_node(^"BlockOutline") as MeshInstance3D).material_override
	assert_not_null(outline_a)
	assert_eq(outline_a, outline_b, "the outline pass is one shared ShaderMaterial regardless of owner colour.")
	assert_ne(outline_a, material_a, "the outline pass must not be the same ShaderMaterial as the solid-mesh one.")


func test_a_different_color_gets_its_own_material() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block_red: Block = autofree(BlockFactory.build(shape, _tuning, 0, Color(0.9, 0.25, 0.25)))
	var block_blue: Block = autofree(BlockFactory.build(shape, _tuning, 1, Color(0.25, 0.55, 0.95)))
	assert_ne(_first_mesh_instance(block_red).material_override, _first_mesh_instance(block_blue).material_override)


# --- Bontago-xtq.27 fix round (review MAJOR): the "contributing to territory --
# --- influence" glow seam now lives on Block itself, not written directly ---
# --- from inside BlockFactory.build() -----------------------------------------

## A freshly built block is never already asleep, so BlockFactory.build()'s own
## initial `block.set_contributing_visual(block.sleeping)` call should leave it
## reading as non-contributing until something says otherwise.
func test_a_freshly_built_block_is_not_contributing_yet() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	assert_false(block.is_contributing_visual())


## BlockFactory.build() connects `block.sleeping_state_changed` to
## `block.set_contributing_visual(block.sleeping)` unconditionally (this
## peer's real physics authority path) -- setting `sleeping` directly and
## re-emitting the signal by hand (outside a live physics step, RigidBody3D's
## own setter is not guaranteed to fire it) exercises exactly that connection
## without needing a real physics simulation.
func test_the_glow_follows_this_blocks_own_sleeping_signal() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))

	block.sleeping = true
	block.sleeping_state_changed.emit()
	assert_true(block.is_contributing_visual(), "sleeping_state_changed(sleeping=true) should light the glow.")

	block.sleeping = false
	block.sleeping_state_changed.emit()
	assert_false(block.is_contributing_visual(), "sleeping_state_changed(sleeping=false) should turn it back off.")


## Block.set_contributing_visual() is the seam net/SnapshotSync.gd's
## client_tick() calls directly (a client's synced body is frozen kinematic
## and never sleeps for real, so it never gets BlockFactory.build()'s own
## sleeping_state_changed connection to fire) -- checked here on its own,
## independent of BlockFactory's wiring, since it is a public method on Block.
func test_set_contributing_visual_is_a_public_seam_independent_of_the_sleeping_signal() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))

	block.set_contributing_visual(true)
	assert_true(block.is_contributing_visual())
	assert_eq(
		_first_mesh_instance(block).get_instance_shader_parameter(&"contributing"), true,
		"the BlockMesh instance shader parameter must reflect it too, not just the cached flag."
	)

	block.set_contributing_visual(false)
	assert_false(block.is_contributing_visual())
	assert_eq(_first_mesh_instance(block).get_instance_shader_parameter(&"contributing"), false)


# --- Bontago-mv0.12 (owner-reported playability): the pivot is the shape's --
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
## about the wrong point (Bontago-mv0.12), because build_visual_only() placed
## cell (0, 0, 0) at this node's own origin instead of the shape's centre.
##
## Bontago-mv0.17 item 3: the pivot moved from the shape's geometric centre to
## its bottom-centre (owner feel report: half the block used to sink below
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
		# Bontago-mv0.17: the collision/visual box is shrunk by cube_margin
		# (spec 2.4's "so neighboring blocks don't jam"), so the bottom face
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
			# Bontago-xtq.27: "BlockOutline" is excluded -- it is a rendering-
			# only outline pass sharing the exact same ArrayMesh (and the exact
			# same node position) as "BlockMesh", not a distinct cell placement,
			# so it must not be double-counted against the ghost's one entry.
			if child is MeshInstance3D and child.name != &"BlockOutline":
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


## Bontago-mv0.17 item 3: autoload/Match.gd's request_place() spawns every
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
