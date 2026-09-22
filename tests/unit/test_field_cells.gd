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
## Upper bound on frames for a 60 m drop to land and sleep (10 s at 60 Hz).
const FALL_TIMEOUT_FRAMES: int = 600


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


## Applied holes across the disk. Bontago-ruw replaced one shape owner per
## cell with one disk trimesh, so this counts the logical applied state rather
## than disabled owners; test_the_disk_is_one_owner_and_collides_exactly_off_holes
## pins that the physics agrees with it.
func _hole_cell_count(field: Field) -> int:
	var holes: int = 0
	for cell: int in field.grid().in_disk_cells():
		if field.is_hole_cell(cell):
			holes += 1
	return holes


## A straight-down ray through a cell's center, from above the surface to
## below the disk's underside. These fixtures hold no other bodies there, so a
## hit means the cell has collision.
func _ray_at_cell(field: Field, cell: int) -> Dictionary:
	var center: Vector2 = field.grid().index_center(cell)
	var start: Vector3 = field.world_from_disk_local(center, field.map_def.disk_height)
	var end: Vector3 = field.world_from_disk_local(center, -2.0 * field.map_def.disk_height)
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, end)
	params.collide_with_areas = false
	return field.get_world_3d().direct_space_state.intersect_ray(params)


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

func test_the_disk_is_one_owner_and_collides_exactly_off_holes() -> void:
	# Bontago-ruw: the disk is one trimesh on one shape owner. What the old
	# one-owner-per-cell assertion protected is that collision and the logical
	# hole state agree cell by cell, so check that directly, with a lone hole,
	# a small patch and a hole on the rim.
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	var expected: int = _expected_in_disk_cells(grid)
	assert_gt(expected, 0, "A 6 m disk should hold cells.")
	assert_eq(field.get_shape_owners().size(), 1, "The disk is one shape owner.")
	assert_eq(field.cell_count(), expected)
	assert_eq(_hole_cell_count(field), 0, "No cell starts out as a hole.")

	var middle: int = floori(float(grid.res) * 0.5)
	var opened: PackedInt32Array = PackedInt32Array([
		grid.cell_index(middle, middle),
		grid.cell_index(middle + 3, middle), grid.cell_index(middle + 4, middle),
		grid.cell_index(middle + 3, middle + 1),
		grid.in_disk_cells()[0],
	])
	field.set_hole_cells(opened, PackedInt32Array())
	field._drain_toggles()
	await wait_physics_frames(1)

	for cell: int in grid.in_disk_cells():
		var hit: Dictionary = _ray_at_cell(field, cell)
		if field.is_hole_cell(cell):
			assert_true(hit.is_empty(), "Hole cell %d must have no collision." % cell)
			continue
		assert_false(hit.is_empty(), "Solid cell %d must have collision." % cell)
		if not hit.is_empty():
			assert_eq(hit["collider"], field, "Cell %d is the disk's own collision." % cell)
			assert_almost_eq(
				(hit["position"] as Vector3).y, 0.0, 0.0001,
				"Cell %d's surface is the disk top, y = 0." % cell
			)
	assert_eq(_hole_cell_count(field), opened.size())


func test_cells_outside_the_disk_have_no_owner() -> void:
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	# The -x/-z corner of the bounding square is the farthest cell from the
	# center, so it is always outside the disk.
	var corner: int = grid.cell_index(0, 0)
	assert_false(grid.is_in_disk(0, 0), "The corner cell is outside the disk.")
	assert_eq(field.cell_owner_id(corner), -1)
	assert_false(field.is_hole_cell(corner))


func test_every_in_disk_cell_reports_the_disk_owner() -> void:
	var field: Field = _make_field()
	var owners: PackedInt32Array = field.get_shape_owners()
	assert_eq(owners.size(), 1)
	for cell: int in field.grid().in_disk_cells():
		assert_eq(field.cell_owner_id(cell), owners[0])


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

func test_set_hole_cells_opens_the_named_cells() -> void:
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
		assert_true(_ray_at_cell(field, cell).is_empty(), "Cell %d lost its collision." % cell)
	assert_eq(_hole_cell_count(field), opened.size())


