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
	var option: CycleSelector = lobby.get_node("%GameModeOption")
	option.selected = mode
	option.item_selected.emit(mode)


# --- 6fc.1 -------------------------------------------------------------------

func test_timer_min_and_default_per_mode() -> void:
	assert_eq(MatchConfig.timer_min_minutes(MatchConfig.GameMode.CLASSIC), 0)
	assert_eq(MatchConfig.timer_min_minutes(MatchConfig.GameMode.CAPTURE_THE_FLAG), MatchConfig.ROUND_TIMER_MIN_MINUTES)
	assert_eq(MatchConfig.timer_min_minutes(MatchConfig.GameMode.REACH_THE_SKY), 2)
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


func test_round_slider_minimum_and_defaults_follow_the_mode() -> void:
	var lobby: Lobby = _make_lobby(true)
	var slider: HSlider = lobby.get_node("%RoundTimerSlider")
	_pick_mode(lobby, MatchConfig.GameMode.ELIMINATION)
	assert_eq(slider.min_value, 0.0)
	assert_eq(slider.value, 0.0, "Elimination starts with its timer off")
	assert_eq((lobby.get_node("%RoundTimerValue") as Label).text, "Off", "leftmost stop reads Off")
	_pick_mode(lobby, MatchConfig.GameMode.CAPTURE_THE_FLAG)
	assert_eq(slider.min_value, 2.0)
	assert_eq(slider.max_value, 30.0)
	assert_eq(slider.value, 5.0, "owner playtest 2026-10-03: the default round is 5 minutes")
	assert_eq(slider.value, float(MatchConfig.ROUND_TIMER_DEFAULT_MINUTES))
	assert_eq((lobby.get_node("%RoundTimerValue") as Label).text, "5 min")
	slider.value = 15
	_pick_mode(lobby, MatchConfig.GameMode.REACH_THE_SKY)
	assert_eq(slider.value, 15.0, "CTF and Sky share a timer meaning, so the length is kept")
	assert_eq((lobby.get_node("%RoundTimerValue") as Label).text, "15 min")


func test_timer_control_writes_the_matching_config_field() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = lobby.net_provider as FakeNet
	(lobby.get_node("%MatchTimerSlider") as HSlider).value = 12
	assert_eq(fake.set_lobby_data_calls[-1]["match_timer_minutes"], 12)
	_pick_mode(lobby, MatchConfig.GameMode.ELIMINATION)
	assert_eq(fake.set_lobby_data_calls[-1]["round_timer_minutes"], 0)
	(lobby.get_node("%RoundTimerSlider") as HSlider).value = 7
	assert_eq(fake.set_lobby_data_calls[-1]["round_timer_minutes"], 7)
	assert_eq(fake.set_lobby_data_calls[-1]["match_timer_minutes"], 12, "classic value kept")


func test_elimination_no_limit_round_trips_to_a_client() -> void:
	var host: Lobby = _make_lobby(true)
	_pick_mode(host, MatchConfig.GameMode.ELIMINATION)
	var published: Dictionary = (host.net_provider as FakeNet).set_lobby_data_calls[-1]
	var client: Lobby = _make_lobby(false)
	client._apply_data(published)
	assert_eq((client.get_node("%RoundTimerSlider") as HSlider).value, 0.0)
	assert_eq((client.get_node("%RoundTimerValue") as Label).text, "Off")
	assert_eq((client.get_node("%GameModeOption") as CycleSelector).selected, MatchConfig.GameMode.ELIMINATION)
	assert_true((client.get_node("%RoundTimerCol") as Control).visible)
	var ctf: Dictionary = published.duplicate()
	ctf["game_mode"] = MatchConfig.GameMode.CAPTURE_THE_FLAG
	ctf["round_timer_minutes"] = 20
	client._apply_data(ctf)
	assert_eq((client.get_node("%RoundTimerSlider") as HSlider).value, 20.0)
	assert_eq((client.get_node("%RoundTimerSlider") as HSlider).min_value, 2.0)


