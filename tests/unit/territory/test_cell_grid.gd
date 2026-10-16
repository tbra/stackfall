extends GutTest
## CellGrid is the one disk-local coordinate convention the solver, the raster,
## Field's collision cells and placement validation all share (spec 3.3,
## docs/archive/M2_PLAN.md "Raster coordinates"). If these break, the three disagree
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


func test_index_and_coords_round_trip() -> void:
	var grid: CellGrid = _grid()
	for index: int in [0, 1, 89, 90, 4095, grid.cell_count() - 1]:
		var coords: Vector2i = grid.cell_coords(index)
		assert_eq(grid.cell_index(coords.x, coords.y), index)


func test_world_to_cell_inverts_cell_center() -> void:
	var grid: CellGrid = _grid()
	for cy: int in [0, 7, 45, 90]:
		for cx: int in [0, 13, 45, 90]:
			assert_eq(grid.world_to_cell(grid.cell_center(cx, cy)), Vector2i(cx, cy))


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


func test_in_disk_cells_matches_the_count_and_is_ascending() -> void:
	var grid: CellGrid = _grid()
	var cells: PackedInt32Array = grid.in_disk_cells()
	assert_eq(cells.size(), grid.in_disk_cell_count())
	var previous: int = -1
	for index: int in cells:
		assert_gt(index, previous, "in_disk_cells() is row-major ascending.")
		previous = index


# --- The map-shape mechanism: an optional third p_shape_test Callable
# (docs/archive/M6_PLAN.md package A0, config/match/MapDef.gd's shape_test()) -------------

func _always_false(_local: Vector2) -> bool:
	return false


func test_a_false_shape_test_excludes_every_cell() -> void:
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, CELL, Callable(self, "_always_false"))
	assert_eq(
		grid.in_disk_cell_count(), 0,
		"an always-false shape_test must reject every cell, including the disk center"
	)
	assert_true(grid.in_disk_cells().is_empty())


