extends GutTest
## Field's cell collision and its batched hole toggles (spec 2.1, 3.3).
##
## Every test builds a deliberately small disk — a 6 m radius is 113 in-disk
## cells at cell_size 1, enough to overflow the 64-per-frame toggle budget in
## exactly two frames and small enough that a physics test runs in a blink.

## Frames to let a dropped cube come to rest on the disk.
const SETTLE_FRAMES: int = 90
## Frames to let a woken cube fall clear of the disk once its cell opens. At
## 60 Hz this is 1.5 s, roughly 11 m of free fall, well short of the kill
## plane at -40.
const FALL_FRAMES: int = 90


func _small_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_small"
	map_def.field_radius = 6.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	return map_def


func _make_field() -> Field:
	var field: Field = Field.new()
	field.map_def = _small_map()
	add_child_autofree(field)
	return field


func _expected_in_disk_cells(grid: CellGrid) -> int:
	var count: int = 0
	for cy: int in range(grid.res):
		for cx: int in range(grid.res):
			if grid.is_in_disk(cx, cy):
				count += 1
	return count


func _disabled_owner_count(field: Field) -> int:
	var disabled: int = 0
	for owner_id: int in field.get_shape_owners():
		if field.is_shape_owner_disabled(owner_id):
			disabled += 1
	return disabled


func _make_cube(field: Field, at: Vector3) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3.ONE
	collision.shape = box
	body.add_child(collision)
	field.get_parent().add_child(body)
	autofree(body)
	body.global_position = at
	return body


## Cells whose centers lie within `reach` of the disk-local origin — the patch
## under a 1 m cube resting at the middle of the disk, plus a ring of margin so
## the cube cannot bridge the gap.
func _cells_near_center(grid: CellGrid, reach: float) -> PackedInt32Array:
	var cells: PackedInt32Array = PackedInt32Array()
	for cy: int in range(grid.res):
		for cx: int in range(grid.res):
			if not grid.is_in_disk(cx, cy):
				continue
			if grid.cell_center(cx, cy).length() <= reach:
				cells.append(grid.cell_index(cx, cy))
	return cells


# --- The grid ---------------------------------------------------------------

func test_one_enabled_shape_owner_per_in_disk_cell() -> void:
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	var expected: int = _expected_in_disk_cells(grid)

	assert_gt(expected, 0, "A 6 m disk should hold cells.")
	assert_eq(
		field.get_shape_owners().size(),
		expected,
		"Field should build exactly one shape owner per in-disk cell."
	)
	assert_eq(field.cell_count(), expected)
	assert_eq(_disabled_owner_count(field), 0, "No cell starts out as a hole.")


func test_cells_outside_the_disk_have_no_owner() -> void:
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	# The -x/-z corner of the bounding square is the farthest cell from the
	# center, so it is always outside the disk.
	var corner: int = grid.cell_index(0, 0)
	assert_false(grid.is_in_disk(0, 0), "The corner cell is outside the disk.")
	assert_eq(field.cell_owner_id(corner), -1)
	assert_false(field.is_hole_cell(corner))


func test_cell_owner_sits_under_its_cell_center() -> void:
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	var middle: int = floori(float(grid.res) * 0.5)
	var index: int = grid.cell_index(middle, middle)
	var owner_id: int = field.cell_owner_id(index)
	assert_gt(owner_id, -1, "A center cell has collision.")

	var origin: Vector3 = field.shape_owner_get_transform(owner_id).origin
	var center: Vector2 = grid.index_center(index)
	assert_almost_eq(origin.x, center.x, 0.0001)
	assert_almost_eq(origin.z, center.y, 0.0001)
	assert_almost_eq(
		origin.y,
		-field.map_def.disk_height * 0.5,
		0.0001,
		"The cell box hangs below the disk surface, so the surface is y = 0."
	)


# --- Coordinates ------------------------------------------------------------

func test_disk_local_and_world_round_trip() -> void:
	var field: Field = _make_field()
	var local: Vector2 = Vector2(2.5, -3.25)
	var world: Vector3 = field.world_from_disk_local(local, 4.0)

	assert_almost_eq(world.y, 4.0, 0.0001, "Height is measured from the surface.")
	var back: Vector2 = field.disk_local_from_world(world)
	assert_almost_eq(back.x, local.x, 0.0001)
	assert_almost_eq(back.y, local.y, 0.0001)


func test_surface_y_is_zero_while_the_disk_is_flat() -> void:
	var field: Field = _make_field()
	assert_almost_eq(field.surface_y(), 0.0, 0.0001)