func test_focus_loops_skip_the_hidden_timer_column() -> void:
	var lobby: Lobby = _make_lobby(true)
	var match_slider: HSlider = lobby.get_node("%MatchTimerSlider")
	var round_slider: HSlider = lobby.get_node("%RoundTimerSlider")
	var sudden: Control = lobby.get_node("%SuddenDeathCheck")
	_pick_mode(lobby, MatchConfig.GameMode.CAPTURE_THE_FLAG)
	# Bontago-1pi.53 (S1a): sudden death moved from the popup into ROUND main, so it is
	# part of the main loop only while Classic shows it (the popup has no conditional
	# column left).
	var shown: Array[Control] = lobby._visible_chain(lobby._main_chain)
	assert_true(shown.has(round_slider))
	assert_false(shown.has(match_slider))
	assert_false(shown.has(sudden))
	_assert_closed_loop(shown)
	_pick_mode(lobby, MatchConfig.GameMode.CLASSIC)
	shown = lobby._visible_chain(lobby._main_chain)
	assert_true(shown.has(match_slider))
	assert_true(shown.has(sudden))
	assert_false(shown.has(round_slider))
	_assert_closed_loop(shown)
	# Focus order follows the visual order: the game mode (GAME), then the ROUND timer,
	# then sudden death, then the GIFTS and EXPERIMENTS sections (Bontago-1pi.53 S1b: the
	# players/AI controls and the AI difficulty left the settings card).
	assert_lt(shown.find(lobby.get_node("%GameModeOption")), shown.find(match_slider))
	assert_lt(shown.find(match_slider), shown.find(sudden))
	var gifts_header: Control = (lobby.get_node("%GiftsSection") as LobbySection).advanced_button
	var experiments_header: Control = (lobby.get_node("%ExperimentsSection") as LobbySection).advanced_button
	assert_lt(shown.find(sudden), shown.find(gifts_header))
	assert_lt(shown.find(gifts_header), shown.find(experiments_header))
	assert_lt(shown.find(experiments_header), shown.find(lobby.get_node("%BackButton")))


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


func test_mid_join_toggle_sits_after_turn_based_in_the_game_advanced_focus_loop() -> void:
	# Bontago-1pi.53 (S1a/S1b): Turn-based and Mid-join moved from the popup into the GAME
	# section's Advanced block, so they are in the main loop once it is opened.
	var lobby: Lobby = _make_lobby(true)
	(lobby.get_node("%GameSection") as LobbySection).set_advanced_open(true)
	var shown: Array[Control] = lobby._visible_chain(lobby._main_chain)
	var turn: int = shown.find(lobby.get_node("%TurnBasedCheck"))
	var mid: int = shown.find(lobby.get_node("%MidJoinCheck"))
	assert_gt(turn, -1)
	assert_eq(mid, turn + 1)
	# QoL Q1 (Bontago-1pi.18.5) / S1b: the Experiments toggles (their section's Advanced block)
	# come after the GAME block and before the footer (Back) once opened.
	(lobby.get_node("%ExperimentsSection") as LobbySection).set_advanced_open(true)
	shown = lobby._visible_chain(lobby._main_chain)
	var gift_slot: int = shown.find(lobby.get_node("%QolGiftSlotCheck"))
	assert_gt(gift_slot, shown.find(lobby.get_node("%QolTimerPauseCheck")))
	assert_gt(shown.find(lobby.get_node("%QolTimerPauseCheck")), mid)
	assert_lt(gift_slot, shown.find(lobby.get_node("%BackButton")))


# --- Bontago-1pi.25.1 Domination --------------------------------------------

func test_lobby_forces_a_timer_for_domination() -> void:
	var lobby: Lobby = _make_lobby(true)
	var slider: HSlider = lobby.get_node("%RoundTimerSlider")
	_pick_mode(lobby, MatchConfig.GameMode.ELIMINATION)
	assert_eq(slider.value, 0.0)
	_pick_mode(lobby, MatchConfig.GameMode.DOMINATION)
	assert_true((lobby.get_node("%RoundTimerCol") as Control).visible)
	assert_eq(slider.min_value, float(MatchConfig.ROUND_TIMER_MIN_MINUTES), "cannot be set to off")
	assert_eq(slider.value, float(MatchConfig.DOMINATION_ROUND_MINUTES_DEFAULT))
	slider.value = 0
	assert_gte(slider.value, float(MatchConfig.ROUND_TIMER_MIN_MINUTES))
	var fake: FakeNet = lobby.net_provider as FakeNet
	assert_gte(int(fake.set_lobby_data_calls[-1]["round_timer_minutes"]), MatchConfig.ROUND_TIMER_MIN_MINUTES)
	assert_true((lobby.get_node("%RoundTimerValue") as Label).text.find("required") >= 0)
	assert_false((lobby.get_node("%GameModeOption") as CycleSelector).tooltip_text.is_empty(), "mode description")


