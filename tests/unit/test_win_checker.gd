extends GutTest
## Spec 2.3: "A player or team wins when one connected territory contains every
## goal flag continuously for capture_hold = 3 s."
##
## Spec 3.3 says to check it against the raster. The decisive detail
## (docs/M2_PLAN.md, "Solver -> raster -> win check") is that every goal must
## read back the same *group*, not merely the same team: that is what makes it
## one connected territory, so a team holding two goals with two separate
## towers correctly does not win.

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const CENTRE_GOAL: Vector2 = Vector2(0.0, 0.0)

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


func _rasterize(circles: Array[InfluenceCircle]) -> void:
	_raster.update(circles, _solver.solve(circles), 0.1, true, false)


## Rasterizes `circles`, then advances the win check `ticks` times by `delta`.
func _run(
	checker: WinChecker, circles: Array[InfluenceCircle], ticks: int, delta: float = 0.1
) -> void:
	_rasterize(circles)
	for i: int in range(ticks):
		checker.update(_raster, delta)


func _checker(goals: PackedVector2Array) -> WinChecker:
	return WinChecker.new(goals, _tuning.capture_hold)


## -- Construction ------------------------------------------------------------

func test_it_starts_with_nobody_capturing() -> void:
	var checker: WinChecker = _checker(PackedVector2Array([CENTRE_GOAL]))
	assert_eq(checker.capturing_team(), WinChecker.NO_TEAM)
	assert_eq(checker.winner(), WinChecker.NO_TEAM)
	assert_almost_eq(checker.capture_progress(), 0.0, 0.0001)
	assert_almost_eq(checker.capture_hold(), _tuning.capture_hold, 0.0001)
	assert_eq(checker.goal_positions().size(), 1)


## -- Capturing ---------------------------------------------------------------

func test_holding_the_only_goal_starts_a_capture() -> void:
	var checker: WinChecker = _checker(PackedVector2Array([CENTRE_GOAL]))
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_run(checker, circles, 1)
	assert_eq(checker.capturing_team(), 0)
	assert_gt(checker.capture_progress(), 0.0)
	assert_eq(checker.winner(), WinChecker.NO_TEAM, "Far too early to win.")


func test_progress_ramps_towards_capture_hold() -> void:
	var checker: WinChecker = _checker(PackedVector2Array([CENTRE_GOAL]))
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_run(checker, circles, 10)
	assert_almost_eq(checker.capture_progress(), 1.0 / 3.0, 0.02,
		"1.0 s of a 3.0 s hold is a third of the way.")
	_run(checker, circles, 10)
	assert_almost_eq(checker.capture_progress(), 2.0 / 3.0, 0.02)


func test_the_capture_completes_at_capture_hold() -> void:
	var checker: WinChecker = _checker(PackedVector2Array([CENTRE_GOAL]))
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_run(checker, circles, 29)
	assert_eq(checker.winner(), WinChecker.NO_TEAM, "2.9 s is not yet a win.")
	_run(checker, circles, 1)
	assert_eq(checker.winner(), 0, "3.0 s of unbroken hold wins the match.")
	assert_almost_eq(checker.capture_progress(), 1.0, 0.0001)


func test_breaking_the_hold_at_29_seconds_resets_progress() -> void:
	var checker: WinChecker = _checker(PackedVector2Array([CENTRE_GOAL]))
	var holding: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_run(checker, holding, 29)
	assert_gt(checker.capture_progress(), 0.9, "Setup: nearly there.")

	## The tower falls: the home circle is now nowhere near the goal.
	var broken: Array[InfluenceCircle] = [_home(15.0, 15.0, 0)]
	_run(checker, broken, 1)
	assert_eq(checker.winner(), WinChecker.NO_TEAM)
	assert_eq(checker.capturing_team(), WinChecker.NO_TEAM)
	assert_almost_eq(checker.capture_progress(), 0.0, 0.0001,
		"The hold has to be continuous, so a break sends progress back to 0.")


func test_a_broken_capture_starts_over_rather_than_resuming() -> void:
	var checker: WinChecker = _checker(PackedVector2Array([CENTRE_GOAL]))
	var holding: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_run(checker, holding, 29)
	_run(checker, [_home(15.0, 15.0, 0)] as Array[InfluenceCircle], 1)
	_run(checker, holding, 5)
	assert_eq(checker.winner(), WinChecker.NO_TEAM)
	assert_almost_eq(checker.capture_progress(), 0.5 / 3.0, 0.02,
		"Only the 0.5 s since the break counts.")


