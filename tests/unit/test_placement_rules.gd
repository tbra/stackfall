extends GutTest
## Spec 3.3: "On the host, the cell under the ghost's footprint must be owned
## by the placing player's team and not contested or a hole." Every cell of the
## footprint has to pass, not just the one under the centre.
##
## Spec 2.5: "When the timer runs out, the held block drops from its current
## ghost position. If that spot isn't valid, it drops at the closest valid
## point."

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const CUBE: float = 1.0

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _physics: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _grid: CellGrid = null
var _solver: TerritorySolver = null
var _raster: TerritoryRaster = null

var _one_cube: Array[Vector3i] = [Vector3i.ZERO]
var _domino: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(1, 0, 0)]


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, CELL)
	_solver = TerritorySolver.new(_tuning)
	_raster = TerritoryRaster.new(_grid, _tuning)


func _home(x: float, z: float, team: int, slot: int = -1) -> InfluenceCircle:
	return InfluenceCircle.new(
		Vector2(x, z), _tuning.home_radius, team, slot if slot >= 0 else team, true, -1
	)


func _rasterize(circles: Array[InfluenceCircle], delta: float = 0.1) -> void:
	_raster.update(circles, _solver.solve(circles), delta, false)


## A team-0 home circle at the disk centre, so cells within home_radius are mine.
func _my_territory() -> void:
	_rasterize([_home(0.0, 0.0, 0)] as Array[InfluenceCircle])


func _footprint(origin: Vector2, cells: Array[Vector3i] = [], basis: Basis = Basis.IDENTITY
) -> PackedInt32Array:
	var shape: Array[Vector3i] = cells if not cells.is_empty() else _one_cube
	return PlacementRules.footprint_cells(shape, basis, origin, CUBE, _grid)


func _validate(origin: Vector2, team: int = 0) -> PlacementRules.Result:
	return PlacementRules.validate(_footprint(origin), _raster, team)


## -- footprint_cells ---------------------------------------------------------

func test_a_cube_on_a_cell_centre_covers_exactly_that_cell() -> void:
	var cells: PackedInt32Array = _footprint(Vector2(0.5, 0.5))
	assert_eq(cells.size(), 1, "A 1 m cube aligned with a 1 m cell covers one cell.")
	assert_eq(cells[0], _grid.cell_index(_grid.res / 2, _grid.res / 2))


func test_a_cube_straddling_a_cell_corner_covers_four_cells() -> void:
	## docs/M2_PLAN.md: "a rotated cube covers up to four cells... every cube
	## contributes the cells its footprint square overlaps, not just the one
	## under its centre."
	var cells: PackedInt32Array = _footprint(Vector2(0.0, 0.0))
	assert_eq(cells.size(), 4, "Sitting on a cell corner, it overlaps all four.")


func test_a_cube_straddling_one_edge_covers_two_cells() -> void:
	assert_eq(_footprint(Vector2(0.0, 0.5)).size(), 2)
	assert_eq(_footprint(Vector2(0.5, 0.0)).size(), 2)


func test_footprint_cells_are_ascending_and_unique() -> void:
	var cells: PackedInt32Array = _footprint(Vector2(0.0, 0.0), _domino)
	var previous: int = -1
	for index: int in cells:
		assert_gt(index, previous, "Ascending with no repeats.")
		previous = index


func test_a_domino_covers_both_of_its_cubes() -> void:
	var cells: PackedInt32Array = _footprint(Vector2(0.5, 0.5), _domino)
	assert_eq(cells.size(), 2)
	var first: Vector2i = _grid.cell_coords(cells[0])
	var second: Vector2i = _grid.cell_coords(cells[1])
	assert_eq(first.y, second.y, "Unrotated it lies along x.")
	assert_eq(absi(first.x - second.x), 1)


func test_rotating_a_domino_rotates_its_footprint() -> void:
	## A yaw of 90 degrees has to swing the second cube onto the other axis;
	## the footprint must follow the basis, not the untransformed cells.
	var yawed: Basis = BlockOrientations.get_basis(BlockOrientations.step_yaw_ccw(0))
	var cells: PackedInt32Array = _footprint(Vector2(0.5, 0.5), _domino, yawed)
	assert_eq(cells.size(), 2)
	var first: Vector2i = _grid.cell_coords(cells[0])
	var second: Vector2i = _grid.cell_coords(cells[1])
	assert_eq(first.x, second.x, "After a 90 degree yaw it lies along z.")
	assert_eq(absi(first.y - second.y), 1)