func test_bot_goal_is_a_territory_objective_in_domination() -> void:
	Match.start_match(_config(MatchConfig.GameMode.DOMINATION))
	var goal: BotModeGoal = Match.bot_mode_goal(0)
	assert_not_null(goal)
	assert_eq(goal.mode, MatchConfig.GameMode.DOMINATION)
	assert_true(goal.own_team_leads, "no territory yet: nobody to contest")



# --- Bontago-1pi.30 round timer slider (owner playtest 2026-10-03) ------------------

func _dpad_event(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	event.pressed = true
	return event


## Feeds [param slider] a real D-pad press the way a focused control receives it: its
## gui_input signal (GUT cannot route key/pad events through the viewport to a focus
## owner here). The event is matched against the real InputMap's ui_left/ui_right.
func _dpad_step(slider: HSlider, button: JoyButton) -> void:
	var event: InputEventJoypadButton = _dpad_event(button)
	assert_true(event.is_action_pressed(&"ui_left", true) or event.is_action_pressed(&"ui_right", true),
		"fixture: the D-pad maps to ui_left/ui_right")
	slider.gui_input.emit(event)


func test_timer_defaults_are_five_minutes_and_two_to_thirty() -> void:
	assert_eq(MatchConfig.ROUND_TIMER_DEFAULT_MINUTES, 5)
	assert_eq(MatchConfig.ROUND_TIMER_MIN_MINUTES, 2)
	assert_eq(MatchConfig.ROUND_TIMER_MAX_MINUTES, 30)
	var fresh: MatchConfig = MatchConfig.new()
	assert_eq(fresh.round_timer_minutes, 5)
	assert_eq(fresh.match_timer_minutes, 0, "Classic's match timer stays Off by default")
	assert_eq(MatchConfig.timer_default_minutes(MatchConfig.GameMode.CAPTURE_THE_FLAG), 5)
	var lobby: Lobby = _make_lobby(true)
	var match_slider: HSlider = lobby.get_node("%MatchTimerSlider")
	var round_slider: HSlider = lobby.get_node("%RoundTimerSlider")
	assert_eq([match_slider.min_value, match_slider.max_value, match_slider.step], [0.0, 30.0, 1.0])
	assert_eq([round_slider.min_value, round_slider.max_value, round_slider.step], [2.0, 30.0, 1.0])
	assert_eq(match_slider.value, 0.0)
	assert_eq((lobby.get_node("%MatchTimerValue") as Label).text, "Off")
	assert_eq(round_slider.value, 5.0, "the lobby's default round length")
	assert_eq((lobby.get_node("%RoundTimerValue") as Label).text, "5 min")
	var config: MatchConfig = lobby._config_from_controls()
	assert_eq([config.match_timer_minutes, config.round_timer_minutes], [0, 5])


func test_round_slider_round_trips_through_config_serialize_and_a_client() -> void:
	var host: Lobby = _make_lobby(true)
	_pick_mode(host, MatchConfig.GameMode.CAPTURE_THE_FLAG)
	var slider: HSlider = host.get_node("%RoundTimerSlider")
	var fake: FakeNet = host.net_provider as FakeNet
	for minutes: int in [2, 17, 30]:
		slider.value = minutes
		var published: Dictionary = fake.set_lobby_data_calls[-1]
		assert_eq(published["round_timer_minutes"], minutes)
		assert_eq(MatchConfig.from_dict(published).round_timer_minutes, minutes, "serialize -> deserialize")
		var client: Lobby = _make_lobby(false)
		client._apply_data(published)
		assert_eq((client.get_node("%RoundTimerSlider") as HSlider).value, float(minutes))
		assert_eq((client.get_node("%RoundTimerValue") as Label).text, "%d min" % minutes)
	slider.value = 99
	assert_eq(slider.value, 30.0, "the slider cannot pass the maximum")
	slider.value = 0
	assert_eq(slider.value, 2.0, "CTF's slider cannot reach Off")


func test_match_timer_slider_runs_off_to_thirty_and_skips_one_minute() -> void:
	var lobby: Lobby = _make_lobby(true)
	var slider: HSlider = lobby.get_node("%MatchTimerSlider")
	var fake: FakeNet = lobby.net_provider as FakeNet
	slider.value = 30
	assert_eq(fake.set_lobby_data_calls[-1]["match_timer_minutes"], 30)
	assert_eq((lobby.get_node("%MatchTimerValue") as Label).text, "30 min")
	slider.value = 0
	assert_eq(fake.set_lobby_data_calls[-1]["match_timer_minutes"], 0)
	assert_eq((lobby.get_node("%MatchTimerValue") as Label).text, "Off")
	slider.value = 1
	assert_eq(slider.value, 2.0, "stepping up from Off lands on 2 minutes")
	assert_eq(fake.set_lobby_data_calls[-1]["match_timer_minutes"], 2)
	slider.value = 1
	assert_eq(slider.value, 0.0, "stepping down from 2 minutes lands on Off")
	assert_eq(fake.set_lobby_data_calls[-1]["match_timer_minutes"], 0)


func test_gamepad_left_right_changes_the_focused_timer_slider() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = lobby.net_provider as FakeNet
	var match_slider: HSlider = lobby.get_node("%MatchTimerSlider")
	_dpad_step(match_slider, JOY_BUTTON_DPAD_RIGHT)
	assert_eq(match_slider.value, 2.0, "right from Off skips the 1-minute gap")
	_dpad_step(match_slider, JOY_BUTTON_DPAD_RIGHT)
	assert_eq(match_slider.value, 3.0)
	assert_eq(fake.set_lobby_data_calls[-1]["match_timer_minutes"], 3, "a gamepad edit is published")
	_dpad_step(match_slider, JOY_BUTTON_DPAD_LEFT)
	_dpad_step(match_slider, JOY_BUTTON_DPAD_LEFT)
	assert_eq(match_slider.value, 0.0, "left from 2 minutes reaches Off")
	_pick_mode(lobby, MatchConfig.GameMode.CAPTURE_THE_FLAG)
	var round_slider: HSlider = lobby.get_node("%RoundTimerSlider")
	_dpad_step(round_slider, JOY_BUTTON_DPAD_RIGHT)
	assert_eq(round_slider.value, 6.0)
	_dpad_step(round_slider, JOY_BUTTON_DPAD_LEFT)
	_dpad_step(round_slider, JOY_BUTTON_DPAD_LEFT)
	assert_eq(round_slider.value, 4.0)
	assert_eq(fake.set_lobby_data_calls[-1]["round_timer_minutes"], 4)
	# Up/down is not a slider axis: the focus chain owns it (closed-loop tests above).
	assert_ne(round_slider.focus_neighbor_top, NodePath(""))
	assert_ne(round_slider.focus_neighbor_bottom, NodePath(""))


func test_clients_see_the_timer_sliders_read_only() -> void:
	var host: Lobby = _make_lobby(true)
	var client: Lobby = _make_lobby(false)
	for unique_name: String in ["%MatchTimerSlider", "%RoundTimerSlider"]:
		assert_true((host.get_node(unique_name) as HSlider).editable, "host edits %s" % unique_name)
		assert_false((client.get_node(unique_name) as HSlider).editable, "client reads %s" % unique_name)
	var slider: HSlider = client.get_node("%MatchTimerSlider")
	_dpad_step(slider, JOY_BUTTON_DPAD_RIGHT)
	assert_eq(slider.value, 0.0, "a client's gamepad cannot move the host's setting")
	assert_eq((client.net_provider as FakeNet).set_lobby_data_calls.size(), 0)
