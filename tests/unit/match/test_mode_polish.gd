extends "res://tests/unit/match/match_world_test.gd"
## (one lobby timer control per mode) and (no goal
## flags in Reach the Sky / Elimination; the sandbox never wins on a goal hold).
## The bot-targeting check lives in test_bot_controller.gd (its fake match).

func _config(mode: int, sandbox: bool = false) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
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
	var lobby: Lobby = autofree((load("res://ui/lobby/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = is_host
	fake.is_offline_value = is_host
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func _pick_mode(lobby: Lobby, mode: int) -> void:
	var option: UiCycler = lobby.get_node("%GameModeOption")
	option.select(mode)
	option.item_selected.emit(mode)


# --- round timer -------------------------------------------------------------------

# --- lobby labels -------------------------------------------------------------------

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


# --- Domination --------------------------------------------

func test_lobby_forces_a_timer_for_domination() -> void:
	var lobby: Lobby = _make_lobby(true)
	var slider: UiStepper = lobby.get_node("%RoundTimerStepper")
	_pick_mode(lobby, MatchConfig.GameMode.ELIMINATION)
	assert_eq(slider.value, MatchConfig.ROUND_TIMER_DEFAULT_MINUTES)
	_pick_mode(lobby, MatchConfig.GameMode.DOMINATION)
	assert_true((lobby.get_node("%RoundTimerCol") as Control).visible)
	assert_eq(slider.min_value, MatchConfig.ROUND_TIMER_MIN_MINUTES, "cannot be set to off")
	assert_eq(slider.value, MatchConfig.DOMINATION_ROUND_MINUTES_DEFAULT)
	slider.value = 0
	assert_gte(slider.value, MatchConfig.ROUND_TIMER_MIN_MINUTES)
	var fake: FakeNet = lobby.net_provider as FakeNet
	assert_gte(int(fake.set_lobby_data_calls[-1]["round_timer_minutes"]), MatchConfig.ROUND_TIMER_MIN_MINUTES)
	assert_null(lobby.get_node_or_null("%RoundTimerValue"), "no \"required\" readout")
	assert_eq(((lobby.get_node("%RoundTimerCol") as UiRow).label.text), "Round length (min)")
	assert_false(OptionHelpTable.shared().text_for(UiHelpLine.key_of(lobby.get_node("%GameModeOption").get_parent()), 0).is_empty(), "mode description")


# --- round timer slider ------------------

func _dpad_event(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	event.pressed = true
	return event


## Feeds [param slider] a real D-pad press the way a focused control receives it: its
## gui_input signal (GUT cannot route key/pad events through the viewport to a focus
## control here). The event is matched against the real InputMap's ui_left/ui_right.
func _dpad_step(slider: UiStepper, button: JoyButton) -> void:
	var event: InputEventJoypadButton = _dpad_event(button)
	assert_true(event.is_action_pressed(&"ui_left", true) or event.is_action_pressed(&"ui_right", true),
		"fixture: the D-pad maps to ui_left/ui_right")
	slider._gui_input(event)


func test_gamepad_left_right_changes_the_focused_timer_slider() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = lobby.net_provider as FakeNet
	var match_slider: UiStepper = lobby.get_node("%MatchTimerStepper")
	_dpad_step(match_slider, JOY_BUTTON_DPAD_RIGHT)
	assert_eq(match_slider.value, 2, "right from Off skips the 1-minute gap")
	_dpad_step(match_slider, JOY_BUTTON_DPAD_RIGHT)
	assert_eq(match_slider.value, 3)
	assert_eq(fake.set_lobby_data_calls[-1]["match_timer_minutes"], 3, "a gamepad edit is published")
	_dpad_step(match_slider, JOY_BUTTON_DPAD_LEFT)
	_dpad_step(match_slider, JOY_BUTTON_DPAD_LEFT)
	assert_eq(match_slider.value, 0, "left from 2 minutes reaches Off")
	_pick_mode(lobby, MatchConfig.GameMode.CAPTURE_THE_FLAG)
	var round_slider: UiStepper = lobby.get_node("%RoundTimerStepper")
	_dpad_step(round_slider, JOY_BUTTON_DPAD_RIGHT)
	assert_eq(round_slider.value, 6)
	_dpad_step(round_slider, JOY_BUTTON_DPAD_LEFT)
	_dpad_step(round_slider, JOY_BUTTON_DPAD_LEFT)
	assert_eq(round_slider.value, 4)
	assert_eq(fake.set_lobby_data_calls[-1]["round_timer_minutes"], 4)
	# Up/down is not a slider axis: the focus chain owns it (closed-loop tests above).
	assert_ne(round_slider.focus_neighbor_top, NodePath(""))
	assert_ne(round_slider.focus_neighbor_bottom, NodePath(""))