func test_closing_a_hole_restores_its_collision() -> void:
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	var cells: PackedInt32Array = _cells_near_center(grid, 1.5)

	field.set_hole_cells(cells, PackedInt32Array())
	await wait_physics_frames(1)
	field.set_hole_cells(PackedInt32Array(), cells)
	await wait_physics_frames(1)

	assert_eq(_hole_cell_count(field), 0, "Every hole closed again.")
	for cell: int in cells:
		assert_false(field.is_hole_cell(cell))
		assert_false(_ray_at_cell(field, cell).is_empty(), "Cell %d collides again." % cell)


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
	assert_eq(_hole_cell_count(field), budget, "One frame applies exactly the budget.")
	assert_eq(field.pending_toggle_count(), all_cells.size() - budget)
	field._drain_toggles()
	assert_lte(
		_hole_cell_count(field),
		budget * 2,
		"Spec 3.3: at most max_cell_toggles_per_frame toggles in a frame."
	)

	var frames: int = 0
	while field.pending_toggle_count() > 0 and frames < 100:
		await wait_physics_frames(1)
		frames += 1
	assert_eq(
		_hole_cell_count(field),
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


## Bontago-ruw: spec 2.2, "blocks resting on holes fall through", for a *lone*
## hole cell with every neighbour still solid. The old per-cell boxes were
## grown by MapDef.cell_overlap, so a lone hole was only 0.8 m of clear
## opening under a 1 m block and the block caught on its neighbours' rims
## (this test was pending for that). The disk trimesh leaves an exact
## cell_size opening, so the block now drops through.
func test_a_block_over_a_lone_hole_cell_falls_through() -> void:
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	var middle: int = floori(float(grid.res) * 0.5)
	var lone_cell: int = grid.cell_index(middle, middle)
	var center: Vector2 = grid.index_center(lone_cell)
	# DECISION (tests/unit/test_field_cells.gd, Bontago-ruw): a real cube block
	# from BlockFactory (cube_size - cube_margin = 0.98 m), not _make_cube()'s
	# bare 1.0 m box. A box exactly as wide as the hole has zero clearance and
	# wedges on the opening's edges, which is not a block the game can place.
	var body: RigidBody3D = BlockFactory.build(load("res://config/blocks/cube.tres"), field.tuning)
	field.get_parent().add_child(body)
	autofree(body)
	body.global_position = Vector3(center.x, 2.0, center.y)
	await wait_physics_frames(SETTLE_FRAMES)

	body.sleeping = true
	field.set_hole_cells(PackedInt32Array([lone_cell]), PackedInt32Array())
	await wait_physics_frames(FALL_FRAMES)

	assert_true(is_instance_valid(body), "The kill plane is far below; the cube lives.")
	assert_lt(
		body.global_position.y,
		-field.map_def.disk_height,
		"A block on a lone hole cell falls clear through the disk."
	)


## The trimesh is a surface, not a 1 m thick box, so check it still stops a
## block arriving at the fastest speed a match plausibly produces: a fall from
## map_def.cell_wake_height (60 m, the tallest tower the wake query covers),
## ~34 m/s, over half a block per physics tick.
func test_a_block_dropped_from_the_wake_height_lands_on_the_surface() -> void:
	var field: Field = _make_field()
	var body: RigidBody3D = _make_cube(field, Vector3(0.0, field.map_def.cell_wake_height, 0.0))
	var frames: int = 0
	while frames < FALL_TIMEOUT_FRAMES and not body.sleeping:
		await wait_physics_frames(1)
		frames += 1
	assert_almost_eq(
		body.global_position.y, 0.5, 0.1, "The cube stops on the surface instead of tunnelling."
	)


## Spec 3.3 via docs/M4_PLAN.md P0a: the mesh is rebuilt at most once per
## drain, and only when a toggle was actually applied.
func test_the_disk_mesh_rebuilds_once_per_applied_batch() -> void:
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	var built: int = field._rebuild_count
	field._drain_toggles()
	assert_eq(field._rebuild_count, built, "Nothing queued, nothing rebuilt.")

	var all_cells: PackedInt32Array = _cells_near_center(grid, field.map_def.field_radius)
	field.set_hole_cells(all_cells, PackedInt32Array())
	field._drain_toggles()
	assert_eq(field._rebuild_count, built + 1, "One rebuild for a whole budget of toggles.")
	while field.pending_toggle_count() > 0:
		field._drain_toggles()
	var drained: int = field._rebuild_count
	# Every cell is a hole now: the mesh is empty and the owner disabled.
	assert_true(field.is_shape_owner_disabled(field.get_shape_owners()[0]))

	field._drain_toggles()
	assert_eq(field._rebuild_count, drained, "An empty backlog does not rebuild.")
	field.set_hole_cells(PackedInt32Array(), all_cells)
	field._drain_toggles()
	assert_false(field.is_shape_owner_disabled(field.get_shape_owners()[0]))
