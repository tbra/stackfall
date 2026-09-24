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
	_raster.update(circles, _solver.solve(circles), delta, true, false)


## A team-0 home circle at the disk centre, so cells within home_radius are mine.
func _my_territory() -> void:
	_rasterize([_home(0.0, 0.0, 0)] as Array[InfluenceCircle])


func _footprint(origin: Vector2, cells: Array[Vector3i] = [], basis: Basis = Basis.IDENTITY
) -> PackedInt32Array:
	var shape: Array[Vector3i] = cells if not cells.is_empty() else _one_cube
	return PlacementRules.footprint_cells(shape, basis, origin, CUBE, _grid)


func _validate(origin: Vector2, team: int = 0) -> PlacementRules.Result:
	return PlacementRules.validate(_footprint(origin), _raster, team)


## Which literal coordinates are cell centres depends on how CellGrid lays its
## square down (see the DECISION there — it centres a cell on the disk centre
## so Field's per-cell collision does not jitter blocks). These two ask the
## grid instead of hard-coding it, so the footprint tests below keep meaning
## "centred on a cell" and "sitting on the corner where four cells meet".
func _cell_centre(cx: int = 0, cy: int = 0) -> Vector2:
	return _grid.cell_center(_grid.res / 2 + cx, _grid.res / 2 + cy)


func _cell_corner(cx: int = 0, cy: int = 0) -> Vector2:
	return _cell_centre(cx, cy) + Vector2(CELL, CELL) * 0.5


## -- footprint_cells ---------------------------------------------------------

func test_a_cube_on_a_cell_centre_covers_exactly_that_cell() -> void:
	var cells: PackedInt32Array = _footprint(_cell_centre())
	assert_eq(cells.size(), 1, "A 1 m cube aligned with a 1 m cell covers one cell.")
	assert_eq(cells[0], _grid.cell_index(_grid.res / 2, _grid.res / 2))


func test_a_cube_straddling_a_cell_corner_covers_four_cells() -> void:
	## docs/M2_PLAN.md: "a rotated cube covers up to four cells... every cube
	## contributes the cells its footprint square overlaps, not just the one
	## under its centre."
	var cells: PackedInt32Array = _footprint(_cell_corner())
	assert_eq(cells.size(), 4, "Sitting on a cell corner, it overlaps all four.")


func test_a_cube_straddling_one_edge_covers_two_cells() -> void:
	assert_eq(_footprint(_cell_centre() + Vector2(CELL * 0.5, 0.0)).size(), 2)
	assert_eq(_footprint(_cell_centre() + Vector2(0.0, CELL * 0.5)).size(), 2)


func test_footprint_cells_are_ascending_and_unique() -> void:
	var cells: PackedInt32Array = _footprint(_cell_corner(), _domino)
	var previous: int = -1
	for index: int in cells:
		assert_gt(index, previous, "Ascending with no repeats.")
		previous = index


func test_a_domino_covers_both_of_its_cubes() -> void:
	var cells: PackedInt32Array = _footprint(_cell_centre(), _domino)
	assert_eq(cells.size(), 2)
	var first: Vector2i = _grid.cell_coords(cells[0])
	var second: Vector2i = _grid.cell_coords(cells[1])
	assert_eq(first.y, second.y, "Unrotated it lies along x.")
	assert_eq(absi(first.x - second.x), 1)


func test_rotating_a_domino_rotates_its_footprint() -> void:
	## A yaw of 90 degrees has to swing the second cube onto the other axis;
	## the footprint must follow the basis, not the untransformed cells.
	var yawed: Basis = BlockOrientations.get_basis(BlockOrientations.step_yaw_ccw(0))
	var cells: PackedInt32Array = _footprint(_cell_centre(), _domino, yawed)
	assert_eq(cells.size(), 2)
	var first: Vector2i = _grid.cell_coords(cells[0])
	var second: Vector2i = _grid.cell_coords(cells[1])
	assert_eq(first.x, second.x, "After a 90 degree yaw it lies along z.")
	assert_eq(absi(first.y - second.y), 1)


