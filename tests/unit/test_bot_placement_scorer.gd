extends GutTest
## core/ai/BotPlacementScorer.gd (docs/M5_PLAN.md P2, Bontago-d5c.3): real
## placement scoring -- height gained, goal progress, stability, risk,
## combined by BotTuning's four weights -- plus flattest_orientations()'s
## pure geometry and pick_best()'s highest-scorer selection.
##
## Fixture style mirrors tests/unit/test_placement_rules.gd (a real CellGrid/
## TerritoryRaster, no Field/scene tree): BotCandidate is pure data, so every
## candidate here is hand-built rather than generated through
## game/BotController.gd (which this package's own brief does not own).

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0

var _territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _bot_tuning: BotTuning = preload("res://config/bot_tuning.tres")
var _cube_shape: BlockShape = preload("res://config/blocks/cube.tres")
var _bar4_shape: BlockShape = preload("res://config/blocks/bar4.tres")
var _slab6_shape: BlockShape = preload("res://config/blocks/slab6.tres")
var _pillar_shape: BlockShape = preload("res://config/blocks/pillar.tres")
var _l4_shape: BlockShape = preload("res://config/blocks/L4.tres")

## A 2x2-cube footprint, like the first four cells of config/blocks/slab6.tres.
var _two_by_two: Array[Vector3i] = [
	Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)
]

var _grid: CellGrid = null
var _raster: TerritoryRaster = null


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, CELL)
	_raster = TerritoryRaster.new(_grid, _territory_tuning)


func _cell_centre(cx: int = 0, cy: int = 0) -> Vector2:
	return _grid.cell_center(_grid.res / 2 + cx, _grid.res / 2 + cy)


## The 2x2 footprint below is built with its origin on a cell centre (so each
## of its four sub-cubes lands aligned on its own single cell, giving exactly
## four covered cells -- an origin on a cell *corner* would have each sub-cube
## itself straddle a corner and cover up to nine cells in the union). The
## footprint's own geometric centre then sits half a cell in from that origin.
func _two_by_two_footprint_origin(cx: int = 0, cy: int = 0) -> Vector2:
	return _cell_centre(cx, cy)


func _two_by_two_footprint_centre(cx: int = 0, cy: int = 0) -> Vector2:
	return _two_by_two_footprint_origin(cx, cy) + Vector2(CELL, CELL) * 0.5


func _candidate(
	origin: Vector2,
	support_height: float = 0.0,
	footprint_cells: PackedInt32Array = PackedInt32Array(),
	on_top_of_own_stack: bool = false,
	corner_support_hits: int = -1
) -> BotCandidate:
	var candidate: BotCandidate = BotCandidate.new()
	candidate.origin = origin
	candidate.support_height = support_height
	candidate.footprint_cells = footprint_cells
	candidate.on_top_of_own_stack = on_top_of_own_stack
	candidate.corner_support_hits = corner_support_hits
	return candidate


func _score(
	candidate: BotCandidate,
	goal_positions: PackedVector2Array = PackedVector2Array(),
	enemy_circle_centers: PackedVector2Array = PackedVector2Array(),
	active_special_positions: PackedVector2Array = PackedVector2Array()
) -> float:
	return BotPlacementScorer.score(
		candidate, _raster, _grid, 0, goal_positions, enemy_circle_centers,
		active_special_positions, _bot_tuning, MAP_RADIUS
	)


## -- score(): stability -------------------------------------------------------

func test_a_fully_supported_flat_candidate_beats_a_corner_balanced_one() -> void:
	## docs/M5_PLAN.md P2: "A candidate resting entirely on
	## on_top_of_own_stack == true with full contact scores higher than one
	## balanced on a corner." Same footprint, same origin, same height --
	## only the contact/stack signals differ.
	var footprint: PackedInt32Array = PlacementRules.footprint_cells(
		_two_by_two, Basis.IDENTITY, _two_by_two_footprint_origin(), CELL, _grid
	)
	assert_eq(footprint.size(), 4, "Setup: a grid-aligned 2x2 footprint covers exactly four cells.")

	var centre: Vector2 = _two_by_two_footprint_centre()
	var full_contact: BotCandidate = _candidate(centre, 3.0, footprint, true, 4)
	var corner_balanced: BotCandidate = _candidate(centre, 3.0, footprint, false, 1)
	assert_gt(_score(full_contact), _score(corner_balanced),
		"Full contact on its own stack must outscore a corner-balanced placement at equal height.")


