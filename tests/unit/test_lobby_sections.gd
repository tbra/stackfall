extends GutTest
## Bontago-1pi.53 (S1a/S1b, docs/LOBBY_REWORK_PLAN.md sections 2 and 4): the settings column
## is a stack of LobbySections (GAME, ROUND, GIFTS, EXPERIMENTS) with static headers (Bontago-1pi.61:
## never collapsible), an optional collapsible Advanced block, a one-line summary each, and a focus
## loop that follows them.
## Host edits every setting from its section; a client reads them read-only; no
## collapsed block or hidden column ever leaves an invisible focus stop. S1b: the
## per-gift checklist is GIFTS Advanced, the experiment checks are the EXPERIMENTS block, and
## the Advanced rules popup, bar, Players/AI steppers and segmented Teams are gone.

const QOL_NAMES: Array[String] = ["%QolTimerPauseCheck", "%QolBacklogCheck", "%QolGoalRadiusCheck", "%QolGiftSlotCheck"]


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


func _section(lobby: Lobby, unique_name: String) -> UiSection:
	return lobby.get_node(unique_name) as UiSection


func _published(lobby: Lobby) -> MatchConfig:
	return MatchConfig.from_dict(_fake_of(lobby).lobby_data_value)


func _pick_mode(lobby: Lobby, mode: int) -> void:
	var option: UiDropdown = lobby.get_node("%GameModeOption") as UiDropdown
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


func test_controls_live_in_their_plan_sections() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game: UiSection = _section(lobby, "%GameSection")
	var round_section: UiSection = _section(lobby, "%RoundSection")
	var gifts: UiSection = _section(lobby, "%GiftsSection")
	for unique_name: String in ["%GameModeOption", "%DiscSizeMeter", "%SkyThemeOption", "%WeatherOption"]:
		assert_true(game.body.is_ancestor_of(lobby.get_node(unique_name)), "%s is GAME main" % unique_name)
	for unique_name: String in ["%GravityMeter", "%TurnBasedCheck", "%HoleModeOption", "%TiltModeOption", "%MidJoinCheck"]:
		assert_true(game.advanced.is_ancestor_of(lobby.get_node(unique_name)), "%s is GAME advanced" % unique_name)
	for unique_name: String in ["%RoundTimerStepper", "%MatchTimerStepper", "%SuddenDeathCheck", "%BlockTimerStepper", "%GoalFlagStepper", "%SkyTeamSumCheck"]:
		assert_true(round_section.body.is_ancestor_of(lobby.get_node(unique_name)), "%s is ROUND main" % unique_name)
	assert_false(round_section.has_advanced(), "ROUND has no Advanced block (plan D1)")
	for unique_name: String in ["%GiftsCheck", "%SpecialFreqMeter"]:
		assert_true(gifts.body.is_ancestor_of(lobby.get_node(unique_name)), "%s is GIFTS main" % unique_name)
	assert_true(gifts.advanced.is_ancestor_of(lobby.get_node("%SpecialsChecklist")), "the per-gift checkboxes are GIFTS Advanced")
	var experiments: UiSection = _section(lobby, "%ExperimentsSection")
	assert_null(experiments.body, "EXPERIMENTS has no main body")
	assert_not_null(experiments.advanced_button, "its checks sit behind the Advanced chip like every section")
	for unique_name: String in QOL_NAMES:
		assert_true(experiments.advanced.is_ancestor_of(lobby.get_node(unique_name)), "%s is EXPERIMENTS Advanced" % unique_name)
	assert_eq(lobby._sections(), [game, round_section, gifts, experiments] as Array[UiSection], "visual order: GAME, ROUND, GIFTS, EXPERIMENTS")


func test_sections_default_with_advanced_collapsed() -> void:
	var lobby: Lobby = _make_lobby(true)
	for section: UiSection in lobby._sections():
		assert_false(section.is_advanced_open(), "%s starts with Advanced collapsed" % section.name)
		assert_true((section.get_node("HeaderRow") as Control).is_visible_in_tree(), "%s header is shown" % section.name)
		if section.has_advanced():
			assert_eq(section.advanced_button.focus_mode, Control.FOCUS_ALL)
		if section.body != null:
			assert_true(section.body.is_visible_in_tree(), "%s body is always shown" % section.name)
	var game: UiSection = _section(lobby, "%GameSection")
	assert_false(game.advanced.visible)
	assert_false((lobby.get_node("%GravityMeter") as Control).is_visible_in_tree(), "collapsed Advanced hides its controls")
	assert_true((lobby.get_node("%GameModeOption") as Control).is_visible_in_tree())


