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
	# Bontago-xtq.13: the locked colour's own RGB must win, but its alpha now
	# always comes from ghost_tuning.ghost_opacity, not locked_tint_color's own
	# stored alpha channel -- compare against that, not the raw constant.
	var expected_locked: Color = Color(
		ghost.ghost_tuning.locked_tint_color.r, ghost.ghost_tuning.locked_tint_color.g,
		ghost.ghost_tuning.locked_tint_color.b, ghost.ghost_tuning.ghost_opacity
	)
	assert_true(
		ghost.current_tint_color().is_equal_approx(expected_locked),
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


## Bontago-xtq.9 (owner test 2026-09-23, "the preview starts from the bottom
## of the ghost block which looks a bit weird when it's angled"): the mirror
## image of _visual_world_bottom_y() above -- the highest world-space Y any
## corner of the ghost's own shape visual reaches, used to check the
## projection prism's own new top-of-column cap.
func _visual_world_top_y(ghost: GhostPreview) -> float:
	var visual: Node3D = null
	for child: Node in ghost.get_children():
		if child.name == "ShapeVisual":
			visual = child as Node3D
			break
	assert_not_null(visual, "fixture: the ghost should have a shape visual once a shape is set.")
	var max_world_y: float = -INF
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
			max_world_y = maxf(max_world_y, world_corner.y)
	return max_world_y


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


# --- Bontago-mv0.17 item 6 / Bontago-xtq.7: footprint projection ------------
# (docs/solid-blocks2-issue.png, owner test 2026-09-23): the footprint is now
# always the *whole* rotated shape's own silhouette -- one polygon, not one
# per bottom cell -- so every case below that used to expect one quad per
# distinct column now expects exactly 1.

func test_no_footprint_quads_when_no_shape_is_held() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_eq(ghost.footprint_quad_count(), 0)


func test_footprint_has_exactly_one_quad_for_a_flat_multi_cell_shape() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/square4.tres"))

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_eq(
		ghost.footprint_quad_count(), 1,
		"Bontago-xtq.7: the footprint is the whole shape's own hull, not one quad per one of square4's 4 cells."
	)


func test_footprint_has_one_quad_for_a_shape_stacked_straight_up() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/pillar.tres"))

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_eq(ghost.footprint_quad_count(), 1, "pillar standing upright touches the ground in exactly one column.")


func test_footprint_stays_one_quad_for_a_rotated_shape_spanning_many_columns() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/pillar.tres"))
	ghost.set_orientation_index(BlockOrientations.step_pitch_fwd(0))

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_eq(
		ghost.footprint_quad_count(), 1,
		"Bontago-xtq.7: tipped onto its side, pillar's 3 cells span 3 columns but still project one whole-shape hull."
	)


## Bontago-xtq.10 (owner test 2026-09-23, "the footprint on the disc should
## be almost white"): the footprint no longer shows the *full* state colour
## the held shape's own body does -- only footprint_base_color blended with a
## faint (footprint_hue_strength) amount of it -- so this test's own
## expectations are now built the same way _footprint_color_for_state()
## computes them, not a bare copy of the state colour.
func test_footprint_tint_follows_validity_like_the_held_shapes_own_body() -> void:
	var ghost: GhostPreview = _make_ghost()

	ghost.apply_validity(PlacementRules.Result.VALID)
	assert_almost_eq(ghost.current_footprint_tint_color().a, ghost.ghost_tuning.footprint_alpha, 0.001)

	ghost.apply_validity(PlacementRules.Result.OUTSIDE_TERRITORY)
	var expected_invalid: Color = ghost.ghost_tuning.footprint_base_color.lerp(
		ghost.ghost_tuning.invalid_tint_color, ghost.ghost_tuning.footprint_hue_strength
	)
	assert_true(
		ghost.current_footprint_tint_color().is_equal_approx(
			Color(expected_invalid.r, expected_invalid.g, expected_invalid.b, ghost.ghost_tuning.footprint_alpha)
		),
		"the footprint should blend a faint invalid hue into its near-white base, at footprint_alpha."
	)

	ghost.set_locked(true)
	var expected_locked: Color = ghost.ghost_tuning.footprint_base_color.lerp(
		ghost.ghost_tuning.locked_tint_color, ghost.ghost_tuning.footprint_hue_strength
	)
	assert_true(
		ghost.current_footprint_tint_color().is_equal_approx(
			Color(expected_locked.r, expected_locked.g, expected_locked.b, ghost.ghost_tuning.footprint_alpha)
		),
		"the locked tint should win over validity for the footprint too, exactly like the body does."
	)


## Must fail against the pre-Bontago-xtq.10 code (where the footprint showed
## the *full* state colour, e.g. invalid_tint_color's own 0.6 grey channels)
## and pass once the footprint blends only a faint hue into a near-white base.
func test_footprint_colour_reads_near_white_even_in_the_invalid_state() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_player_color(Color(0.25, 0.55, 0.95, 1.0))

	assert_true(
		ghost.ghost_tuning.footprint_base_color.r >= 0.85
		and ghost.ghost_tuning.footprint_base_color.g >= 0.85
		and ghost.ghost_tuning.footprint_base_color.b >= 0.85,
		"the footprint's own base colour must be near-white by default (each channel >= 0.85)."
	)

	ghost.apply_validity(PlacementRules.Result.OUTSIDE_TERRITORY)
	var footprint_color: Color = ghost.current_footprint_tint_color()
	assert_true(
		footprint_color.r >= 0.85 and footprint_color.g >= 0.85 and footprint_color.b >= 0.85,
		"even the invalid-state footprint (%s) should still read close to white, just faintly tinted -- not the old full grey." % footprint_color
	)
	assert_almost_eq(footprint_color.a, ghost.ghost_tuning.footprint_alpha, 0.001, "the footprint should also be highly opaque.")


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

	# The footprint/projection are the only ground markers now: the shape
	# visual, the persistent projection-prism mesh (Bontago-xtq.7 -- added
	# once in _ready(), always present even with an empty mesh), the
	# persistent block-projection decal (Bontago-xtq.15 -- same "added once,
	# always present" idea, just hidden rather than freed when nothing is
	# held), and one footprint quad -- no separate shadow quad.
	assert_eq(
		ghost.get_child_count(), 3 + ghost.footprint_quad_count(),
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
## where a truly rotated shape's footprint becomes a diamond -- a bug that
## left the bounding box at the original axis-aligned size would be caught by
## the 45-degree case's larger, non-axis-aligned bounding box.
##
## Bontago-xtq.7: updated for the whole-shape hull contract -- there is now
## exactly one footprint polygon (index 0) covering every cell's own rotated
## corners together, not one polygon per cell, so the expected points below
## are gathered across all of the L-shape's 3 cells before taking their own
## convex hull (the same primitive the implementation calls, but the corner
## *rotation* math is still independently hand-expanded, which is the part
## Bontago-mv0.25's regression was actually in).
func test_footprint_polygon_matches_the_whole_rotated_shapes_projected_corners() -> void:
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

		var expected_points: PackedVector2Array = PackedVector2Array()
		for cell: Vector3i in shape.cells:
			var local_center: Vector3 = (Vector3(cell) - pivot) * ghost.tuning.cube_size
			for corner_sign: Vector3 in corner_signs:
				var corner: Vector3 = local_center + corner_sign * half_size
				# Basis(Vector3.UP, angle) * corner, hand-expanded (matches
				# CameraRig/PlayerController's own forward = (sin, 0, cos)
				# convention: yaw increasing rotates +Z toward +X).
				var x: float = corner.x * cos(angle) + corner.z * sin(angle)
				var z: float = -corner.x * sin(angle) + corner.z * cos(angle)
				expected_points.append(Vector2(x, z))
		var expected_hull: PackedVector2Array = Geometry2D.convex_hull(expected_points)
		var expected_bbox: Rect2 = _bbox_of(expected_hull)
		var expected_area: float = _polygon_area(expected_hull)

		assert_eq(ghost.footprint_quad_count(), 1, "the whole L-shape must still show exactly one footprint polygon.")
		var actual_polygon: PackedVector2Array = ghost.footprint_polygon_world(0)
		var actual_bbox: Rect2 = _bbox_of(actual_polygon)
		assert_true(
			actual_bbox.position.is_equal_approx(expected_bbox.position),
			"bbox origin wrong at angle %.3f: got %s expected %s" % [angle, actual_bbox.position, expected_bbox.position]
		)
		assert_true(
			actual_bbox.size.is_equal_approx(expected_bbox.size),
			"bbox size wrong at angle %.3f: got %s expected %s" % [angle, actual_bbox.size, expected_bbox.size]
		)
		assert_almost_eq(
			_polygon_area(actual_polygon), expected_area, 0.001,
			"a rigid rotation must preserve the whole shape's own footprint area exactly, at any angle."
		)


# --- Bontago-xtq.7: the whole-shape projection prism -------------------------
# (docs/solid-blocks2-issue.png, owner test 2026-09-23) -----------------------

func _footprint_test_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_ghost_preview_footprint_disk"
	map_def.field_radius = 12.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 16
	return map_def


## The owner's own repro ("I took a screenshot where I'm hovering a tilted
## ghost block on top of a dropped block and you can see that the middle
## section of the ghost block shows up on top of the dropped block and the
## other sections land on the disc"): a tilted bar3 held above a real placed
## pillar must show exactly one footprint polygon, landed on the bare disc
## (never the pillar's own top face -- the old per-cell raycast against the
## unfiltered world happily landed there), plus a projection prism reaching
## from that same disc height up to the held shape's own current highest
## point (Bontago-xtq.9: the column now caps at the shape's top, not its
## bottom, so a pitched/yawed ghost sits fully inside it).
func test_pitched_bar3_over_a_placed_block_gets_one_disc_footprint_and_a_matching_prism() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = _footprint_test_map()
	add_child_autofree(field)

	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var block: Block = BlockFactory.build(load("res://config/blocks/pillar.tres"), tuning)
	field.get_parent().add_child(block)
	autofree(block)
	block.global_position = Vector3(0.0, 5.0, 0.0)
	await wait_physics_frames(90)
	block.sleeping = true

	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/bar3.tres"))
	# A partial pitch (not a 90-degree step, which for an X-extending bar
	# pitched about X is a geometric no-op -- see game/PlayerController.gd's
	# own test_moving_horizontally_into_a_placed_block_stops_short_of_it_at_a_
	# pitched_rotation for the same choice), same as the owner's own
	# rotate-drag gesture.
	ghost.apply_free_rotation_delta(0.0, deg_to_rad(20.0), Vector3.RIGHT)

	# The disk-only probe (Bontago-mv0.17 item 5) reports the bare disk
	# surface at the field's own origin regardless of the pillar sitting
	# there -- same surface_point PlayerController's own probe would report.
	var disk_surface_point: Vector3 = Vector3.ZERO
	ghost.update_placement(disk_surface_point, Vector3.UP)

	assert_eq(ghost.footprint_quad_count(), 1, "one whole-shape footprint, not one per cell.")
	assert_almost_eq(
		ghost.footprint_quad_position(0).y, disk_surface_point.y + ghost.ghost_tuning.footprint_offset, 0.01,
		"the footprint must land on the bare disc, never the placed pillar's own top face."
	)

	assert_true(ghost.has_projection_mesh(), "a real gap between the shape and the disc must show a projection prism.")
	var span: Vector2 = ghost.projection_span_y()
	# Bontago-xtq.9: unlike _rotated_bottom_offset() (deliberately the
	# cube_margin-shrunk *collision* half_size, so placed blocks don't jam --
	# this file's own DECISION on collision_box_local_centers()),
	# _rotated_top_offset() uses the same full cube_size the *visual* mesh
	# itself is built from (core/blocks/BlockMeshBuilder.gd's own
	# `half: float = cube_size * 0.5`), so the prism's own top should match
	# _visual_world_top_y() tightly, not just within a cube_margin tolerance.
	assert_almost_eq(
		span.x, _visual_world_top_y(ghost), 0.01,
		"Bontago-xtq.9: the prism's own top must reach the held shape's own current highest rendered point, not its lowest."
	)
	assert_true(
		span.x >= _visual_world_top_y(ghost) - 0.001,
		"the prism mesh's own AABB top must be at or above the ghost body's own AABB max Y."
	)
	assert_almost_eq(
		span.y, disk_surface_point.y, 0.01,
		"the prism's own bottom must match the footprint's disc landing height, not the pillar's top."
	)


func test_no_projection_prism_when_no_shape_is_held() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_false(ghost.has_projection_mesh())
	assert_eq(ghost.projection_span_y(), Vector2.ZERO)


## Bontago-xtq.9: the prism's own top cap now reaches the shape's own
## *highest* point (this file's own header), so a merely-flush placement (the
## shape's underside touching the ground, manual_hover_offset cancelling out
## tuning.hover_height) no longer collapses the prism -- the column still has
## to show the whole body's own height standing above the disc. The prism
## only collapses now when the shape is pushed down so far that even its own
## *highest* point sits at or below the footprint's own landing height -- a
## degenerate/adversarial manual_hover_offset no real player input reaches,
## but still a case _update_projection_mesh()'s own guard must not render a
## paper-thin (or inverted) sliver for.
func test_projection_prism_collapses_when_even_the_shapes_own_top_is_at_the_ground() -> void:
	var ghost: GhostPreview = _make_ghost()
	var half_collision: float = (ghost.tuning.cube_size - ghost.tuning.cube_margin) * 0.5
	var half_visual: float = ghost.tuning.cube_size * 0.5
	ghost.manual_hover_offset = -(ghost.tuning.hover_height + half_collision + half_visual + 1.0)

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_false(
		ghost.has_projection_mesh(),
		"with the shape's own top at or below the ground, the collapsed prism should not render a sliver."
	)
	assert_eq(ghost.projection_span_y(), Vector2.ZERO)


## hover_height alone (spec 2.5's default lift) is a real, known gap -- proof
## the collapse guard above isn't just always true.
func test_projection_prism_spans_hover_height_plus_the_shapes_own_height_over_flat_ground() -> void:
	var ghost: GhostPreview = _make_ghost()

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_true(ghost.has_projection_mesh(), "hover_height alone should still show a prism.")
	var span: Vector2 = ghost.projection_span_y()
	# Bontago-xtq.9: the prism's own top is now the shape's own highest
	# point, not its lowest -- for an unrotated cube resting hover_height
	# above the ground, that adds the collision half-extent (how far the
	# node's own origin sits above the ground, _rotated_bottom_offset()) plus
	# the visual half-extent (how far the shape's own top sits above that
	# same origin, _rotated_top_offset()) on top of hover_height itself.
	var half_collision: float = (ghost.tuning.cube_size - ghost.tuning.cube_margin) * 0.5
	var half_visual: float = ghost.tuning.cube_size * 0.5
	var expected_span: float = ghost.tuning.hover_height + half_collision + half_visual
	assert_almost_eq(
		span.x - span.y, expected_span, 0.01,
		"the prism should span hover_height plus the whole cube's own height above flat ground."
	)


## Bontago-xtq.9 (owner test 2026-09-23, "the preview starts from the bottom
## of the ghost block which looks a bit weird when it's angled"): the
## regression this pins -- before the fix, the prism's own top tracked the
## rotated shape's *lowest* point, which for a steeply pitched/yawed shape
## sits well below its own highest rendered corner, so the column visibly cut
## through the middle of the ghost instead of surrounding it. Must fail
## against the pre-fix code (which used _rotated_bottom_offset() for the
## prism's own top) and pass once the prism uses _rotated_top_offset().
func test_projection_prism_top_reaches_the_ghosts_highest_point_when_pitched_and_yawed() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_free_rotation_delta(deg_to_rad(35.0), deg_to_rad(25.0), Vector3.RIGHT)

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_true(ghost.has_projection_mesh(), "fixture: a real gap should still show a prism once rotated.")
	# projection_span_y()'s own doc: (top, bottom) are exactly the Y extremes
	# _build_prism_mesh() uses for every wall vertex, i.e. the prism mesh's
	# own world-space AABB Y span.
	var span: Vector2 = ghost.projection_span_y()
	var body_top_y: float = _visual_world_top_y(ghost)
	var body_bottom_y: float = _visual_world_bottom_y(ghost)

	assert_true(
		span.x >= body_top_y - 0.001,
		"the prism mesh's own AABB top (%s) must be at or above the ghost body's own AABB max Y (%s)." % [span.x, body_top_y]
	)
	assert_true(
		span.x > body_bottom_y,
		"fixture: the prism's own top must not still be sitting down at the shape's lowest point (the pre-fix bug)."
	)
	assert_almost_eq(
		span.y, ghost.footprint_quad_position(0).y - ghost.ghost_tuning.footprint_offset, 0.01,
		"the prism's own bottom must sit at the disc surface, matching the footprint."
	)


# --- Bontago-xtq.10 (owner test 2026-09-23, "any surface that falls within
# the projection should be a lot brighter (maybe emissive?)") ---------------

## Must fail against the pre-Bontago-xtq.10 material (plain alpha
## compositing, no emission) and pass once the prism material blends
## additively and emits its own light.
func test_projection_prism_material_uses_additive_blend_and_emission() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.VALID)

	assert_true(
		ghost.projection_uses_additive_blend(),
		"the projection prism's own material must blend additively so surfaces behind/inside it brighten."
	)
	assert_true(
		ghost.projection_emission_enabled(),
		"the projection prism's own material must also emit its own light."
	)
	assert_true(
		ghost.ghost_tuning.projection_emission_energy > 0.0,
		"a zero emission energy would make the emission_enabled switch above pointless."
	)
	var emission: Color = ghost.current_projection_emission_color()
	var tint: Color = ghost.current_projection_tint_color()
	assert_true(
		Color(emission.r, emission.g, emission.b).is_equal_approx(Color(tint.r, tint.g, tint.b)),
		"the prism's own emission colour should track its current state tint, not a fixed/neutral colour."
	)


# --- Bontago-xtq.19 (owner screenshots 2026-09-24: a tilted 4-long bar and a
# T-piece both show dark vertical seams / overlapping stepped columns inside
# the translucent prism) --------------------------------------------------------
# Attempt 3 walls the *merged rendered mesh's* own silhouette (game/
# GhostPreview.gd's _shape_silhouette_loops(), Geometry2D.merge_polygons over
# every triangle of the shape's own real visual shell) instead of xtq.16's
# per-column hulls, so no interior wall is left to double-blend. Attempt 4
# restores xtq.16's owner-verified rule on top of that: the prism is the shaft
# *under* the shape -- every wall's top follows the shape's own underside along
# the outline (sloped for a tilted shape, stepped where an overhang begins),
# never the whole shape's top. projection_span_y()/projection_column_span_y()
# stay the whole-shape bookkeeping game/PlayerController.gd reads; the tests
# below check the built mesh itself (projection_mesh_vertices_world()).

## The same 8 corner signs _CORNER_SIGNS declares (game/GhostPreview.gd),
## independently re-declared here so the per-cell expectations below are a real
## check of the implementation, not its own self-consistency.
const _TEST_CORNER_SIGNS: Array[Vector3] = [
	Vector3(-1.0, -1.0, -1.0), Vector3(1.0, -1.0, -1.0), Vector3(-1.0, 1.0, -1.0), Vector3(1.0, 1.0, -1.0),
	Vector3(-1.0, -1.0, 1.0), Vector3(1.0, -1.0, 1.0), Vector3(-1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0),
]
## How far the independent underside probe below nudges its sample point off
## the wall line toward the shape (it must not land exactly on the outline,
## which every neighbouring triangle touches) -- deliberately different from
## GhostPreview's own inset so the two are not trivially the same computation.
const _TEST_PROBE_NUDGE: float = 0.004
## Allowed mismatch between a wall's top edge and the independently probed
## underside: the nudge times the steepest face slope a 30-degree roll makes
## (tan 60 ~ 1.73) plus float slack.
const _TEST_UNDERSIDE_TOLERANCE: float = 0.015


## One rotated `cell`'s own lowest world-space Y (its own underside), from the
## visual cube_size box and the shape's bottom_center() pivot.
func _expected_cell_min_y(ghost: GhostPreview, cell: Vector3i) -> float:
	var half_size: float = ghost.tuning.cube_size * 0.5
	var pivot: Vector3 = ghost.get_shape().bottom_center()
	var local_center: Vector3 = (Vector3(cell) - pivot) * ghost.tuning.cube_size
	var min_y: float = INF
	for corner_sign: Vector3 in _TEST_CORNER_SIGNS:
		var rotated: Vector3 = ghost.basis * (local_center + corner_sign * half_size)
		min_y = minf(min_y, rotated.y)
	return ghost.global_position.y + min_y


## Signed area via the shoelace formula -- used by the outer-loop tests below
## to check the merged silhouette's own *area* (not vertex count, since
## Geometry2D.merge_polygons may leave collinear points on a straight run).
func _outline_area(points: PackedVector2Array) -> float:
	return _polygon_area(points)


## Every world-space triangle of the ghost's own rendered shell, read straight
## off the ShapeVisual meshes (not through any GhostPreview helper).
func _world_shell_triangles(ghost: GhostPreview) -> Array[PackedVector3Array]:
	var triangles: Array[PackedVector3Array] = []
	for child: Node in ghost.get_children():
		if child.name != "ShapeVisual":
			continue
		for mesh_child: Node in child.get_children():
			var mesh_instance: MeshInstance3D = mesh_child as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			for surface: int in range(mesh_instance.mesh.get_surface_count()):
				var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for i: int in range(0, indices.size(), 3):
					var triangle: PackedVector3Array = PackedVector3Array()
					for k: int in range(3):
						triangle.append(ghost.global_position + ghost.basis * (mesh_instance.position + verts[indices[i + k]]))
					triangles.append(triangle)
	return triangles


## The lowest point of the shell straight above/below world XZ `point`
## (INF if no triangle covers it) -- a closed shell's lowest surface there is
## its underside. Own barycentric math, skipping edge-on (vertical) triangles.
func _probe_underside_y(triangles: Array[PackedVector3Array], point: Vector2) -> float:
	var lowest: float = INF
	for triangle: PackedVector3Array in triangles:
		var p0: Vector2 = Vector2(triangle[0].x, triangle[0].z)
		var e1: Vector2 = Vector2(triangle[1].x, triangle[1].z) - p0
		var e2: Vector2 = Vector2(triangle[2].x, triangle[2].z) - p0
		var denominator: float = e1.x * e2.y - e2.x * e1.y
		if absf(denominator) < 1e-8:
			continue
		var d: Vector2 = point - p0
		var w1: float = (d.x * e2.y - e2.x * d.y) / denominator
		var w2: float = (e1.x * d.y - d.x * e1.y) / denominator
		if w1 < 0.0 or w2 < 0.0 or w1 + w2 > 1.0:
			continue
		lowest = minf(lowest, triangle[0].y + w1 * (triangle[1].y - triangle[0].y) + w2 * (triangle[2].y - triangle[0].y))
	return lowest


## Every prism wall's top edge must sit on the shape's own underside: sampled
## at 3 interior points per wall, nudged toward whichever side the shell
## covers, and compared against the independently probed underside. Must fail
## against attempt 3 (every wall capped at the whole shape's own top).
func _assert_wall_tops_follow_the_underside(ghost: GhostPreview) -> void:
	var triangles: Array[PackedVector3Array] = _world_shell_triangles(ghost)
	var vertices: PackedVector3Array = ghost.projection_mesh_vertices_world()
	assert_false(vertices.is_empty(), "fixture: a real gap between the shape and the disc must show prism geometry.")
	for wall_index: int in range(vertices.size() / 4):
		var top_a: Vector3 = vertices[wall_index * 4]
		var top_b: Vector3 = vertices[wall_index * 4 + 1]
		var a: Vector2 = Vector2(top_a.x, top_a.z)
		var b: Vector2 = Vector2(top_b.x, top_b.z)
		if a.distance_to(b) < 0.01:
			continue
		var direction: Vector2 = (b - a).normalized()
		var side_normal: Vector2 = Vector2(-direction.y, direction.x)
		for t: float in [0.25, 0.5, 0.75]:
			var point: Vector2 = a.lerp(b, t)
			var wall_top: float = lerpf(top_a.y, top_b.y, t)
			var underside: float = _probe_underside_y(triangles, point + side_normal * _TEST_PROBE_NUDGE)
			if underside == INF:
				underside = _probe_underside_y(triangles, point - side_normal * _TEST_PROBE_NUDGE)
			assert_true(underside != INF, "wall at (%.3f, %.3f) has no shape over it at all." % [point.x, point.y])
			assert_almost_eq(
				wall_top, underside, _TEST_UNDERSIDE_TOLERANCE,
				"wall top at (%.3f, %.3f) must follow the shape's own underside there." % [point.x, point.y]
			)


## No two prism walls may overlap along the same stretch of ground-plane line
## -- the exact seam symptom the owner's own screenshots show (two walls
## Z-fighting/double-blending). Reconstructs each wall quad from the flat
## vertex list (GhostPreview always appends exactly 4 vertices per wall, in
## (a_top, b_top, b_bottom, a_bottom) order) and checks every pair of collinear
## walls for a shared interior span, not just identical endpoints (walls are
## split into pieces now, so a duplicate need not share both ends).
func _assert_no_duplicate_wall_edges(vertices: PackedVector3Array) -> void:
	assert_eq(vertices.size() % 4, 0, "fixture: GhostPreview always appends exactly 4 vertices per wall.")
	var wall_count: int = vertices.size() / 4
	for i: int in range(wall_count):
		var a: Vector2 = Vector2(vertices[i * 4].x, vertices[i * 4].z)
		var b: Vector2 = Vector2(vertices[i * 4 + 1].x, vertices[i * 4 + 1].z)
		var length: float = a.distance_to(b)
		if length < 0.001:
			continue
		var direction: Vector2 = (b - a) / length
		for j: int in range(i + 1, wall_count):
			var c: Vector2 = Vector2(vertices[j * 4].x, vertices[j * 4].z)
			var d: Vector2 = Vector2(vertices[j * 4 + 1].x, vertices[j * 4 + 1].z)
			# Collinear with wall i?
			if absf(direction.cross(c - a)) > 0.001 or absf(direction.cross(d - a)) > 0.001:
				continue
			var t_c: float = direction.dot(c - a)
			var t_d: float = direction.dot(d - a)
			var overlap: float = minf(length, maxf(t_c, t_d)) - maxf(0.0, minf(t_c, t_d))
			assert_true(
				overlap <= 0.001,
				"walls %d and %d overlap by %.3f m along the same line -- coincident walls double-blend into a visible seam." % [i, j, overlap]
			)


## Every prism wall must lie on one of the merged silhouette's own outline
## edges (no interior wall left over from a per-cell/per-column approximation,
## the seam bug's own root cause), and -- with the whole shape clear of the
## ground -- together they must cover the outline's whole perimeter exactly.
func _assert_walls_tile_the_outline(ghost: GhostPreview) -> void:
	var edges: Array[PackedVector2Array] = []
	var perimeter: float = 0.0
	for loop_index: int in range(ghost.projection_outline_loop_count()):
		var loop: PackedVector2Array = ghost.projection_outline_polygon_world(loop_index)
		for i: int in range(loop.size()):
			var edge: PackedVector2Array = PackedVector2Array([loop[i], loop[(i + 1) % loop.size()]])
			edges.append(edge)
			perimeter += edge[0].distance_to(edge[1])
	var vertices: PackedVector3Array = ghost.projection_mesh_vertices_world()
	var wall_length: float = 0.0
	for wall_index: int in range(vertices.size() / 4):
		var a: Vector2 = Vector2(vertices[wall_index * 4].x, vertices[wall_index * 4].z)
		var b: Vector2 = Vector2(vertices[wall_index * 4 + 1].x, vertices[wall_index * 4 + 1].z)
		wall_length += a.distance_to(b)
		var on_edge: bool = false
		for edge: PackedVector2Array in edges:
			var closest_a: Vector2 = Geometry2D.get_closest_point_to_segment(a, edge[0], edge[1])
			var closest_b: Vector2 = Geometry2D.get_closest_point_to_segment(b, edge[0], edge[1])
			if closest_a.distance_to(a) < 0.001 and closest_b.distance_to(b) < 0.001:
				on_edge = true
				break
		assert_true(on_edge, "wall (%.3f, %.3f)->(%.3f, %.3f) is not on the silhouette outline." % [a.x, a.y, b.x, b.y])
	assert_almost_eq(wall_length, perimeter, 0.01, "the walls must cover the whole silhouette perimeter, once.")


func _max_wall_vertex_y(ghost: GhostPreview) -> float:
	var highest: float = -INF
	for vertex: Vector3 in ghost.projection_mesh_vertices_world():
		highest = maxf(highest, vertex.y)
	return highest


func _held_ghost(shape_path: String, roll_degrees: float) -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load(shape_path))
	if roll_degrees != 0.0:
		ghost.apply_free_rotation_delta(0.0, deg_to_rad(roll_degrees), Vector3.RIGHT)
	ghost.update_placement(Vector3.ZERO, Vector3.UP)
	return ghost