func test_stability_prefers_a_centred_origin_over_one_outside_the_footprint() -> void:
	var footprint: PackedInt32Array = PlacementRules.footprint_cells(
		_two_by_two, Basis.IDENTITY, _two_by_two_footprint_origin(), CELL, _grid
	)
	var centre: Vector2 = _two_by_two_footprint_centre()
	var centred: BotCandidate = _candidate(centre, 0.0, footprint, false, 4)
	var off_centre: BotCandidate = _candidate(centre + Vector2(10.0, 10.0), 0.0, footprint, false, 4)
	assert_gt(_score(centred), _score(off_centre),
		"A centre of mass inside the supported footprint scores higher than one far outside it.")


## -- score(): goal progress ---------------------------------------------------

func test_closer_to_goal_beats_farther_all_else_equal() -> void:
	var goal: PackedVector2Array = PackedVector2Array([Vector2(15.0, 0.0)])
	var closer: BotCandidate = _candidate(Vector2(10.0, 0.0), 2.0)
	var farther: BotCandidate = _candidate(Vector2(-10.0, 0.0), 2.0)
	assert_gt(_score(closer, goal), _score(farther, goal),
		"A candidate nearer the goal flag scores higher, all else equal.")


func test_a_candidate_whose_estimated_circle_already_reaches_the_goal_scores_at_least_as_well() -> void:
	var goal: PackedVector2Array = PackedVector2Array([Vector2(2.0, 0.0)])
	# Bontago-d5c.9 (rebalanced): support_height is held equal between the two
	# candidates so only the goal metric differs -- a taller *oriented shape*
	# (shape_height, not support_height) right next to the goal makes its
	# estimated influence circle already reach the goal (a negative
	# goal-progress metric), without also picking up the unrelated height-term
	# bonus a differing support_height would have conflated this with.
	var reaching: BotCandidate = _candidate(Vector2(0.0, 0.0), 2.0)
	reaching.shape_height = 20.0
	var not_reaching: BotCandidate = _candidate(Vector2(0.0, 0.0), 2.0)
	assert_gt(_score(reaching, goal), _score(not_reaching, goal))


func test_taller_shape_height_estimates_a_larger_goal_progress_radius() -> void:
	# Bontago-d5c.9 (item E): BotCandidate.shape_height (the oriented shape's
	# own height in cube units) feeds InfluenceCircle.radius_for_height()
	# alongside support_height -- at equal support_height, a taller shape
	# estimates a larger future influence radius, which is a better (higher)
	# goal-progress score.
	var goal: PackedVector2Array = PackedVector2Array([Vector2(15.0, 0.0)])
	var tall: BotCandidate = _candidate(Vector2(0.0, 0.0), 2.0)
	tall.shape_height = 3.0
	var short: BotCandidate = _candidate(Vector2(0.0, 0.0), 2.0)
	short.shape_height = 0.0
	assert_gt(_score(tall, goal), _score(short, goal),
		"A taller oriented shape at equal support height scores higher via the goal-progress metric alone.")


## -- score(): risk -------------------------------------------------------------

func test_a_candidate_inside_the_enemy_territory_risk_radius_is_penalised() -> void:
	var safe: BotCandidate = _candidate(Vector2(0.0, 0.0), 1.0)
	var risky: BotCandidate = _candidate(Vector2(0.0, 0.0), 1.0)
	var enemy_far: PackedVector2Array = PackedVector2Array(
		[Vector2(0.0, 0.0) + Vector2(_bot_tuning.risk_enemy_territory_radius_m * 10.0, 0.0)]
	)
	var enemy_near: PackedVector2Array = PackedVector2Array([Vector2(0.5, 0.0)])
	assert_gt(_score(safe, PackedVector2Array(), enemy_far), _score(risky, PackedVector2Array(), enemy_near),
		"A candidate close to an enemy circle center is penalised relative to a safe one.")