# --- Toggling ------------------------------------------------------------------------------

## Section headers are static (Bontago-1pi.61): no collapse API, no focus stop, no chevron.
func test_section_headers_are_static_and_not_focus_stops() -> void:
	var lobby: Lobby = _make_lobby(true)
	for section: UiSection in lobby._sections():
		assert_false(section.has_method("set_expanded"), "%s cannot be collapsed" % section.name)
		assert_false(section.has_signal("expanded_changed"))
		var header: Control = section.get_node("HeaderRow") as Control
		for child: Node in header.find_children("*", "Control", true, false):
			assert_eq((child as Control).focus_mode, Control.FOCUS_NONE, "%s header is not focusable" % section.name)
		for stop: Control in lobby._visible_chain(lobby._main_chain):
			assert_false(header.is_ancestor_of(stop), "no header control is a stop")
	_assert_loop_has_no_invisible_stops(lobby, "static headers")


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


func test_toggle_advanced_flips_the_block() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game: UiSection = _section(lobby, "%GameSection")
	game.toggle_advanced()
	assert_true(game.is_advanced_open())
	game.toggle_advanced()
	assert_false(game.is_advanced_open())
	_assert_loop_has_no_invisible_stops(lobby, "toggle_advanced")


func test_ui_accept_on_a_focused_chip_toggles_it() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game: UiSection = _section(lobby, "%GameSection")
	game.advanced_button.grab_focus()
	assert_true(game.advanced_button.has_focus(), "fixture: the chip holds focus")
	Input.parse_input_event(_accept_event(true))
	Input.parse_input_event(_accept_event(false))
	Input.flush_buffered_events()
	await get_tree().process_frame
	assert_true(game.is_advanced_open(), "ui_accept on the Advanced chip opens the block")
	assert_true(lobby._visible_chain(lobby._main_chain).has(lobby.get_node("%GravityMeter")))
	Input.parse_input_event(_accept_event(true))
	Input.parse_input_event(_accept_event(false))
	Input.flush_buffered_events()
	await get_tree().process_frame
	assert_false(game.is_advanced_open(), "a second ui_accept closes it again")


func test_ui_down_walk_visits_every_section_chip_once() -> void:
	var lobby: Lobby = _make_lobby(true)
	var visited: Array[Control] = _walk_loop(lobby)
	for section: UiSection in lobby._sections():
		if section.has_advanced():
			assert_eq(visited.count(section.advanced_button), 1, "%s chip is a stop exactly once" % section.name)
	assert_eq(visited.size(), lobby._visible_chain(lobby._main_chain).size(), "the walk covers the shown chain, no more, no less")
	_assert_loop_has_no_invisible_stops(lobby, "default")


func test_loop_has_no_invisible_stops_in_every_game_mode() -> void:
	var lobby: Lobby = _make_lobby(true)
	for section: UiSection in lobby._sections():
		section.set_advanced_open(true)
	for mode: int in MatchConfig.SELECTABLE_GAME_MODES:
		_pick_mode(lobby, mode)
		_assert_loop_has_no_invisible_stops(lobby, "mode %d" % mode)


func test_gifts_and_experiments_advanced_blocks_join_the_loop_when_opened() -> void:
	var lobby: Lobby = _make_lobby(true)
	var gifts: UiSection = _section(lobby, "%GiftsSection")
	var experiments: UiSection = _section(lobby, "%ExperimentsSection")
	var checklist: Array[Control] = []
	checklist.append_array(lobby._special_checkboxes)
	assert_gt(checklist.size(), 0, "fixture: the gift checklist exists")
	var experiment_checks: Array[Control] = []
	experiment_checks.append_array(lobby._qol_checks)
	assert_gt(experiment_checks.size(), 0, "fixture: the experiments block has checks")
	var shown: Array[Control] = lobby._visible_chain(lobby._main_chain)
	for control: Control in checklist + experiment_checks:
		assert_false(shown.has(control), "%s is not a stop while its Advanced block is closed" % control.name)
	gifts.advanced_button.button_pressed = true
	experiments.advanced_button.button_pressed = true
	assert_true(experiments.is_advanced_open(), "the EXPERIMENTS chip opens its block")
	shown = lobby._visible_chain(lobby._main_chain)
	for control: Control in checklist + experiment_checks:
		assert_true(shown.has(control), "%s joins the loop once its block is open" % control.name)
	_assert_loop_has_no_invisible_stops(lobby, "GIFTS + EXPERIMENTS open")
	experiments.advanced_button.button_pressed = false
	assert_false(experiments.is_advanced_open())
	for control: Control in experiment_checks:
		assert_false(lobby._visible_chain(lobby._main_chain).has(control), "%s leaves the loop when closed again" % control.name)
	_assert_loop_has_no_invisible_stops(lobby, "EXPERIMENTS closed again")


