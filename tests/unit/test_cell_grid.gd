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
	assert_eq(grid.res, 90, "A 45 m radius disk needs 90 cells of 1 m per side.")
	assert_eq(grid.cell_count(), 90 * 90)


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
	assert_almost_eq(center.x, -MAP_RADIUS + 0.5 * CELL, 0.0001)
	assert_almost_eq(center.y, -MAP_RADIUS + 0.5 * CELL, 0.0001)


func test_disk_center_falls_at_the_middle_cell() -> void:
	var grid: CellGrid = _grid()
	var coords: Vector2i = grid.world_to_cell(Vector2.ZERO)
	assert_eq(coords, Vector2i(grid.res / 2, grid.res / 2))


func test_world_to_cell_inverts_cell_center() -> void:
	var grid: CellGrid = _grid()
	for cy: int in [0, 7, 45, 89]:
		for cx: int in [0, 13, 45, 89]:
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