func test_a_candidate_inside_the_active_special_risk_radius_is_penalised() -> void:
	var safe: BotCandidate = _candidate(Vector2(0.0, 0.0), 1.0)
	var risky: BotCandidate = _candidate(Vector2(0.0, 0.0), 1.0)
	var special_far: PackedVector2Array = PackedVector2Array(
		[Vector2(_bot_tuning.risk_active_special_radius_m * 10.0, 0.0)]
	)
	var special_near: PackedVector2Array = PackedVector2Array([Vector2(0.5, 0.0)])
	assert_gt(
		_score(safe, PackedVector2Array(), PackedVector2Array(), special_far),
		_score(risky, PackedVector2Array(), PackedVector2Array(), special_near),
		"A candidate close to an active special is penalised relative to a safe one."
	)


## -- score(): height -----------------------------------------------------------

func test_a_taller_candidate_scores_higher_all_else_equal() -> void:
	var tall: BotCandidate = _candidate(Vector2.ZERO, 5.0)
	var flat: BotCandidate = _candidate(Vector2.ZERO, 0.0)
	assert_gt(_score(tall), _score(flat))


## -- flattest_orientations -----------------------------------------------------

func test_cube_flattest_orientation_is_the_identity() -> void:
	var result: Array[int] = BotPlacementScorer.flattest_orientations(_cube_shape, 5)
	assert_false(result.is_empty())
	assert_eq(result[0], 0, "Any face of a cube is equally flat; the tie-break picks the identity first.")


func _assert_flat(shape: BlockShape, orientation_index: int) -> void:
	var basis: Basis = BlockOrientations.get_basis(orientation_index)
	var min_height: float = INF
	var max_height: float = -INF
	for cell: Vector3i in shape.cells:
		var height: float = (basis * Vector3(cell)).y
		min_height = minf(min_height, height)
		max_height = maxf(max_height, height)
	assert_almost_eq(min_height, max_height, 0.01,
		"Every cube of the flattest orientation must sit at the same height (lying flat, not standing on end).")


func test_bar4_flattest_orientation_lies_flat_not_on_end() -> void:
	var result: Array[int] = BotPlacementScorer.flattest_orientations(_bar4_shape, 5)
	assert_false(result.is_empty())
	_assert_flat(_bar4_shape, result[0])


func test_slab6_flattest_orientation_lies_flat_not_on_end() -> void:
	var result: Array[int] = BotPlacementScorer.flattest_orientations(_slab6_shape, 5)
	assert_false(result.is_empty())
	_assert_flat(_slab6_shape, result[0])


func test_pillar_flattest_orientation_lies_flat_not_on_end() -> void:
	# config/blocks/pillar.tres is a 3-cube vertical column
	# (Vector3i(0,0,0),(0,1,0),(0,2,0)) -- orientation 0 (identity) stands it
	# on end (heights 0/1/2, not flat), so the flattest lay must not be it.
	var result: Array[int] = BotPlacementScorer.flattest_orientations(_pillar_shape, 5)
	assert_false(result.is_empty())
	assert_ne(result[0], 0, "orientation 0 stands the pillar on end; the flattest lay must not be the identity.")
	_assert_flat(_pillar_shape, result[0])


func test_l4_flattest_orientation_lies_flat_not_on_end() -> void:
	# config/blocks/L4.tres's cells span y = 0..2 under the identity
	# orientation (not flat), so its flattest lay must not be orientation 0.
	var result: Array[int] = BotPlacementScorer.flattest_orientations(_l4_shape, 5)
	assert_false(result.is_empty())
	assert_ne(result[0], 0, "orientation 0 does not lay the L4 flat; the flattest lay must not be the identity.")
	_assert_flat(_l4_shape, result[0])


func test_flattest_orientations_returns_distinct_indices_up_to_max_count() -> void:
	var result: Array[int] = BotPlacementScorer.flattest_orientations(_cube_shape, 6)
	assert_eq(result.size(), 6)
	var seen: Dictionary = {}
	for index: int in result:
		assert_false(seen.has(index), "flattest_orientations() must not repeat an index.")
		seen[index] = true