func test_a_free_rotation_still_produces_a_footprint() -> void:
	var tilted: Basis = Basis(Vector3.UP, deg_to_rad(45.0))
	var cells: PackedInt32Array = _footprint(Vector2(0.5, 0.5), _domino, tilted)
	assert_gt(cells.size(), 0, "A freely rotated block still covers cells.")


func test_an_empty_shape_has_an_empty_footprint() -> void:
	var none: Array[Vector3i] = []
	assert_eq(PlacementRules.footprint_cells(none, Basis.IDENTITY, Vector2.ZERO, CUBE, _grid),
		PackedInt32Array())


func test_cells_beyond_the_grid_are_dropped() -> void:
	assert_eq(_footprint(Vector2(500.0, 500.0)).size(), 0,
		"Nothing of a block that far out lands on the grid at all.")


## -- validate ----------------------------------------------------------------

func test_a_cell_inside_my_own_territory_is_valid() -> void:
	_my_territory()
	assert_eq(_validate(Vector2(0.5, 0.5)), PlacementRules.Result.VALID)


func test_a_cell_outside_any_territory_is_rejected() -> void:
	_my_territory()
	assert_eq(_validate(Vector2(12.5, 0.5)), PlacementRules.Result.OUTSIDE_TERRITORY)


func test_another_teams_territory_is_outside_mine() -> void:
	_rasterize([_home(-8.0, 0.0, 0), _home(12.0, 0.0, 1)] as Array[InfluenceCircle])
	assert_eq(_validate(Vector2(12.5, 0.5), 0), PlacementRules.Result.OUTSIDE_TERRITORY)
	assert_eq(_validate(Vector2(12.5, 0.5), 1), PlacementRules.Result.VALID)


func test_a_contested_cell_is_rejected() -> void:
	_rasterize([_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)] as Array[InfluenceCircle])
	assert_eq(_validate(Vector2(0.5, 0.5)), PlacementRules.Result.CONTESTED,
		"Spec 2.2: players can't place blocks in contested areas.")


func test_a_hole_is_rejected_and_outranks_contested() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	for i: int in range(10):
		_rasterize(circles)
	var cell: Vector2i = _grid.world_to_cell(Vector2(0.5, 0.5))
	assert_true(_raster.is_hole(cell.x, cell.y), "Setup: the cell has holed through.")
	assert_eq(_validate(Vector2(0.5, 0.5)), PlacementRules.Result.HOLE)


func test_crossing_the_rim_is_off_disk() -> void:
	## A circle big enough to own every cell it can, so the only thing wrong
	## with the spot is that part of it hangs over the edge.
	_rasterize([
		_home(0.0, 0.0, 0),
		InfluenceCircle.new(Vector2.ZERO, MAP_RADIUS * 2.0, 0, 0, false, 1),
	] as Array[InfluenceCircle])
	assert_eq(_validate(Vector2(0.5, 0.5)), PlacementRules.Result.VALID, "Setup: mid-disk is fine.")

	## (14, 14) is 19.8 m out, so the block's near cells are on the disk and its
	## far corner cell is past the 20 m rim. Off the disk outranks the fact that
	## nobody owns that cell either.
	assert_eq(_validate(Vector2(14.0, 14.0)), PlacementRules.Result.OFF_DISK)


func test_every_cell_of_the_footprint_must_pass_not_just_the_centre() -> void:
	## The block sits on a cell corner, so it covers four cells. Three are
	## mine; the fourth is deliberately not.
	_my_territory()
	var edge: Vector2 = Vector2(6.0, 0.0)
	var footprint: PackedInt32Array = _footprint(edge)
	assert_eq(footprint.size(), 4, "Setup: straddling four cells.")

	var owned: int = 0
	for index: int in footprint:
		var coords: Vector2i = _grid.cell_coords(index)
		if _raster.team_at(coords.x, coords.y) == 0:
			owned += 1
	assert_gt(owned, 0, "Setup: some of the footprint is mine...")
	assert_lt(owned, 4, "...but not all of it.")

	assert_eq(PlacementRules.validate(footprint, _raster, 0),
		PlacementRules.Result.OUTSIDE_TERRITORY,
		"One bad cell rejects the whole placement.")