## The owner's own first repro shape (screenshot_20260924_204137.png): a flat,
## unrotated 4-long bar must show exactly one outer silhouette loop, at the
## whole shape's own true footprint area (4 cells * cube_size^2), with every
## wall top at the bar's own underside.
func test_flat_bar_silhouette_is_a_single_outer_loop_with_full_area() -> void:
	var ghost: GhostPreview = _held_ghost("res://config/blocks/bar4.tres", 0.0)

	assert_eq(ghost.projection_outline_loop_count(), 1, "a flat 4-long bar's rendered silhouette is one outer loop.")
	var area: float = _outline_area(ghost.projection_outline_polygon_world(0))
	var expected_area: float = 4.0 * ghost.tuning.cube_size * ghost.tuning.cube_size
	assert_almost_eq(area, expected_area, 0.01, "the outline's own area must match the whole bar's true footprint.")
	var underside_y: float = _visual_world_bottom_y(ghost)
	var vertices: PackedVector3Array = ghost.projection_mesh_vertices_world()
	for wall_index: int in range(vertices.size() / 4):
		for k: int in range(2):
			assert_almost_eq(
				vertices[wall_index * 4 + k].y, underside_y, 0.001,
				"a flat bar's every wall top must sit at the bar's own underside, not its top."
			)
	_assert_walls_tile_the_outline(ghost)
	_assert_no_duplicate_wall_edges(vertices)