func test_ui_accept_on_the_experiments_chip_toggles_its_block() -> void:
	var lobby: Lobby = _make_lobby(true)
	var experiments: UiSection = _section(lobby, "%ExperimentsSection")
	experiments.advanced_button.grab_focus()
	assert_true(experiments.advanced_button.has_focus(), "fixture: the chip holds focus")
	Input.parse_input_event(_accept_event(true))
	Input.parse_input_event(_accept_event(false))
	Input.flush_buffered_events()
	await get_tree().process_frame
	assert_true(experiments.is_advanced_open(), "ui_accept on the chip opens the experiments")
	assert_true(lobby._visible_chain(lobby._main_chain).has(lobby.get_node("%QolBacklogCheck")))


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

func test_goal_flags_show_only_in_modes_that_use_them() -> void:
	var lobby: Lobby = _make_lobby(true)
	var goal_col: Control = lobby.get_node("%GoalFlagCol") as Control
	var stepper: Control = lobby._goal_flag_stepper
	for mode: int in MatchConfig.SELECTABLE_GAME_MODES:
		_pick_mode(lobby, mode)
		var expected: bool = MatchConfig.mode_uses_goal_flags(mode)
		assert_eq(goal_col.visible, expected, "goal flags visible for mode %d" % mode)
		assert_eq(lobby._visible_chain(lobby._main_chain).has(stepper), expected, "goal stepper is a stop only when shown (mode %d)" % mode)


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
	assert_eq(stepper.value_label.text, "6.5 s")
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


func test_block_timer_stepper_is_keyboard_and_gamepad_steppable_in_focus_order() -> void:
	var lobby: Lobby = _make_lobby(true)
	var chain: Array[Control] = lobby._visible_chain(lobby._main_chain)
	var sudden: Control = lobby.get_node("%SuddenDeathCheck") as Control
	var stepper: UiStepper = lobby.get_node("%BlockTimerStepper") as UiStepper
	var at: int = chain.find(sudden)
	assert_eq(chain[at + 1], stepper, "the block stepper follows sudden death")
	assert_eq(chain[at + 2], lobby._goal_flag_stepper, "then the goal flags' stepper")
	assert_eq(stepper.focus_mode, Control.FOCUS_ALL)
	stepper.value = roundi(6.0 / Lobby.BLOCK_TIMER_STEP_S)
	stepper.grab_focus()
	# Keyboard / d-pad right (ui_right) steps the focused stepper once.
	stepper._gui_input(_action(&"ui_right", true))
	stepper._gui_input(_action(&"ui_right", false))
	assert_almost_eq(lobby._block_timer_seconds(), 6.5, 0.001, "ui_right steps the block timer once")
	stepper._gui_input(_action(&"ui_left", true))
	stepper._gui_input(_action(&"ui_left", false))
	assert_almost_eq(lobby._block_timer_seconds(), 6.0, 0.001, "ui_left steps it back")


func test_a_client_sees_the_block_timer_but_its_stepper_is_inert() -> void:
	var lobby: Lobby = _make_lobby(false)
	var stepper: UiStepper = lobby.get_node("%BlockTimerStepper") as UiStepper
	assert_true(stepper.disabled, "host-only")
	assert_true(stepper.plus_button.disabled and stepper.minus_button.disabled)
	assert_false(stepper.nudge(1), "a disabled stepper does not move")
	var config: MatchConfig = MatchConfig.new()
	config.block_timer = 10.5
	Events.net_lobby_data_changed.emit(config.to_dict())
	assert_almost_eq(lobby._block_timer_seconds(), 10.5, 0.001, "replicated value arrives")
	assert_eq(stepper.value_label.text, "10.5 s")


func _action(action: StringName, pressed: bool) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


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
	assert_eq((lobby.get_node("%SkyTeamCol") as UiRow).label.text, "Team height: sum of members")


# --- Summaries ----------------------------------------------------------------------------------