func test_flattest_orientations_is_empty_for_a_shapeless_block_or_zero_count() -> void:
	var no_cells: BlockShape = BlockShape.new()
	assert_true(BotPlacementScorer.flattest_orientations(no_cells, 5).is_empty())
	assert_true(BotPlacementScorer.flattest_orientations(_cube_shape, 0).is_empty())


## -- pick_best ------------------------------------------------------------------

func test_pick_best_returns_null_on_an_empty_list() -> void:
	var empty: Array[BotCandidate] = []
	assert_null(BotPlacementScorer.pick_best(
		empty, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
		_bot_tuning, MAP_RADIUS
	))


func test_pick_best_returns_the_highest_scoring_candidate() -> void:
	var low: BotCandidate = _candidate(Vector2.ZERO, 0.0)
	var high: BotCandidate = _candidate(Vector2.ZERO, 5.0)
	var mid: BotCandidate = _candidate(Vector2.ZERO, 2.0)
	var candidates: Array[BotCandidate] = [low, high, mid]
	var best: BotCandidate = BotPlacementScorer.pick_best(
		candidates, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
		_bot_tuning, MAP_RADIUS
	)
	assert_eq(best, high)


## -- Bontago-1t5.3 phase A: mode-aware scoring ------------------------------------

## A home circle (team 0) covering the middle of the field so candidates there
## stand in a home-connected group.
func _connect_home_territory() -> void:
	var circles: Array[InfluenceCircle] = [InfluenceCircle.new(Vector2.ZERO, 12.0, 0, 0, true, 0)]
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	_raster.update(circles, solver.solve(circles), 0.1, false, false)


func _ctf_goal(held: Array[bool]) -> BotModeGoal:
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = MatchConfig.GameMode.CAPTURE_THE_FLAG
	goal.beacon_positions = PackedVector2Array([Vector2(8.0, 0.0), Vector2(-8.0, 0.0)])
	goal.beacon_held_by_own = held
	goal.beacon_score_rate = 1.0
	return goal


func _pick(candidates: Array[BotCandidate], goal: BotModeGoal) -> BotCandidate:
	return BotPlacementScorer.pick_best(
		candidates, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
		_bot_tuning, MAP_RADIUS, goal
	)


func test_ctf_extends_towards_an_unheld_beacon() -> void:
	_connect_home_territory()
	var towards: BotCandidate = _candidate(Vector2(7.0, 0.0))
	var away: BotCandidate = _candidate(Vector2(-7.0, 0.0))
	var held: Array[bool] = [false, true]
	var candidates: Array[BotCandidate] = [away, towards]
	assert_eq(_pick(candidates, _ctf_goal(held)), towards)


func test_ctf_reinforces_a_held_beacon_when_all_are_held() -> void:
	_connect_home_territory()
	var near_held: BotCandidate = _candidate(Vector2(-7.0, 0.0))
	var far: BotCandidate = _candidate(Vector2(0.0, 7.0))
	var held: Array[bool] = [true, true]
	var candidates: Array[BotCandidate] = [far, near_held]
	assert_eq(_pick(candidates, _ctf_goal(held)), near_held)


## -- Bontago-1t5.1: classic with several goals ------------------------------------

func _classic_goal(held: Array[bool], goals: PackedVector2Array) -> BotModeGoal:
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = MatchConfig.GameMode.CLASSIC
	goal.goal_positions = goals
	goal.goal_in_home_group = held
	goal.home_group = _raster.group_at_point(Vector2.ZERO)
	var component: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	for i: int in range(goals.size()):
		if held[i]:
			component.append(goals[i])
	goal.component_points = component
	goal.target_goal_index = BotPlacementScorer.next_goal_index(goals, held, component, Vector2.ZERO)
	return goal


func test_next_goal_index_picks_the_unheld_goal_nearest_the_component() -> void:
	var goals: PackedVector2Array = PackedVector2Array([Vector2(3.0, 0.0), Vector2(-9.0, 0.0), Vector2(0.0, 12.0)])
	var held: Array[bool] = [true, false, false]
	var component: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2(3.0, 0.0)])
	assert_eq(BotPlacementScorer.next_goal_index(goals, held, component, Vector2.ZERO), 1)
	var all_held: Array[bool] = [true, true, true]
	assert_eq(BotPlacementScorer.next_goal_index(goals, all_held, component, Vector2.ZERO), -1)