## config/blocks/T4.tres and S4.tres both stack one cell vertically off a
## straight row -- each must still show exactly one outer silhouette loop, with
## no interior wall left over from treating the stacked cell as its own column.
func test_t_and_s_piece_silhouettes_are_single_outer_loops() -> void:
	for shape_path: String in ["res://config/blocks/T4.tres", "res://config/blocks/S4.tres"]:
		var ghost: GhostPreview = _held_ghost(shape_path, 0.0)

		assert_eq(
			ghost.projection_outline_loop_count(), 1,
			"%s's rendered silhouette must be one outer loop, not one per cell/column." % shape_path
		)
		_assert_walls_tile_the_outline(ghost)
		_assert_no_duplicate_wall_edges(ghost.projection_mesh_vertices_world())
		_assert_wall_tops_follow_the_underside(ghost)


## Bontago-xtq.16's own "single cube unchanged" case: the shaft's top is the
## cube's own underside, never its top (the xtq.9 whole-shape cap attempt 3
## reverted to). Must fail against attempt 3.
func test_single_cube_projection_walls_cap_at_its_own_underside_not_the_shapes_own_top() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_true(ghost.has_projection_mesh(), "fixture: hover_height alone leaves a real gap under the cube.")
	assert_almost_eq(
		_max_wall_vertex_y(ghost), _visual_world_bottom_y(ghost), 0.001,
		"the walls' own top must be the cube's own underside, not its top."
	)
	assert_true(
		_max_wall_vertex_y(ghost) < _visual_world_top_y(ghost) - 0.001,
		"the walls must stop below the cube's own top, not enclose the whole solid body."
	)
	_assert_walls_tile_the_outline(ghost)