func test_a_free_rotation_still_produces_a_footprint() -> void:
	var tilted: Basis = Basis(Vector3.UP, deg_to_rad(45.0))
	var cells: PackedInt32Array = _footprint(_cell_centre(), _domino, tilted)
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

	## On the corner where the cells around (14, 14) meet: the near one is
	## 19.8 m out and on the disk, the far one is 20.5 m out and past the 20 m
	## rim. Off the disk outranks the fact that nobody owns that cell either.
	assert_eq(_validate(_cell_corner(14, 14)), PlacementRules.Result.OFF_DISK)


func test_every_cell_of_the_footprint_must_pass_not_just_the_centre() -> void:
	## The block sits on a cell corner, so it covers four cells. Three are
	## mine; the fourth is deliberately not.
	_my_territory()
	# The corner where the four cells around (6, 0) meet: the home circle's
	# 6 m rim runs between them, so some are mine and some are not.
	var edge: Vector2 = _cell_corner(6, 0)
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


## -- v2: one point, no footprint (docs/TERRITORY_V2_PLAN.md) ------------------
##
## Owner clarifications 2026-09-20: "Placement check: one raycast from the
## middle of the ghost block straight down; the hit point must be inside your
## own area and outside every goal flag's area. No cell footprint tests."
## Package B does the raycast; everything from the hit point on is here.

const ZONE_RADIUS: float = 3.0


## Solves and rasterizes through the v2 (holes_enabled = false) path.
func _rasterize_v2(circles: Array[InfluenceCircle]) -> void:
	_raster.update(circles, _solver.solve(circles), 0.1, false, false)


## A team-0 home circle at the disk centre under v2 rules.
func _my_v2_territory() -> void:
	_rasterize_v2([_home(0.0, 0.0, 0)] as Array[InfluenceCircle])


func _validate_point(point: Vector2, team: int = 0) -> PlacementRules.Result:
	return PlacementRules.validate_point(point, _raster, team)


func _closest_point(desired: Vector2, team: int = 0) -> Vector2:
	return PlacementRules.closest_valid_point(desired, _raster, team, _tuning)


func test_a_point_inside_my_own_area_is_valid() -> void:
	_my_v2_territory()
	assert_eq(_validate_point(Vector2(0.5, 0.5)), PlacementRules.Result.VALID)
	assert_eq(_validate_point(Vector2(-4.2, 1.3)), PlacementRules.Result.VALID,
		"Anywhere inside home_radius = 6 counts, cell boundaries included.")


func test_a_point_nobody_owns_is_outside_my_territory() -> void:
	_my_v2_territory()
	assert_eq(_validate_point(Vector2(12.5, 0.5)), PlacementRules.Result.OUTSIDE_TERRITORY)


func test_another_teams_area_is_outside_mine_point_wise() -> void:
	_rasterize_v2([_home(-8.0, 0.0, 0), _home(12.0, 0.0, 1)] as Array[InfluenceCircle])
	assert_eq(_validate_point(Vector2(12.0, 0.0), 0), PlacementRules.Result.OUTSIDE_TERRITORY)
	assert_eq(_validate_point(Vector2(12.0, 0.0), 1), PlacementRules.Result.VALID)


func test_a_point_past_the_rim_is_off_disk() -> void:
	_rasterize_v2([
		_home(0.0, 0.0, 0),
		InfluenceCircle.new(Vector2.ZERO, MAP_RADIUS * 2.0, 0, 0, true, -1),
	] as Array[InfluenceCircle])
	assert_eq(_validate_point(Vector2(0.5, 0.5)), PlacementRules.Result.VALID, "Setup: mid-disk is fine.")
	assert_eq(_validate_point(Vector2(19.9, 19.9)), PlacementRules.Result.OFF_DISK,
		"Inside the bounding square but outside the disk.")
	assert_eq(_validate_point(Vector2(500.0, 0.0)), PlacementRules.Result.OFF_DISK,
		"And well off the grid entirely.")


