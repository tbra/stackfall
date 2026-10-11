extends GutTest
## core/ai/BotStrategy.gd (Bontago-1t5.23, Bot V2 P4): the intent rule table (HOLD, DEFEND,
## STRIKE, FINISH, ANCHOR, RACE) and the mode adapters (Elimination SIEGE and the per-seat
## target spread, Domination AREA, Reach the Sky ANCHOR, CTF RACE/HOLD, multi-goal target).
## Pure: hand-built BotWorldViews, no scene tree.

const MAP_RADIUS: float = 60.0
const CELL: float = 1.0
const TEAM: int = 0
const ENEMY: int = 1
const OWN_HOME: Vector2 = Vector2(-13.0, 0.0)
const ENEMY_HOME: Vector2 = Vector2(13.0, 0.0)
const GOAL: Vector2 = Vector2(0.0, 0.0)
const RING_RADIUS: float = 30.0
const RING_SEATS: int = 8
## Top heights (cone radius = 1.5 + 0.84 * top at the shipped 40 degree half-angle).
const LOW_TOP: float = 1.0
const MID_TOP: float = 3.0
const TALL_TOP: float = 14.0

var _territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _tuning: BotStrategyTuning = null


func before_each() -> void:
	_tuning = BotStrategyTuning.new()


func _profile(mask: int = 255, lookahead: float = 3.0) -> BotDifficultyProfile:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.intent_mask = mask
	profile.threat_lookahead_m = lookahead
	return profile


func _radius(top: float) -> float:
	return InfluenceCircle.radius_for_height(top, _territory_tuning, MAP_RADIUS)


## `circles`: Array of [x, z, top, team]; both homes alive, classic goal at GOAL unless `goals` is empty.
func _view(circles: Array, goals: PackedVector2Array = PackedVector2Array([GOAL])) -> BotWorldView:
	var view: BotWorldView = BotWorldView.new()
	view.team_id = TEAM
	view.field_radius = MAP_RADIUS
	view.own_home = OWN_HOME
	view.has_home = true
	view.team_homes = PackedVector2Array([OWN_HOME])
	view.enemy_homes = PackedVector2Array([ENEMY_HOME])
	view.enemy_home_teams = PackedInt32Array([ENEMY])
	view.goals = goals
	for entry: Array in circles:
		view.cx.append(float(entry[0]))
		view.cz.append(float(entry[1]))
		view.cr.append(_radius(float(entry[2])))
		view.cteam.append(int(entry[3]))
	return view


func _choose(view: BotWorldView, profile: BotDifficultyProfile = null) -> BotIntent:
	return BotStrategy.choose(
		view, BotChains.build(view), profile if profile != null else _profile(), _tuning
	)


# --- default ------------------------------------------------------------------

func test_far_from_everything_races_to_the_goal() -> void:
	var intent: BotIntent = _choose(_view([[-20.0, 0.0, MID_TOP, TEAM], [-24.0, 0.0, MID_TOP, TEAM]]))
	assert_eq(intent.kind, BotIntent.Kind.RACE)
	assert_eq(intent.target, GOAL)
	assert_eq(intent.weights, _tuning.weights_race)
	assert_eq(intent.weights.size(), BotIntent.Term.size())


## Bontago-1t5.32: every intent of the defaults and of the shipped resource (its race override
## included) penalises HAZARD, so no intent walks a base into a dissolving overlap.
func test_every_intent_penalises_hazard() -> void:
	for tuning: BotStrategyTuning in [_tuning, BotStrategy.SHIPPED_TUNING]:
		for kind: int in BotIntent.Kind.values():
			var weights: PackedFloat32Array = tuning.weights_for(kind)
			assert_eq(weights.size(), BotIntent.Term.size(), "full vector for %s" % BotIntent.Kind.keys()[kind])
			assert_gt(weights[BotIntent.Term.HAZARD], 0.0, "%s penalises hazard" % BotIntent.Kind.keys()[kind])


