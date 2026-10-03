extends GutTest
## Bontago-1pi.53 (S1a, docs/LOBBY_REWORK_PLAN.md sections 2 and 4): the settings column
## is a stack of LobbySections (GAME, ROUND, GIFTS) with collapsible headers, an
## optional Advanced block, a one-line summary each, and a focus loop that follows them.
## Host edits every setting from its section; a client reads them read-only; no
## collapsed block or hidden column ever leaves an invisible focus stop.

## Every control the lobby round trip governs must still resolve by its unique name.
const UNIQUE_NAMES: Array[String] = [
	"%GameModeOption", "%MapComboOption", "%MapThumbnail", "%MapVariantOption", "%MapSizeOption",
	"%SkyThemeOption", "%WeatherOption", "%GravitySlider", "%TurnBasedCheck", "%HoleModeOption",
	"%TiltModeOption", "%MidJoinCheck", "%RoundTimerSlider", "%MatchTimerSlider", "%SuddenDeathCheck",
	"%BlockTimerSlider", "%GoalFlagSpin", "%SkyTeamSumCheck", "%GiftsCheck", "%SpecialFreqSlider",
	"%SpecialsChecklist", "%QolTimerPauseCheck", "%PlayerCountSpin", "%AiCountSpin", "%AiDifficultyOption",
	"%TeamModeOption", "%GameSection", "%RoundSection", "%GiftsSection",
]