func test_a_goal_zone_refuses_the_placement_even_on_my_own_ground() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.0, 0.0)]), ZONE_RADIUS)
	_my_v2_territory()
	assert_eq(_raster.team_at(_grid.world_to_cell(Vector2(0.0, 0.0)).x,
		_grid.world_to_cell(Vector2(0.0, 0.0)).y), 0, "Setup: the zone sits on my own area.")
	assert_eq(_validate_point(Vector2(0.0, 0.0)), PlacementRules.Result.GOAL_ZONE,
		"The no-build zone wins over ownership: no player may build there.")
	assert_eq(_validate_point(Vector2(5.0, 0.0)), PlacementRules.Result.VALID,
		"Just outside the zone, my own area is buildable again.")


func test_a_goal_zone_outside_my_area_still_reports_the_zone() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(12.0, 0.0)]), ZONE_RADIUS)
	_my_v2_territory()
	assert_eq(_validate_point(Vector2(12.0, 0.0)), PlacementRules.Result.GOAL_ZONE,
		"The zone is checked before ownership, so the player is told the real reason.")


func test_the_goal_zone_result_maps_to_its_reason() -> void:
	assert_eq(PlacementRules.reason_for(PlacementRules.Result.GOAL_ZONE),
		PlacementRules.REASON_GOAL_ZONE)


func test_an_already_valid_point_is_returned_untouched() -> void:
	_my_v2_territory()
	var desired: Vector2 = Vector2(1.25, -0.75)
	assert_eq(_closest_point(desired), desired,
		"The common case must not drift the block off the player's aim.")


func test_an_invalid_point_snaps_to_the_nearest_valid_one() -> void:
	_my_v2_territory()
	var desired: Vector2 = Vector2(8.5, 0.0)
	assert_eq(_validate_point(desired), PlacementRules.Result.OUTSIDE_TERRITORY, "Setup.")

	var found: Vector2 = _closest_point(desired)
	assert_false(PlacementRules.is_no_origin(found), "A valid point exists nearby.")
	assert_eq(_validate_point(found), PlacementRules.Result.VALID)
	assert_lt(found.distance_to(desired), 5.0,
		"home_radius is 6, so the nearest owned ground is about 2.5 m away; the "
		+ "ring search must not overshoot it.")


func test_the_search_walks_out_of_a_goal_zone() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.0, 0.0)]), ZONE_RADIUS)
	_my_v2_territory()
	var found: Vector2 = _closest_point(Vector2(0.0, 0.0))
	assert_false(PlacementRules.is_no_origin(found))
	assert_eq(_validate_point(found), PlacementRules.Result.VALID)
	var cell: Vector2i = _grid.world_to_cell(found)
	assert_false(_raster.is_goal_zone(cell.x, cell.y),
		"The relocated drop has to land outside the no-build zone.")


## Bontago-xtq.23 (owner playtest 2026-09-24, "if I'm close to my area it
## relocates, otherwise it just yeets the block in a direction"): the ring
## search alone only reaches auto_drop_search_max_radius (12 m); this pins the
## fix -- once the team's own territory is farther than that, the disk-scan
## fallback still finds it instead of reporting NO_ORIGIN. Before the fix
## this asserted is_no_origin(); MapDef's 20 m test map keeps -15/0 and 15/0
## both on the disk, ~30 m apart, well past auto_drop_search_max_radius=12.
func test_a_point_far_beyond_the_search_radius_still_finds_the_teams_own_territory() -> void:
	_rasterize_v2([_home(-15.0, 0.0, 0)] as Array[InfluenceCircle])
	var desired: Vector2 = Vector2(15.0, 0.0)
	assert_gt(desired.distance_to(Vector2(-15.0, 0.0)), _tuning.auto_drop_search_max_radius,
		"Setup: the only owned ground is farther than the fine ring search reaches.")

	var found: Vector2 = _closest_point(desired)

	assert_false(PlacementRules.is_no_origin(found),
		"The team owns ground somewhere on the disk, so it must relocate there, not burn.")
	assert_eq(_validate_point(found), PlacementRules.Result.VALID)
	var cell: Vector2i = _grid.world_to_cell(found)
	assert_eq(_raster.team_at(cell.x, cell.y), 0,
		"The relocated point must actually belong to the requesting team.")


