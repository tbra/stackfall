extends GutTest
## Bontago-1pi.53 (S1a/S1b, docs/LOBBY_REWORK_PLAN.md sections 2 and 4): the settings column
## is a stack of UiSections (GAME, ROUND, GIFTS, EXPERIMENTS) with static headers (Bontago-1pi.61:
## never collapsible), an optional collapsible Advanced block, a one-line summary each, and a focus
## loop that follows them.
## Host edits every setting from its section; a client reads them read-only; no
## collapsed block or hidden column ever leaves an invisible focus stop. S1b: the
## per-gift checklist is GIFTS Advanced, the experiment checks are the EXPERIMENTS block, and
## the Advanced rules popup, bar, Players/AI steppers and segmented Teams are gone.

const QOL_NAMES: Array[String] = ["%QolTimerPauseCheck", "%QolBacklogCheck", "%QolGoalRadiusCheck", "%QolGiftSlotCheck"]


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


func _section(lobby: Lobby, unique_name: String) -> UiSection:
	return lobby.get_node(unique_name) as UiSection


func _published(lobby: Lobby) -> MatchConfig:
	return MatchConfig.from_dict(_fake_of(lobby).lobby_data_value)


func _pick_mode(lobby: Lobby, mode: int) -> void:
	var option: UiCycler = lobby.get_node("%GameModeOption") as UiCycler
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


func test_every_chain_control_belongs_to_at_most_one_section_and_every_section_is_reachable() -> void:
	var lobby: Lobby = _make_lobby(true)
	for section: UiSection in lobby._sections():
		section.set_advanced_open(true)
	var sections: Array[UiSection] = lobby._sections()
	# The sections the lobby loops over are exactly the UiSection nodes in its tree.
	var in_tree: Array[Node] = lobby.find_children("*", "UiSection", true, false)
	assert_eq(sections.size(), in_tree.size(), "every UiSection in the tree is walked by the lobby")
	for section: UiSection in sections:
		assert_true(in_tree.has(section), "%s is in the lobby tree" % section.name)
	var chain: Array[Control] = lobby._visible_chain(lobby._main_chain)
	for section: UiSection in sections:
		var reachable: int = 0
		for control: Control in chain:
			if section.is_ancestor_of(control) or control == section.advanced_button:
				reachable += 1
		assert_gt(reachable, 0, "%s offers at least one focus stop" % section.name)
	for control: Control in chain:
		var owners: int = 0
		for section: UiSection in sections:
			if section.is_ancestor_of(control):
				owners += 1
		assert_lte(owners, 1, "%s sits in at most one section" % control.name)
	for section: UiSection in sections:
		if section.has_advanced():
			assert_not_null(section.advanced_button, "%s has a chip for its Advanced block" % section.name)
			assert_true(section.advanced_button.is_visible_in_tree())


func test_advanced_chip_opens_the_block_and_adds_its_controls_to_the_loop() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game: UiSection = _section(lobby, "%GameSection")
	var gravity: Control = lobby.get_node("%GravityMeter") as Control
	assert_not_null(game.advanced_button)
	assert_false(lobby._visible_chain(lobby._main_chain).has(gravity))
	watch_signals(game)
	game.advanced_button.button_pressed = true
	assert_true(game.is_advanced_open())
	assert_signal_emitted_with_parameters(game, "advanced_changed", [true])
	assert_true(gravity.is_visible_in_tree())
	for unique_name: String in ["%GravityMeter", "%TiltModeOption", "%HoleModeOption", "%TurnBasedCheck", "%MidJoinCheck"]:
		assert_true(lobby._visible_chain(lobby._main_chain).has(lobby.get_node(unique_name)), "%s joins the loop" % unique_name)
	# Visual order: the chip leads straight into the first Advanced control.
	assert_eq(game.advanced_button.get_node(game.advanced_button.focus_neighbor_bottom), gravity)
	_assert_loop_has_no_invisible_stops(lobby, "GAME advanced open")
	game.advanced_button.button_pressed = false
	assert_false(gravity.is_visible_in_tree())
	_assert_loop_has_no_invisible_stops(lobby, "GAME advanced closed again")


