extends GutTest
## The settings column
## is a stack of UiSections (GAME, ROUND, GIFTS, EXPERIMENTS) with static headers (
## never collapsible), an optional collapsible Advanced block, a one-line summary each, and a focus
## loop that follows them.
## Host edits every setting from its section; a client reads them read-only; no
## collapsed block or hidden column ever leaves an invisible focus stop. S1b: the
## per-gift checklist is GIFTS Advanced, the experiment checks are the EXPERIMENTS block, and
## the Advanced rules popup, bar, Players/AI steppers and segmented Teams are gone.

func _make_lobby(is_host: bool) -> Lobby:
	var scene: PackedScene = load("res://ui/lobby/Lobby.tscn")
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


func _card_of(lobby: Lobby) -> LobbySettingsCard:
	return lobby.find_child("LobbySettingsCard", true, false) as LobbySettingsCard


func _section(lobby: Lobby, unique_name: String) -> UiSection:
	return lobby.find_child(unique_name, true, false) as UiSection


func _published(lobby: Lobby) -> MatchConfig:
	return MatchConfig.from_dict(_fake_of(lobby).lobby_data_value)


func _pick_mode(lobby: Lobby, mode: int) -> void:
	var option: UiCycler = lobby.find_child("GameModeOption", true, false) as UiCycler
	option.select(mode)
	option.item_selected.emit(mode)


## The loop's anchor: Start for a host, Ready for a client (the footer stop the loop wraps at).
func _anchor(lobby: Lobby) -> Control:
	var start: Control = lobby.find_child("StartButton", true, false) as Control
	return start if start.is_visible_in_tree() else lobby.find_child("ReadyCheck", true, false) as Control


## Focus-down from the anchor, once around: the loop closes, no stop is invisible, and every live
## focusable control of the settings column is on it.
func _assert_loop_has_no_invisible_stops(lobby: Lobby, label: String) -> void:
	var anchor: Control = _anchor(lobby)
	var stops: Array[Control] = FocusWalk.loop(anchor)
	assert_true(FocusWalk.is_closed(stops, anchor), "%s: the loop is closed" % label)
	for control: Control in stops:
		assert_true(control.is_visible_in_tree(), "%s: %s is an invisible focus stop" % [label, control.name])
	for control: Control in FocusWalk.live_focusable(lobby.find_child("Settings", true, false) as Control):
		assert_true(stops.has(control), "%s: %s is shown but missing from the loop" % [label, control.name])


func test_every_section_is_reachable_by_focus() -> void:
	var lobby: Lobby = _make_lobby(true)
	for section: UiSection in lobby.find_children("*", "UiSection", true, false):
		section.set_advanced_open(true)
	var stops: Array[Control] = FocusWalk.loop(_anchor(lobby))
	for section: UiSection in lobby.find_children("*", "UiSection", true, false):
		var reachable: int = 0
		for control: Control in stops:
			if section.is_ancestor_of(control):
				reachable += 1
		assert_gt(reachable, 0, "%s offers at least one focus stop" % section.name)


func test_advanced_chip_opens_the_block_and_adds_its_controls_to_the_loop() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game: UiSection = _section(lobby, "GameSection")
	var gravity: Control = lobby.find_child("GravityMeter", true, false) as Control
	assert_not_null(game.advanced_button)
	assert_false(FocusWalk.loop(_anchor(lobby)).has(gravity), "closed Advanced controls are not stops")
	watch_signals(game)
	game.advanced_button.button_pressed = true
	assert_true(game.advanced.visible)
	assert_signal_emitted_with_parameters(game, "advanced_changed", [true])
	assert_true(gravity.is_visible_in_tree())
	for unique_name: String in ["GravityMeter", "TiltModeOption", "HoleModeOption", "TurnBasedCheck", "MidJoinCheck"]:
		assert_true(FocusWalk.loop(_anchor(lobby)).has(lobby.find_child(unique_name, true, false)), "%s joins the loop" % unique_name)
	_assert_loop_has_no_invisible_stops(lobby, "GAME advanced open")
	game.advanced_button.button_pressed = false
	assert_false(gravity.is_visible_in_tree())
	_assert_loop_has_no_invisible_stops(lobby, "GAME advanced closed again")


func test_loop_has_no_invisible_stops_in_every_game_mode() -> void:
	var lobby: Lobby = _make_lobby(true)
	for section: UiSection in lobby.find_children("*", "UiSection", true, false):
		section.set_advanced_open(true)
	for mode: int in MatchConfig.SELECTABLE_GAME_MODES:
		_pick_mode(lobby, mode)
		_assert_loop_has_no_invisible_stops(lobby, "mode %d" % mode)


