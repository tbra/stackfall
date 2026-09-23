extends GutTest
## core/rules/ThrowRules.gd: a throw's release-point check collapses to
## exactly two outcomes -- REASON_OK inside the throwing player's own
## territory, REASON_OUTSIDE_TERRITORY everywhere else (spec 2.5). Same
## fixture pattern as tests/unit/test_placement_rules.gd's v2 point-API
## section (grid/solver/raster built directly, no Match/Field involved).

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const ZONE_RADIUS: float = 3.0

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _grid: CellGrid = null
var _solver: TerritorySolver = null
var _raster: TerritoryRaster = null


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, CELL)
	_solver = TerritorySolver.new(_tuning)
	_raster = TerritoryRaster.new(_grid, _tuning)


func _home(x: float, z: float, team: int, slot: int = -1) -> InfluenceCircle:
	return InfluenceCircle.new(
		Vector2(x, z), _tuning.home_radius, team, slot if slot >= 0 else team, true, -1
	)


func _rasterize(circles: Array[InfluenceCircle], holes_enabled: bool = false) -> void:
	_raster.update(circles, _solver.solve(circles), 0.1, holes_enabled, false)


func _my_territory() -> void:
	_rasterize([_home(0.0, 0.0, 0)] as Array[InfluenceCircle])


func _validate(point: Vector2, team: int = 0) -> PlacementRules.Result:
	return ThrowRules.validate_release_point(point, _raster, team)


func _reason(point: Vector2, team: int = 0) -> StringName:
	return ThrowRules.reason_for(_validate(point, team))


## -- validate_release_point delegates to PlacementRules.validate_point ------

func test_a_point_inside_my_own_territory_is_valid() -> void:
	_my_territory()
	assert_eq(_validate(Vector2(0.5, 0.5)), PlacementRules.Result.VALID)


func test_a_point_nobody_owns_is_outside_territory() -> void:
	_my_territory()
	assert_eq(_validate(Vector2(12.5, 0.5)), PlacementRules.Result.OUTSIDE_TERRITORY)


func test_a_contested_point_is_not_valid() -> void:
	_rasterize([_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)], true)
	assert_eq(_validate(Vector2(0.5, 0.5)), PlacementRules.Result.CONTESTED)


func test_a_holed_point_is_not_valid() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	for i: int in range(10):
		_rasterize(circles, true)
	var cell: Vector2i = _grid.world_to_cell(Vector2(0.5, 0.5))
	assert_true(_raster.is_hole(cell.x, cell.y), "Setup: the cell has holed through.")
	assert_eq(_validate(Vector2(0.5, 0.5)), PlacementRules.Result.HOLE)


func test_a_point_past_the_rim_is_off_disk() -> void:
	_my_territory()
	assert_eq(_validate(Vector2(500.0, 0.0)), PlacementRules.Result.OFF_DISK)


func test_a_goal_zone_point_is_not_valid_even_on_my_own_ground() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.0, 0.0)]), ZONE_RADIUS)
	_my_territory()
	assert_eq(_validate(Vector2(0.0, 0.0)), PlacementRules.Result.GOAL_ZONE)


## -- reason_for collapses every non-VALID result to one reason ---------------

func test_valid_maps_to_reason_ok() -> void:
	_my_territory()
	assert_eq(_reason(Vector2(0.5, 0.5)), PlacementRules.REASON_OK)


func test_outside_territory_maps_to_reason_outside_territory() -> void:
	_my_territory()
	assert_eq(_reason(Vector2(12.5, 0.5)), ThrowRules.REASON_OUTSIDE_TERRITORY)


func test_contested_collapses_to_reason_outside_territory() -> void:
	_rasterize([_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)], true)
	assert_eq(_reason(Vector2(0.5, 0.5)), ThrowRules.REASON_OUTSIDE_TERRITORY)


func test_hole_collapses_to_reason_outside_territory() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	for i: int in range(10):
		_rasterize(circles, true)
	assert_eq(_reason(Vector2(0.5, 0.5)), ThrowRules.REASON_OUTSIDE_TERRITORY)


func test_off_disk_collapses_to_reason_outside_territory() -> void:
	_my_territory()
	assert_eq(_reason(Vector2(500.0, 0.0)), ThrowRules.REASON_OUTSIDE_TERRITORY)


func test_goal_zone_collapses_to_reason_outside_territory() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.0, 0.0)]), ZONE_RADIUS)
	_my_territory()
	assert_eq(_reason(Vector2(0.0, 0.0)), ThrowRules.REASON_OUTSIDE_TERRITORY)


func test_reason_not_a_special_is_a_distinct_constant() -> void:
	# MatchPlacement.request_throw() returns this directly (never produced by
	# reason_for()) when the slot has no pending special at all -- pinned here
	# so it can never collide with REASON_OUTSIDE_TERRITORY or REASON_OK.
	assert_ne(ThrowRules.REASON_NOT_A_SPECIAL, ThrowRules.REASON_OUTSIDE_TERRITORY)
	assert_ne(ThrowRules.REASON_NOT_A_SPECIAL, PlacementRules.REASON_OK)
