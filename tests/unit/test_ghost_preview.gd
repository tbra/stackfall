extends GutTest
## GhostPreview must apply the orientation-index + free-quaternion rotation
## correctly and never drift on reset (spec 1.7, 2.5 — M1 acceptance).


func _make_ghost() -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	return ghost


func test_default_orientation_is_identity() -> void:
	var ghost: GhostPreview = _make_ghost()
	assert_eq(ghost.orientation_index, 0)
	assert_eq(ghost.basis, Basis.IDENTITY)


func test_orientation_step_matches_table() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_orientation_index(BlockOrientations.step_yaw_ccw(0))
	assert_eq(ghost.orientation_index, BlockOrientations.step_yaw_ccw(0))
	assert_eq(ghost.basis, BlockOrientations.get_basis(ghost.orientation_index))


func test_set_orientation_index_wraps() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_orientation_index(-1)
	assert_eq(ghost.orientation_index, 23)
	ghost.set_orientation_index(24)
	assert_eq(ghost.orientation_index, 0)


func test_free_rotation_layers_on_top_of_index() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_orientation_index(BlockOrientations.step_yaw_ccw(0))
	ghost.apply_free_rotation_delta(0.3, 0.1)
	assert_ne(ghost.free_quaternion, Quaternion.IDENTITY)
	var expected: Basis = Basis(ghost.free_quaternion) * BlockOrientations.get_basis(ghost.orientation_index)
	assert_true(ghost.basis.is_equal_approx(expected))


func test_reset_clears_free_rotation_and_index() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_orientation_index(5)
	ghost.apply_free_rotation_delta(1.2, 0.7)
	ghost.reset_rotation()
	assert_eq(ghost.orientation_index, 0)
	assert_eq(ghost.free_quaternion, Quaternion.IDENTITY)
	assert_eq(ghost.basis, Basis.IDENTITY)


## Bontago-mv0.10 (spec 2.4/2.5 "[ORIGINAL target]" cadence): "A distinct
## timer-locked state must remain visible even at a legal location."
func test_set_locked_overrides_the_validity_tint() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.VALID)
	assert_eq(ghost.current_state(), GhostPreview.STATE_VALID)

	ghost.set_locked(true)

	assert_eq(ghost.current_state(), GhostPreview.STATE_LOCKED)
	assert_true(
		ghost.current_tint_color().is_equal_approx(ghost.ghost_tuning.locked_tint_color),
		"the locked tint must win over the (still legal) validity tint."
	)

	ghost.set_locked(false)
	assert_eq(ghost.current_state(), GhostPreview.STATE_VALID, "unlocking restores whatever validity last said.")


