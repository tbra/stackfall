extends GutTest
## core/ai/BotStrategy.gd (Bot V2 P4): the intent rule table (HOLD, DEFEND,
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
## Top heights (cone radius = 1.5 + 0.84 * top at the shipped 40 degree half-angle).
const LOW_TOP: float = 1.0
const MID_TOP: float = 3.0
const TALL_TOP: float = 14.0

var _territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
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


# --- FINISH ------------------------------------------------------------------


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


# --- ANCHOR ------------------------------------------------------------------


func test_contested_low_tip_anchors() -> void:
	_tuning.finish_gap_m = 0.5
	var view: BotWorldView = _view([[-6.0, 0.0, LOW_TOP, TEAM], [6.0, 0.0, MID_TOP, ENEMY]])
	var intent: BotIntent = _choose(view)
	assert_eq(intent.kind, BotIntent.Kind.ANCHOR)
	assert_eq(intent.target, Vector2(-6.0, 0.0), "the tip circle")
	assert_eq(intent.weights, _tuning.weights_anchor)


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


# --- Elimination -------------------------------------------------------------


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