func test_the_winner_latches() -> void:
	var checker: WinChecker = _checker(PackedVector2Array([CENTRE_GOAL]))
	var holding: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_run(checker, holding, 30)
	assert_eq(checker.winner(), 0, "Setup.")

	_run(checker, [_home(15.0, 15.0, 0)] as Array[InfluenceCircle], 20)
	assert_eq(checker.winner(), 0, "Losing the goal afterwards does not un-win.")
	assert_almost_eq(checker.capture_progress(), 1.0, 0.0001)


## -- One connected territory, not one team -----------------------------------

func test_every_goal_must_sit_in_the_same_group() -> void:
	var goals: PackedVector2Array = PackedVector2Array([Vector2(-4.0, 0.0), Vector2(4.0, 0.0)])
	var checker: WinChecker = _checker(goals)
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_run(checker, circles, 30)
	assert_eq(checker.winner(), 0, "One circle covering both goals is one territory.")


func test_one_team_holding_two_goals_in_two_groups_does_not_win() -> void:
	var goals: PackedVector2Array = PackedVector2Array([
		Vector2(-15.0, 0.0), Vector2(15.0, 0.0)
	])
	var checker: WinChecker = _checker(goals)
	## Two slots of the same team, far enough apart that their territories
	## never touch. Each owns one goal.
	var circles: Array[InfluenceCircle] = [_home(-15.0, 0.0, 0, 0), _home(15.0, 0.0, 0, 1)]
	var groups: TerritoryGroups = _solver.solve(circles)
	assert_eq(groups.group_count(), 2, "Setup: two disconnected groups, one team.")

	_run(checker, circles, 60)
	assert_eq(checker.winner(), WinChecker.NO_TEAM,
		"Spec 2.3 wants ONE connected territory holding every goal.")
	assert_eq(checker.capturing_team(), WinChecker.NO_TEAM)
	assert_almost_eq(checker.capture_progress(), 0.0, 0.0001)


func test_holding_only_some_of_the_goals_does_not_capture() -> void:
	var goals: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(15.0, 0.0)])
	var checker: WinChecker = _checker(goals)
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_run(checker, circles, 60)
	assert_eq(checker.winner(), WinChecker.NO_TEAM)
	assert_eq(checker.capturing_team(), WinChecker.NO_TEAM)


func test_a_contested_goal_captures_for_nobody() -> void:
	var checker: WinChecker = _checker(PackedVector2Array([CENTRE_GOAL]))
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	_run(checker, circles, 60)
	assert_eq(checker.capturing_team(), WinChecker.NO_TEAM,
		"A contested cell belongs to neither team.")
	assert_eq(checker.winner(), WinChecker.NO_TEAM)


func test_an_unowned_goal_captures_for_nobody() -> void:
	var checker: WinChecker = _checker(PackedVector2Array([CENTRE_GOAL]))
	var circles: Array[InfluenceCircle] = [_home(15.0, 15.0, 0)]
	_run(checker, circles, 60)
	assert_eq(checker.capturing_team(), WinChecker.NO_TEAM)


func test_the_capture_restarts_when_the_holder_changes() -> void:
	var checker: WinChecker = _checker(PackedVector2Array([CENTRE_GOAL]))
	_run(checker, [_home(0.0, 0.0, 0)] as Array[InfluenceCircle], 20)
	assert_eq(checker.capturing_team(), 0, "Setup: team 0 is two thirds through.")

	_run(checker, [_home(0.0, 0.0, 1)] as Array[InfluenceCircle], 5)
	assert_eq(checker.capturing_team(), 1, "Team 1 took the goal.")
	assert_almost_eq(checker.capture_progress(), 0.5 / 3.0, 0.02,
		"Team 1 starts its own hold from zero, not from team 0's progress.")


## -- Layout changes ----------------------------------------------------------

