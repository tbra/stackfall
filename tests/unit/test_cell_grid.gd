extends GutTest
## CellGrid is the one disk-local coordinate convention the solver, the raster,
## Field's collision cells and placement validation all share (spec 3.3,
## docs/M2_PLAN.md "Raster coordinates"). If these break, the three disagree
## about where a hole is.

const MAP_RADIUS: float = 45.0
const CELL: float = 1.0


func _grid() -> CellGrid:
	return CellGrid.new(MAP_RADIUS, CELL)


func test_resolution_covers_the_bounding_square() -> void:
	var grid: CellGrid = _grid()
	# 90 cells of 1 m cover a 45 m radius disk, rounded up to 91 so the square
	# has a middle cell and it is centred on the disk centre (the DECISION in
	# CellGrid.gd: Field's per-cell collision needs that alignment).
	assert_eq(grid.res, 91)
	assert_eq(grid.cell_count(), 91 * 91)
	assert_eq(grid.res % 2, 1, "res is always odd.")
	assert_almost_eq(grid.half_extent, 45.5, 0.0001)


func test_a_cell_is_centred_on_the_disk_centre() -> void:
	var grid: CellGrid = _grid()
	var middle: Vector2i = grid.world_to_cell(Vector2.ZERO)
	assert_true(
		grid.cell_center(middle.x, middle.y).is_equal_approx(Vector2.ZERO),
		"The disk centre must be a cell centre, not a cell corner."
	)


func test_every_cell_centre_is_a_multiple_of_cell_size() -> void:
	var grid: CellGrid = _grid()
	for cx: int in [0, 1, 45, 90]:
		var center: Vector2 = grid.cell_center(cx, cx)
		assert_almost_eq(center.x - roundf(center.x / CELL) * CELL, 0.0, 0.0001)


func test_resolution_rounds_up_for_non_dividing_cell_sizes() -> void:
	var grid: CellGrid = CellGrid.new(10.0, 3.0)
	assert_eq(grid.res, 7, "ceil(20 / 3) = 7 cells per side.")


func test_index_and_coords_round_trip() -> void:
	var grid: CellGrid = _grid()
	for index: int in [0, 1, 89, 90, 4095, grid.cell_count() - 1]:
		var coords: Vector2i = grid.cell_coords(index)
		assert_eq(grid.cell_index(coords.x, coords.y), index)


func test_index_is_row_major() -> void:
	var grid: CellGrid = _grid()
	assert_eq(grid.cell_index(0, 0), 0, "Cell (0,0) is the -x/-z corner.")
	assert_eq(grid.cell_index(1, 0), 1, "x advances first.")
	assert_eq(grid.cell_index(0, 1), grid.res, "Then z, a whole row at a time.")


func test_cell_zero_is_the_negative_corner() -> void:
	var grid: CellGrid = _grid()
	var center: Vector2 = grid.cell_center(0, 0)
	assert_almost_eq(center.x, -grid.half_extent + 0.5 * CELL, 0.0001)
	assert_almost_eq(center.y, -grid.half_extent + 0.5 * CELL, 0.0001)
	assert_lt(center.x, -MAP_RADIUS + CELL, "Cell 0 sits outside the disk rim.")


func test_disk_center_falls_at_the_middle_cell() -> void:
	var grid: CellGrid = _grid()
	var coords: Vector2i = grid.world_to_cell(Vector2.ZERO)
	assert_eq(coords, Vector2i(grid.res / 2, grid.res / 2))


func test_world_to_cell_inverts_cell_center() -> void:
	var grid: CellGrid = _grid()
	for cy: int in [0, 7, 45, 90]:
		for cx: int in [0, 13, 45, 90]:
			assert_eq(grid.world_to_cell(grid.cell_center(cx, cy)), Vector2i(cx, cy))


func test_index_center_matches_cell_center() -> void:
	var grid: CellGrid = _grid()
	var index: int = grid.cell_index(12, 34)
	assert_eq(grid.index_center(index), grid.cell_center(12, 34))


