extends GutTest
## Bontago-6fc.1 (one lobby timer control per mode) and Bontago-6fc.2 (no goal
## flags in Reach the Sky / Elimination; the sandbox never wins on a goal hold).
## The bot-targeting check lives in test_bot_controller.gd (its fake match).

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(mode: int, sandbox: bool = false) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = true
	config.block_timer = 6.0
	config.rng_seed = 99
	config.sudden_death = false
	config.game_mode = mode as MatchConfig.GameMode
	config.sandbox = sandbox
	return config


func _make_lobby(is_host: bool) -> Lobby:
	var lobby: Lobby = autofree((load("res://ui/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = is_host
	fake.is_offline_value = is_host
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func _pick_mode(lobby: Lobby, mode: int) -> void:
	var option: OptionButton = lobby.get_node("%GameModeOption")
	option.selected = mode
	option.item_selected.emit(mode)


# --- 6fc.1 -------------------------------------------------------------------

func test_timer_min_and_default_per_mode() -> void:
	assert_eq(MatchConfig.timer_min_minutes(MatchConfig.GameMode.CLASSIC), 0)
	assert_eq(MatchConfig.timer_min_minutes(MatchConfig.GameMode.CAPTURE_THE_FLAG), 1)
	assert_eq(MatchConfig.timer_min_minutes(MatchConfig.GameMode.REACH_THE_SKY), 1)
	assert_eq(MatchConfig.timer_min_minutes(MatchConfig.GameMode.ELIMINATION), 0)
	assert_eq(MatchConfig.timer_default_minutes(MatchConfig.GameMode.CLASSIC), 0)
	assert_eq(MatchConfig.timer_default_minutes(MatchConfig.GameMode.ELIMINATION), 0)
	assert_eq(MatchConfig.timer_default_minutes(MatchConfig.GameMode.CAPTURE_THE_FLAG), MatchConfig.ROUND_TIMER_DEFAULT_MINUTES)
	assert_eq(MatchConfig.timer_default_minutes(MatchConfig.GameMode.REACH_THE_SKY), MatchConfig.ROUND_TIMER_DEFAULT_MINUTES)


func test_one_timer_column_visible_per_mode() -> void:
	var lobby: Lobby = _make_lobby(true)
	var match_col: Control = lobby.get_node("%MatchTimerCol")
	var round_col: Control = lobby.get_node("%RoundTimerCol")
	var sudden_col: Control = lobby.get_node("%SuddenDeathCol")
	assert_true(match_col.visible and sudden_col.visible and not round_col.visible, "classic")
	for mode: int in [MatchConfig.GameMode.CAPTURE_THE_FLAG, MatchConfig.GameMode.ELIMINATION, MatchConfig.GameMode.REACH_THE_SKY]:
		_pick_mode(lobby, mode)
		assert_true(round_col.visible and not match_col.visible and not sudden_col.visible, "mode %d" % mode)
	_pick_mode(lobby, MatchConfig.GameMode.CLASSIC)
	assert_true(match_col.visible and not round_col.visible)


func test_round_spin_minimum_and_defaults_follow_the_mode() -> void:
	var lobby: Lobby = _make_lobby(true)
	var spin: SpinBox = lobby.get_node("%RoundTimerSpin")
	_pick_mode(lobby, MatchConfig.GameMode.ELIMINATION)
	assert_eq(spin.min_value, 0.0)
	assert_eq(spin.value, 0.0, "Elimination starts with no limit")
	assert_eq((lobby.get_node("%RoundTimerHint") as Label).text, "No limit")
	_pick_mode(lobby, MatchConfig.GameMode.CAPTURE_THE_FLAG)
	assert_eq(spin.min_value, 1.0)
	assert_eq(spin.value, float(MatchConfig.ROUND_TIMER_DEFAULT_MINUTES))
	spin.value = 15
	_pick_mode(lobby, MatchConfig.GameMode.REACH_THE_SKY)
	assert_eq(spin.value, 15.0, "CTF and Sky share a timer meaning, so the length is kept")
	assert_eq((lobby.get_node("%RoundTimerCaption") as Label).text.find("0=off"), -1)


func test_timer_control_writes_the_matching_config_field() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = lobby.net_provider as FakeNet
	(lobby.get_node("%MatchTimerSpin") as SpinBox).value = 12
	assert_eq(fake.set_lobby_data_calls[-1]["match_timer_minutes"], 12)
	_pick_mode(lobby, MatchConfig.GameMode.ELIMINATION)
	assert_eq(fake.set_lobby_data_calls[-1]["round_timer_minutes"], 0)
	(lobby.get_node("%RoundTimerSpin") as SpinBox).value = 7
	assert_eq(fake.set_lobby_data_calls[-1]["round_timer_minutes"], 7)
	assert_eq(fake.set_lobby_data_calls[-1]["match_timer_minutes"], 12, "classic value kept")


func test_elimination_no_limit_round_trips_to_a_client() -> void:
	var host: Lobby = _make_lobby(true)
	_pick_mode(host, MatchConfig.GameMode.ELIMINATION)
	var published: Dictionary = (host.net_provider as FakeNet).set_lobby_data_calls[-1]
	var client: Lobby = _make_lobby(false)
	client._apply_data(published)
	assert_eq((client.get_node("%RoundTimerSpin") as SpinBox).value, 0.0)
	assert_eq((client.get_node("%GameModeOption") as OptionButton).selected, MatchConfig.GameMode.ELIMINATION)
	assert_true((client.get_node("%RoundTimerCol") as Control).visible)
	var ctf: Dictionary = published.duplicate()
	ctf["game_mode"] = MatchConfig.GameMode.CAPTURE_THE_FLAG
	ctf["round_timer_minutes"] = 20
	client._apply_data(ctf)
	assert_eq((client.get_node("%RoundTimerSpin") as SpinBox).value, 20.0)
	assert_eq((client.get_node("%RoundTimerSpin") as SpinBox).min_value, 1.0)


func test_focus_loops_skip_the_hidden_timer_column() -> void:
	var lobby: Lobby = _make_lobby(true)
	var match_spin: SpinBox = lobby.get_node("%MatchTimerSpin")
	var round_spin: SpinBox = lobby.get_node("%RoundTimerSpin")
	var sudden: Control = lobby.get_node("%SuddenDeathCheck")
	_pick_mode(lobby, MatchConfig.GameMode.CAPTURE_THE_FLAG)
	var shown: Array[Control] = lobby._visible_chain(lobby._main_chain)
	var popup_shown: Array[Control] = lobby._visible_chain(lobby._popup_chain)
	assert_true(shown.has(round_spin))
	assert_false(shown.has(match_spin))
	assert_false(popup_shown.has(sudden))
	_assert_closed_loop(shown)
	_assert_closed_loop(popup_shown)
	_pick_mode(lobby, MatchConfig.GameMode.CLASSIC)
	shown = lobby._visible_chain(lobby._main_chain)
	popup_shown = lobby._visible_chain(lobby._popup_chain)
	assert_true(shown.has(match_spin))
	assert_true(popup_shown.has(sudden))
	assert_false(shown.has(round_spin))
	_assert_closed_loop(shown)
	_assert_closed_loop(popup_shown)
	# Focus order follows the visual order: mode, then the timer, then the map.
	assert_lt(shown.find(lobby.get_node("%GameModeOption")), shown.find(match_spin))
	assert_lt(shown.find(match_spin), shown.find(lobby.get_node("%MapComboOption")))
	assert_lt(shown.find(lobby.get_node("%AiCountSpin")), shown.find(lobby.get_node("%AiDifficultyOption")))


func _assert_closed_loop(shown: Array[Control]) -> void:
	for control: Control in shown:
		var up: Control = control.get_node_or_null(control.focus_neighbor_top) as Control
		var down: Control = control.get_node_or_null(control.focus_neighbor_bottom) as Control
		assert_true(shown.has(up) and shown.has(down), "no orphaned neighbour on %s" % control.name)


# --- 6fc.2 -------------------------------------------------------------------

func test_objective_goal_flag_hook_per_mode() -> void:
	var empty: PackedVector2Array = PackedVector2Array()
	var teams: PackedInt32Array = PackedInt32Array([0, 1])
	for mode: int in [MatchConfig.GameMode.CLASSIC, MatchConfig.GameMode.CAPTURE_THE_FLAG]:
		assert_true(ModeObjective.create(mode, empty, 3.0, 2, 1.0, 1.0, teams).uses_goal_flags(), "mode %d" % mode)
	for mode: int in [MatchConfig.GameMode.ELIMINATION, MatchConfig.GameMode.REACH_THE_SKY]:
		assert_false(ModeObjective.create(mode, empty, 3.0, 2, 1.0, 1.0, teams).uses_goal_flags(), "mode %d" % mode)


func test_goal_flag_nodes_and_zones_only_in_goal_modes() -> void:
	for mode: int in [MatchConfig.GameMode.CLASSIC, MatchConfig.GameMode.CAPTURE_THE_FLAG]:
		var config: MatchConfig = _config(mode)
		Match.start_match(config)
		_field.place_flags(config.player_count, config.player_colors, config.effective_goal_flag_count())
		assert_eq(_field.goal_flags().size(), config.goal_flag_count, "flags in mode %d" % mode)
		assert_false(Match._territory._goal_positions.is_empty())
		Match.abort_match()
	for mode: int in [MatchConfig.GameMode.ELIMINATION, MatchConfig.GameMode.REACH_THE_SKY]:
		var config: MatchConfig = _config(mode)
		Match.start_match(config)
		_field.place_flags(config.player_count, config.player_colors, config.effective_goal_flag_count())
		assert_true(_field.goal_flags().is_empty(), "no goal flag in mode %d" % mode)
		assert_eq(_field.home_flags().size(), 2, "home flags remain")
		assert_true(Match._territory._goal_positions.is_empty(), "no goal circles/zones")
		Match.abort_match()


func test_sandbox_keeps_its_goal_flag_in_any_mode() -> void:
	var config: MatchConfig = _config(MatchConfig.GameMode.REACH_THE_SKY, true)
	assert_eq(config.effective_goal_flag_count(), config.goal_flag_count)


func test_sandbox_never_wins_on_the_all_goal_hold() -> void:
	Match.start_match(_config(MatchConfig.GameMode.CLASSIC, true))
	for _i: int in range(int(Match.COUNTDOWN_SECONDS * 60.0) + 10):
		Match._process(1.0 / 60.0)
	var checker: WinChecker = (Match._territory._objective as ClassicObjective).checker()
	checker._winner = 0
	Match._territory._finish_objective_step()
	assert_ne(Match.state(), Match.State.END, "a sandbox match does not end on the goal hold")


func test_non_sandbox_classic_still_wins_on_the_hold() -> void:
	Match.start_match(_config(MatchConfig.GameMode.CLASSIC, false))
	for _i: int in range(int(Match.COUNTDOWN_SECONDS * 60.0) + 10):
		Match._process(1.0 / 60.0)
	var checker: WinChecker = (Match._territory._objective as ClassicObjective).checker()
	checker._winner = 0
	Match._territory._finish_objective_step()
	assert_eq(Match.state(), Match.State.END)


func test_mid_join_toggle_sits_after_turn_based_in_the_popup_focus_loop() -> void:
	var lobby: Lobby = _make_lobby(true)
	var popup_shown: Array[Control] = lobby._visible_chain(lobby._popup_chain)
	var turn: int = popup_shown.find(lobby.get_node("%TurnBasedCheck"))
	var mid: int = popup_shown.find(lobby.get_node("%MidJoinCheck"))
	assert_gt(turn, -1)
	assert_eq(mid, turn + 1)
	# QoL Q1 (Bontago-1pi.18.5) appends the Experiments toggles after Mid-join;
	# Done/Close stays the last stop of the popup loop.
	var close: int = popup_shown.find(lobby.get_node("%AdvancedPopupClose"))
	assert_gt(close, mid)
	assert_eq(close, popup_shown.size() - 1)


# --- Bontago-1pi.25.1 Domination --------------------------------------------

func test_lobby_forces_a_timer_for_domination() -> void:
	var lobby: Lobby = _make_lobby(true)
	var spin: SpinBox = lobby.get_node("%RoundTimerSpin")
	_pick_mode(lobby, MatchConfig.GameMode.ELIMINATION)
	assert_eq(spin.value, 0.0)
	_pick_mode(lobby, MatchConfig.GameMode.DOMINATION)
	assert_true((lobby.get_node("%RoundTimerCol") as Control).visible)
	assert_eq(spin.min_value, float(MatchConfig.ROUND_TIMER_MIN_MINUTES), "cannot be set to off")
	assert_eq(spin.value, float(MatchConfig.DOMINATION_ROUND_MINUTES_DEFAULT))
	spin.value = 0
	assert_gte(spin.value, 1.0)
	var fake: FakeNet = lobby.net_provider as FakeNet
	assert_gte(int(fake.set_lobby_data_calls[-1]["round_timer_minutes"]), 1)
	assert_true((lobby.get_node("%RoundTimerHint") as Label).text.find("required") >= 0)
	assert_false((lobby.get_node("%GameModeOption") as OptionButton).tooltip_text.is_empty(), "mode description")


func test_bot_goal_is_a_territory_objective_in_domination() -> void:
	Match.start_match(_config(MatchConfig.GameMode.DOMINATION))
	var goal: BotModeGoal = Match.bot_mode_goal(0)
	assert_not_null(goal)
	assert_eq(goal.mode, MatchConfig.GameMode.DOMINATION)
	assert_true(goal.own_team_leads, "no territory yet: nobody to contest")