func test_classic_multi_goal_extends_towards_the_next_unheld_goal() -> void:
	_connect_home_territory()
	var goals: PackedVector2Array = PackedVector2Array([Vector2(6.0, 0.0), Vector2(-9.0, 0.0), Vector2(0.0, 11.0)])
	var held: Array[bool] = [true, false, false]
	var goal: BotModeGoal = _classic_goal(held, goals)
	assert_eq(goal.target_goal_index, 1)
	# Legacy nearest-goal scoring would favour (5,0) (next to held goal 0).
	var towards: BotCandidate = _candidate(Vector2(-7.0, 0.0))
	var near_held: BotCandidate = _candidate(Vector2(4.0, 1.0))
	var candidates: Array[BotCandidate] = [near_held, towards]
	assert_eq(_pick(candidates, goal), towards)


func test_classic_multi_goal_keeps_held_goals_reinforced_once_all_are_held() -> void:
	_connect_home_territory()
	var goals: PackedVector2Array = PackedVector2Array([Vector2(7.0, 0.0), Vector2(-7.0, 0.0)])
	var held: Array[bool] = [true, true]
	var goal: BotModeGoal = _classic_goal(held, goals)
	assert_eq(goal.target_goal_index, -1)
	var near_held: BotCandidate = _candidate(Vector2(-6.0, 1.0))
	var far: BotCandidate = _candidate(Vector2(0.0, 8.0))
	var candidates: Array[BotCandidate] = [far, near_held]
	assert_eq(_pick(candidates, goal), near_held)


func test_classic_multi_goal_penalises_a_spot_outside_the_home_component() -> void:
	_connect_home_territory()
	var goals: PackedVector2Array = PackedVector2Array([Vector2(6.0, 0.0), Vector2(-9.0, 0.0)])
	var held: Array[bool] = [true, false]
	var goal: BotModeGoal = _classic_goal(held, goals)
	var inside: BotCandidate = _candidate(Vector2(-3.0, 0.0))
	var outside: BotCandidate = _candidate(Vector2(-19.0, 0.0))
	assert_lt(_raster.group_at_point(outside.origin), 0, "Setup: the far point is outside the home group.")
	var inside_score: float = BotPlacementScorer.score(inside, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), _bot_tuning, MAP_RADIUS, goal)
	var legacy_outside: float = BotPlacementScorer.score(outside, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), _bot_tuning, MAP_RADIUS, null)
	var outside_score: float = BotPlacementScorer.score(outside, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), _bot_tuning, MAP_RADIUS, goal)
	assert_lt(outside_score, legacy_outside + 1.0, "Outside the component the extra term only subtracts the penalty (plus goal pull).")
	assert_gt(inside_score, outside_score)


func test_classic_single_goal_scoring_is_unchanged() -> void:
	_connect_home_territory()
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = MatchConfig.GameMode.CLASSIC
	goal.goal_positions = PackedVector2Array([Vector2(6.0, 0.0)])
	assert_true(goal.is_neutral())
	var spot: BotCandidate = _candidate(Vector2(3.0, 0.0), 1.0)
	var goals: PackedVector2Array = PackedVector2Array([Vector2(6.0, 0.0)])
	var with_goal: float = BotPlacementScorer.score(spot, _raster, _grid, 0, goals, PackedVector2Array(), PackedVector2Array(), _bot_tuning, MAP_RADIUS, goal)
	var without: float = BotPlacementScorer.score(spot, _raster, _grid, 0, goals, PackedVector2Array(), PackedVector2Array(), _bot_tuning, MAP_RADIUS, null)
	assert_eq(with_goal, without)


func test_ctf_term_needs_a_home_connected_spot() -> void:
	# Raster left empty: nothing is connected, so the CTF term is zero.
	var held: Array[bool] = [false, true]
	var goal: BotModeGoal = _ctf_goal(held)
	var spot: BotCandidate = _candidate(Vector2(7.0, 0.0))
	var with_goal: float = BotPlacementScorer.score(
		spot, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
		_bot_tuning, MAP_RADIUS, goal
	)
	assert_eq(with_goal, _score(spot))