func test_loop_has_no_invisible_stops_in_every_game_mode() -> void:
	var lobby: Lobby = _make_lobby(true)
	for section: UiSection in lobby._sections():
		section.set_advanced_open(true)
	for mode: int in MatchConfig.SELECTABLE_GAME_MODES:
		_pick_mode(lobby, mode)
		_assert_loop_has_no_invisible_stops(lobby, "mode %d" % mode)


## Hiding a block while focus is inside it hands focus to the section's chip instead of
## dropping it with the hidden control.
func test_collapsing_a_block_with_focus_inside_keeps_focus_on_a_visible_stop() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game: UiSection = _section(lobby, "%GameSection")
	game.set_advanced_open(true)
	(lobby.get_node("%TurnBasedCheck") as Control).grab_focus()
	assert_true((lobby.get_node("%TurnBasedCheck") as Control).has_focus(), "fixture: focus inside Advanced")
	game.set_advanced_open(false)
	assert_true(game.advanced_button.has_focus(), "focus moved to the chip")
	var experiments: UiSection = _section(lobby, "%ExperimentsSection")
	experiments.set_advanced_open(true)
	(lobby.get_node("%QolGiftSlotCheck") as Control).grab_focus()
	experiments.set_advanced_open(false)
	assert_true(experiments.advanced_button.has_focus(), "focus moves to the chip")
	# Focus elsewhere is never stolen by a toggle.
	(lobby.get_node("%BackButton") as Control).grab_focus()
	game.set_advanced_open(true)
	game.set_advanced_open(false)
	assert_true((lobby.get_node("%BackButton") as Control).has_focus(), "an unrelated focus stays put")


# --- Visibility rules ------------------------------------------------------------------------

## Bontago-1pi.147 / 159.2.1: the block timer is a UiStepper (-/value/+ in a well), half a second a step.
func test_block_timer_is_a_stepper_with_the_old_range_and_step() -> void:
	var lobby: Lobby = _make_lobby(true)
	var stepper: UiStepper = lobby.get_node("%BlockTimerStepper") as UiStepper
	assert_almost_eq(Lobby._block_timer_seconds_for(stepper.min_value), MatchConfig.BLOCK_TIMER_MIN, 0.001)
	assert_almost_eq(Lobby._block_timer_seconds_for(stepper.max_value), MatchConfig.BLOCK_TIMER_MAX, 0.001)
	assert_almost_eq(Lobby._block_timer_seconds_for(stepper.step), Lobby.BLOCK_TIMER_STEP_S, 0.001)
	assert_null(lobby.get_node_or_null("%BlockTimerSlider"), "no slider remains")
	assert_null(lobby.get_node_or_null("%BlockTimerSpin"), "no spin box remains")
	stepper.value = roundi(6.0 / Lobby.BLOCK_TIMER_STEP_S)
	stepper.plus_button.button_down.emit()
	stepper.plus_button.button_up.emit()
	assert_almost_eq(lobby._block_timer_seconds(), 6.5, 0.001)
	assert_eq(stepper.value_label.text, "6.5")
	assert_almost_eq(_published(lobby).block_timer, 6.5, 0.001, "host edits publish")
	stepper.minus_button.button_down.emit()
	stepper.minus_button.button_up.emit()
	stepper.minus_button.button_down.emit()
	stepper.minus_button.button_up.emit()
	assert_almost_eq(lobby._block_timer_seconds(), 5.5, 0.001)
	stepper.value = stepper.min_value
	stepper.nudge(-1)
	assert_almost_eq(lobby._block_timer_seconds(), MatchConfig.BLOCK_TIMER_MIN, 0.001, "clamped at the minimum")
	assert_true(stepper.minus_button.disabled, "- dims at the minimum")
	stepper.value = stepper.max_value
	stepper.nudge(1)
	assert_almost_eq(lobby._block_timer_seconds(), MatchConfig.BLOCK_TIMER_MAX, 0.001, "clamped at the maximum")