## Hiding a block while focus is inside it hands focus to the section's chip instead of
## dropping it with the hidden control.
func test_collapsing_a_block_with_focus_inside_keeps_focus_on_a_visible_stop() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game: UiSection = _section(lobby, "GameSection")
	game.set_advanced_open(true)
	(lobby.find_child("TurnBasedCheck", true, false) as Control).grab_focus()
	assert_true((lobby.find_child("TurnBasedCheck", true, false) as Control).has_focus(), "fixture: focus inside Advanced")
	game.set_advanced_open(false)
	assert_true(game.advanced_button.has_focus(), "focus moved to the chip")
	# Focus elsewhere is never stolen by a toggle.
	(lobby.find_child("BackButton", true, false) as Control).grab_focus()
	game.set_advanced_open(true)
	game.set_advanced_open(false)
	assert_true((lobby.find_child("BackButton", true, false) as Control).has_focus(), "an unrelated focus stays put")


# --- Visibility rules ------------------------------------------------------------------------

## The block timer is a UiStepper (-/value/+ in a well), half a second a step.
func test_block_timer_is_a_stepper_with_the_old_range_and_step() -> void:
	var lobby: Lobby = _make_lobby(true)
	var stepper: UiStepper = lobby.find_child("BlockTimerStepper", true, false) as UiStepper
	assert_almost_eq(float(stepper.min_value) * LobbySettingsCard.BLOCK_TIMER_STEP_S, MatchConfig.BLOCK_TIMER_MIN, 0.001)
	assert_almost_eq(float(stepper.max_value) * LobbySettingsCard.BLOCK_TIMER_STEP_S, MatchConfig.BLOCK_TIMER_MAX, 0.001)
	assert_almost_eq(float(stepper.step) * LobbySettingsCard.BLOCK_TIMER_STEP_S, LobbySettingsCard.BLOCK_TIMER_STEP_S, 0.001)
	assert_null(lobby.find_child("BlockTimerSlider", true, false), "no slider remains")
	assert_null(lobby.find_child("BlockTimerSpin", true, false), "no spin box remains")
	stepper.value = roundi(6.0 / LobbySettingsCard.BLOCK_TIMER_STEP_S)
	stepper.plus_button.button_down.emit()
	stepper.plus_button.button_up.emit()
	assert_almost_eq(_card_of(lobby).config().block_timer, 6.5, 0.001)
	assert_eq(stepper.value_label.text, "6.5")
	assert_almost_eq(_published(lobby).block_timer, 6.5, 0.001, "host edits publish")
	stepper.minus_button.button_down.emit()
	stepper.minus_button.button_up.emit()
	stepper.minus_button.button_down.emit()
	stepper.minus_button.button_up.emit()
	assert_almost_eq(_card_of(lobby).config().block_timer, 5.5, 0.001)
	stepper.value = stepper.min_value
	stepper.nudge(-1)
	assert_almost_eq(_card_of(lobby).config().block_timer, MatchConfig.BLOCK_TIMER_MIN, 0.001, "clamped at the minimum")
	assert_true(stepper.minus_button.disabled, "- dims at the minimum")
	stepper.value = stepper.max_value
	stepper.nudge(1)
	assert_almost_eq(_card_of(lobby).config().block_timer, MatchConfig.BLOCK_TIMER_MAX, 0.001, "clamped at the maximum")


