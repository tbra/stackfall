extends "res://tests/unit/match/match_world_test.gd"
## Classic multi-goal bot context in sudden death (spec 1.9: a latched flag stays with its last
## claimer): a goal latched to the bot's own team reads as held for it even after the territory has
## left the goal, a goal latched to another team does not, and outside sudden death nothing latches.
## Driven through Match.bot_mode_goal(), the call the bots themselves make.

const TUNING: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
const NO_TEAM: int = -1
const GOALS: int = 2
## Painted circles are smaller than a home so a goal sits outside the home territory and only a
## latch can make it read as held.
const PAINT_RADIUS_FRACTION: float = 0.4
const STEP: float = 1.0 / 20.0
## Longer than the match timer, so one frame crosses into sudden death.
const PAST_MATCH_TIMER_S: float = 120.0


func _start(sudden_death: bool) -> void:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = 2
	config.team_mode = MatchConfig.TeamMode.OFF
	config.game_mode = MatchConfig.GameMode.CLASSIC
	config.hole_mode = MatchConfig.HoleMode.TEMPORARY
	config.goal_flag_count = GOALS
	config.rng_seed = 4242
	config.sudden_death = sudden_death
	config.match_timer_minutes = 1 if sudden_death else 0
	config.round_timer_minutes = 0
	Match.start_match(config)
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the match is running")
	if sudden_death:
		Match._process(PAST_MATCH_TIMER_S)
		assert_eq(Match.state(), Match.State.SUDDEN_DEATH, "fixture: sudden death began")


func _goals() -> PackedVector2Array:
	return PlayerSlot.goal_positions_for(GOALS, Match.config.map_def())


## The goal index nearest to `slot_id`'s home.
func _near_goal(slot_id: int) -> int:
	var home: Vector2 = Match.slot(slot_id).home_position
	var goals: PackedVector2Array = _goals()
	return 0 if home.distance_squared_to(goals[0]) <= home.distance_squared_to(goals[1]) else 1


func _paint(circles: Array[InfluenceCircle]) -> void:
	var raster: TerritoryRaster = Match.raster()
	raster.fill_ownership(circles, TerritorySolver.new(TUNING).solve(circles), false)
	raster.adopt_fill(raster, STEP, false, false)


func _home_circle(slot_id: int) -> InfluenceCircle:
	var seat: PlayerSlot = Match.slot(slot_id)
	return _circle(seat.home_position, slot_id)


func _circle(at: Vector2, slot_id: int) -> InfluenceCircle:
	return InfluenceCircle.new(at, TUNING.home_radius * PAINT_RADIUS_FRACTION, Match.slot(slot_id).team_id, slot_id, true, -1)


## A circle of `slot_id`'s team centred on goal `goal`, as a claim on that flag.
func _goal_circle(slot_id: int, goal: int) -> InfluenceCircle:
	return _circle(_goals()[goal], slot_id)


func _homes_only() -> Array[InfluenceCircle]:
	return [_home_circle(0), _home_circle(1)] as Array[InfluenceCircle]


## Paints `circles` and runs one real objective update on the board.
func _settle(circles: Array[InfluenceCircle]) -> void:
	_paint(circles)
	Match._territory.objective().update(Match.raster(), STEP)


func _latched(goal: int) -> int:
	return (Match._territory.objective() as ClassicObjective).latched_team(goal)


func test_fixture_homes_do_not_cover_a_goal_so_only_the_latch_can_hold_it() -> void:
	_start(true)
	_paint(_homes_only())
	var goals: PackedVector2Array = _goals()
	for slot_id: int in range(2):
		var group: int = Match.raster().group_at_point(Match.slot(slot_id).home_position)
		for goal: int in range(GOALS):
			assert_ne(Match.raster().group_at_point(goals[goal]), group, "goal %d is outside home %d's territory" % [goal, slot_id])


func test_a_goal_latched_to_the_bots_own_team_reads_as_held_after_the_territory_leaves() -> void:
	_start(true)
	var bot: int = 0
	var near: int = _near_goal(bot)
	var far: int = 1 - near
	_settle([_home_circle(0), _home_circle(1), _goal_circle(bot, near)] as Array[InfluenceCircle])
	assert_eq(_latched(near), Match.team_of(bot), "fixture: the bot's team latched its nearest goal")

	_settle(_homes_only())
	assert_eq(_latched(near), Match.team_of(bot), "the latch outlives the territory")
	var goal: BotModeGoal = Match.bot_mode_goal(bot)
	assert_true(goal.is_multi_goal())
	assert_eq(goal.target_goal_index, far, "the bot treats its latched goal as held and moves on")


func test_a_goal_latched_to_another_team_is_still_a_target() -> void:
	_start(true)
	var bot: int = 0
	var rival: int = 1
	var near: int = _near_goal(bot)
	_settle([_home_circle(0), _home_circle(1), _goal_circle(rival, near)] as Array[InfluenceCircle])
	assert_eq(_latched(near), Match.team_of(rival), "fixture: the rival latched the bot's nearest goal")

	_settle(_homes_only())
	var goal: BotModeGoal = Match.bot_mode_goal(bot)
	assert_eq(goal.target_goal_index, near, "a rival's latch is not held for the bot, the nearest goal stays its target")


func test_outside_sudden_death_nothing_is_latched_and_no_goal_reads_as_held() -> void:
	_start(false)
	var bot: int = 0
	var near: int = _near_goal(bot)
	_settle([_home_circle(0), _home_circle(1), _goal_circle(bot, near)] as Array[InfluenceCircle])
	_settle(_homes_only())
	for goal_index: int in range(GOALS):
		assert_eq(_latched(goal_index), NO_TEAM, "no latch before sudden death")
	var goal: BotModeGoal = Match.bot_mode_goal(bot)
	assert_eq(goal.target_goal_index, near, "territory left the goal and nothing keeps it, so it is a target again")
