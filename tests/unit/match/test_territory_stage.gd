extends "res://tests/unit/match/match_world_test.gd"
## TerritoryStage: the helpers other territory tests use to stage a hold or a home loss through
## public play. Each helper is proven through public reads only (Match state, raster, Events).

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")

var _saved_hold: float


func before_each() -> void:
	super.before_each()
	_saved_hold = _tuning.capture_hold


func after_each() -> void:
	_tuning.capture_hold = _saved_hold
	super.after_each()


func _start(players: int, mode: MatchConfig.GameMode, teams: MatchConfig.TeamMode = MatchConfig.TeamMode.OFF,
		holes: MatchConfig.HoleMode = MatchConfig.HoleMode.OFF) -> void:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = players
	config.team_mode = teams
	config.game_mode = mode
	config.hole_mode = holes
	config.sudden_death = false
	config.round_timer_minutes = 0
	config.block_timer = 6.0
	config.rng_seed = 4242
	Match.start_match(config)
	_run_countdown()


func test_tick_advances_the_match_clock_through_process() -> void:
	_start(2, MatchConfig.GameMode.CLASSIC)
	watch_signals(Events)
	TerritoryStage.tick(0.5)
	assert_gt(get_signal_emit_count(Events, "goal_capture_progress"), 0, "match time passed: the territory step ran")


func test_hold_goals_gives_one_team_every_goal_cell() -> void:
	_start(2, MatchConfig.GameMode.CLASSIC)
	_tuning.capture_hold = 30.0
	await TerritoryStage.hold_goals(0, _blocks_root)
	var raster: TerritoryRaster = Match.raster()
	for goal: Vector2 in Match.circle_render_arrays()["goal_positions"]:
		var cell: Vector2i = Match.cell_grid().world_to_cell(goal)
		assert_eq(raster.team_at(cell.x, cell.y), 0, "team 0 owns the goal cell")
	assert_eq(Match.state(), Match.State.PLAYING, "a hold in progress has not won yet")


func test_hold_goals_for_latches_the_win_after_capture_hold() -> void:
	_start(2, MatchConfig.GameMode.CLASSIC)
	_tuning.capture_hold = 2.0
	await TerritoryStage.hold_goals_for(1, _blocks_root)
	assert_eq(Match.state(), Match.State.END)
	assert_eq(Match.winner_team(), 1)


func test_hold_goals_does_not_win_before_the_hold_elapses() -> void:
	_start(2, MatchConfig.GameMode.CLASSIC)
	_tuning.capture_hold = 20.0
	await TerritoryStage.hold_goals(0, _blocks_root)
	TerritoryStage.tick(5.0)
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_eq(Match.winner_team(), -1)


# --- lose_homes: the R1 spike -------------------------------------------------------

func test_lose_homes_eliminates_a_slot_in_classic() -> void:
	_start(3, MatchConfig.GameMode.CLASSIC)
	watch_signals(Events)
	await TerritoryStage.lose_homes([1] as Array[int], _blocks_root)
	assert_false(Match.slot(1).home_flag_alive, "the covered home is out")
	assert_true(Match.slot(0).home_flag_alive)
	assert_true(Match.slot(2).home_flag_alive)
	assert_signal_emitted(Events, "player_eliminated")
	assert_eq(Match.state(), Match.State.PLAYING, "two players still stand")


func test_lose_homes_of_the_last_rival_ends_the_match() -> void:
	_start(2, MatchConfig.GameMode.CLASSIC)
	watch_signals(Events)
	await TerritoryStage.lose_homes([0] as Array[int], _blocks_root)
	assert_false(Match.slot(0).home_flag_alive)
	assert_eq(Match.state(), Match.State.END)
	assert_signal_emitted_with_parameters(Events, "match_won", [1])


func test_lose_homes_in_elimination_needs_the_claim_hold() -> void:
	_start(3, MatchConfig.GameMode.ELIMINATION)
	await TerritoryStage.lose_homes([2] as Array[int], _blocks_root)
	assert_false(Match.slot(2).home_flag_alive, "the claim hold ran and knocked the home out")
	assert_eq(Match.state(), Match.State.PLAYING)


func test_lose_homes_in_elimination_ends_when_one_team_remains() -> void:
	_start(2, MatchConfig.GameMode.ELIMINATION)
	await TerritoryStage.lose_homes([1] as Array[int], _blocks_root)
	assert_eq(Match.state(), Match.State.END)
	assert_eq(Match.winner_team(), 0)


func test_lose_homes_takes_several_slots_and_teams_survive_by_a_teammate() -> void:
	_start(4, MatchConfig.GameMode.ELIMINATION, MatchConfig.TeamMode.TEAMS_2)
	await TerritoryStage.lose_homes([0] as Array[int], _blocks_root)
	assert_eq(Match.state(), Match.State.PLAYING, "slot 2 keeps team 0 up")
	await TerritoryStage.lose_homes([2] as Array[int], _blocks_root)
	assert_eq(Match.state(), Match.State.END)
	assert_eq(Match.winner_team(), 1)


func test_lose_homes_in_overlap_mode_opens_a_hole_under_the_home() -> void:
	_start(3, MatchConfig.GameMode.CLASSIC, MatchConfig.TeamMode.OFF, MatchConfig.HoleMode.TEMPORARY)
	await TerritoryStage.lose_homes([1] as Array[int], _blocks_root)
	assert_false(Match.slot(1).home_flag_alive)
	assert_true(Match.slot(0).home_flag_alive)