## The literal Bontago-xtq.16 S4 repro, restored: config/blocks/S4.tres has
## cells (1,0,0)/(2,0,0) in a bottom row and (0,1,0)/(1,1,0) directly above,
## offset one column left. No wall vertex may rise above the lower cells' own
## top (a full cube_size below the shape's own top), the x=0 end (under the
## overhanging (0,1,0)) must reach exactly that overhang's underside, and the
## x=2 end must stop at (2,0,0)'s own underside. Must fail against attempt 3
## (every wall capped at the whole shape's own top).
func test_s4_at_identity_rotation_never_projects_above_the_lower_cells_own_top() -> void:
	var ghost: GhostPreview = _held_ghost("res://config/blocks/S4.tres", 0.0)

	var lower_cell_underside_y: float = _expected_cell_min_y(ghost, Vector3i(2, 0, 0))
	var overhang_underside_y: float = _expected_cell_min_y(ghost, Vector3i(0, 1, 0))
	var lower_cell_top_y: float = lower_cell_underside_y + ghost.tuning.cube_size
	assert_almost_eq(overhang_underside_y, lower_cell_top_y, 0.001, "fixture: the overhang sits on the lower row's top level.")

	var vertices: PackedVector3Array = ghost.projection_mesh_vertices_world()
	assert_false(vertices.is_empty(), "fixture: a real gap between the shape and the disc must show prism geometry.")
	var min_x: float = INF
	var max_x: float = -INF
	for vertex: Vector3 in vertices:
		min_x = minf(min_x, vertex.x)
		max_x = maxf(max_x, vertex.x)
		assert_true(
			vertex.y <= lower_cell_top_y + 0.01,
			"no prism vertex may sit above the lower cells' own top (%.3f); got %.3f at (%.3f, %.3f)"
				% [lower_cell_top_y, vertex.y, vertex.x, vertex.z]
		)
	for wall_index: int in range(vertices.size() / 4):
		for k: int in range(2):
			var top: Vector3 = vertices[wall_index * 4 + k]
			if absf(top.x - min_x) < 0.001:
				assert_almost_eq(top.y, overhang_underside_y, 0.001, "the overhang's own end wall reaches its underside.")
			elif absf(top.x - max_x) < 0.001:
				assert_almost_eq(top.y, lower_cell_underside_y, 0.001, "(2,0,0)'s end wall stops at its own underside.")
	_assert_no_duplicate_wall_edges(vertices)