func test_headers_summarise_their_section() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game_summary: String = _section(lobby, "%GameSection").get_summary()
	assert_true(game_summary.contains("Classic"), "GAME names the mode")
	assert_true(game_summary.contains("Cycle"), "GAME names the time of day")
	assert_true(game_summary.contains(" · "), "the parts are separated")
	var round_summary: String = _section(lobby, "%RoundSection").get_summary()
	var block_text: String = Lobby.SUMMARY_BLOCK_TIMER_FORMAT % lobby._block_timer_seconds()
	assert_true(round_summary.contains(block_text), "ROUND names the block timer (%s in %s)" % [block_text, round_summary])
	assert_true(round_summary.contains("goal flag"), "Classic shows its goal flags")
	_pick_mode(lobby, MatchConfig.GameMode.ELIMINATION)
	assert_false(_section(lobby, "%RoundSection").get_summary().contains("goal flag"), "no goal flags outside their modes")
	assert_true(_section(lobby, "%GiftsSection").get_summary().begins_with("On"))
	assert_false(_section(lobby, "%GiftsSection").get_summary().contains("gifts"), "all gifts enabled: no count")
	if not lobby._special_checkboxes.is_empty():
		lobby._special_checkboxes[0].button_pressed = false
		var count: String = Lobby.SUMMARY_GIFT_COUNT_FORMAT % [lobby._special_checkboxes.size() - 1, lobby._special_checkboxes.size()]
		assert_true(_section(lobby, "%GiftsSection").get_summary().ends_with(count), "GIFTS names how many gifts are on (%s)" % count)
		lobby._special_checkboxes[0].button_pressed = true
	(lobby.get_node("%GiftsCheck") as UiToggle).button_pressed = false
	assert_eq(_section(lobby, "%GiftsSection").get_summary(), Lobby.SUMMARY_GIFTS_OFF)
	assert_eq(_section(lobby, "%ExperimentsSection").get_summary(), "0 on")
	(lobby.get_node("%QolGoalRadiusCheck") as UiChipToggle).button_pressed = true
	assert_eq(_section(lobby, "%ExperimentsSection").get_summary(), "1 on")


# --- Host edits and client read-only ------------------------------------------------------------

func test_host_edits_every_game_setting_from_the_game_section() -> void:
	var lobby: Lobby = _make_lobby(true)
	_section(lobby, "%GameSection").set_advanced_open(true)
	_pick_mode(lobby, MatchConfig.GameMode.ELIMINATION)
	(lobby.get_node("%DiscSizeMeter") as UiSegmentMeter).value = 6
	var sky: UiDropdown = lobby.get_node("%SkyThemeOption") as UiDropdown
	sky.select(MatchConfig.SkyThemeMode.NIGHT)
	sky.item_selected.emit(MatchConfig.SkyThemeMode.NIGHT)
	var weather: UiDropdown = lobby.get_node("%WeatherOption") as UiDropdown
	weather.select(MatchConfig.WeatherMode.SNOW)
	weather.item_selected.emit(MatchConfig.WeatherMode.SNOW)
	(lobby.get_node("%GravityMeter") as UiSegmentMeter).value = Lobby._gravity_cells_for(0.5)
	(lobby.get_node("%TurnBasedCheck") as UiToggle).button_pressed = true
	var hole: UiDropdown = lobby.get_node("%HoleModeOption") as UiDropdown
	hole.select(MatchConfig.HoleMode.PERMANENT)
	hole.item_selected.emit(MatchConfig.HoleMode.PERMANENT)
	var tilt: UiDropdown = lobby.get_node("%TiltModeOption") as UiDropdown
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


func test_host_edits_every_gift_setting_from_the_gifts_section() -> void:
	var lobby: Lobby = _make_lobby(true)
	(lobby.get_node("%SpecialFreqMeter") as UiSegmentMeter).value = 7
	(lobby.get_node("%GiftsCheck") as UiToggle).button_pressed = false
	var config: MatchConfig = _published(lobby)
	assert_eq(config.special_frequency, 70)
	assert_false(config.gifts_enabled)


func test_host_edits_the_gift_checkboxes_and_experiments_from_their_blocks() -> void:
	var lobby: Lobby = _make_lobby(true)
	_section(lobby, "%GiftsSection").set_advanced_open(true)
	_section(lobby, "%ExperimentsSection").set_advanced_open(true)
	if not lobby._special_checkboxes.is_empty():
		var off_id: StringName = lobby._special_ids[0]
		lobby._special_checkboxes[0].button_pressed = false
		var published: Array[StringName] = _published(lobby).enabled_specials
		assert_false(published.has(off_id), "the unchecked gift is no longer enabled")
	(lobby.get_node("%QolBacklogCheck") as UiChipToggle).button_pressed = true
	assert_true(_published(lobby).qol.backlog_enabled)


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
		elif control is UiSegmentMeter:
			assert_false((control as UiSegmentMeter).editable, "%s is read-only for a client" % unique_name)
		else:
			assert_true((control as BaseButton).disabled, "%s is disabled for a client" % unique_name)
	assert_false(game.advanced_button.disabled, "a client can still open the Advanced block to read it")
	game.advanced_button.button_pressed = true
	assert_true(game.is_advanced_open())
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0, "opening a block publishes nothing")
	_assert_loop_has_no_invisible_stops(lobby, "client")


