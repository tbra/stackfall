extends GutTest
## core/rules/ThrowRules: a throw's release point is OK in own territory, OUTSIDE_TERRITORY elsewhere (spec 1.4);
## hole, off-disk and goal-zone reasons keep their names.

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const ZONE_RADIUS: float = 3.0

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
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
	_raster.fill_ownership(circles, _solver.solve(circles), holes_enabled)
	_raster.adopt_fill(_raster, 0.1, holes_enabled, false)


func _my_territory() -> void:
	_rasterize([_home(0.0, 0.0, 0)] as Array[InfluenceCircle])


func _validate(point: Vector2, team: int = 0) -> PlacementRules.Result:
	return ThrowRules.validate_release_point(point, _raster, team)


func _reason(point: Vector2, team: int = 0) -> StringName:
	return ThrowRules.reason_for(_validate(point, team))


## -- validate_release_point delegates to PlacementRules.validate_point ------

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


func test_hole_reports_its_own_reason() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	for i: int in range(10):
		_rasterize(circles, true)
	assert_eq(_reason(Vector2(0.5, 0.5)), PlacementRules.REASON_HOLE)


func test_off_disk_reports_its_own_reason() -> void:
	_my_territory()
	assert_eq(_reason(Vector2(500.0, 0.0)), PlacementRules.REASON_OFF_DISK)


func test_goal_zone_reports_its_own_reason() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.0, 0.0)]), ZONE_RADIUS)
	_my_territory()
	assert_eq(_reason(Vector2(0.0, 0.0)), PlacementRules.REASON_GOAL_ZONE)