func test_disabled_intent_falls_back_to_race() -> void:
	var view: BotWorldView = _view([[-8.0, 0.0, MID_TOP, TEAM]])
	assert_eq(_choose(view).kind, BotIntent.Kind.FINISH, "precondition: finish range")
	var race_only: int = 1 << int(BotIntent.Kind.RACE)
	assert_eq(_choose(view, _profile(race_only)).kind, BotIntent.Kind.RACE)


# --- FINISH ------------------------------------------------------------------

func test_gap_inside_finish_range_builds_the_finish_tower() -> void:
	# Circle edge at 8 - 4.0 = 4 m from the goal; finish_gap_m is 6.
	var intent: BotIntent = _choose(_view([[-8.0, 0.0, MID_TOP, TEAM]]))
	assert_eq(intent.kind, BotIntent.Kind.FINISH)
	assert_eq(intent.target, GOAL)
	assert_eq(intent.weights, _tuning.weights_finish)


func test_gap_outside_finish_range_keeps_racing() -> void:
	assert_eq(_choose(_view([[-20.0, 0.0, MID_TOP, TEAM]])).kind, BotIntent.Kind.RACE)


# --- HOLD --------------------------------------------------------------------

func _owned_goal_view() -> BotWorldView:
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, CELL)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, _territory_tuning)
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(OWN_HOME, TEAM, 0, _territory_tuning),
		InfluenceCircle.for_home(ENEMY_HOME, ENEMY, 1, _territory_tuning),
		InfluenceCircle.for_block(Vector2(-4.0, 0.0), TALL_TOP, TEAM, 0, 7, _territory_tuning, MAP_RADIUS),
	]
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	raster.update(circles, solver.solve(circles), 0.1, false, false)
	var view: BotWorldView = _view([[-4.0, 0.0, TALL_TOP, TEAM]])
	view.raster = raster
	view.grid = grid
	return view


func test_goal_already_own_holds() -> void:
	var view: BotWorldView = _owned_goal_view()
	var cell: Vector2i = view.grid.world_to_cell(GOAL)
	assert_eq(view.raster.team_at(cell.x, cell.y), TEAM, "precondition: the goal cell is own")
	var intent: BotIntent = _choose(view)
	assert_eq(intent.kind, BotIntent.Kind.HOLD)
	assert_eq(intent.target, GOAL)
	assert_eq(intent.focus_circle, -1, "no threat")


func test_hold_names_an_enemy_circle_that_reaches_the_goal() -> void:
	var view: BotWorldView = _owned_goal_view()
	view.cx.append(8.0)
	view.cz.append(0.0)
	view.cr.append(_radius(MID_TOP))
	view.cteam.append(ENEMY)
	var intent: BotIntent = _choose(view)
	assert_eq(intent.kind, BotIntent.Kind.HOLD)
	assert_eq(intent.focus_circle, 1, "the enemy circle within reach plus allowance of the goal")


func test_hold_needs_the_tier_to_have_it() -> void:
	var view: BotWorldView = _owned_goal_view()
	var no_hold: int = 255 & ~(1 << int(BotIntent.Kind.HOLD))
	assert_ne(_choose(view, _profile(no_hold)).kind, BotIntent.Kind.HOLD)


# --- DEFEND ------------------------------------------------------------------

## Own chain of three circles: only the first touches the home, so it carries all three.
func _own_chain() -> Array:
	return [[-9.0, 0.0, MID_TOP, TEAM], [-2.0, 0.0, MID_TOP, TEAM], [-2.0, 7.0, MID_TOP, TEAM]]


func test_threatened_chain_root_defends_against_the_threatener() -> void:
	var circles: Array = _own_chain()
	circles.append([4.0, 0.0, TALL_TOP, ENEMY])
	var view: BotWorldView = _view(circles)
	var intent: BotIntent = _choose(view)
	assert_eq(intent.kind, BotIntent.Kind.DEFEND)
	assert_eq(intent.focus_circle, 3)
	assert_eq(intent.target, Vector2(4.0, 0.0), "aims at the threatener's base")
	assert_eq(intent.weights, _tuning.weights_defend)