## "a pitched bar is enclosed from below", restored against the new model:
## bar3 pitched 20 degrees about its own long axis -- every wall top follows
## the bar's own (tilted) underside, so the prism never reaches the bar's own
## highest point. Must fail against attempt 3 (walls capped at that point).
func test_pitched_bar_is_enclosed_from_below_never_above_its_own_cells() -> void:
	var ghost: GhostPreview = _held_ghost("res://config/blocks/bar3.tres", 20.0)

	assert_true(
		_max_wall_vertex_y(ghost) < _visual_world_top_y(ghost) - 0.01,
		"must be enclosed strictly below the shape's own highest point (%.3f) -- the whole-hull cap."
			% _visual_world_top_y(ghost)
	)
	_assert_wall_tops_follow_the_underside(ghost)
	_assert_walls_tile_the_outline(ghost)


## The owner's own literal repro shape/gesture: a 1x4 bar rolled 30 degrees
## about its own long axis (screenshot_20260924_204137.png) sends every one of
## its 4 cells to a distinct, overlapping rotated footprint -- exactly the case
## xtq.16's per-column model could not merge or dedupe. One outer loop, no
## overlapping walls, and every wall top on the bar's own sloped underside.
func test_tilted_bar_silhouette_stays_a_single_outer_loop_with_no_overlapping_walls() -> void:
	var ghost: GhostPreview = _held_ghost("res://config/blocks/bar4.tres", 30.0)

	assert_eq(
		ghost.projection_outline_loop_count(), 1,
		"a rolled bar's 4 cells project to overlapping quads, but the true rendered silhouette is one outer loop."
	)
	_assert_walls_tile_the_outline(ghost)
	_assert_no_duplicate_wall_edges(ghost.projection_mesh_vertices_world())
	_assert_wall_tops_follow_the_underside(ghost)
	assert_true(
		_max_wall_vertex_y(ghost) < _visual_world_top_y(ghost) - 0.01,
		"the rolled bar's shaft must stay under the bar, never reach its own top."
	)