func test_set_goal_positions_replaces_the_layout_and_stops_the_capture() -> void:
	var checker: WinChecker = _checker(PackedVector2Array([CENTRE_GOAL]))
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_run(checker, circles, 20)
	assert_gt(checker.capture_progress(), 0.0, "Setup.")

	checker.set_goal_positions(PackedVector2Array([Vector2(15.0, 0.0)]))
	assert_eq(checker.goal_positions().size(), 1)
	assert_almost_eq(checker.capture_progress(), 0.0, 0.0001)
	assert_eq(checker.capturing_team(), WinChecker.NO_TEAM)

	_run(checker, circles, 60)
	assert_eq(checker.winner(), WinChecker.NO_TEAM, "The new goal is out of reach.")


func test_reset_clears_the_latched_winner() -> void:
	var checker: WinChecker = _checker(PackedVector2Array([CENTRE_GOAL]))
	_run(checker, [_home(0.0, 0.0, 0)] as Array[InfluenceCircle], 30)
	assert_eq(checker.winner(), 0, "Setup.")

	checker.reset()
	assert_eq(checker.winner(), WinChecker.NO_TEAM)
	assert_eq(checker.capturing_team(), WinChecker.NO_TEAM)
	assert_almost_eq(checker.capture_progress(), 0.0, 0.0001)


func test_no_goals_at_all_never_captures() -> void:
	var checker: WinChecker = _checker(PackedVector2Array())
	_run(checker, [_home(0.0, 0.0, 0)] as Array[InfluenceCircle], 60)
	assert_eq(checker.winner(), WinChecker.NO_TEAM,
		"A match with no goal flags cannot be won by standing still.")


## -- The win check against the v2 argmax field -------------------------------
##
## docs/TERRITORY_V2_PLAN.md: WinChecker is unchanged; it keeps working once
## the raster's fill produces v2's ownership groups instead of cell-stamped
## ones. These pin that, so a later change to the fill cannot quietly break
## the capture rule.

func _rasterize_v2(circles: Array[InfluenceCircle]) -> void:
	_raster.update(circles, _solver.solve(circles), 0.1, false, false)


func _run_v2(
	checker: WinChecker, circles: Array[InfluenceCircle], ticks: int, delta: float = 0.1
) -> void:
	_rasterize_v2(circles)
	for i: int in range(ticks):
		checker.update(_raster, delta)


func test_v2_a_goal_inside_my_area_captures_after_capture_hold() -> void:
	var checker: WinChecker = _checker(PackedVector2Array([CENTRE_GOAL]))
	_run_v2(checker, [_home(0.0, 0.0, 0)] as Array[InfluenceCircle], 60)
	assert_eq(checker.winner(), 0, "Spec 2.3 still decides the match off the raster.")


func test_v2_a_goal_where_two_areas_meet_belongs_to_the_argmax_winner() -> void:
	## Under v2 no cell is contested, so a goal between two equal stacks is not
	## neutral ground any more: whichever circle scores higher there holds it,
	## and a dead heat goes to the lower team id.
	var checker: WinChecker = _checker(PackedVector2Array([CENTRE_GOAL]))
	_run_v2(checker, [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)] as Array[InfluenceCircle], 60)
	assert_eq(checker.capturing_team(), 0)
	assert_eq(checker.winner(), 0)


func test_v2_a_cut_off_tower_cannot_hold_a_goal() -> void:
	## home(-10, r6) -- A(-2, r3) -- B(4, r7); the goal sits inside B only, and
	## B does not reach home on its own (14 > 6 + 7), so removing A really cuts.
	var goal: PackedVector2Array = PackedVector2Array([Vector2(6.0, 0.0)])
	var home: InfluenceCircle = _home(-10.0, 0.0, 0)
	var a: InfluenceCircle = InfluenceCircle.new(Vector2(-2.0, 0.0), 3.0, 0, 0, false, 0)
	var b: InfluenceCircle = InfluenceCircle.new(Vector2(4.0, 0.0), 7.0, 0, 0, false, 1)

	var connected: WinChecker = _checker(goal)
	_run_v2(connected, [home, a, b] as Array[InfluenceCircle], 60)
	assert_eq(connected.winner(), 0, "Setup: connected through A, B holds the goal.")

	var severed: WinChecker = _checker(goal)
	_run_v2(severed, [home, b] as Array[InfluenceCircle], 60)
	assert_eq(severed.capturing_team(), WinChecker.NO_TEAM,
		"Cut off from home, B's circle is not in the field at all.")
	assert_eq(severed.winner(), WinChecker.NO_TEAM)