func test_an_empty_footprint_is_a_malformed_intent() -> void:
	_my_territory()
	assert_eq(PlacementRules.validate(PackedInt32Array(), _raster, 0),
		PlacementRules.Result.EMPTY)


## -- reason_for --------------------------------------------------------------

func test_every_result_maps_to_its_reason() -> void:
	assert_eq(PlacementRules.reason_for(PlacementRules.Result.VALID),
		PlacementRules.REASON_OK)
	assert_eq(PlacementRules.reason_for(PlacementRules.Result.OUTSIDE_TERRITORY),
		PlacementRules.REASON_OUTSIDE_TERRITORY)
	assert_eq(PlacementRules.reason_for(PlacementRules.Result.CONTESTED),
		PlacementRules.REASON_CONTESTED)
	assert_eq(PlacementRules.reason_for(PlacementRules.Result.HOLE),
		PlacementRules.REASON_HOLE)
	assert_eq(PlacementRules.reason_for(PlacementRules.Result.OFF_DISK),
		PlacementRules.REASON_OFF_DISK)
	assert_eq(PlacementRules.reason_for(PlacementRules.Result.EMPTY),
		PlacementRules.REASON_EMPTY)


## -- closest_valid_origin ----------------------------------------------------

func _closest(desired: Vector2, team: int = 0) -> Vector2:
	return PlacementRules.closest_valid_origin(
		desired, _one_cube, Basis.IDENTITY, CUBE, _grid, _raster, team, _tuning
	)


func test_an_already_valid_spot_is_returned_untouched() -> void:
	_my_territory()
	var desired: Vector2 = Vector2(0.5, 0.5)
	assert_eq(_closest(desired), desired,
		"The common case must not drift the block off the player's aim.")


func test_an_invalid_spot_snaps_to_a_nearby_valid_one() -> void:
	_my_territory()
	var desired: Vector2 = Vector2(8.5, 0.5)
	assert_eq(_validate(desired), PlacementRules.Result.OUTSIDE_TERRITORY, "Setup.")

	var found: Vector2 = _closest(desired)
	assert_false(PlacementRules.is_no_origin(found), "A valid spot exists nearby.")
	assert_eq(PlacementRules.validate(_footprint(found), _raster, 0),
		PlacementRules.Result.VALID)
	assert_lt(found.distance_to(desired), _tuning.auto_drop_search_max_radius,
		"And it is inside the search radius.")


func test_the_snap_finds_a_near_point_rather_than_any_point() -> void:
	_my_territory()
	var desired: Vector2 = Vector2(8.5, 0.5)
	var found: Vector2 = _closest(desired)
	## home_radius is 6, so the nearest owned ground is roughly 2.5 m away.
	assert_lt(found.distance_to(desired), 5.0,
		"The ring search widens outward, so it must not overshoot.")


func test_no_origin_when_nothing_within_the_search_radius_works() -> void:
	## Territory on the far side of the disk, well beyond
	## auto_drop_search_max_radius from where the block is held.
	_rasterize([_home(-15.0, 0.0, 0)] as Array[InfluenceCircle])
	var desired: Vector2 = Vector2(15.0, 0.0)
	var found: Vector2 = _closest(desired)
	assert_true(PlacementRules.is_no_origin(found),
		"With nowhere valid in reach the block has to be rejected, not teleported.")


func test_no_origin_when_the_team_owns_nothing_at_all() -> void:
	_my_territory()
	assert_true(PlacementRules.is_no_origin(_closest(Vector2(0.5, 0.5), 5)),
		"Team 5 has no territory anywhere.")


func test_is_no_origin_recognises_the_sentinel_only() -> void:
	assert_true(PlacementRules.is_no_origin(PlacementRules.NO_ORIGIN))
	assert_false(PlacementRules.is_no_origin(Vector2.ZERO))
	assert_false(PlacementRules.is_no_origin(Vector2(1000.0, -1000.0)))
