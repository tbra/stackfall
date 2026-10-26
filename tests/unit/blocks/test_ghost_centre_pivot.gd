extends GutTest
## Requirement: "when rotating the block the camera
## adjusts; lock the camera to the center of the box without messing up the
## bottom center": GhostPreview.rotated_center_offset()/rotated_center_world()
## must keep the *rotated* held shape's own geometric centre over the cursor
## as it spins -- the thing game/player/CameraRig.gd's follow target now tracks --
## while _rotated_bottom_offset()'s existing bottom-centre fix (the shape's
## lowest point always lands at the reported hover height) stays exactly as
## it was. See game/player/GhostPreview.gd's own DECISION header for the full story.

const _CORNER_SIGNS: Array[Vector3] = [
	Vector3(-1.0, -1.0, -1.0), Vector3(1.0, -1.0, -1.0), Vector3(-1.0, 1.0, -1.0), Vector3(1.0, 1.0, -1.0),
	Vector3(-1.0, -1.0, 1.0), Vector3(1.0, -1.0, 1.0), Vector3(-1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0),
]


func _make_ghost(shape_path: String, parent: Node = self) -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	ghost.name = &"Ghost"
	parent.add_child(ghost)
	ghost.set_shape(load(shape_path))
	return ghost


## Every rotated corner of `ghost`'s own held shape, in world space -- built
## purely from the public surface (collision_box_local_centers()/
## collision_half_size(), basis, global_position), not GhostPreview's private
## _CORNER_SIGNS/_rotated_bottom_offset() table, so this is a genuine
## regression check against the shipped API, not a tautology against the
## implementation it is pinning.
func _rotated_world_corners(ghost: GhostPreview) -> Array[Vector3]:
	var half_size: float = ghost.collision_half_size()
	var corners: Array[Vector3] = []
	for center: Vector3 in ghost.collision_box_local_centers():
		for corner_sign: Vector3 in _CORNER_SIGNS:
			corners.append(ghost.global_position + ghost.basis * (center + corner_sign * half_size))
	return corners


func _min_world_y(corners: Array[Vector3]) -> float:
	var min_y: float = INF
	for corner: Vector3 in corners:
		min_y = minf(min_y, corner.y)
	return min_y


# --- free-quaternion rotation (rotate_drag) -----------------------------------

func test_free_rotation_spins_the_centre_in_place_and_keeps_the_bottom_fix() -> void:
	var ghost: GhostPreview = _make_ghost("res://config/blocks/bar4.tres")
	var surface_point: Vector3 = Vector3(2.0, 5.0, -3.0)

	ghost.apply_free_rotation_delta(0.7, 1.1, Vector3.RIGHT)
	ghost.update_placement(surface_point, Vector3.UP)

	# (a) the rotated shape's own geometric centre -- not the node's own
	# swinging origin -- stays over the cursor's XZ.
	var center_world: Vector3 = ghost.rotated_center_world()
	assert_almost_eq(center_world.x, surface_point.x, 0.0001, "the rotated centre must spin in place, not drift off the cursor's X.")
	assert_almost_eq(center_world.z, surface_point.z, 0.0001, "the rotated centre must spin in place, not drift off the cursor's Z.")

	# Regression proof this isn't vacuous: the node's own origin (still the
	# unrotated bottom-centre pivot) really did move off the cursor once
	# rotated -- that's the swing the user reported the camera following.
	assert_true(
		not is_equal_approx(ghost.global_position.x, surface_point.x) or not is_equal_approx(ghost.global_position.z, surface_point.z),
		"fixture: a pitched/yawed bar's own node origin should have swung off the cursor's XZ -- otherwise this test isn't exercising the bug."
	)

	# (b) the bottom-centre fix must be untouched:
	# the rotated shape's own lowest point still rests exactly at the
	# reported hover height.
	var expected_bottom: float = surface_point.y + ghost.tuning.hover_height
	var actual_bottom: float = _min_world_y(_rotated_world_corners(ghost))
	assert_almost_eq(actual_bottom, expected_bottom, 0.0001, "rotating must never move the shape's own rotated lowest point off the reported hover height.")


# --- Spawn parity: the real placement path spawns exactly what the ghost
# showed (see MatchPlacement._spawn_block()'s own comment: world_origin/basis
# straight from the ghost's own global_position/orientation_index/
# free_quaternion). The test spawns a block from the intent the controller sent
# through the FakeMatchContext with that same math, so a ghost_place press exercises the
# intent -> spawn contract without the full Match autoload's territory/feed state. ---

