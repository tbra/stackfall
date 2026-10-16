extends GutTest
## Spec 2.5 placement legality: the point under the ghost must be owned by the
## placing player's team, outside every goal zone and not contested or a hole.

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const CUBE: float = 1.0

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _grid: CellGrid = null
var _solver: TerritorySolver = null
var _raster: TerritoryRaster = null

var _one_cube: Array[Vector3i] = [Vector3i.ZERO]


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, CELL)
	_solver = TerritorySolver.new(_tuning)
	_raster = TerritoryRaster.new(_grid, _tuning)


func _home(x: float, z: float, team: int, slot: int = -1) -> InfluenceCircle:
	return InfluenceCircle.new(
		Vector2(x, z), _tuning.home_radius, team, slot if slot >= 0 else team, true, -1
	)


func _rasterize(circles: Array[InfluenceCircle], delta: float = 0.1) -> void:
	_raster.fill_ownership(circles, _solver.solve(circles), true)
	_raster.adopt_fill(_raster, delta, true, false)


func _footprint(origin: Vector2, cells: Array[Vector3i] = [], basis: Basis = Basis.IDENTITY
) -> PackedInt32Array:
	var shape: Array[Vector3i] = cells if not cells.is_empty() else _one_cube
	return PlacementRules.footprint_cells(shape, basis, origin, CUBE, _grid)


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

func test_a_cube_straddling_a_cell_corner_covers_four_cells() -> void:
	## Design rule: "a rotated cube covers up to four cells... every cube
	## contributes the cells its footprint square overlaps, not just the one
	## under its centre."
	var cells: PackedInt32Array = _footprint(_cell_corner())
	assert_eq(cells.size(), 4, "Sitting on a cell corner, it overlaps all four.")


## -- validate_point: the rim ------------------------------------------------

func test_a_point_past_the_rim_is_off_disk() -> void:
	## A circle big enough to own every cell it can, so the only thing wrong
	## with the spot is that it lies past the edge.
	_rasterize([
		_home(0.0, 0.0, 0),
		InfluenceCircle.new(Vector2.ZERO, MAP_RADIUS * 2.0, 0, 0, false, 1),
	] as Array[InfluenceCircle])
	assert_eq(PlacementRules.validate_point(Vector2(0.5, 0.5), _raster, 0), PlacementRules.Result.VALID,
		"Setup: mid-disk is fine.")
	assert_eq(PlacementRules.validate_point(_cell_corner(14, 14) + Vector2(1.0, 1.0), _raster, 0),
		PlacementRules.Result.OFF_DISK, "Past the 20 m rim, off the disk outranks ownership.")


## -- v2: one point, no footprint ------------------
##
## Clarification: "Placement check: one raycast from the
## middle of the ghost block straight down; the hit point must be inside your
## own area and outside every goal flag's area. No cell footprint tests."
## Package B does the raycast; everything from the hit point on is here.

const ZONE_RADIUS: float = 3.0


## Solves and rasterizes through the v2 (holes_enabled = false) path.
func _rasterize_v2(circles: Array[InfluenceCircle]) -> void:
	_raster.fill_ownership(circles, _solver.solve(circles), false)
	_raster.adopt_fill(_raster, 0.1, false, false)


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


func test_a_goal_zone_refuses_the_placement_even_on_my_own_ground() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.0, 0.0)]), ZONE_RADIUS)
	_my_v2_territory()
	assert_eq(_raster.team_at(_grid.world_to_cell(Vector2(0.0, 0.0)).x,
		_grid.world_to_cell(Vector2(0.0, 0.0)).y), 0, "Setup: the zone sits on my own area.")
	assert_eq(_validate_point(Vector2(0.0, 0.0)), PlacementRules.Result.GOAL_ZONE,
		"The no-build zone wins over ownership: no player may build there.")
	assert_eq(_validate_point(Vector2(5.0, 0.0)), PlacementRules.Result.VALID,
		"Just outside the zone, my own area is buildable again.")


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


## DECISION: validate_point() now also rejects a
## contested/holed point, so every MatchConfig.HoleMode can validate placement
## through one raycast + validate_point() (autoload/Match.gd request_place()),
## without falling back to footprint_cells()/validate() for TEMPORARY/
## PERMANENT. SPEC.md's audit, 3.3 "Placement validation": "one
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