func test_in_bounds_rejects_outside_the_square() -> void:
	var grid: CellGrid = _grid()
	assert_true(grid.in_bounds(0, 0))
	assert_true(grid.in_bounds(grid.res - 1, grid.res - 1))
	assert_false(grid.in_bounds(-1, 0))
	assert_false(grid.in_bounds(0, -1))
	assert_false(grid.in_bounds(grid.res, 0))
	assert_false(grid.in_bounds(0, grid.res))


func test_membership_is_decided_by_the_cell_center() -> void:
	var grid: CellGrid = _grid()
	assert_true(grid.is_in_disk(grid.res / 2, grid.res / 2), "The center cell is in.")
	assert_false(grid.is_in_disk(0, 0), "The corner of the bounding square is out.")
	assert_false(grid.is_in_disk(grid.res - 1, grid.res - 1))


func test_in_disk_cell_count_approximates_the_disk_area() -> void:
	var grid: CellGrid = _grid()
	var area: float = PI * MAP_RADIUS * MAP_RADIUS / (CELL * CELL)
	var count: int = grid.in_disk_cell_count()
	assert_almost_eq(float(count), area, area * 0.01,
		"A 1 m grid over a 45 m disk should be within 1%% of pi*r^2 cells.")


func test_in_disk_cells_matches_the_count_and_is_ascending() -> void:
	var grid: CellGrid = _grid()
	var cells: PackedInt32Array = grid.in_disk_cells()
	assert_eq(cells.size(), grid.in_disk_cell_count())
	var previous: int = -1
	for index: int in cells:
		assert_gt(index, previous, "in_disk_cells() is row-major ascending.")
		previous = index


func test_every_listed_cell_is_really_in_the_disk() -> void:
	var grid: CellGrid = CellGrid.new(8.0, 1.0)
	var listed: Dictionary[int, bool] = {}
	for index: int in grid.in_disk_cells():
		listed[index] = true
	for cy: int in range(grid.res):
		for cx: int in range(grid.res):
			var index: int = grid.cell_index(cx, cy)
			assert_eq(listed.has(index), grid.is_in_disk(cx, cy),
				"Cell (%d,%d) listing must agree with is_in_disk." % [cx, cy])


func test_in_disk_cells_are_cached_not_rebuilt() -> void:
	var grid: CellGrid = _grid()
	var first: PackedInt32Array = grid.in_disk_cells()
	var second: PackedInt32Array = grid.in_disk_cells()
	assert_eq(first.size(), second.size())
	assert_eq(grid.in_disk_cell_count(), first.size())


# --- The map-shape mechanism: an optional third p_shape_test Callable
# (docs/M6_PLAN.md package A0, config/MapDef.gd's shape_test()) -------------

func _always_false(_local: Vector2) -> bool:
	return false


func _always_true(_local: Vector2) -> bool:
	return true


func test_a_false_shape_test_excludes_every_cell() -> void:
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, CELL, Callable(self, "_always_false"))
	assert_eq(
		grid.in_disk_cell_count(), 0,
		"an always-false shape_test must reject every cell, including the disk center"
	)
	assert_true(grid.in_disk_cells().is_empty())


func test_a_true_shape_test_matches_the_plain_circle_count() -> void:
	var plain: CellGrid = _grid()
	var shaped: CellGrid = CellGrid.new(MAP_RADIUS, CELL, Callable(self, "_always_true"))
	assert_eq(
		shaped.in_disk_cell_count(), plain.in_disk_cell_count(),
		"a shape_test present but equivalent to the circle must change nothing"
	)
	assert_eq(shaped.in_disk_cells(), plain.in_disk_cells())


func test_two_argument_constructor_still_behaves_as_a_plain_circle() -> void:
	# Byte-identical regression: every existing two-argument CellGrid.new()
	# call site (a dozen of them, tests included) must keep compiling and
	# behaving exactly as before this package.
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, CELL)
	assert_eq(grid.in_disk_cell_count(), _grid().in_disk_cell_count())