func test_many_random_steps_then_reset_never_drifts() -> void:
	var ghost: GhostPreview = _make_ghost()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	for _i: int in range(200):
		match rng.randi_range(0, 5):
			0: ghost.set_orientation_index(BlockOrientations.step_yaw_ccw(ghost.orientation_index))
			1: ghost.set_orientation_index(BlockOrientations.step_yaw_cw(ghost.orientation_index))
			2: ghost.set_orientation_index(BlockOrientations.step_pitch_fwd(ghost.orientation_index))
			3: ghost.set_orientation_index(BlockOrientations.step_pitch_back(ghost.orientation_index))
			4: ghost.set_orientation_index(BlockOrientations.step_roll_left(ghost.orientation_index))
			5: ghost.set_orientation_index(BlockOrientations.step_roll_right(ghost.orientation_index))
		ghost.apply_free_rotation_delta(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
	ghost.reset_rotation()
	assert_eq(ghost.basis, Basis.IDENTITY, "However far rotation drifted, reset must land exactly on identity.")


# --- Bontago-mv0.17 item 3: rotated-bottom pivot -----------------------------

## The lowest world-space Y any corner of the ghost's own shape visual
## reaches -- the thing an owner actually sees clip into the disk or float
## above the cursor if the pivot math is wrong. Each mesh's local box corners
## have to go through `ghost.basis` (not just a Y-translation) to land in
## world space correctly once the ghost itself is rotated -- a MeshInstance3D
## child's own `.position` is local to the (unrotated) ShapeVisual/ghost
## frame, and its rotation comes entirely from the ghost node's own basis.
func _visual_world_bottom_y(ghost: GhostPreview) -> float:
	var visual: Node3D = null
	for child: Node in ghost.get_children():
		if child.name == "ShapeVisual":
			visual = child as Node3D
			break
	assert_not_null(visual, "fixture: the ghost should have a shape visual once a shape is set.")
	var min_world_y: float = INF
	for mesh_child: Node in visual.get_children():
		var mesh_instance: MeshInstance3D = mesh_child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local_aabb: AABB = mesh_instance.mesh.get_aabb()
		for corner_index: int in range(8):
			var corner_local: Vector3 = local_aabb.position + Vector3(
				local_aabb.size.x * float(corner_index & 1),
				local_aabb.size.y * float((corner_index >> 1) & 1),
				local_aabb.size.z * float((corner_index >> 2) & 1)
			)
			var world_corner: Vector3 = ghost.global_position + ghost.basis * (mesh_instance.position + corner_local)
			min_world_y = minf(min_world_y, world_corner.y)
	return min_world_y


func test_update_placement_puts_an_unrotated_shapes_visual_bottom_at_the_reported_height() -> void:
	var ghost: GhostPreview = _make_ghost()

	ghost.update_placement(Vector3(2.0, 5.0, -3.0), Vector3.UP)

	assert_almost_eq(ghost.global_position.x, 2.0, 0.001)
	assert_almost_eq(ghost.global_position.z, -3.0, 0.001)
	var expected_bottom: float = 5.0 + ghost.tuning.hover_height
	assert_almost_eq(
		_visual_world_bottom_y(ghost), expected_bottom, ghost.tuning.cube_margin * 0.5 + 0.001,
		"the ghost's own bottom face should sit at the reported disk height plus hover_height."
	)


## The regression this item exists to fix: pillar is 3 cells tall unrotated,
## so tipping it 90 degrees onto its side used to leave its old bottom-centre
## pivot -- now off to one side of the tipped shape, not underneath it --
## sitting at the cursor height while the actual lowest point hung well
## below it (or floated above, depending on direction).
func test_update_placement_keeps_a_rotated_talls_shapes_visual_bottom_at_the_reported_height() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/pillar.tres"))
	ghost.set_orientation_index(BlockOrientations.step_pitch_fwd(0))

	ghost.update_placement(Vector3(0.0, 4.0, 0.0), Vector3.UP)

	var expected_bottom: float = 4.0 + ghost.tuning.hover_height
	assert_almost_eq(
		_visual_world_bottom_y(ghost), expected_bottom, ghost.tuning.cube_margin * 0.5 + 0.001,
		"after a 90-degree pitch, the pillar's own rotated lowest point must sit at the reported height."
	)


# --- Bontago-mv0.17 item 6: footprint projection -----------------------------

func test_no_footprint_quads_when_no_shape_is_held() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_eq(ghost.footprint_quad_count(), 0)


func test_footprint_has_one_quad_per_cell_for_a_flat_shape() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/square4.tres"))

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_eq(ghost.footprint_quad_count(), 4, "square4's 4 cells sit in 4 distinct (x, z) columns.")


func test_footprint_has_one_quad_for_a_shape_stacked_straight_up() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/pillar.tres"))

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_eq(ghost.footprint_quad_count(), 1, "pillar standing upright touches the ground in exactly one column.")


func test_footprint_quad_count_matches_the_rotated_shapes_own_columns() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/pillar.tres"))
	ghost.set_orientation_index(BlockOrientations.step_pitch_fwd(0))

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_eq(ghost.footprint_quad_count(), 3, "tipped onto its side, pillar's 3 cells occupy 3 distinct footprint columns.")


func test_footprint_tint_follows_validity_like_the_held_shapes_own_body() -> void:
	var ghost: GhostPreview = _make_ghost()

	ghost.apply_validity(PlacementRules.Result.VALID)
	assert_almost_eq(ghost.current_footprint_tint_color().a, ghost.ghost_tuning.footprint_alpha, 0.001)

	ghost.apply_validity(PlacementRules.Result.OUTSIDE_TERRITORY)
	var expected_invalid: Color = ghost.ghost_tuning.invalid_tint_color
	assert_true(
		ghost.current_footprint_tint_color().is_equal_approx(
			Color(expected_invalid.r, expected_invalid.g, expected_invalid.b, ghost.ghost_tuning.footprint_alpha)
		),
		"the footprint should turn invalid-red (at footprint_alpha) exactly like the body does."
	)

	ghost.set_locked(true)
	var expected_locked: Color = ghost.ghost_tuning.locked_tint_color
	assert_true(
		ghost.current_footprint_tint_color().is_equal_approx(
			Color(expected_locked.r, expected_locked.g, expected_locked.b, ghost.ghost_tuning.footprint_alpha)
		),
		"the locked tint should win over validity for the footprint too, exactly like the body does."
	)


# --- Bontago-mv0.25 (docs/rotation-issue.png, owner test 2026-09-22): the
# out-of-territory tint reads grey, not red -----------------------------------

func test_invalid_state_uses_the_same_grey_as_locked() -> void:
	var ghost: GhostPreview = _make_ghost()

	ghost.apply_validity(PlacementRules.Result.OUTSIDE_TERRITORY)
	var invalid_color: Color = ghost.current_tint_color()
	assert_eq(ghost.current_state(), GhostPreview.STATE_INVALID)

	ghost.set_locked(true)
	var locked_color: Color = ghost.current_tint_color()

	assert_true(
		invalid_color.is_equal_approx(locked_color),
		"aiming outside your own territory should read the same calm grey as the interval-locked state, not an alarming red."
	)


# --- Bontago-mv0.25 (docs/rotation-issue.png): the shadow blob is gone -------

func test_no_shadow_node_remains_once_a_shape_is_held() -> void:
	var ghost: GhostPreview = _make_ghost()

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	# The footprint is the only ground marker now: exactly the shape visual
	# plus one footprint quad per bottom cell, no separate shadow quad.
	assert_eq(
		ghost.get_child_count(), 1 + ghost.footprint_quad_count(),
		"a leftover shadow child would show up here as an extra, unaccounted-for node."
	)


# --- Bontago-mv0.25 (docs/rotation-issue.png): reject kick is world-space ----

func test_reject_animation_moves_the_root_offset_not_the_rotated_shape_visual() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_orientation_index(BlockOrientations.step_pitch_fwd(0))
	assert_eq(ghost.reject_offset(), Vector3.ZERO, "fixture: no reject kick yet.")

	ghost.play_reject_animation()
	await wait_seconds(ghost.ghost_tuning.reject_arc_duration * 0.25)

	var shape_visual: Node3D = null
	for child: Node in ghost.get_children():
		if child.name == "ShapeVisual":
			shape_visual = child as Node3D
			break
	assert_not_null(shape_visual, "fixture: the ghost should have a shape visual once a shape is set.")
	assert_eq(
		shape_visual.position, Vector3.ZERO,
		"the shape visual's own local position must never move (it would ride along with the ghost's own rotation)."
	)
	assert_ne(
		ghost.reject_offset(), Vector3.ZERO,
		"the kick should be visible on the world-space root offset partway through the animation."
	)


# --- Bontago-mv0.25 (docs/rotation-issue.png): rotated footprint polygons ----

func _flat_l_shape() -> BlockShape:
	var shape: BlockShape = BlockShape.new()
	shape.id = &"test_flat_l"
	shape.cells = [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1)]
	return shape