func test_host_edits_every_game_setting_from_the_game_section() -> void:
	var lobby: Lobby = _make_lobby(true)
	_section(lobby, "GameSection").set_advanced_open(true)
	_pick_mode(lobby, MatchConfig.GameMode.ELIMINATION)
	(lobby.find_child("DiscSizeMeter", true, false) as UiSegmentMeter).value = 6
	var sky: UiCycler = lobby.find_child("SkyThemeOption", true, false) as UiCycler
	sky.select(MatchConfig.SkyThemeMode.NIGHT)
	sky.item_selected.emit(MatchConfig.SkyThemeMode.NIGHT)
	var weather: UiCycler = lobby.find_child("WeatherOption", true, false) as UiCycler
	weather.select(MatchConfig.WeatherMode.SNOW)
	weather.item_selected.emit(MatchConfig.WeatherMode.SNOW)
	(lobby.find_child("GravityMeter", true, false) as UiSegmentMeter).value = roundi(0.5 / MatchConfig.GRAVITY_STEP)
	(lobby.find_child("TurnBasedCheck", true, false) as UiToggle).button_pressed = true
	var hole: UiCycler = lobby.find_child("HoleModeOption", true, false) as UiCycler
	hole.select(MatchConfig.HoleMode.PERMANENT)
	hole.item_selected.emit(MatchConfig.HoleMode.PERMANENT)
	var tilt: UiCycler = lobby.find_child("TiltModeOption", true, false) as UiCycler
	tilt.select(MatchConfig.TiltMode.PHYSICAL_BALANCE)
	tilt.item_selected.emit(MatchConfig.TiltMode.PHYSICAL_BALANCE)
	(lobby.find_child("MidJoinCheck", true, false) as UiToggle).button_pressed = false
	var config: MatchConfig = _published(lobby)
	assert_eq(config.game_mode, MatchConfig.GameMode.ELIMINATION)
	assert_eq(config.disc_size_step, 5)
	assert_eq(config.sky_theme_mode, MatchConfig.SkyThemeMode.NIGHT)
	assert_eq(config.weather_mode, MatchConfig.WeatherMode.SNOW)
	assert_almost_eq(config.gravity_multiplier, 0.5, 0.06, "the meter snaps to its nearest cell value")
	assert_true(config.turn_based)
	assert_eq(config.hole_mode, MatchConfig.HoleMode.PERMANENT)
	assert_eq(config.tilt_mode, MatchConfig.TiltMode.PHYSICAL_BALANCE)
	assert_false(config.allow_mid_match_join)


func test_host_edits_every_round_setting_from_the_round_section() -> void:
	var lobby: Lobby = _make_lobby(true)
	(lobby.find_child("MatchTimerStepper", true, false) as UiStepper).value = 12
	(lobby.find_child("SuddenDeathCheck", true, false) as UiToggle).button_pressed = true
	(lobby.find_child("BlockTimerStepper", true, false) as UiStepper).value = 17
	(lobby.find_child("GoalFlagStepper", true, false) as UiStepper).value = 3
	var config: MatchConfig = _published(lobby)
	assert_eq(config.match_timer_minutes, 12)
	assert_true(config.sudden_death)
	assert_almost_eq(config.block_timer, 8.5, 0.001)
	assert_eq(config.goal_flag_count, 3)
	_pick_mode(lobby, MatchConfig.GameMode.REACH_THE_SKY)
	(lobby.find_child("RoundTimerStepper", true, false) as UiStepper).value = 9
	(lobby.find_child("SkyTeamSumCheck", true, false) as UiToggle).button_pressed = true
	config = _published(lobby)
	assert_eq(config.round_timer_minutes, 9)
	assert_true(config.sky_team_sum)


## A button that belongs to a stepper, cycler or meter (its own -/+ or arrows), not a setting itself.
func _inside_widget(control: Control) -> bool:
	var node: Node = control.get_parent()
	while node != null:
		if node is UiStepper or node is UiCycler or node is UiSegmentMeter:
			return true
		node = node.get_parent()
	return false


func test_client_reads_the_sections_but_cannot_edit_them() -> void:
	var lobby: Lobby = _make_lobby(false)
	var game: UiSection = _section(lobby, "GameSection")
	var chips: Array[Node] = []
	for section: UiSection in lobby.find_children("*", "UiSection", true, false):
		if section.advanced_button != null:
			chips.append(section.advanced_button)
	var checked: int = 0
	for control: Node in lobby.find_child("Settings", true, false).find_children("*", "Control", true, false):
		if control is UiStepper:
			assert_true((control as UiStepper).disabled, "%s is read-only for a client" % control.name)
		elif control is UiCycler:
			assert_true((control as UiCycler).disabled, "%s is read-only for a client" % control.name)
		elif control is UiSegmentMeter:
			assert_false((control as UiSegmentMeter).editable, "%s is read-only for a client" % control.name)
		elif control is BaseButton and not chips.has(control) and not _inside_widget(control as Control):
			assert_true((control as BaseButton).disabled, "%s is disabled for a client" % control.name)
		else:
			continue
		checked += 1
	assert_gt(checked, 20, "the settings column was actually walked")
	for box: Node in lobby.find_children("*", "UiChipToggle", true, false):
		assert_true((box as UiChipToggle).disabled, "%s is a read-only chip for a client" % box.name)
	assert_false(game.advanced_button.disabled, "a client can still open the Advanced block to read it")
	game.advanced_button.button_pressed = true
	assert_true(game.advanced.visible)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0, "opening a block publishes nothing")
	_assert_loop_has_no_invisible_stops(lobby, "client")
