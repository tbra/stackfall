extends GutTest
## ClassicObjective in sudden death republishes its replicated mode state whenever any goal's
## latch changes, including the last goal (the host sends the state only when it is dirty).

const MAP_RADIUS: float = 20.0
const STEP: float = 0.1
const GOAL_FIRST: Vector2 = Vector2(-15.0, 0.0)
const GOAL_LAST: Vector2 = Vector2(15.0, 0.0)
const HOLD: float = 2.0

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")


func _raster_of(circles: Array[InfluenceCircle]) -> TerritoryRaster:
	var raster: TerritoryRaster = TerritoryRaster.new(CellGrid.new(MAP_RADIUS, 1.0), _tuning)
	raster.fill_ownership(circles, TerritorySolver.new(_tuning).solve(circles), true)
	raster.adopt_fill(raster, STEP, true, false)
	return raster


func _home(at: Vector2, team: int) -> InfluenceCircle:
	return InfluenceCircle.new(at, _tuning.home_radius, team, team, true, -1)


func test_a_latch_change_on_the_last_goal_alone_marks_the_state_dirty() -> void:
	var objective: ClassicObjective = ClassicObjective.new(PackedVector2Array([GOAL_FIRST, GOAL_LAST]), HOLD)
	objective.reset(2)
	var nobody: Array[InfluenceCircle] = [_home(Vector2(0.0, -15.0), 0)]
	objective.begin_sudden_death(_raster_of(nobody))
	objective.consume_state_dirty()

	var last_goal_only: Array[InfluenceCircle] = [_home(GOAL_LAST, 1)]
	objective.update(_raster_of(last_goal_only), STEP)

	assert_eq(objective.latched_team(1), 1, "fixture: the last goal latched")
	assert_eq(objective.latched_team(0), -1, "fixture: the first goal did not change")
	assert_true(objective.consume_state_dirty(), "the change is published")