func test_threat_lookahead_separates_reactive_and_hard_tiers() -> void:
	# The enemy stack reaches the chain root only with the 3 m look-ahead on top of the allowance.
	var circles: Array = _own_chain()
	circles.append([7.0, 0.0, TALL_TOP, ENEMY])
	var view: BotWorldView = _view(circles, PackedVector2Array())
	assert_eq(_choose(view, _profile(255, 3.0)).kind, BotIntent.Kind.DEFEND)
	assert_ne(_choose(view, _profile(255, 0.0)).kind, BotIntent.Kind.DEFEND)


func test_unconnected_enemy_circle_is_no_threat() -> void:
	var circles: Array = _own_chain()
	circles.append([40.0, 40.0, TALL_TOP, ENEMY])
	assert_ne(_choose(_view(circles)).kind, BotIntent.Kind.DEFEND)


func test_goal_covering_stack_is_defended_even_when_small() -> void:
	# One circle over the goal (downstream 1) under an enemy circle's reach.
	var circles: Array = [[-8.0, 0.0, TALL_TOP, TEAM], [3.0, 0.0, TALL_TOP, ENEMY]]
	var view: BotWorldView = _view(circles)
	var intent: BotIntent = _choose(view)
	assert_eq(intent.kind, BotIntent.Kind.DEFEND)
	assert_eq(intent.focus_circle, 1)


func test_elimination_own_home_is_the_first_defend_key() -> void:
	var view: BotWorldView = _view([[4.0, 0.0, TALL_TOP, ENEMY]], PackedVector2Array())
	view.mode = MatchConfig.GameMode.ELIMINATION
	view.enemy_homes = PackedVector2Array([Vector2(14.0, 0.0)])
	view.own_home = Vector2(-8.0, 0.0)
	view.team_homes = PackedVector2Array([view.own_home])
	var intent: BotIntent = _choose(view)
	assert_eq(intent.kind, BotIntent.Kind.DEFEND)
	assert_eq(intent.focus_circle, 0)


# --- STRIKE ------------------------------------------------------------------

## Enemy trunk e0 at the field centre carrying two branches, an own circle 3 m from its base.
func _strike_view() -> BotWorldView:
	var view: BotWorldView = _view(
		[[-7.0, 0.0, MID_TOP, TEAM], [0.0, 0.0, 5.0, ENEMY], [0.0, 9.0, MID_TOP, ENEMY], [0.0, -9.0, MID_TOP, ENEMY]],
		PackedVector2Array()
	)
	view.enemy_homes = PackedVector2Array([Vector2(6.0, 0.0)])
	return view


func test_hard_strikes_an_enemy_trunk_it_can_cover() -> void:
	var view: BotWorldView = _strike_view()
	var chains: BotChains = BotChains.build(view)
	assert_eq(chains.downstream(1), 3, "precondition: the trunk carries three circles")
	var intent: BotIntent = _choose(view)
	assert_eq(intent.kind, BotIntent.Kind.STRIKE)
	assert_eq(intent.focus_circle, 1)
	assert_eq(intent.target, Vector2(0.0, 0.0))
	assert_eq(intent.weights, _tuning.weights_strike)


func test_normal_tier_never_strikes() -> void:
	var normal_mask: int = 255 & ~(1 << int(BotIntent.Kind.STRIKE))
	assert_ne(_choose(_strike_view(), _profile(normal_mask, 0.0)).kind, BotIntent.Kind.STRIKE)


func test_strike_ignores_a_trunk_out_of_reach() -> void:
	var view: BotWorldView = _strike_view()
	view.cx[0] = -20.0
	view.own_home = Vector2(-26.0, 0.0)
	view.team_homes = PackedVector2Array([view.own_home])
	assert_ne(_choose(view).kind, BotIntent.Kind.STRIKE)


# --- ANCHOR ------------------------------------------------------------------