func test_spawned_block_matches_the_rotated_ghosts_own_geometry() -> void:
	var blocks_root: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks_root)

	var shape: BlockShape = load("res://config/blocks/bar4.tres")
	var holder: Node = Node.new()
	add_child_autofree(holder)
	var ghost: GhostPreview = autofree(GhostPreview.new())
	ghost.name = &"Ghost"
	holder.add_child(ghost)
	ghost.set_shape(shape)
	ghost.set_orientation_index(BlockOrientations.step_pitch_fwd(0))  # "pitch a bar 90 degrees" (manual step)

	var context: FakeMatchContext = FakeMatchContext.new()
	context.held_shape_by_slot[0] = shape
	var controller: PlayerController = autofree(PlayerController.new())
	controller.ghost_path = NodePath("../Ghost")
	controller.match_context = context
	holder.add_child(controller)
	controller.set_acting_slot(0)

	var surface_point: Vector3 = Vector3(1.5, 3.0, -2.5)
	ghost.update_placement(surface_point, Vector3.UP)
	var expected_center_xz: Vector2 = Vector2(ghost.rotated_center_world().x, ghost.rotated_center_world().z)
	var expected_bottom_y: float = _min_world_y(_rotated_world_corners(ghost))

	controller._unhandled_input(_ghost_place_event())

	assert_eq(context.submit_place_calls.size(), 1, "fixture: one ghost_place press sends exactly one intent.")
	var intent: Dictionary = context.submit_place_calls[0]
	var placed: Block = BlockFactory.build(shape, ghost.tuning)
	blocks_root.add_child(placed)
	placed.global_position = intent["origin"] as Vector3
	placed.global_transform.basis = (
		Basis(intent["free_quat"] as Quaternion) * BlockOrientations.get_basis(int(intent["orientation_index"]))
	)

	assert_eq(blocks_root.get_child_count(), 1, "fixture: the intent should have spawned exactly one block.")
	var block: Block = blocks_root.get_child(0) as Block
	assert_not_null(block)

	# The spawned body's own collision boxes, read straight off its real
	# CollisionShape3D children (not GhostPreview's duplicated table) --
	# BlockFactory.build()'s own local_pos formula, independently.
	var half_size: float = (ghost.tuning.cube_size - ghost.tuning.cube_margin) * 0.5
	var local_centers: Array[Vector3] = []
	for child: Node in block.get_children():
		var collision: CollisionShape3D = child as CollisionShape3D
		if collision != null:
			local_centers.append(collision.position)
	assert_eq(local_centers.size(), shape.cells.size(), "fixture: one CollisionShape3D per cell.")

	var min_local: Vector3 = Vector3(INF, INF, INF)
	var max_local: Vector3 = Vector3(-INF, -INF, -INF)
	var min_y: float = INF
	for center: Vector3 in local_centers:
		min_local.x = minf(min_local.x, center.x)
		min_local.y = minf(min_local.y, center.y)
		min_local.z = minf(min_local.z, center.z)
		max_local.x = maxf(max_local.x, center.x)
		max_local.y = maxf(max_local.y, center.y)
		max_local.z = maxf(max_local.z, center.z)
		for corner_sign: Vector3 in _CORNER_SIGNS:
			var world_corner: Vector3 = block.global_position + block.global_transform.basis * (center + corner_sign * half_size)
			min_y = minf(min_y, world_corner.y)
	var center_local: Vector3 = (min_local + max_local) * 0.5
	var block_center_world: Vector3 = block.global_position + block.global_transform.basis * center_local

	assert_almost_eq(block_center_world.x, expected_center_xz.x, 0.0001, "the spawned block's own geometric centre X should match the ghost's rotated_center_world().")
	assert_almost_eq(block_center_world.z, expected_center_xz.y, 0.0001, "the spawned block's own geometric centre Z should match the ghost's rotated_center_world().")
	assert_almost_eq(min_y, expected_bottom_y, 0.0001, "the spawned block's own lowest collision corner should rest exactly where the ghost showed it.")


# --- Collision sweep must target the same point update_placement() will
# actually render (game/player/PlayerController.gd's _clamp_cursor_collision(),
# point 3: "confirm nothing else assumed origin == cursor")
# -------------------------------------------------------------------------

func _small_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_ghost_centre_pivot_disk"
	map_def.field_radius = 12.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 16
	return map_def


## ghost_place the way a gamepad A press reaches the controller (the Input Map action).
func _ghost_place_event() -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = JOY_BUTTON_A
	event.pressed = true
	return event


func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.relative = relative
	return event