func _make_lobby(is_host: bool) -> Lobby:
	var scene: PackedScene = load("res://ui/Lobby.tscn")
	var lobby: Lobby = autofree(scene.instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = is_host
	fake.is_offline_value = is_host
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func _fake_of(lobby: Lobby) -> FakeNet:
	return lobby.net_provider as FakeNet


func _section(lobby: Lobby, unique_name: String) -> LobbySection:
	return lobby.get_node(unique_name) as LobbySection


func _published(lobby: Lobby) -> MatchConfig:
	return MatchConfig.from_dict(_fake_of(lobby).lobby_data_value)


func _pick_mode(lobby: Lobby, mode: int) -> void:
	var option: OptionButton = lobby.get_node("%GameModeOption") as OptionButton
	option.select(mode)
	option.item_selected.emit(mode)


## Walks focus_neighbor_bottom from the loop's last shown stop (Start for a host, Ready
## for a client) once around and returns the controls visited (that stop last). Asserts
## the loop is closed and never revisits a stop.
func _walk_loop(lobby: Lobby) -> Array[Control]:
	var start: Control = lobby._visible_chain(lobby._main_chain).back()
	var visited: Array[Control] = []
	var current: Control = start
	var steps: int = 0
	while steps <= lobby._main_chain.size() + 1:
		current = current.get_node(current.focus_neighbor_bottom) as Control
		steps += 1
		visited.append(current)
		if current == start:
			break
		assert_false(visited.slice(0, visited.size() - 1).has(current), "%s visited twice before the loop closed" % current.name)
	assert_eq(current, start, "the loop is closed")
	return visited


## No stop on the loop may be invisible, and every shown chain control is on it.
func _assert_loop_has_no_invisible_stops(lobby: Lobby, label: String) -> void:
	var visited: Array[Control] = _walk_loop(lobby)
	for control: Control in visited:
		assert_true(control.is_visible_in_tree(), "%s: %s is an invisible focus stop" % [label, control.name])
	for control: Control in lobby._visible_chain(lobby._main_chain):
		assert_true(visited.has(control), "%s: %s is shown but missing from the loop" % [label, control.name])


func _accept_event(pressed: bool) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = pressed
	return event


# --- Structure -------------------------------------------------------------------------

func test_every_unique_name_still_resolves() -> void:
	var lobby: Lobby = _make_lobby(true)
	for unique_name: String in UNIQUE_NAMES:
		assert_not_null(lobby.get_node_or_null(unique_name), "%s resolves" % unique_name)


func test_controls_live_in_their_plan_sections() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game: LobbySection = _section(lobby, "%GameSection")
	var round_section: LobbySection = _section(lobby, "%RoundSection")
	var gifts: LobbySection = _section(lobby, "%GiftsSection")
	for unique_name: String in ["%GameModeOption", "%MapComboOption", "%SkyThemeOption", "%WeatherOption"]:
		assert_true(game.body.is_ancestor_of(lobby.get_node(unique_name)), "%s is GAME main" % unique_name)
	for unique_name: String in ["%GravitySlider", "%TurnBasedCheck", "%HoleModeOption", "%TiltModeOption", "%MidJoinCheck"]:
		assert_true(game.advanced.is_ancestor_of(lobby.get_node(unique_name)), "%s is GAME advanced" % unique_name)
	for unique_name: String in ["%RoundTimerSlider", "%MatchTimerSlider", "%SuddenDeathCheck", "%BlockTimerSlider", "%GoalFlagSpin", "%SkyTeamSumCheck"]:
		assert_true(round_section.body.is_ancestor_of(lobby.get_node(unique_name)), "%s is ROUND main" % unique_name)
	assert_false(round_section.has_advanced(), "ROUND has no Advanced block (plan D1)")
	for unique_name: String in ["%GiftsCheck", "%SpecialFreqSlider"]:
		assert_true(gifts.body.is_ancestor_of(lobby.get_node(unique_name)), "%s is GIFTS main" % unique_name)


func test_sections_default_expanded_with_advanced_collapsed() -> void:
	var lobby: Lobby = _make_lobby(true)
	for section: LobbySection in lobby._sections():
		assert_true(section.is_expanded(), "%s starts expanded" % section.name)
		assert_false(section.is_advanced_open(), "%s starts with Advanced collapsed" % section.name)
		assert_true(section.header_button.is_visible_in_tree(), "%s header is shown" % section.name)
		assert_eq(section.header_button.focus_mode, Control.FOCUS_ALL)
	var game: LobbySection = _section(lobby, "%GameSection")
	assert_false(game.advanced.visible)
	assert_false((lobby.get_node("%GravitySlider") as Control).is_visible_in_tree(), "collapsed Advanced hides its controls")
	assert_true((lobby.get_node("%GameModeOption") as Control).is_visible_in_tree())


# --- Toggling ------------------------------------------------------------------------------

func test_header_press_collapses_and_restores_a_section_and_its_focus_stops() -> void:
	var lobby: Lobby = _make_lobby(true)
	var round_section: LobbySection = _section(lobby, "%RoundSection")
	var block_slider: Control = lobby.get_node("%BlockTimerSlider") as Control
	assert_true(lobby._visible_chain(lobby._main_chain).has(block_slider))
	watch_signals(round_section)
	round_section.header_button.pressed.emit()
	assert_false(round_section.is_expanded())
	assert_signal_emitted_with_parameters(round_section, "expanded_changed", [false])
	assert_false(block_slider.is_visible_in_tree(), "the body is hidden")
	assert_false(lobby._visible_chain(lobby._main_chain).has(block_slider), "its controls leave the loop")
	assert_true(lobby._visible_chain(lobby._main_chain).has(round_section.header_button), "the header stays a stop")
	_assert_loop_has_no_invisible_stops(lobby, "ROUND collapsed")
	round_section.header_button.pressed.emit()
	assert_true(round_section.is_expanded())
	assert_true(block_slider.is_visible_in_tree())
	_assert_loop_has_no_invisible_stops(lobby, "ROUND restored")


func test_advanced_chip_opens_the_block_and_adds_its_controls_to_the_loop() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game: LobbySection = _section(lobby, "%GameSection")
	var gravity: Control = lobby.get_node("%GravitySlider") as Control
	assert_not_null(game.advanced_button)
	assert_false(lobby._visible_chain(lobby._main_chain).has(gravity))
	watch_signals(game)
	game.advanced_button.button_pressed = true
	assert_true(game.is_advanced_open())
	assert_signal_emitted_with_parameters(game, "advanced_changed", [true])
	assert_true(gravity.is_visible_in_tree())
	for unique_name: String in ["%GravitySlider", "%TiltModeOption", "%HoleModeOption", "%TurnBasedCheck", "%MidJoinCheck"]:
		assert_true(lobby._visible_chain(lobby._main_chain).has(lobby.get_node(unique_name)), "%s joins the loop" % unique_name)
	# Visual order: the chip leads straight into the first Advanced control.
	assert_eq(game.advanced_button.get_node(game.advanced_button.focus_neighbor_bottom), gravity)
	_assert_loop_has_no_invisible_stops(lobby, "GAME advanced open")
	game.advanced_button.button_pressed = false
	assert_false(gravity.is_visible_in_tree())
	_assert_loop_has_no_invisible_stops(lobby, "GAME advanced closed again")


func test_toggle_advanced_expands_a_collapsed_section_first() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game: LobbySection = _section(lobby, "%GameSection")
	game.set_expanded(false)
	game.toggle_advanced()
	assert_true(game.is_expanded())
	assert_true(game.is_advanced_open())
	game.toggle_advanced()
	assert_false(game.is_advanced_open())
	_assert_loop_has_no_invisible_stops(lobby, "toggle_advanced")


func test_ui_accept_on_a_focused_header_and_chip_toggles_them() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game: LobbySection = _section(lobby, "%GameSection")
	game.header_button.grab_focus()
	assert_true(game.header_button.has_focus(), "fixture: the header holds focus")
	Input.parse_input_event(_accept_event(true))
	Input.parse_input_event(_accept_event(false))
	Input.flush_buffered_events()
	await get_tree().process_frame
	assert_false(game.is_expanded(), "ui_accept on the header collapses the section")
	Input.parse_input_event(_accept_event(true))
	Input.parse_input_event(_accept_event(false))
	Input.flush_buffered_events()
	await get_tree().process_frame
	assert_true(game.is_expanded(), "a second ui_accept expands it again")
	game.advanced_button.grab_focus()
	Input.parse_input_event(_accept_event(true))
	Input.parse_input_event(_accept_event(false))
	Input.flush_buffered_events()
	await get_tree().process_frame
	assert_true(game.is_advanced_open(), "ui_accept on the Advanced chip opens the block")
	assert_true(lobby._visible_chain(lobby._main_chain).has(lobby.get_node("%GravitySlider")))


func test_ui_down_walks_the_sections_in_visual_order() -> void:
	var lobby: Lobby = _make_lobby(true)
	var visited: Array[Control] = _walk_loop(lobby)
	var order: Array[Control] = [
		_section(lobby, "%GameSection").header_button, lobby.get_node("%GameModeOption") as Control,
		_section(lobby, "%RoundSection").header_button, _section(lobby, "%GiftsSection").header_button,
	]
	var last_index: int = -1
	for control: Control in order:
		var index: int = visited.find(control)
		assert_gt(index, last_index, "%s follows the previous stop" % control.name)
		last_index = index
	_assert_loop_has_no_invisible_stops(lobby, "default")


func test_loop_has_no_invisible_stops_in_every_game_mode() -> void:
	var lobby: Lobby = _make_lobby(true)
	_section(lobby, "%GameSection").set_advanced_open(true)
	for mode: int in MatchConfig.SELECTABLE_GAME_MODES:
		_pick_mode(lobby, mode)
		_assert_loop_has_no_invisible_stops(lobby, "mode %d" % mode)


# --- Visibility rules ------------------------------------------------------------------------

func test_goal_flags_show_only_in_modes_that_use_them() -> void:
	var lobby: Lobby = _make_lobby(true)
	var goal_col: Control = lobby.get_node("%GoalFlagCol") as Control
	var stepper: Button = lobby._goal_stepper_buttons[0]
	for mode: int in MatchConfig.SELECTABLE_GAME_MODES:
		_pick_mode(lobby, mode)
		var expected: bool = MatchConfig.mode_uses_goal_flags(mode)
		assert_eq(goal_col.visible, expected, "goal flags visible for mode %d" % mode)
		assert_eq(lobby._visible_chain(lobby._main_chain).has(stepper), expected, "goal stepper is a stop only when shown (mode %d)" % mode)


func test_team_height_shows_only_for_reach_the_sky_and_sudden_death_only_for_classic() -> void:
	var lobby: Lobby = _make_lobby(true)
	var team_col: Control = lobby.get_node("%SkyTeamCol") as Control
	var sudden_col: Control = lobby.get_node("%SuddenDeathCol") as Control
	for mode: int in MatchConfig.SELECTABLE_GAME_MODES:
		_pick_mode(lobby, mode)
		assert_eq(team_col.visible, mode == MatchConfig.GameMode.REACH_THE_SKY, "team height for mode %d" % mode)
		assert_eq(sudden_col.visible, mode == MatchConfig.GameMode.CLASSIC, "sudden death for mode %d" % mode)
	_pick_mode(lobby, MatchConfig.GameMode.REACH_THE_SKY)
	var team_check: Control = lobby.get_node("%SkyTeamSumCheck") as Control
	assert_true(team_check.is_visible_in_tree())
	assert_true(lobby._visible_chain(lobby._main_chain).has(team_check))
	assert_eq((team_check as Button).text, "Team height: sum of members")


# --- Summaries ----------------------------------------------------------------------------------

func test_headers_summarise_their_section() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game_summary: String = _section(lobby, "%GameSection").summary()
	assert_true(game_summary.contains("Classic"), "GAME names the mode")
	assert_true(game_summary.contains("Cycle"), "GAME names the time of day")
	assert_true(game_summary.contains(" · "), "the parts are separated")
	var round_summary: String = _section(lobby, "%RoundSection").summary()
	var block_text: String = Lobby.SUMMARY_BLOCK_TIMER_FORMAT % (lobby.get_node("%BlockTimerSlider") as HSlider).value
	assert_true(round_summary.contains(block_text), "ROUND names the block timer (%s in %s)" % [block_text, round_summary])
	assert_true(round_summary.contains("goal flag"), "Classic shows its goal flags")
	_pick_mode(lobby, MatchConfig.GameMode.ELIMINATION)
	assert_false(_section(lobby, "%RoundSection").summary().contains("goal flag"), "no goal flags outside their modes")
	assert_true(_section(lobby, "%GiftsSection").summary().begins_with("On"))
	(lobby.get_node("%GiftsCheck") as CheckButton).button_pressed = false
	assert_eq(_section(lobby, "%GiftsSection").summary(), Lobby.SUMMARY_GIFTS_OFF)


# --- Host edits and client read-only ------------------------------------------------------------

func test_host_edits_every_game_setting_from_the_game_section() -> void:
	var lobby: Lobby = _make_lobby(true)
	_section(lobby, "%GameSection").set_advanced_open(true)
	_pick_mode(lobby, MatchConfig.GameMode.ELIMINATION)
	var combo: OptionButton = lobby.get_node("%MapComboOption") as OptionButton
	combo.select(5)
	combo.item_selected.emit(5)
	var sky: OptionButton = lobby.get_node("%SkyThemeOption") as OptionButton
	sky.select(MatchConfig.SkyThemeMode.NIGHT)
	sky.item_selected.emit(MatchConfig.SkyThemeMode.NIGHT)
	var weather: OptionButton = lobby.get_node("%WeatherOption") as OptionButton
	weather.select(MatchConfig.WeatherMode.SNOW)
	weather.item_selected.emit(MatchConfig.WeatherMode.SNOW)
	(lobby.get_node("%GravitySlider") as HSlider).value = 0.5
	(lobby.get_node("%TurnBasedCheck") as CheckButton).button_pressed = true
	var hole: OptionButton = lobby.get_node("%HoleModeOption") as OptionButton
	hole.select(MatchConfig.HoleMode.PERMANENT)
	hole.item_selected.emit(MatchConfig.HoleMode.PERMANENT)
	var tilt: OptionButton = lobby.get_node("%TiltModeOption") as OptionButton
	tilt.select(MatchConfig.TiltMode.PHYSICAL_BALANCE)
	tilt.item_selected.emit(MatchConfig.TiltMode.PHYSICAL_BALANCE)
	(lobby.get_node("%MidJoinCheck") as CheckButton).button_pressed = false
	var config: MatchConfig = _published(lobby)
	assert_eq(config.game_mode, MatchConfig.GameMode.ELIMINATION)
	assert_eq(int(config.map_variant) * 3 + int(config.map_size), 5)
	assert_eq(config.sky_theme_mode, MatchConfig.SkyThemeMode.NIGHT)
	assert_eq(config.weather_mode, MatchConfig.WeatherMode.SNOW)
	assert_almost_eq(config.gravity_multiplier, 0.5, 0.001)
	assert_true(config.turn_based)
	assert_eq(config.hole_mode, MatchConfig.HoleMode.PERMANENT)
	assert_eq(config.tilt_mode, MatchConfig.TiltMode.PHYSICAL_BALANCE)
	assert_false(config.allow_mid_match_join)


func test_host_edits_every_round_setting_from_the_round_section() -> void:
	var lobby: Lobby = _make_lobby(true)
	(lobby.get_node("%MatchTimerSlider") as HSlider).value = 12
	(lobby.get_node("%SuddenDeathCheck") as CheckButton).button_pressed = true
	(lobby.get_node("%BlockTimerSlider") as HSlider).value = 8.5
	(lobby.get_node("%GoalFlagSpin") as SpinBox).value = 3
	var config: MatchConfig = _published(lobby)
	assert_eq(config.match_timer_minutes, 12)
	assert_true(config.sudden_death)
	assert_almost_eq(config.block_timer, 8.5, 0.001)
	assert_eq(config.goal_flag_count, 3)
	_pick_mode(lobby, MatchConfig.GameMode.REACH_THE_SKY)
	(lobby.get_node("%RoundTimerSlider") as HSlider).value = 9
	(lobby.get_node("%SkyTeamSumCheck") as CheckButton).button_pressed = true
	config = _published(lobby)
	assert_eq(config.round_timer_minutes, 9)
	assert_true(config.sky_team_sum)


func test_host_edits_every_gift_setting_from_the_gifts_section() -> void:
	var lobby: Lobby = _make_lobby(true)
	(lobby.get_node("%SpecialFreqSlider") as HSlider).value = 70
	(lobby.get_node("%GiftsCheck") as CheckButton).button_pressed = false
	var config: MatchConfig = _published(lobby)
	assert_eq(config.special_frequency, 70)
	assert_false(config.gifts_enabled)


func test_client_reads_the_sections_but_cannot_edit_them() -> void:
	var lobby: Lobby = _make_lobby(false)
	var game: LobbySection = _section(lobby, "%GameSection")
	for unique_name: String in [
		"%GameModeOption", "%MapComboOption", "%SkyThemeOption", "%WeatherOption", "%GravitySlider",
		"%TurnBasedCheck", "%HoleModeOption", "%TiltModeOption", "%MidJoinCheck", "%MatchTimerSlider",
		"%SuddenDeathCheck", "%BlockTimerSlider", "%GiftsCheck", "%SpecialFreqSlider",
	]:
		var control: Control = lobby.get_node(unique_name) as Control
		if control is Range:
			assert_false((control as Range).editable, "%s is read-only for a client" % unique_name)
		else:
			assert_true((control as BaseButton).disabled, "%s is disabled for a client" % unique_name)
	assert_false(game.header_button.disabled, "a client can still open a section to read it")
	game.advanced_button.button_pressed = true
	assert_true(game.is_advanced_open())
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0, "opening a block publishes nothing")
	_assert_loop_has_no_invisible_stops(lobby, "client")


func test_section_state_is_not_published_or_persisted() -> void:
	var lobby: Lobby = _make_lobby(true)
	var before: int = _fake_of(lobby).set_lobby_data_calls.size()
	_section(lobby, "%GameSection").set_advanced_open(true)
	_section(lobby, "%RoundSection").set_expanded(false)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), before, "toggling a section is local UI state")
	var fresh: Lobby = _make_lobby(true)
	assert_false(_section(fresh, "%GameSection").is_advanced_open(), "a new lobby starts collapsed (plan D7)")
	assert_true(_section(fresh, "%RoundSection").is_expanded())