func test_sky_prefers_the_stable_candidate_on_its_own_tower() -> void:
	var cells: PackedInt32Array = PackedInt32Array([0, 1, 2, 3])
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = MatchConfig.GameMode.REACH_THE_SKY
	goal.has_tower = true
	goal.tower_origin = Vector2(2.0, 2.0)
	goal.tower_height = 4.0
	var on_tower: BotCandidate = _candidate(Vector2(2.0, 2.0), 4.0, cells, true, 4)
	on_tower.shape_height = 1.0
	var overhang: BotCandidate = _candidate(Vector2(2.0, 2.0), 4.0, cells, true, 1)
	overhang.shape_height = 1.0
	var spread: BotCandidate = _candidate(Vector2(-10.0, 5.0), 0.0, cells, false, 4)
	spread.shape_height = 1.0
	var candidates: Array[BotCandidate] = [spread, overhang, on_tower]
	assert_eq(_pick(candidates, goal), on_tower)


func test_classic_and_neutral_modes_score_identically_to_no_goal() -> void:
	var candidate: BotCandidate = _candidate(Vector2(3.0, 1.0), 2.0, PackedInt32Array([0, 1]), true, 1)
	var plain: float = _score(candidate)
	for mode: int in [MatchConfig.GameMode.CLASSIC]:
		var goal: BotModeGoal = BotModeGoal.new()
		goal.mode = mode
		assert_eq(BotPlacementScorer.score(
			candidate, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
			_bot_tuning, MAP_RADIUS, goal
		), plain)
	assert_eq(BotPlacementScorer.score(
		candidate, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
		_bot_tuning, MAP_RADIUS, null
	), plain)


func test_ctf_does_not_double_weight_unheld_beacons() -> void:
	_connect_home_territory()
	var held: Array[bool] = [false, false]
	var goal: BotModeGoal = _ctf_goal(held)
	var spot: BotCandidate = _candidate(Vector2(7.0, 0.0))
	var with_goal: float = BotPlacementScorer.score(
		spot, _raster, _grid, 0, goal.beacon_positions, PackedVector2Array(), PackedVector2Array(),
		_bot_tuning, MAP_RADIUS, goal
	)
	var ctf_only: float = BotPlacementScorer.score(
		spot, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
		_bot_tuning, MAP_RADIUS, goal
	)
	assert_eq(with_goal, ctf_only, "the classic goal term is replaced, not added, in CTF")


## -- Bontago-1t5.3 phase B: Elimination ---------------------------------------------

func _elim_goal(enemy_homes: PackedVector2Array, shares: PackedFloat32Array, own_home: Vector2) -> BotModeGoal:
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = MatchConfig.GameMode.ELIMINATION
	goal.enemy_home_positions = enemy_homes
	goal.enemy_home_shares = shares
	goal.has_own_home = true
	goal.own_home_position = own_home
	return goal


func _score_with(candidate: BotCandidate, goal: BotModeGoal, enemy_centers: PackedVector2Array) -> float:
	return BotPlacementScorer.score(
		candidate, _raster, _grid, 0, PackedVector2Array(), enemy_centers, PackedVector2Array(),
		_bot_tuning, MAP_RADIUS, goal
	)


func test_elimination_attacks_towards_a_living_enemy_home() -> void:
	var goal: BotModeGoal = _elim_goal(PackedVector2Array([Vector2(12.0, 0.0)]), PackedFloat32Array([0.2]), Vector2(-15.0, 0.0))
	var towards: BotCandidate = _candidate(Vector2(6.0, 0.0), 1.0)
	var away: BotCandidate = _candidate(Vector2(-6.0, 0.0), 1.0)
	var candidates: Array[BotCandidate] = [away, towards]
	assert_eq(_pick(candidates, goal), towards)


func test_elimination_prefers_the_weaker_of_two_equidistant_enemies() -> void:
	var goal: BotModeGoal = _elim_goal(
		PackedVector2Array([Vector2(12.0, 0.0), Vector2(-12.0, 0.0)]), PackedFloat32Array([0.6, 0.05]), Vector2(0.0, 18.0)
	)
	var at_strong: BotCandidate = _candidate(Vector2(7.0, 0.0), 1.0)
	var at_weak: BotCandidate = _candidate(Vector2(-7.0, 0.0), 1.0)
	var candidates: Array[BotCandidate] = [at_strong, at_weak]
	assert_eq(_pick(candidates, goal), at_weak)