## The disk-scan fallback must return the NEAREST owned point, not merely any
## owned point, when the team holds ground in more than one place. Both
## regions sit beyond auto_drop_search_max_radius from `desired`, so the ring
## search finds neither and this exercises the scan itself, not the ring.
func test_the_disk_scan_fallback_finds_the_nearer_of_two_owned_regions() -> void:
	var near_home: Vector2 = Vector2(-2.0, 0.0)
	var far_home: Vector2 = Vector2(-19.0, 0.0)
	_rasterize_v2([
		_home(near_home.x, near_home.y, 0),
		_home(far_home.x, far_home.y, 0),
	] as Array[InfluenceCircle])
	var desired: Vector2 = Vector2(19.0, 0.0)
	assert_gt(desired.distance_to(near_home), _tuning.auto_drop_search_max_radius,
		"Setup: even the nearer region is beyond the fine ring search from here.")
	assert_gt(desired.distance_to(far_home), _tuning.auto_drop_search_max_radius)

	var found: Vector2 = _closest_point(desired)

	assert_false(PlacementRules.is_no_origin(found))
	assert_eq(_validate_point(found), PlacementRules.Result.VALID)
	assert_lt(found.distance_to(near_home), found.distance_to(far_home),
		"The scan must land in the nearer region's territory, not the farther one's.")
	assert_lt(found.distance_to(desired), desired.distance_to(far_home),
		"And the point it lands on must be closer to `desired` than the far region even is.")


func test_no_valid_point_when_the_team_owns_nothing() -> void:
	_my_v2_territory()
	assert_true(PlacementRules.is_no_origin(_closest_point(Vector2(0.5, 0.5), 5)),
		"Team 5 has no area anywhere.")


func test_the_legacy_footprint_path_is_untouched_by_the_point_api() -> void:
	## Both APIs answer the same raster and now agree on a contested/holed
	## cell too (Bontago-cmc.7); footprint_cells()/validate() still read whole
	## footprints, not just a point, which is the only thing the point API
	## does not reproduce.
	_rasterize([_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)] as Array[InfluenceCircle])
	assert_eq(_validate(Vector2(0.5, 0.5)), PlacementRules.Result.CONTESTED)


## DECISION (Bontago-cmc.7): validate_point() now also rejects a
## contested/holed point, so every MatchConfig.HoleMode can validate placement
## through one raycast + validate_point() (autoload/Match.gd request_place()),
## without falling back to footprint_cells()/validate() for TEMPORARY/
## PERMANENT. SPEC.md's 2026-09-20 audit, 3.3 "Placement validation": "one
## downward ray and the hit-point test... for the normal target rules."
func test_the_point_api_also_rejects_a_contested_point_under_the_legacy_fill() -> void:
	_rasterize([_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)] as Array[InfluenceCircle])
	assert_eq(PlacementRules.validate_point(Vector2(0.5, 0.5), _raster, 0),
		PlacementRules.Result.CONTESTED,
		"A contested point is refused with its own reason, not the generic outside-territory one.")


func test_the_point_api_also_rejects_a_holed_point_and_it_outranks_contested() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	for i: int in range(10):
		_rasterize(circles)
	var cell: Vector2i = _grid.world_to_cell(Vector2(0.5, 0.5))
	assert_true(_raster.is_hole(cell.x, cell.y), "Setup: the cell has holed through.")
	assert_eq(PlacementRules.validate_point(Vector2(0.5, 0.5), _raster, 0),
		PlacementRules.Result.HOLE)


func test_the_point_api_still_ignores_hole_and_contested_state_under_the_v2_fill() -> void:
	## The v2 argmax fill never sets is_hole()/is_contested(), so validate_point
	## under HoleMode.OFF is unaffected by this change: this pins that a v2
	## raster answers exactly what it did before.
	_my_v2_territory()
	var cell: Vector2i = _grid.world_to_cell(Vector2(0.5, 0.5))
	assert_false(_raster.is_hole(cell.x, cell.y))
	assert_false(_raster.is_contested(cell.x, cell.y))
	assert_eq(_validate_point(Vector2(0.5, 0.5)), PlacementRules.Result.VALID)
