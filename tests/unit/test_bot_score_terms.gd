extends GutTest
## Bontago-1t5.11 (BT1): BotPlacementScorer.score_terms() + BotScoreTerms.weighted()
## must reproduce score() for every mode, so the offline recorder cannot drift from
## the live policy; plus the pure BotDecisionRecord builders.

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const EPS: float = 0.000001

var _territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _bot_tuning: BotTuning = preload("res://config/bot_tuning.tres")
var _grid: CellGrid = null
var _raster: TerritoryRaster = null


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, CELL)
	_raster = TerritoryRaster.new(_grid, _territory_tuning)
	var circles: Array[InfluenceCircle] = [InfluenceCircle.new(Vector2.ZERO, 12.0, 0, 0, true, 0)]
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	_raster.update(circles, solver.solve(circles), 0.1, false, false)


func _candidates() -> Array[BotCandidate]:
	var result: Array[BotCandidate] = []
	var spots: Array[Vector2] = [Vector2(7.0, 0.0), Vector2(-7.0, 1.0), Vector2(0.0, 6.0), Vector2(3.0, -2.0), Vector2(12.0, 12.0)]
	for i: int in range(spots.size()):
		var candidate: BotCandidate = BotCandidate.new()
		candidate.origin = spots[i]
		candidate.support_height = float(i) * 1.5
		candidate.shape_height = 1.0 + float(i % 3)
		candidate.footprint_cells = PackedInt32Array([_grid.res * (_grid.res / 2) + _grid.res / 2 + i, _grid.res * (_grid.res / 2) + _grid.res / 2 + i + 1])
		candidate.on_top_of_own_stack = i % 2 == 0
		candidate.corner_support_hits = i - 1
		result.append(candidate)
	return result


func _goals(mode: int) -> Array[BotModeGoal]:
	var list: Array[BotModeGoal] = []
	list.append(null)
	var ctf: BotModeGoal = BotModeGoal.new()
	ctf.mode = MatchConfig.GameMode.CAPTURE_THE_FLAG
	ctf.beacon_positions = PackedVector2Array([Vector2(8.0, 0.0), Vector2(-8.0, 0.0)])
	ctf.beacon_held_by_own = [false, true]
	ctf.beacon_score_rate = 1.0
	list.append(ctf)
	var sky: BotModeGoal = BotModeGoal.new()
	sky.mode = MatchConfig.GameMode.REACH_THE_SKY
	sky.has_tower = true
	sky.tower_origin = Vector2(2.0, 2.0)
	sky.tower_height = 4.0
	list.append(sky)
	var elim: BotModeGoal = BotModeGoal.new()
	elim.mode = MatchConfig.GameMode.ELIMINATION
	elim.enemy_home_positions = PackedVector2Array([Vector2(12.0, 0.0), Vector2(0.0, -14.0)])
	elim.enemy_home_shares = PackedFloat32Array([0.2, 0.4])
	elim.has_own_home = true
	elim.own_home_position = Vector2(-12.0, 0.0)
	list.append(elim)
	var dom: BotModeGoal = BotModeGoal.new()
	dom.mode = MatchConfig.GameMode.DOMINATION
	dom.own_team_leads = false
	dom.leader_points = PackedVector2Array([Vector2(12.0, 0.0)])
	list.append(dom)
	var goals: PackedVector2Array = PackedVector2Array([Vector2(3.0, 0.0), Vector2(-9.0, 0.0), Vector2(0.0, 12.0)])
	var multi: BotModeGoal = BotModeGoal.new()
	multi.mode = MatchConfig.GameMode.CLASSIC
	multi.goal_positions = goals
	multi.goal_in_home_group = [true, false, false]
	multi.home_group = _raster.group_at_point(Vector2.ZERO)
	multi.component_points = PackedVector2Array([Vector2.ZERO, Vector2(3.0, 0.0)])
	multi.target_goal_index = 1
	list.append(multi)
	var classic: BotModeGoal = BotModeGoal.new()
	classic.mode = MatchConfig.GameMode.CLASSIC
	list.append(classic)
	if mode >= 0:
		return [list[mode]]
	return list