## The owner's second repro (screenshot_20260924_204154.png): a T-piece rolled
## 30 degrees -- its stem tips out past the bar's silhouette, so part of the
## outline sits under the stem's own tilted underside, higher than the bar's.
func test_tilted_t_piece_silhouette_is_one_loop_hugging_its_underside() -> void:
	var ghost: GhostPreview = _held_ghost("res://config/blocks/T4.tres", 30.0)

	assert_eq(ghost.projection_outline_loop_count(), 1, "a rolled T4's rendered silhouette is one outer loop.")
	_assert_walls_tile_the_outline(ghost)
	_assert_no_duplicate_wall_edges(ghost.projection_mesh_vertices_world())
	_assert_wall_tops_follow_the_underside(ghost)
	assert_true(
		_max_wall_vertex_y(ghost) < _visual_world_top_y(ghost) - 0.01,
		"the rolled T4's shaft must stay under the piece, never reach its own top."
	)


## A shape resting flush on the ground (manual_hover_offset cancelling
## hover_height and the collision margin) has no shaft under it at all --
## Bontago-xtq.16's "no shaft where the shape sits on the ground" -- while
## projection_span_y() (spawn-clearance bookkeeping) still reports the body.
func test_flush_shape_draws_no_shaft_walls() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.manual_hover_offset = ghost.tuning.cube_margin * 0.5 - ghost.tuning.hover_height
	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_false(ghost.has_projection_mesh(), "a cube sitting on the disc has no gap to show a shaft in.")
	assert_true(ghost.projection_span_y().x > 0.0, "projection_span_y() still reports the body's own top for spawn clearance.")