func _bbox_of(points: PackedVector2Array) -> Rect2:
	var min_pt: Vector2 = points[0]
	var max_pt: Vector2 = points[0]
	for point: Vector2 in points:
		min_pt = Vector2(minf(min_pt.x, point.x), minf(min_pt.y, point.y))
		max_pt = Vector2(maxf(max_pt.x, point.x), maxf(max_pt.y, point.y))
	return Rect2(min_pt, max_pt - min_pt)


func _polygon_area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	var n: int = points.size()
	for i: int in range(n):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	return absf(area) * 0.5


## The regression this pins: before Bontago-mv0.25, every footprint quad was a
## fixed axis-aligned unit square whose *position* (not shape) tracked the
## rotated shape (docs/rotation-issue.png: a rotated block with unrotated,
## overlapping footprint squares). At a 90-degree yaw a square's own bounding
## box happens to look the same either way, so this checks 45 degrees too,
## where a truly rotated cell's footprint becomes a diamond -- a bug that
## left the bounding box at the original axis-aligned size would be caught by
## the 45-degree case's larger, non-axis-aligned bounding box.
func test_footprint_polygon_matches_the_rotated_cells_projected_corners() -> void:
	var shape: BlockShape = _flat_l_shape()
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(shape)

	var half_size: float = (ghost.tuning.cube_size - ghost.tuning.cube_margin) * 0.5
	var pivot: Vector3 = shape.bottom_center()
	var corner_signs: Array[Vector3] = [
		Vector3(-1.0, -1.0, -1.0), Vector3(1.0, -1.0, -1.0), Vector3(-1.0, 1.0, -1.0), Vector3(1.0, 1.0, -1.0),
		Vector3(-1.0, -1.0, 1.0), Vector3(1.0, -1.0, 1.0), Vector3(-1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0),
	]

	for angle: float in [PI * 0.5, PI * 0.25]:
		ghost.free_quaternion = Quaternion(Vector3.UP, angle)
		ghost.set_orientation_index(0)
		ghost.update_placement(Vector3.ZERO, Vector3.UP)

		for cell_index: int in range(shape.cells.size()):
			var cell: Vector3i = shape.cells[cell_index]
			var local_center: Vector3 = (Vector3(cell) - pivot) * ghost.tuning.cube_size
			var expected_points: PackedVector2Array = PackedVector2Array()
			for corner_sign: Vector3 in corner_signs:
				var corner: Vector3 = local_center + corner_sign * half_size
				# Basis(Vector3.UP, angle) * corner, hand-expanded (matches
				# CameraRig/PlayerController's own forward = (sin, 0, cos)
				# convention: yaw increasing rotates +Z toward +X).
				var x: float = corner.x * cos(angle) + corner.z * sin(angle)
				var z: float = -corner.x * sin(angle) + corner.z * cos(angle)
				expected_points.append(Vector2(x, z))
			var expected_bbox: Rect2 = _bbox_of(expected_points)
			var expected_area: float = (2.0 * half_size) * (2.0 * half_size)

			var actual_polygon: PackedVector2Array = ghost.footprint_polygon_world(cell_index)
			var actual_bbox: Rect2 = _bbox_of(actual_polygon)
			assert_true(
				actual_bbox.position.is_equal_approx(expected_bbox.position),
				"cell %d bbox origin wrong at angle %.3f: got %s expected %s" % [cell_index, angle, actual_bbox.position, expected_bbox.position]
			)
			assert_true(
				actual_bbox.size.is_equal_approx(expected_bbox.size),
				"cell %d bbox size wrong at angle %.3f: got %s expected %s" % [cell_index, angle, actual_bbox.size, expected_bbox.size]
			)
			assert_almost_eq(
				_polygon_area(actual_polygon), expected_area, 0.001,
				"a rigid rotation must preserve each cell's own footprint area exactly, at any angle."
			)