func test_contested_low_tip_anchors() -> void:
	_tuning.finish_gap_m = 0.5
	var view: BotWorldView = _view([[-6.0, 0.0, LOW_TOP, TEAM], [6.0, 0.0, MID_TOP, ENEMY]])
	var intent: BotIntent = _choose(view)
	assert_eq(intent.kind, BotIntent.Kind.ANCHOR)
	assert_eq(intent.target, Vector2(-6.0, 0.0), "the tip circle")
	assert_eq(intent.weights, _tuning.weights_anchor)


func test_uncontested_tip_keeps_racing() -> void:
	_tuning.finish_gap_m = 0.5
	assert_eq(_choose(_view([[-6.0, 0.0, LOW_TOP, TEAM]])).kind, BotIntent.Kind.RACE)


func test_tall_tip_is_not_anchored() -> void:
	_tuning.finish_gap_m = 0.5
	var view: BotWorldView = _view([[-6.0, 0.0, TALL_TOP, TEAM], [6.0, 0.0, MID_TOP, ENEMY]])
	assert_ne(_choose(view).kind, BotIntent.Kind.ANCHOR)


func test_rhythm_anchors_every_nth_own_circle_even_for_easy() -> void:
	_tuning.finish_gap_m = 0.5
	_tuning.anchor_rhythm = 4
	var circles: Array = [
		[-30.0, 0.0, MID_TOP, TEAM], [-26.0, 0.0, MID_TOP, TEAM],
		[-22.0, 0.0, MID_TOP, TEAM], [-18.0, 0.0, MID_TOP, TEAM],
	]
	# Easy: RACE | ANCHOR | FINISH (no DEFEND bit, so no contest rule).
	var easy_mask: int = 199
	assert_eq(_choose(_view(circles), _profile(easy_mask, 0.0)).kind, BotIntent.Kind.ANCHOR)
	circles.pop_back()
	assert_eq(_choose(_view(circles), _profile(easy_mask, 0.0)).kind, BotIntent.Kind.RACE)


func test_easy_does_not_anchor_on_contest() -> void:
	_tuning.finish_gap_m = 0.5
	var view: BotWorldView = _view([[-6.0, 0.0, LOW_TOP, TEAM], [6.0, 0.0, MID_TOP, ENEMY]])
	assert_eq(_choose(view, _profile(199, 0.0)).kind, BotIntent.Kind.RACE)


# --- Elimination -------------------------------------------------------------

func _ring_view(seat: int) -> BotWorldView:
	var view: BotWorldView = BotWorldView.new()
	view.team_id = seat
	view.slot_id = seat
	view.mode = MatchConfig.GameMode.ELIMINATION
	view.field_radius = MAP_RADIUS
	for other: int in range(RING_SEATS):
		var home: Vector2 = Vector2.from_angle(TAU * float(other) / float(RING_SEATS)) * RING_RADIUS
		if other == seat:
			view.own_home = home
			view.has_home = true
			view.team_homes = PackedVector2Array([home])
		else:
			view.enemy_homes.append(home)
			view.enemy_home_teams.append(other)
	return view


func test_eight_equidistant_seats_pick_eight_distinct_targets() -> void:
	var targets: Dictionary = {}
	for seat: int in range(RING_SEATS):
		var view: BotWorldView = _ring_view(seat)
		var intent: BotIntent = _choose(view)
		assert_eq(intent.kind, BotIntent.Kind.SIEGE, "seat %d sieges" % seat)
		assert_lt(intent.target.distance_to(view.own_home), RING_RADIUS, "seat %d picks a near neighbour" % seat)
		targets[intent.target.snapped(Vector2(0.01, 0.01))] = seat
	assert_eq(targets.size(), RING_SEATS, "no two seats pile on one home")