func test_elimination_defends_the_own_home_when_an_enemy_circle_is_close() -> void:
	var home: Vector2 = Vector2(-15.0, 0.0)
	var goal: BotModeGoal = _elim_goal(PackedVector2Array([Vector2(15.0, 0.0)]), PackedFloat32Array([0.2]), home)
	var threats: PackedVector2Array = PackedVector2Array([Vector2(-10.0, 3.0), Vector2(-9.0, -3.0)])
	var near_home: BotCandidate = _candidate(Vector2(-14.0, 0.0), 1.0)
	var attacking: BotCandidate = _candidate(Vector2(-6.0, 0.0), 1.0)
	assert_gt(_score_with(near_home, goal, threats), _score_with(attacking, goal, threats),
		"with enemy circles at the gate the bot builds up its own home")
	assert_gt(_score_with(near_home, goal, threats), _score_with(near_home, goal, PackedVector2Array()),
		"the defend bonus grows with the threat")


func test_elimination_with_no_enemy_homes_or_own_home_adds_nothing() -> void:
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = MatchConfig.GameMode.ELIMINATION
	var candidate: BotCandidate = _candidate(Vector2(3.0, 1.0), 2.0)
	assert_eq(_score_with(candidate, goal, PackedVector2Array()), _score(candidate))


## -- Bontago-1t5.4: coverage of the enemy home beats a near miss -------------------

func _tall_radius() -> float:
	return InfluenceCircle.radius_for_height(8.0, _territory_tuning, MAP_RADIUS)


func test_elimination_overlap_mode_covering_the_home_beats_a_near_miss() -> void:
	var radius: float = _tall_radius()
	var goal: BotModeGoal = _elim_goal(PackedVector2Array([Vector2(12.0, 0.0)]), PackedFloat32Array([0.2]), Vector2(-15.0, 0.0))
	var covers: BotCandidate = _candidate(Vector2(12.0 - (radius - 0.5), 0.0), 8.0)
	var misses: BotCandidate = _candidate(Vector2(12.0 - (radius + 0.5), 0.0), 8.0)
	assert_gt(_score_with(covers, goal, PackedVector2Array()), _score_with(misses, goal, PackedVector2Array()))


func test_elimination_off_mode_beating_the_home_circle_beats_a_near_miss() -> void:
	var radius: float = _tall_radius()
	var goal: BotModeGoal = _elim_goal(PackedVector2Array([Vector2(12.0, 0.0)]), PackedFloat32Array([0.2]), Vector2(-15.0, 0.0))
	goal.no_overlap_mode = true
	goal.home_radius = 6.0
	var flips: BotCandidate = _candidate(Vector2(12.0 - (radius - 6.0 - 0.5), 0.0), 8.0)
	var misses: BotCandidate = _candidate(Vector2(12.0 - (radius - 6.0 + 0.5), 0.0), 8.0)
	assert_gt(_score_with(flips, goal, PackedVector2Array()), _score_with(misses, goal, PackedVector2Array()))
	# Merely overlapping the home (enough in overlap modes) is not enough in OFF mode.
	var overlap_only: BotCandidate = _candidate(Vector2(12.0 - (radius - 0.5), 0.0), 8.0)
	assert_gt(_score_with(flips, goal, PackedVector2Array()), _score_with(overlap_only, goal, PackedVector2Array()))


func test_elimination_overshoot_has_diminishing_returns() -> void:
	var radius: float = _tall_radius()
	var goal: BotModeGoal = _elim_goal(PackedVector2Array([Vector2(12.0, 0.0)]), PackedFloat32Array([0.0]), Vector2(-15.0, 0.0))
	var neutral: BotModeGoal = BotModeGoal.new()
	var gains: Array[float] = []
	for margin: float in [0.5, 3.5, 6.5]:
		var candidate: BotCandidate = _candidate(Vector2(12.0 - (radius - margin), 0.0), 8.0)
		gains.append(_score_with(candidate, goal, PackedVector2Array()) - _score_with(candidate, neutral, PackedVector2Array()))
	assert_gt(gains[1], gains[0])
	assert_almost_eq(gains[2], gains[1], 0.001, "past the cap extra overshoot adds nothing")