func test_weighted_terms_equal_score_in_every_mode() -> void:
	var enemy: PackedVector2Array = PackedVector2Array([Vector2(5.0, 1.0), Vector2(-3.0, 4.0)])
	var specials: PackedVector2Array = PackedVector2Array([Vector2(6.0, 0.5)])
	var goal_positions: PackedVector2Array = PackedVector2Array([Vector2(6.0, 0.0)])
	var checked: int = 0
	for mode_goal: BotModeGoal in _goals(-1):
		for candidate: BotCandidate in _candidates():
			var score: float = BotPlacementScorer.score(
				candidate, _raster, _grid, 0, goal_positions, enemy, specials, _bot_tuning, MAP_RADIUS, mode_goal)
			var terms: BotScoreTerms = BotPlacementScorer.score_terms(
				candidate, _raster, _grid, 0, goal_positions, enemy, specials, _bot_tuning, MAP_RADIUS, mode_goal)
			assert_almost_eq(terms.weighted(_bot_tuning), score, EPS)
			checked += 1
	assert_eq(checked, 7 * 5)


func test_terms_are_the_unweighted_components() -> void:
	var candidate: BotCandidate = _candidates()[2]
	var terms: BotScoreTerms = BotPlacementScorer.score_terms(
		candidate, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), _bot_tuning, MAP_RADIUS, null)
	assert_eq(terms.height, candidate.support_height)
	assert_eq(terms.mode, 0.0)
	assert_eq(terms.risk, 0.0)
	assert_eq(terms.to_array().size(), 5)


func test_scored_best_matches_pick_best() -> void:
	var candidates: Array[BotCandidate] = _candidates()
	var terms: Array[BotScoreTerms] = []
	for candidate: BotCandidate in candidates:
		terms.append(BotPlacementScorer.score_terms(
			candidate, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), _bot_tuning, MAP_RADIUS, null))
	var picked: BotCandidate = BotPlacementScorer.pick_best(
		candidates, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), _bot_tuning, MAP_RADIUS)
	assert_eq(candidates[BotDecisionRecord.scored_best_index(terms, _bot_tuning)], picked)
	assert_eq(BotDecisionRecord.scored_best_index([], _bot_tuning), -1)


func test_decision_record_json_round_trips_with_rounding() -> void:
	var candidate: BotCandidate = _candidates()[1]
	var terms: BotScoreTerms = BotScoreTerms.new()
	terms.height = 1.23456
	terms.goal = -2.0
	var cands: Array[BotCandidate] = [candidate]
	var term_list: Array[BotScoreTerms] = [terms]
	var meta: Dictionary = {"id": 7, "t": 12.34567, "slot": 2, "team": 1, "shape_id": &"cube", "feed_seq": 3, "piece_index": 4, "state": {"share": 0.5}}
	var record: Dictionary = BotDecisionRecord.to_dict(meta, cands, term_list, 0, 0, Vector2(1.00049, 2.0), &"", BotDecisionRecord.POLICY_SCORE, 0.001)
	var line: String = BotDecisionRecord.to_json_line(record)
	assert_false(line.contains("\n"))
	var parsed: Dictionary = JSON.parse_string(line) as Dictionary
	assert_eq(parsed["kind"], "decision")
	assert_eq(int(parsed["id"]), 7)
	assert_almost_eq(float(parsed["t"]), 12.346, 0.0000001)
	var cand: Dictionary = (parsed["cands"] as Array)[0] as Dictionary
	assert_almost_eq(float((cand["terms"] as Array)[0]), 1.235, 0.0000001)
	assert_eq((cand["terms"] as Array).size(), 5)
	assert_almost_eq(float((parsed["placed_origin"] as Array)[0]), 1.0, 0.0000001)


func test_outcome_and_match_end_records() -> void:
	var outcome: Dictionary = BotDecisionRecord.outcome_to_dict(
		7, 2, PackedFloat32Array([10.0, 30.0, 60.0]), PackedFloat32Array([0.1, 0.2, 0.3]), 12, true, 0.001)
	assert_true(outcome.has("d_share_10s") and outcome.has("d_share_30s") and outcome.has("d_share_60s"))
	assert_eq(outcome["own_blocks_alive_60s"], 12)
	assert_eq(outcome["home_alive_60s"], true)
	var ended: Dictionary = BotDecisionRecord.match_end_to_dict(2, 1, 1, 0.4, -1.0, 0.001)
	assert_true(bool(ended["won"]))
	assert_false(bool(BotDecisionRecord.match_end_to_dict(2, 1, 0, 0.4, -1.0, 0.001)["won"]))