func test_host_edits_every_game_setting_from_the_game_section() -> void:
	var lobby: Lobby = _make_lobby(true)
	_section(lobby, "%GameSection").set_advanced_open(true)
	_pick_mode(lobby, MatchConfig.GameMode.ELIMINATION)
	(lobby.get_node("%DiscSizeMeter") as UiSegmentMeter).value = 6
	var sky: UiCycler = lobby.get_node("%SkyThemeOption") as UiCycler
	sky.select(MatchConfig.SkyThemeMode.NIGHT)
	sky.item_selected.emit(MatchConfig.SkyThemeMode.NIGHT)
	var weather: UiCycler = lobby.get_node("%WeatherOption") as UiCycler
	weather.select(MatchConfig.WeatherMode.SNOW)
	weather.item_selected.emit(MatchConfig.WeatherMode.SNOW)
	(lobby.get_node("%GravityMeter") as UiSegmentMeter).value = Lobby._gravity_cells_for(0.5)
	(lobby.get_node("%TurnBasedCheck") as UiToggle).button_pressed = true
	var hole: UiCycler = lobby.get_node("%HoleModeOption") as UiCycler
	hole.select(MatchConfig.HoleMode.PERMANENT)
	hole.item_selected.emit(MatchConfig.HoleMode.PERMANENT)
	var tilt: UiCycler = lobby.get_node("%TiltModeOption") as UiCycler
	tilt.select(MatchConfig.TiltMode.PHYSICAL_BALANCE)
	tilt.item_selected.emit(MatchConfig.TiltMode.PHYSICAL_BALANCE)
	(lobby.get_node("%MidJoinCheck") as UiToggle).button_pressed = false
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
	(lobby.get_node("%MatchTimerStepper") as UiStepper).value = 12
	(lobby.get_node("%SuddenDeathCheck") as UiToggle).button_pressed = true
	(lobby.get_node("%BlockTimerStepper") as UiStepper).value = 17
	(lobby.get_node("%GoalFlagStepper") as UiStepper).value = 3
	var config: MatchConfig = _published(lobby)
	assert_eq(config.match_timer_minutes, 12)
	assert_true(config.sudden_death)
	assert_almost_eq(config.block_timer, 8.5, 0.001)
	assert_eq(config.goal_flag_count, 3)
	_pick_mode(lobby, MatchConfig.GameMode.REACH_THE_SKY)
	(lobby.get_node("%RoundTimerStepper") as UiStepper).value = 9
	(lobby.get_node("%SkyTeamSumCheck") as UiToggle).button_pressed = true
	config = _published(lobby)
	assert_eq(config.round_timer_minutes, 9)
	assert_true(config.sky_team_sum)


func test_client_reads_the_sections_but_cannot_edit_them() -> void:
	var lobby: Lobby = _make_lobby(false)
	var game: UiSection = _section(lobby, "%GameSection")
	var disabled_names: Array[String] = [
		"%GameModeOption", "%DiscSizeMeter", "%SkyThemeOption", "%WeatherOption", "%GravityMeter",
		"%TurnBasedCheck", "%HoleModeOption", "%TiltModeOption", "%MidJoinCheck", "%MatchTimerStepper",
		"%SuddenDeathCheck", "%BlockTimerStepper", "%GiftsCheck", "%SpecialFreqMeter",
	]
	disabled_names.append_array(QOL_NAMES)
	for box: UiChipToggle in lobby._special_checkboxes:
		assert_true(box.disabled, "%s is a read-only gift checkbox for a client" % box.name)
	for unique_name: String in disabled_names:
		var control: Control = lobby.get_node(unique_name) as Control
		if control is UiStepper:
			assert_true((control as UiStepper).disabled, "%s is read-only for a client" % unique_name)
		elif control is UiCycler:
			assert_true((control as UiCycler).disabled, "%s is read-only for a client" % unique_name)
		elif control is UiSegmentMeter:
			assert_false((control as UiSegmentMeter).editable, "%s is read-only for a client" % unique_name)
		else:
			assert_true((control as BaseButton).disabled, "%s is disabled for a client" % unique_name)
	assert_false(game.advanced_button.disabled, "a client can still open the Advanced block to read it")
	game.advanced_button.button_pressed = true
	assert_true(game.is_advanced_open())
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0, "opening a block publishes nothing")
	_assert_loop_has_no_invisible_stops(lobby, "client")