## A rotation whose axis has both X and Z components (unlike
## test_ghost_collision.gd's pure world-X pitch): held-shape's own unrotated
## centre offset is always purely +Y (rotated_center_offset()'s own doc
## comment), so only a rotation axis that itself isn't purely world up/right
## produces a centre offset with *both* X and Z components nonzero --
## precisely the case a single fixed world axis (e.g. "pitch about RIGHT")
## can never exercise, but a real rotate_drag (whose pitch axis follows
## whatever way the camera currently faces) routinely does.
func _diagonal_rotated_ghost(shape_path: String, parent: Node) -> GhostPreview:
	var ghost: GhostPreview = _make_ghost(shape_path, parent)
	ghost.apply_free_rotation_delta(0.0, 0.9, Vector3(1.0, 0.0, 1.0).normalized())
	return ghost


func test_collision_sweep_stops_the_rendered_rotated_shape_clear_of_a_placed_block() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = _small_map()
	add_child_autofree(field)

	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	# Same (proven) resting spot test_ghost_collision.gd's own fixtures use
	# (field_radius=12, disk_height=1.0) -- (4.0, *, 0.0), not (4, *, 4), so
	# the block actually lands on the disk instead of missing it.
	var block: Block = BlockFactory.build(load("res://config/blocks/cube.tres"), tuning)
	field.get_parent().add_child(block)
	autofree(block)
	block.global_position = Vector3(4.0, 5.0, 0.0)
	for _i: int in range(90):
		await get_tree().physics_frame
	block.sleeping = true

	var ghost_tuning: GhostTuning = GhostTuning.new()
	var holder: Node = Node.new()
	add_child_autofree(holder)
	var ghost: GhostPreview = _diagonal_rotated_ghost("res://config/blocks/bar3.tres", holder)
	var center_offset: Vector3 = ghost.rotated_center_offset()
	assert_ne(center_offset.x, 0.0, "fixture: the diagonal rotation should give the centre offset a real X component.")
	assert_ne(center_offset.z, 0.0, "fixture: the diagonal rotation should give the centre offset a real Z component.")

	var controller: PlayerController = autofree(PlayerController.new())
	controller.ghost_path = NodePath("../Ghost")
	controller.ghost_tuning = ghost_tuning
	holder.add_child(controller)
	controller._process(1.0 / 60.0)
	controller._unhandled_input(_motion(Vector2(-40.0, 0.0)))  # to x = -2 m at the default sensitivity
	controller._process(1.0 / 60.0)

	# Pure +X cursor motion (like test_ghost_collision.gd's own pitched-shape
	# test), same coordinates -- the *rotation*, not the sweep path, is what
	# gives the centre offset a Z component too, so this alone is enough to
	# show a Z mismatch between the swept box and the rendered one.
	for _i: int in range(220):
		controller._unhandled_input(_motion(Vector2(50.0, 0.0)))
		controller._process(1.0 / 60.0)

	# The actually-rendered boxes (ghost.global_position is what
	# update_placement() really set, centre-offset and all) must still clear
	# the block -- if _clamp_cursor_collision() had swept the *cursor's* raw
	# position instead of the point the rotated centre actually renders at,
	# this render would land closer to (or inside) the block than what was
	# validated. Queried through the real physics world with the ghost's own
	# rotated box transform (the boxes are no longer axis-aligned once
	# diagonally rotated, so a hand-rolled AABB check here would be wrong;
	# this is exactly the intersect_shape() query game/player/PlayerController.gd's
	# own _cast_one_box() uses).
	var half_size: float = ghost.collision_half_size()
	var space_state: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3.ONE * (half_size * 2.0)
	var any_overlap: bool = false
	for local_center: Vector3 in ghost.collision_box_local_centers():
		var world_center: Vector3 = ghost.global_position + ghost.basis * local_center
		var probe: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		probe.shape = box_shape
		probe.transform = Transform3D(ghost.basis, world_center)
		probe.collide_with_bodies = true
		probe.collide_with_areas = false
		var overlaps: Array[Dictionary] = space_state.intersect_shape(probe, 8)
		for overlap: Dictionary in overlaps:
			if overlap.get("collider") == block:
				any_overlap = true
	assert_false(
		any_overlap,
		"the rendered (centre-offset) rotated shape must never overlap the placed block."
	)
	assert_true(block.sleeping, "the placed block must never wake from the ghost's shape queries.")

	# Not a vacuous non-approach: the sweep really did engage (the rendered
	# shape stopped near the block, not far off in the distance where this
	# test wouldn't have caught the bug it's pinned against).
	var nearest_local_center: Vector3 = ghost.collision_box_local_centers()[0]
	var nearest_world_center: Vector3 = ghost.global_position + ghost.basis * nearest_local_center
	assert_lt(
		nearest_world_center.distance_to(block.global_position), tuning.cube_size * 6.0,
		"fixture: the diagonal press should have stopped the rendered shape close to the block, not far away."
	)