func test_coordinates_follow_the_field_transform() -> void:
	var field: Field = _make_field()
	field.global_position = Vector3(10.0, 3.0, -4.0)
	assert_almost_eq(field.surface_y(), 3.0, 0.0001)

	var world: Vector3 = field.world_from_disk_local(Vector2(1.0, 2.0), 0.5)
	assert_almost_eq(world.x, 11.0, 0.0001)
	assert_almost_eq(world.y, 3.5, 0.0001)
	assert_almost_eq(world.z, -2.0, 0.0001)


# --- Holes ------------------------------------------------------------------

func test_set_hole_cells_disables_the_named_owners() -> void:
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	var opened: PackedInt32Array = _cells_near_center(grid, 1.5)
	assert_gt(opened.size(), 0)

	field.set_hole_cells(opened, PackedInt32Array())
	assert_eq(
		field.pending_toggle_count(),
		opened.size(),
		"Nothing is applied until the backlog drains."
	)
	await wait_physics_frames(1)

	for cell: int in opened:
		assert_true(field.is_hole_cell(cell), "Cell %d should be a hole." % cell)
		assert_true(field.is_shape_owner_disabled(field.cell_owner_id(cell)))
	assert_eq(_disabled_owner_count(field), opened.size())


func test_closing_a_hole_re_enables_its_owner() -> void:
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	var cells: PackedInt32Array = _cells_near_center(grid, 1.5)

	field.set_hole_cells(cells, PackedInt32Array())
	await wait_physics_frames(1)
	field.set_hole_cells(PackedInt32Array(), cells)
	await wait_physics_frames(1)

	assert_eq(_disabled_owner_count(field), 0, "Every hole closed again.")
	for cell: int in cells:
		assert_false(field.is_hole_cell(cell))


func test_backlog_drains_at_the_per_frame_budget() -> void:
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	var budget: int = field.territory_tuning.max_cell_toggles_per_frame
	var all_cells: PackedInt32Array = _cells_near_center(grid, field.map_def.field_radius)
	assert_gt(
		all_cells.size(),
		budget,
		"The test needs more cells than one frame's budget to be a test."
	)

	field.set_hole_cells(all_cells, PackedInt32Array())
	# Drained by hand rather than by awaiting, because one awaited frame is not
	# guaranteed to be exactly one _physics_process call; the invariant under
	# test is per drain, not per await.
	field._drain_toggles()
	assert_eq(_disabled_owner_count(field), budget, "One frame applies exactly the budget.")
	assert_eq(field.pending_toggle_count(), all_cells.size() - budget)
	field._drain_toggles()
	assert_lte(
		_disabled_owner_count(field),
		budget * 2,
		"Spec 3.3: at most max_cell_toggles_per_frame toggles in a frame."
	)

	var frames: int = 0
	while field.pending_toggle_count() > 0 and frames < 100:
		await wait_physics_frames(1)
		frames += 1
	assert_eq(
		_disabled_owner_count(field),
		all_cells.size(),
		"The backlog drains completely over several frames."
	)


func test_repeating_a_hole_request_does_not_queue_twice() -> void:
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	var cells: PackedInt32Array = _cells_near_center(grid, 1.5)

	field.set_hole_cells(cells, PackedInt32Array())
	field.set_hole_cells(cells, PackedInt32Array())
	assert_eq(
		field.pending_toggle_count(),
		cells.size(),
		"A cell already heading for the same state is not enqueued again."
	)


# --- Waking and falling through (spec 3.3) ----------------------------------

func test_a_sleeping_body_over_a_changed_cell_wakes() -> void:
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	var body: RigidBody3D = _make_cube(field, Vector3(0.0, 2.0, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)

	body.sleeping = true
	await wait_physics_frames(1)
	assert_true(body.sleeping, "The cube should be asleep before the hole opens.")

	field.set_hole_cells(_cells_near_center(grid, 1.5), PackedInt32Array())
	await wait_physics_frames(2)
	assert_false(body.sleeping, "Opening the cell under a body must wake it.")


func test_a_block_falls_through_an_opened_cell() -> void:
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	var body: RigidBody3D = _make_cube(field, Vector3(0.0, 2.0, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	assert_almost_eq(
		body.global_position.y, 0.5, 0.1, "The cube rests on the disk surface."
	)

	body.sleeping = true
	field.set_hole_cells(_cells_near_center(grid, 1.5), PackedInt32Array())
	await wait_physics_frames(FALL_FRAMES)

	assert_true(is_instance_valid(body), "The kill plane is far below; the cube lives.")
	assert_lt(
		body.global_position.y,
		-field.map_def.disk_height,
		"A block on an opened cell falls clear through the disk."
	)