func test_tie_break_spread_is_hard_only() -> void:
	var view: BotWorldView = _ring_view(0)
	view.own_home = Vector2(-10.0, 0.0)
	view.enemy_homes = PackedVector2Array([Vector2(0.0, 10.0), Vector2(0.0, -10.0)])
	view.enemy_home_teams = PackedInt32Array([1, 2])
	view.team_homes = PackedVector2Array([view.own_home])
	assert_eq(_choose(view, _profile(255, 3.0)).target, Vector2(0.0, -10.0), "Hard: the clockwise neighbour")
	assert_eq(_choose(view, _profile(223, 0.0)).target, Vector2(0.0, 10.0), "Normal: first of the tie")


func test_elimination_with_the_target_within_finish_range_finishes() -> void:
	var view: BotWorldView = _ring_view(0)
	view.enemy_homes = PackedVector2Array([view.own_home + Vector2(8.0, 0.0)])
	view.enemy_home_teams = PackedInt32Array([1])
	assert_eq(_choose(view).kind, BotIntent.Kind.FINISH)


func test_elimination_without_living_enemies_does_not_crash() -> void:
	var view: BotWorldView = _ring_view(0)
	view.enemy_homes = PackedVector2Array()
	view.enemy_home_teams = PackedInt32Array()
	assert_eq(_choose(view).kind, BotIntent.Kind.SIEGE)


# --- other modes ---------------------------------------------------------------

func test_domination_plays_area_towards_the_leader() -> void:
	var view: BotWorldView = _view([[-20.0, 0.0, MID_TOP, TEAM]], PackedVector2Array())
	view.mode = MatchConfig.GameMode.DOMINATION
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = MatchConfig.GameMode.DOMINATION
	goal.own_team_leads = false
	goal.leader_points = PackedVector2Array([Vector2(30.0, 5.0), Vector2(10.0, 5.0)])
	view.mode_goal = goal
	var intent: BotIntent = _choose(view)
	assert_eq(intent.kind, BotIntent.Kind.AREA)
	assert_eq(intent.target, Vector2(10.0, 5.0), "the leader point nearest to home")
	goal.own_team_leads = true
	assert_eq(_choose(view).target, Vector2.ZERO, "leading: grow towards the centre")


func test_reach_the_sky_anchors_on_the_own_tower() -> void:
	var view: BotWorldView = _view([[-20.0, 0.0, MID_TOP, TEAM]], PackedVector2Array())
	view.mode = MatchConfig.GameMode.REACH_THE_SKY
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = MatchConfig.GameMode.REACH_THE_SKY
	goal.has_tower = true
	goal.tower_origin = Vector2(-18.0, 3.0)
	view.mode_goal = goal
	var intent: BotIntent = _choose(view)
	assert_eq(intent.kind, BotIntent.Kind.ANCHOR)
	assert_eq(intent.target, Vector2(-18.0, 3.0))


func test_capture_the_flag_races_to_unheld_beacons_and_holds_when_all_are_own() -> void:
	var view: BotWorldView = _view([[-20.0, 0.0, MID_TOP, TEAM]], PackedVector2Array())
	view.mode = MatchConfig.GameMode.CAPTURE_THE_FLAG
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = MatchConfig.GameMode.CAPTURE_THE_FLAG
	goal.beacon_positions = PackedVector2Array([Vector2(-14.0, 0.0), Vector2(10.0, 0.0)])
	goal.beacon_held_by_own = [true, false]
	view.mode_goal = goal
	var race: BotIntent = _choose(view)
	assert_eq(race.kind, BotIntent.Kind.RACE)
	assert_eq(race.target, Vector2(10.0, 0.0))
	goal.beacon_held_by_own = [true, true]
	assert_eq(_choose(view).kind, BotIntent.Kind.HOLD)


func test_multi_goal_classic_races_to_the_named_goal() -> void:
	var goals: PackedVector2Array = PackedVector2Array([Vector2(0.0, 20.0), Vector2(0.0, -20.0)])
	var view: BotWorldView = _view([[-30.0, 0.0, MID_TOP, TEAM]], goals)
	var context: BotModeGoal = BotModeGoal.new()
	context.goal_positions = goals
	context.target_goal_index = 1
	view.mode_goal = context
	assert_eq(_choose(view).target, goals[1], "the mode context's target goal")
	context.target_goal_index = -1
	assert_eq(_choose(view).target, goals[0], "else the smallest gap (ties to the first)")