## The S4 bug's own literal edge-dedup repro (Bontago-xtq.18): still true under
## the silhouette model, now for a structural reason -- one merged outline has
## no internal seam to duplicate at all.
func test_s4_at_identity_rotation_never_draws_the_same_wall_edge_twice() -> void:
	var ghost: GhostPreview = _held_ghost("res://config/blocks/S4.tres", 0.0)

	var vertices: PackedVector3Array = ghost.projection_mesh_vertices_world()
	assert_false(vertices.is_empty(), "fixture: a real gap between the shape and the disc must show prism geometry.")
	_assert_no_duplicate_wall_edges(vertices)


## Cache contract: moving the ghost (same shape, same rotation) re-emits the
## same walls at the new height without rebuilding the outline; the relative
## wall heights are unchanged.
func test_moving_the_ghost_only_offsets_the_cached_walls() -> void:
	var ghost: GhostPreview = _held_ghost("res://config/blocks/T4.tres", 30.0)
	var before: PackedVector3Array = ghost.projection_mesh_vertices_world()
	var before_y: float = ghost.global_position.y
	var cached_loops: Array[PackedVector2Array] = ghost._cached_silhouette_loops

	ghost.update_placement(Vector3(1.0, 0.5, -2.0), Vector3.UP)

	var after: PackedVector3Array = ghost.projection_mesh_vertices_world()
	assert_same(ghost._cached_silhouette_loops, cached_loops, "a pure move must hit the (shape, basis) cache.")
	assert_eq(after.size(), before.size())
	var rise: float = ghost.global_position.y - before_y
	for wall_index: int in range(before.size() / 4):
		for k: int in range(2):
			var old_top: Vector3 = before[wall_index * 4 + k]
			var new_top: Vector3 = after[wall_index * 4 + k]
			assert_almost_eq(new_top.y - old_top.y, rise, 0.001, "wall tops move with the ghost.")
			assert_almost_eq(new_top.x - old_top.x, 1.0, 0.001)
			assert_almost_eq(new_top.z - old_top.z, -2.0, 0.001)


## Bontago-xtq.18 (this file's own fix (1)): the prism's own wall geometry
## must not sit exactly at the disc's own surface height -- CULL_DISABLED
## alpha geometry coincident with the disc's own opaque depth Z-fights into
## the same reported noise. Reuses ghost_tuning.footprint_offset, the same
## epsilon the footprint quad already lifts itself by above the disc
## (_update_footprint()).
func test_projection_prism_wall_bottom_clears_the_disc_by_footprint_offset() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	var vertices: PackedVector3Array = ghost.projection_mesh_vertices_world()
	assert_false(vertices.is_empty(), "fixture: a real gap between the shape and the disc must show prism geometry.")
	var lowest_vertex_y: float = INF
	for vertex: Vector3 in vertices:
		lowest_vertex_y = minf(lowest_vertex_y, vertex.y)

	var disc_landing_y: float = ghost.footprint_quad_position(0).y - ghost.ghost_tuning.footprint_offset
	assert_almost_eq(
		lowest_vertex_y, disc_landing_y + ghost.ghost_tuning.footprint_offset, 0.001,
		"the wall's own lowest vertex must clear the disc surface by footprint_offset, never sit exactly on it."
	)


# --- Bontago-xtq.15 (owner playtest 2026-09-23, "the same white projection
# that shows up on the disk should show up on the blocks as well, just a bit
# fainter") -------------------------------------------------------------------

## Must fail against the pre-xtq.15 code (block_projection_decal_visible()
## did not exist at all -- no decal was ever built) and pass once the decal
## is built, hidden by default, and shown the moment a shape is held.
func test_block_projection_decal_exists_and_is_hidden_with_no_shape_held() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_false(
		ghost.block_projection_decal_visible(),
		"no shape held -> no footprint at all -> the block-projection decal must stay hidden."
	)