func test_elimination_off_mode_defend_rewards_covering_the_home_circle() -> void:
	var radius: float = _tall_radius()
	var home: Vector2 = Vector2(-15.0, 0.0)
	var goal: BotModeGoal = _elim_goal(PackedVector2Array([Vector2(15.0, 0.0)]), PackedFloat32Array([0.2]), home)
	var threats: PackedVector2Array = PackedVector2Array([Vector2(-10.0, 3.0)])
	var on_home: BotCandidate = _candidate(home + Vector2(1.0, 0.0), 8.0)
	var weaker: BotCandidate = _candidate(home + Vector2(radius + 1.0, 0.0), 8.0)
	var overlap_gap: float = _score_with(on_home, goal, threats) - _score_with(weaker, goal, threats)
	goal.no_overlap_mode = true
	goal.home_radius = 6.0
	var off_gap: float = _score_with(on_home, goal, threats) - _score_with(weaker, goal, threats)
	assert_gt(off_gap, overlap_gap, "OFF mode adds a home-coverage defend bonus")


## -- Bontago-1t5.4 part 2: approach / reach ------------------------------------------

func test_elimination_approach_candidate_beats_equal_height_inward_candidate() -> void:
	var goal: BotModeGoal = _elim_goal(PackedVector2Array([Vector2(15.0, 0.0)]), PackedFloat32Array([0.2]), Vector2(-15.0, 0.0))
	var inward: BotCandidate = _candidate(Vector2(-12.0, 0.0), 1.0)
	var frontier: BotCandidate = _candidate(Vector2(-2.0, 0.0), 1.0)
	assert_gt(_score_with(frontier, goal, PackedVector2Array()), _score_with(inward, goal, PackedVector2Array()))
	var saved: float = _bot_tuning.weight_elim_approach
	_bot_tuning.weight_elim_approach = 0.0
	var without: float = _score_with(frontier, goal, PackedVector2Array())
	_bot_tuning.weight_elim_approach = saved
	assert_gt(_score_with(frontier, goal, PackedVector2Array()), without, "the approach term itself adds reward")


func test_elimination_approach_is_damped_when_home_is_threatened() -> void:
	var home: Vector2 = Vector2(-15.0, 0.0)
	var goal: BotModeGoal = _elim_goal(PackedVector2Array([Vector2(15.0, 0.0)]), PackedFloat32Array([0.2]), home)
	var threats: PackedVector2Array = PackedVector2Array([Vector2(-10.0, 3.0), Vector2(-9.0, -3.0)])
	var frontier: BotCandidate = _candidate(Vector2(-2.0, 0.0), 1.0)
	var calm: float = BotPlacementScorer._elimination_approach_term(frontier, goal, PackedVector2Array(), 1.0, _bot_tuning)
	var threatened: float = BotPlacementScorer._elimination_approach_term(frontier, goal, threats, 1.0, _bot_tuning)
	assert_gt(calm, threatened * 2.0)


func test_target_home_index_picks_weakest_then_nearest() -> void:
	var weak_goal: BotModeGoal = _elim_goal(
		PackedVector2Array([Vector2(12.0, 0.0), Vector2(-12.0, 0.0)]), PackedFloat32Array([0.9, 0.0]), Vector2(0.0, 18.0)
	)
	assert_eq(BotPlacementScorer.target_home_index(weak_goal, _bot_tuning), 1, "weaker of equidistant homes")
	var near_goal: BotModeGoal = _elim_goal(
		PackedVector2Array([Vector2(20.0, 0.0), Vector2(-5.0, 0.0)]), PackedFloat32Array([0.2, 0.2]), Vector2(-10.0, 0.0)
	)
	assert_eq(BotPlacementScorer.target_home_index(near_goal, _bot_tuning), 1, "nearer of equal-share homes")
	var none: BotModeGoal = _elim_goal(PackedVector2Array(), PackedFloat32Array(), Vector2.ZERO)
	assert_eq(BotPlacementScorer.target_home_index(none, _bot_tuning), -1)