# --- stickiness ----------------------------------------------------------------

## A contested low tip that stays contested whatever is placed: the anchor condition holds every piece.
func _sequence_view(own_extra: int) -> BotWorldView:
	var circles: Array = [[-6.0, 0.0, LOW_TOP, TEAM], [6.0, 0.0, MID_TOP, ENEMY]]
	for i: int in range(own_extra):
		circles.append([-6.0, 0.5 * float(i + 1), LOW_TOP, TEAM])
	return _view(circles)


func test_anchor_run_is_held_then_released_without_flip_flop() -> void:
	_tuning.finish_gap_m = 0.5
	_tuning.anchor_rhythm = 0
	_tuning.intent_min_hold_pieces = 3
	var memory: Dictionary = {}
	var kinds: Array[int] = []
	for piece: int in range(8):
		kinds.append(int(_choose_with(_sequence_view(piece), memory).kind))
	var flips: int = 0
	for i: int in range(1, kinds.size()):
		if kinds[i] != kinds[i - 1]:
			flips += 1
	assert_eq(flips, 0, "a persistently contested tip keeps one intent: %s" % [kinds])


func test_a_non_contested_piece_does_not_cancel_a_young_anchor() -> void:
	_tuning.finish_gap_m = 0.5
	_tuning.anchor_rhythm = 0
	_tuning.intent_min_hold_pieces = 3
	var memory: Dictionary = {}
	assert_eq(_choose_with(_sequence_view(0), memory).kind, BotIntent.Kind.ANCHOR)
	# Contest gone (enemy removed), one placement later: still held.
	var calm: BotWorldView = _view([[-6.0, 0.0, LOW_TOP, TEAM], [-6.0, 0.5, LOW_TOP, TEAM]])
	assert_eq(_choose_with(calm, memory).kind, BotIntent.Kind.ANCHOR, "held for the minimum pieces")
	var calmer: BotWorldView = _view([[-6.0, 0.0, LOW_TOP, TEAM], [-6.0, 0.5, LOW_TOP, TEAM], [-6.0, 1.0, LOW_TOP, TEAM]])
	assert_eq(_choose_with(calmer, memory).kind, BotIntent.Kind.ANCHOR)
	var calmest: BotWorldView = _view([
		[-6.0, 0.0, LOW_TOP, TEAM], [-6.0, 0.5, LOW_TOP, TEAM], [-6.0, 1.0, LOW_TOP, TEAM], [-6.0, 1.5, LOW_TOP, TEAM]
	])
	assert_eq(_choose_with(calmest, memory).kind, BotIntent.Kind.RACE, "released after the minimum")


func test_repeated_think_without_a_placement_ages_nothing() -> void:
	_tuning.finish_gap_m = 0.5
	_tuning.anchor_rhythm = 0
	var memory: Dictionary = {}
	var view: BotWorldView = _sequence_view(0)
	for _wait_round: int in range(10):
		_choose_with(view, memory)
	assert_eq(int(memory["age"]), 0)


func test_defend_preempts_a_held_anchor() -> void:
	_tuning.finish_gap_m = 0.5
	_tuning.anchor_rhythm = 0
	var memory: Dictionary = {}
	assert_eq(_choose_with(_sequence_view(0), memory).kind, BotIntent.Kind.ANCHOR)
	var circles: Array = _own_chain()
	circles.append([4.0, 0.0, TALL_TOP, ENEMY])
	assert_eq(_choose_with(_view(circles), memory).kind, BotIntent.Kind.DEFEND)


func _choose_with(view: BotWorldView, memory: Dictionary) -> BotIntent:
	return BotStrategy.choose(view, BotChains.build(view), _profile(), _tuning, memory)
