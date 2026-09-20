extends GutTest
## Field.raycast_down_disk_local() (docs/TERRITORY_V2_PLAN.md, "Placement
## validity"): the v2 ruleset's one physics query, straight down from
## map_def.cell_wake_height to tuning.kill_plane_y in world space, converted
## back to disk-local (x, z) through Field's own convention.
##
## Uses the same small-disk fixture as test_field_cells.gd, since this is the
## only other test file that needs a real physics world under a Field.

const SETTLE_FRAMES: int = 90


func _small_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_small_raycast"
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


func _cells_near_center(grid: CellGrid, reach: float) -> PackedInt32Array:
	var cells: PackedInt32Array = PackedInt32Array()
	for cy: int in range(grid.res):
		for cx: int in range(grid.res):
			if not grid.is_in_disk(cx, cy):
				continue
			if grid.cell_center(cx, cy).length() <= reach:
				cells.append(grid.cell_index(cx, cy))
	return cells


func test_hits_the_bare_disk_at_its_own_xz_when_nothing_is_stacked() -> void:
	var field: Field = _make_field()

	var hit: Variant = field.raycast_down_disk_local(Vector3(1.0, 5.0, 2.0))

	assert_typeof(hit, TYPE_VECTOR2, "A hit on the bare disk must return a disk-local point.")
	var point: Vector2 = hit as Vector2
	assert_almost_eq(point.x, 1.0, 0.01)
	assert_almost_eq(point.y, 2.0, 0.01)


func test_ignores_world_origins_own_height_and_always_looks_straight_down() -> void:
	# Deliberately independent of however the caller's own ray got here
	# (docs/TERRITORY_V2_PLAN.md): only (x, z) should matter.
	var field: Field = _make_field()

	var low: Variant = field.raycast_down_disk_local(Vector3(1.5, -3.0, -0.5))
	var high: Variant = field.raycast_down_disk_local(Vector3(1.5, 500.0, -0.5))

	assert_typeof(low, TYPE_VECTOR2)
	assert_typeof(high, TYPE_VECTOR2)
	assert_almost_eq((low as Vector2).x, (high as Vector2).x, 0.01)
	assert_almost_eq((low as Vector2).y, (high as Vector2).y, 0.01)
	assert_almost_eq((low as Vector2).x, 1.5, 0.01)
	assert_almost_eq((low as Vector2).y, -0.5, 0.01)


func test_returns_null_well_past_the_rim_with_nothing_beneath() -> void:
	var field: Field = _make_field()

	var hit: Variant = field.raycast_down_disk_local(Vector3(50.0, 5.0, 50.0))

	assert_null(hit, "Off the 6 m rim, with no collision anywhere in the column, the ray must miss.")


func test_hits_the_top_of_a_resting_block_even_through_an_open_hole_beneath_it() -> void:
	# Proves the query actually stops on the block's own collision rather than
	# only ever finding the disk: the disk cell directly under the block is
	# turned into a hole (disabled collision) and the block is frozen in place
	# (a client's mirrored blocks are frozen too, per the plan's own note that
	# freezing a body doesn't disable its collision shape) so nothing besides
	# the block itself remains in the column above the kill plane. If the
	# raycast quietly ignored bodies, this would fall straight through to a
	# miss instead.
	var field: Field = _make_field()
	var grid: CellGrid = field.grid()
	var body: RigidBody3D = _make_cube(field, Vector3(0.0, 2.0, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)

	body.freeze = true
	field.set_hole_cells(_cells_near_center(grid, 1.5), PackedInt32Array())
	await wait_physics_frames(2)

	var hit: Variant = field.raycast_down_disk_local(Vector3(0.0, 10.0, 0.0))

	assert_typeof(hit, TYPE_VECTOR2, "The frozen block's own collision must still be hit.")
	var point: Vector2 = hit as Vector2
	assert_almost_eq(point.x, 0.0, 0.2)
	assert_almost_eq(point.y, 0.0, 0.2)
