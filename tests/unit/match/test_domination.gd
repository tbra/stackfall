extends GutTest
## Domination (Bontago-1pi.25): no early win; the largest territory share
## (TerritoryRaster.team_share) wins at the round timer; equal shares are a
## shared win. Pure objective tests plus config / wire round trips.

const MAP_RADIUS: float = 20.0

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _grid: CellGrid = null
var _solver: TerritorySolver = null
var _raster: TerritoryRaster = null


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, 1.0)
	_solver = TerritorySolver.new(_tuning)
	_raster = TerritoryRaster.new(_grid, _tuning)


func _circle(x: float, z: float, r: float, team: int, slot: int) -> InfluenceCircle:
	return InfluenceCircle.new(Vector2(x, z), r, team, slot, true, -1)


func _rasterize(circles: Array[InfluenceCircle]) -> void:
	_raster.update(circles, _solver.solve(circles), 0.1, true, false)


func _objective(teams: int = 2) -> DominationObjective:
	var objective: DominationObjective = DominationObjective.new(0.0)
	objective.reset(teams)
	return objective


func test_no_win_before_the_timer_even_with_total_dominance() -> void:
	var objective: DominationObjective = _objective()
	_rasterize([_circle(0.0, 0.0, 12.0, 0, 0)])
	for _i: int in range(50):
		objective.update(_raster, 0.1)
	assert_eq(objective.winner(), ModeObjective.NO_TEAM)
	assert_gt(objective.team_score(0), 0.0)
	assert_true(objective.is_timed())


func test_largest_share_wins_at_the_timer() -> void:
	var objective: DominationObjective = _objective()
	_rasterize([_circle(-8.0, 0.0, 3.0, 0, 0), _circle(8.0, 0.0, 6.0, 1, 1)])
	objective.update(_raster, 0.1)
	assert_gt(objective.team_score(1), objective.team_score(0))
	assert_eq(objective.on_round_timer_end(), 1)
	assert_eq(objective.winners(), PackedInt32Array([1]))
	assert_eq(objective.results_fields()["winners"], "1")


func test_equal_shares_are_a_shared_win_with_lowest_id_returned() -> void:
	var objective: DominationObjective = _objective(3)
	objective.set_shares(PackedFloat32Array([0.25, 0.25, 0.1]))
	assert_eq(objective.on_round_timer_end(), 0)
	assert_eq(objective.winners(), PackedInt32Array([0, 1]))
	assert_eq(objective.results_fields()["winners"], "0,1")
	var zero: DominationObjective = _objective()
	assert_eq(zero.on_round_timer_end(), 0, "nobody built anything")
	assert_eq(zero.winners(), PackedInt32Array([0, 1]))


func test_team_shares_aggregate_all_members_of_a_team() -> void:
	# Teams 0 (two slots, small circles) vs team 1 (one slot, slightly larger).
	var objective: DominationObjective = _objective()
	_rasterize([
		_circle(-10.0, -6.0, 3.0, 0, 0), _circle(-10.0, 6.0, 3.0, 0, 2),
		_circle(10.0, 0.0, 4.0, 1, 1),
	])
	objective.update(_raster, 0.1)
	assert_almost_eq(objective.team_score(0), _raster.team_share(0), 0.00001)
	assert_gt(objective.team_score(0), objective.team_score(1), "two small holdings beat one larger")
	assert_eq(objective.on_round_timer_end(), 0)


func test_results_block_validates() -> void:
	var host: DominationObjective = _objective()
	host.set_shares(PackedFloat32Array([0.2, 0.4]))
	host.on_round_timer_end()
	var block: Dictionary = host.results_fields()
	block["mode_id"] = host.mode_id()
	block["scores"] = Array(host.scores())
	var clean: Dictionary = ResultsPayload.validate_mode_block(block)
	assert_eq(clean["winners"], "1")
	assert_eq(clean["mode_id"], MatchConfig.GameMode.DOMINATION)