func test_section_state_is_not_published_or_persisted() -> void:
	var lobby: Lobby = _make_lobby(true)
	var before: int = _fake_of(lobby).set_lobby_data_calls.size()
	_section(lobby, "%GameSection").set_advanced_open(true)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), before, "toggling a section is local UI state")
	var fresh: Lobby = _make_lobby(true)
	assert_false(_section(fresh, "%GameSection").is_advanced_open(), "a new lobby starts collapsed (plan D7)")


# --- Alignment (Bontago-1pi.61) ---------------------------------------------------------------

## Lays the lobby out at a real size so cell rectangles mean something.
func _laid_out_lobby(size: Vector2) -> Lobby:
	var lobby: Lobby = _make_lobby(true)
	lobby.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lobby.size = size
	for section: UiSection in lobby._sections():
		section.set_advanced_open(true)
	await get_tree().process_frame
	await get_tree().process_frame
	return lobby


## The visible UiRows of one block (the Body or the Advanced block of a section).
func _rows_in(block: Control) -> Array[UiRow]:
	var rows: Array[UiRow] = []
	if block == null:
		return rows
	for node: Node in block.find_children("*", "HBoxContainer", true, false):
		var row: UiRow = node as UiRow
		if row != null and row.is_visible_in_tree():
			rows.append(row)
	return rows


## Bontago-1pi.159.2.1: every row's label cell is the one UiRow label width (the Advanced block's
## rows sit one indent in) and every row of a block starts its control column at the same x.
func test_label_and_control_columns_share_one_x_and_width_in_every_block() -> void:
	var lobby: Lobby = await _laid_out_lobby(Vector2(1920, 1080))
	var label_width: float = float(UiRowItem.metrics().row_label_width_px)
	var total: int = 0
	for section: UiSection in lobby._sections():
		for block: Control in [section.body, section.advanced]:
			var label_x: float = NAN
			var control_x: float = NAN
			for row: UiRow in _rows_in(block):
				total += 1
				assert_almost_eq(row.label.size.x, label_width, 0.51, "%s label width" % row.name)
				if is_nan(label_x):
					label_x = row.label.global_position.x
				assert_almost_eq(row.label.global_position.x, label_x, 0.51, "%s label x" % row.name)
				var first: Control = row.get_child(1) as Control
				if is_nan(control_x):
					control_x = first.global_position.x
				assert_almost_eq(first.global_position.x, control_x, 0.51, "%s control column x" % row.name)
	assert_gt(total, 10, "rows found")


## Every row's items share one height (the UiRowItem contract) and never stretch: a toggle, stepper or
## chip keeps its own width, only meters and dropdowns fill the control column.
func test_row_items_share_one_height_and_only_meters_and_dropdowns_stretch() -> void:
	var lobby: Lobby = await _laid_out_lobby(Vector2(1920, 1080))
	var row_height: float = float(UiRowItem.metrics().row_height_px)
	var seen: int = 0
	for section: UiSection in lobby._sections():
		for block: Control in [section.body, section.advanced]:
			for row: UiRow in _rows_in(block):
				for child: Node in row.get_children():
					var item: Control = child as Control
					if item == null or not item.is_in_group(UiRowItem.GROUP) or not item.is_visible_in_tree():
						continue
					seen += 1
					assert_almost_eq(item.size.y, row_height, 0.51, "%s in %s is one row height" % [item.name, row.name])
					if item is UiToggle or item is UiStepper:
						assert_almost_eq(item.size.x, item.get_combined_minimum_size().x, 0.51, "%s keeps its own width" % item.name)
	assert_gt(seen, 10, "row items found")


## Nothing in the settings column is wider than the column: no row overflows its card.
func test_no_settings_row_overflows_the_column() -> void:
	var lobby: Lobby = await _laid_out_lobby(Vector2(1280, 720))
	var column: Control = lobby.get_node("%Settings") as Control
	var right: float = column.global_position.x + column.size.x + 0.51
	for section: UiSection in lobby._sections():
		for block: Control in [section.body, section.advanced]:
			for row: UiRow in _rows_in(block):
				assert_lt(row.global_position.x + row.size.x, right, "%s fits the column" % row.name)
				for child: Node in row.get_children():
					var item: Control = child as Control
					if item != null and item.is_visible_in_tree():
						assert_lt(item.global_position.x + item.size.x, right, "%s fits the column" % item.name)