func test_block_projection_decal_is_visible_enabled_once_a_shape_is_held() -> void:
	var ghost: GhostPreview = _make_ghost()

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_true(
		ghost.block_projection_decal_visible(),
		"a real gap between a held cube and the disc must show the block-projection decal."
	)


## The decal's own horizontal size/position must track the footprint hull's
## own world-space bounding box exactly -- the same hull the flat footprint
## quad (footprint_polygon_world()) already shows.
func test_block_projection_decal_size_tracks_the_footprint_hull() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/bar3.tres"))

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	var hull: PackedVector2Array = ghost.footprint_polygon_world(0)
	var min_point: Vector2 = hull[0]
	var max_point: Vector2 = hull[0]
	for point: Vector2 in hull:
		min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
		max_point = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))

	var decal_size: Vector3 = ghost.block_projection_decal_size()
	assert_almost_eq(decal_size.x, max_point.x - min_point.x, 0.01, "decal width must match the footprint hull's own width.")
	assert_almost_eq(decal_size.z, max_point.y - min_point.y, 0.01, "decal depth must match the footprint hull's own depth.")

	var decal_position: Vector3 = ghost.block_projection_decal_position()
	assert_almost_eq(decal_position.x, (min_point.x + max_point.x) * 0.5, 0.01, "decal must be centred on the footprint hull.")
	assert_almost_eq(decal_position.z, (min_point.y + max_point.y) * 0.5, 0.01, "decal must be centred on the footprint hull.")


## The decal's own vertical span must reach from the ghost's own current
## underside down to the disc -- never any higher (the held ghost's own body
## must never fall inside the decal's own projection volume, this file's
## own _update_block_projection_decal() DECISION) and never any lower (the
## disc/a placed block sitting on it is the floor).
func test_block_projection_decal_spans_from_the_ghosts_underside_to_the_disc() -> void:
	var ghost: GhostPreview = _make_ghost()

	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	var decal_size: Vector3 = ghost.block_projection_decal_size()
	var decal_position: Vector3 = ghost.block_projection_decal_position()
	var decal_top: float = decal_position.y + decal_size.y * 0.5
	var decal_bottom: float = decal_position.y - decal_size.y * 0.5

	assert_almost_eq(
		decal_top, _visual_world_bottom_y(ghost), 0.05,
		"the decal's own top must reach the ghost's own current underside, not any higher into its solid body."
	)
	assert_almost_eq(
		decal_bottom, ghost.footprint_quad_position(0).y - ghost.ghost_tuning.footprint_offset, 0.05,
		"the decal's own bottom must match the footprint's own disc landing height."
	)


## Colour/alpha must come straight from GhostTuning, not a hard-coded value.
func test_block_projection_decal_colour_comes_from_tuning() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	var color: Color = ghost.block_projection_decal_color()
	assert_almost_eq(color.r, ghost.ghost_tuning.block_projection_color.r, 0.001)
	assert_almost_eq(color.g, ghost.ghost_tuning.block_projection_color.g, 0.001)
	assert_almost_eq(color.b, ghost.ghost_tuning.block_projection_color.b, 0.001)
	assert_almost_eq(color.a, ghost.ghost_tuning.block_projection_alpha, 0.001, "alpha must come from block_projection_alpha, not the colour's own stored alpha.")


func test_block_projection_defaults() -> void:
	var fresh: GhostTuning = GhostTuning.new()
	assert_almost_eq(fresh.block_projection_alpha, 0.5, 0.0001)
	assert_true(fresh.block_projection_color.r >= 0.85 and fresh.block_projection_color.g >= 0.85 and fresh.block_projection_color.b >= 0.85, "default must be near-white, matching the disc's own footprint marker.")


# --- Bontago-xtq.18 attempt 3 (feel8a, feedback/owner-noise-footprint.png:
# black/white speckle under the ghost; root cause was the block-projection
# decal painting the disc with a box bottom exactly on the disc and 0.0
# fades, i.e. pow(0, 0) = NaN per pixel) ------------------------------------

## Failed before the fix: the decal kept Decal's default all-layers cull_mask,
## which includes DiscMirror.DISC_LAYER_BIT, the disc's only render layer.
func test_block_projection_decal_never_paints_the_disc_layer() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	var mask: int = ghost._block_projection_decal.cull_mask
	assert_eq(mask & DiscMirror.DISC_LAYER_BIT, 0, "the decal must not reach the disc's own render layer.")
	assert_ne(mask & 1, 0, "placed blocks (render layer 1) must still receive the projection.")


## Failed before the fix: both fades were hard-coded 0.0, so any surface
## lying exactly on the decal box's top or bottom plane evaluated pow(0, 0).
func test_block_projection_decal_fades_stay_above_zero() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_gt(ghost._block_projection_decal.upper_fade, 0.0, "upper fade 0.0 renders NaN speckle on the box's top plane.")
	assert_gt(ghost._block_projection_decal.lower_fade, 0.0, "lower fade 0.0 renders NaN speckle on the box's bottom plane.")


## A tuning value of 0 (reachable from the F4 panel or a hand-edited .tres)
## must still be clamped above zero, not passed straight to the Decal.
func test_block_projection_decal_fade_is_clamped_when_tuning_is_zero() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	ghost.ghost_tuning = (load("res://config/ghost_tuning.tres") as GhostTuning).duplicate()
	ghost.ghost_tuning.block_projection_edge_fade = 0.0
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	var fades: Vector2 = ghost.block_projection_decal_fades()
	assert_gt(fades.x, 0.0)
	assert_gt(fades.y, 0.0)
	assert_eq(ghost.block_projection_decal_cull_mask(), ghost._block_projection_decal.cull_mask)


func test_block_projection_edge_fade_default_is_small_and_positive() -> void:
	var fresh: GhostTuning = GhostTuning.new()
	assert_gt(fresh.block_projection_edge_fade, 0.0)
	assert_lt(fresh.block_projection_edge_fade, 0.05, "the shaft should stay crisp, not visibly fade.")
