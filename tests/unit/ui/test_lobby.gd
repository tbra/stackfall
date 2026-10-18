extends GutTest
## Every spec 1.9 setting round-trips
## through MatchConfig.to_dict() -> Net.set_lobby_data -> Events.
## net_lobby_data_changed -> from_dict -> sanitize(); a client's controls are
## disabled while the host's are not; an out-of-range value arriving over the
## wire is clamped; Start is gated on Net.all_peers_ready().


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


## E1: the roster title row and rows live in the instanced
## ui/lobby/LobbyPlayersPanel.tscn, so %PlayerList and %PlayerCountLabel resolve
## through %PlayersPanel (unique names are scoped to their own scene).
func _panel_of(lobby: Lobby) -> LobbyPlayersPanel:
	return lobby.get_node("%PlayersPanel") as LobbyPlayersPanel


func test_cycle_option_round_trips_through_lobby_data() -> void:
	var lobby: Lobby = _make_lobby(true)
	var option: UiCycler = lobby.get_node("%SkyThemeOption") as UiCycler
	assert_eq(option.get_item_count(), MatchConfig.SkyThemeMode.size())
	assert_eq(option.get_item_text(MatchConfig.SkyThemeMode.CYCLE), "Cycle")
	option.select(MatchConfig.SkyThemeMode.CYCLE)
	lobby._on_option_changed(MatchConfig.SkyThemeMode.CYCLE)
	var published: MatchConfig = MatchConfig.from_dict(_fake_of(lobby).lobby_data_value)
	assert_eq(published.sky_theme_mode, MatchConfig.SkyThemeMode.CYCLE)
	Events.net_lobby_data_changed.emit(published.to_dict())
	assert_eq(option.selected(), MatchConfig.SkyThemeMode.CYCLE)


## this file's own real-gamepad-B tests below route real
## InputEventJoypadButton events through Input.parse_input_event(), which
## flips the Settings autoload's own active_input_device() to DEVICE_GAMEPAD
## as a side effect -- reset it so a later test file in the same run doesn't
## inherit gamepad mode from this one (tests/unit/ui/test_options_menu.gd's own
## after_each() already does this for its own gamepad tests).
func after_each() -> void:
	Settings._input(InputEventKey.new())


func test_host_changing_a_setting_publishes_lobby_data() -> void:
	var lobby: Lobby = _make_lobby(true)
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 6
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	assert_eq(calls.size(), 1)
	assert_eq(int(calls[0].get("player_count")), 6)


## A client's Teams toggle never edits or publishes (host only).
func test_a_client_teams_toggle_is_ignored() -> void:
	var lobby: Lobby = _make_lobby(false)
	_panel_of(lobby).teams_toggled.emit(true)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0)
	assert_eq((lobby.get_node("%TeamModeOption") as OptionButton).selected, MatchConfig.TeamMode.OFF)


## the disc-size meter defaults to medium (step 2, 100%), publishes the chosen
## step and pins the map to Round/Medium; the other map pickers are gone from the card.
## a UiSegmentMeter that lights step + 1 cells.
func test_disc_size_meter_defaults_to_medium_and_publishes_the_step() -> void:
	var lobby: Lobby = _make_lobby(true)
	var meter: UiSegmentMeter = lobby.get_node("%DiscSizeMeter") as UiSegmentMeter
	assert_eq(meter.value, MatchConfig.DISC_SIZE_STEP_DEFAULT + 1)
	assert_eq(meter.step_count, DiscSizeTuning.shared().step_count())
	assert_eq(meter.display_text(), "100%")
	assert_eq(lobby._disc_size_text(), "Medium - 100%")
	meter.value = 1
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	assert_eq(calls.size(), 1)
	assert_eq(int(calls[0].get("disc_size_step")), 0)
	assert_eq(meter.display_text(), "50%")
	assert_eq(lobby._disc_size_text(), "Tiny - 50%")


func test_every_2_8_setting_round_trips_through_to_dict_and_from_dict() -> void:
	var lobby: Lobby = _make_lobby(true)
	var config: MatchConfig = MatchConfig.new()
	config.disc_size_step = 3
	config.player_count = 7
	config.ai_count = 3
	config.ai_difficulty = MatchConfig.AiDifficulty.HARD
	config.team_mode = MatchConfig.TeamMode.TEAMS_2
	config.block_timer = 9.5
	config.gravity_multiplier = 1.25
	config.goal_flag_count = 3
	config.gifts_enabled = false
	config.special_frequency = 80
	config.tilt_mode = MatchConfig.TiltMode.PHYSICAL_BALANCE
	config.hole_mode = MatchConfig.HoleMode.PERMANENT
	config.match_timer_minutes = 20
	config.sudden_death = true
	config.turn_based = true
	config.sky_theme_mode = MatchConfig.SkyThemeMode.NIGHT

	Events.net_lobby_data_changed.emit(config.to_dict())
	assert_eq((lobby.get_node("%SkyThemeOption") as UiCycler).selected(), int(MatchConfig.SkyThemeMode.NIGHT))

	assert_eq(int((lobby.get_node("%PlayerCountSpin") as SpinBox).value), 7)
	assert_eq(int((lobby.get_node("%AiCountSpin") as SpinBox).value), 3)
	assert_eq((lobby.get_node("%AiDifficultyOption") as UiCycler).selected(), MatchConfig.AiDifficulty.HARD)
	assert_eq((lobby.get_node("%TeamModeOption") as OptionButton).selected, MatchConfig.TeamMode.TEAMS_2)
	assert_almost_eq(lobby._block_timer_seconds(), 9.5, 0.01)
	assert_almost_eq(lobby._gravity_value, 1.25, 0.01)
	assert_eq((lobby.get_node("%GravityMeter") as UiSegmentMeter).value, Lobby._gravity_cells_for(1.25))
	assert_eq((lobby.get_node("%GoalFlagStepper") as UiStepper).value, 3)
	assert_false((lobby.get_node("%GiftsCheck") as UiToggle).button_pressed)
	assert_eq(lobby._special_frequency_value, 80)
	assert_eq((lobby.get_node("%SpecialFreqMeter") as UiSegmentMeter).value, 8)
	assert_eq((lobby.get_node("%TiltModeOption") as UiCycler).selected(), MatchConfig.TiltMode.PHYSICAL_BALANCE)
	assert_eq((lobby.get_node("%HoleModeOption") as UiCycler).selected(), MatchConfig.HoleMode.PERMANENT)
	assert_eq((lobby.get_node("%MatchTimerStepper") as UiStepper).value, 20)
	assert_true((lobby.get_node("%SuddenDeathCheck") as UiToggle).button_pressed)
	assert_true((lobby.get_node("%TurnBasedCheck") as UiToggle).button_pressed)


func test_out_of_range_value_arriving_over_the_wire_is_clamped() -> void:
	var lobby: Lobby = _make_lobby(false)
	var bad_data: Dictionary = {
		"player_count": 999,
		"block_timer": -5.0,
		"special_frequency": 500,
		"goal_flag_count": 0,
	}
	Events.net_lobby_data_changed.emit(bad_data)
	assert_eq(int((lobby.get_node("%PlayerCountSpin") as SpinBox).value), MatchConfig.PLAYER_COUNT_MAX)
	assert_almost_eq(lobby._block_timer_seconds(), MatchConfig.BLOCK_TIMER_MIN, 0.01)
	assert_eq(lobby._special_frequency_value, MatchConfig.SPECIAL_FREQUENCY_MAX)
	assert_eq((lobby.get_node("%SpecialFreqMeter") as UiSegmentMeter).value, Lobby.FREQUENCY_CELLS)
	assert_eq((lobby.get_node("%GoalFlagStepper") as UiStepper).value, MatchConfig.GOAL_FLAG_MIN)


func test_applying_remote_data_does_not_republish() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.set_lobby_data_calls.clear()
	Events.net_lobby_data_changed.emit(MatchConfig.new().to_dict())
	assert_eq(fake.set_lobby_data_calls.size(), 0, "an inbound update must not bounce straight back out")


# --- Host vs client gating ----------------------------------------------------

func test_client_controls_are_disabled_while_hosts_are_not() -> void:
	var host_lobby: Lobby = _make_lobby(true)
	var client_lobby: Lobby = _make_lobby(false)
	assert_true((host_lobby.get_node("%PlayerCountSpin") as SpinBox).editable)
	assert_false((client_lobby.get_node("%PlayerCountSpin") as SpinBox).editable)
	assert_true((client_lobby.get_node("%GiftsCheck") as UiToggle).disabled)
	assert_false((host_lobby.get_node("%GiftsCheck") as UiToggle).disabled)


func test_start_pressed_emits_start_requested_only_when_ready() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.all_peers_ready_value = false
	watch_signals(lobby)
	lobby._on_start_pressed()
	assert_signal_not_emitted(lobby, "start_requested")
	fake.all_peers_ready_value = true
	lobby._on_start_pressed()
	assert_signal_emitted(lobby, "start_requested")


## config/match/match_defaults.tres ships player_count = 4, but a
## slot with no connected peer still runs a feed timer (autoload/Match.gd's
## _tick_feed) and auto-drops a block at its home flag forever -- read by a
## player as a phantom opponent taking turns. Windowed repro: host + one
## client, default settings, Start pressed with no edits -- the host's own
## territory HUD showed P1..P4 bars although only two slots had a human
## behind them.
func test_start_clamps_player_count_to_connected_peers() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.all_peers_ready_value = true
	fake.slots_by_peer = {1: 0, 2: 1}  # host + exactly one connected client
	watch_signals(lobby)

	lobby._on_start_pressed()

	assert_signal_emitted(lobby, "start_requested")
	var config: MatchConfig = get_signal_parameters(lobby, "start_requested")[0]
	assert_eq(config.player_count, 2, "no slot may be left without a connected peer")
	assert_eq(config.ai_count, 0, "match_defaults.tres ships ai_count = 0, so no bots were requested")


## The host's own outbound
## LobbyPlayersPanel.build_roster() must append one synthetic row per bot seat -- slot_id
## running from player_count - ai_count up, matching autoload/match/
## MatchLifecycle.gd's _build_slots() formula for PlayerSlot.is_bot -- so the
## lobby preview and the eventual real match slots never disagree about
## which ids are bots.
func test_build_roster_appends_bot_rows_for_ai_count() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.slots_by_peer = {1: 0, 2: 1, 3: 2, 4: 3}  # 4 connected peers
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 6
	(lobby.get_node("%AiCountSpin") as SpinBox).value = 2

	var calls: Array[Dictionary] = fake.set_lobby_data_calls
	var roster: Array = calls[calls.size() - 1].get("roster") as Array
	assert_eq(roster.size(), 6, "4 connected peers + 2 bot seats")
	var bot_one: Dictionary = roster[4] as Dictionary
	var bot_two: Dictionary = roster[5] as Dictionary
	assert_eq(int(bot_one.get("slot_id")), 4)
	assert_eq(int(bot_two.get("slot_id")), 5)
	# each bot carries the host-assigned themed name, also in bot_names.
	var names: Array = calls[calls.size() - 1].get("bot_names") as Array
	assert_eq(names.size(), 2)
	assert_ne(names[0], names[1])
	assert_eq(str(bot_one.get("name")), "%s (Normal)" % names[0])
	assert_eq(str(bot_two.get("name")), "%s (Normal)" % names[1])
	assert_true(bool(bot_one.get("ready")))
	assert_true(bool(bot_two.get("ready")))


## .9b: -- "I can add bots up to the player limit"
## -- nothing previously stopped ai_count + connected humans from exceeding
## player_count. %AiCountSpin's own max_value must track the empty-seat count
## (seats - humans) and clamp an already-too-high value down to it.
func test_ai_count_spin_clamps_to_seats_minus_connected_humans() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.slots_by_peer = {1: 0, 2: 1, 3: 2, 4: 3}  # 4 connected humans
	var ai_spin: SpinBox = lobby.get_node("%AiCountSpin")
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 8
	ai_spin.value = 6  # only 4 empty seats exist (8 seats - 4 humans)

	assert_eq(int(ai_spin.max_value), 4, "8 seats - 4 connected humans = 4 empty seats for bots")
	assert_eq(int(ai_spin.value), 4, "an over-large request clamps down to the room actually left")

	# A 5th human joining shrinks the room left for the existing bots too.
	fake.slots_by_peer[5] = 4
	var roster: Array[Dictionary] = []
	for peer_id: int in fake.slots_by_peer.keys():
		roster.append({"peer_id": peer_id, "slot_id": int(fake.slots_by_peer[peer_id]), "name": "P", "ready": true})
	Events.net_roster_changed.emit(roster)

	assert_eq(int(ai_spin.max_value), 3, "a 5th human leaves only 3 empty seats of 8")
	assert_eq(int(ai_spin.value), 3, "the existing 4 bots shrink to fit the now-smaller headroom")


# --- Invite Friends -------------------------------------

func test_unchecking_one_special_and_publishing_removes_exactly_that_id() -> void:
	var lobby: Lobby = _make_lobby(true)
	if lobby._special_checkboxes.size() < 2:
		pass_test("fewer than 2 SpecialDef .tres on disk in this checkout; nothing to distinguish")
		return
	var unchecked_id: StringName = lobby._special_ids[0]
	lobby._special_checkboxes[0].button_pressed = false

	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	assert_eq(calls.size(), 1)
	var published: Array = calls[0].get("enabled_specials") as Array
	assert_false(published.has(unchecked_id), "the unchecked id must be gone")
	for i: int in range(1, lobby._special_ids.size()):
		assert_true(published.has(lobby._special_ids[i]), "every still-checked id must remain")
	assert_eq(published.size(), lobby._special_ids.size() - 1)


func test_unchecking_every_special_publishes_the_sentinel_not_an_empty_array() -> void:
	var lobby: Lobby = _make_lobby(true)
	if lobby._special_checkboxes.is_empty():
		pass_test("no SpecialDef .tres on disk in this checkout; nothing to uncheck")
		return
	for box: UiChipToggle in lobby._special_checkboxes:
		box.button_pressed = false

	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	var published: Array = calls[calls.size() - 1].get("enabled_specials") as Array
	assert_eq(published.size(), 1)
	assert_eq(published[0], Lobby.ALL_DISABLED_SENTINEL)


## S1b: ui_cancel backs out of the lobby (synthetic action through
## _unhandled_input(), the way Esc would reach it) -- the popup case is gone.
func test_ui_cancel_backs_out_of_the_lobby() -> void:
	var lobby: Lobby = _make_lobby(true)
	watch_signals(lobby)
	var event: InputEventAction = InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	lobby._unhandled_input(event)
	assert_signal_emitted(lobby, "back_requested")


# --- Gamepad parity ("gamepad works in some menus but not
# all; B never goes back in any menu") ------------------------------------------
#
# Real InputEventJoypadButton, checked against the real InputMap via the
# event's own is_action_pressed() (not a synthetic InputEventAction) -- proves
# tools/bootstrap_project.gd's ui_cancel gamepad-B binding actually reaches
# this screen, the same real-binding technique test_pause_menu.gd's own
# _pad_press()/test_gamepad_start_toggles_visibility() already uses.

func _pad_press_release_action_event(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	event.pressed = true
	return event


func test_focus_chain_is_a_closed_loop_through_every_row() -> void:
	# ui/lobby/Lobby.tscn (unlike ui/menus/OptionsMenu.tscn) carries no static
	# focus_neighbor_* NodePaths -- _wire_focus_chain() builds the chain at
	# runtime once the dynamic specials checklist exists. Mirror
	# test_options_menu.gd's test_focus_chain_is_a_closed_loop_through_every_row().
	var lobby: Lobby = _make_lobby(true)

	var start_button: Control = lobby.get_node("%StartButton") as Control
	# section headers are static; the loop starts at the GAME mode.
	var first_stop: Control = lobby.get_node("%GameModeOption") as Control
	var start_bottom: Node = start_button.get_node(start_button.focus_neighbor_bottom)
	assert_eq(start_bottom, first_stop, "the chain must wrap from StartButton back to the game mode")

	var top_neighbor: Node = first_stop.get_node(first_stop.focus_neighbor_top)
	assert_eq(top_neighbor, start_button, "the game mode's up neighbor must close the loop back to StartButton")
	var second_option: Control = lobby.get_node("%DiscSizeMeter") as Control
	assert_eq(first_stop.get_node(first_stop.focus_neighbor_bottom), second_option, "the map picker follows the mode picker")

	# S1b: the hidden sources of truth (%TeamModeOption, the seat spins and
	# the default-difficulty dropdown, plus the map variant/size options behind the combined
	# map dropdown) are never stops a Tab press could not visibly land on. Collapsed Advanced
	# blocks and the hidden Steam-only invite button are not stops either.
	var chain_unique_names: Array[String] = [
		"%DiscSizeMeter", "%GameModeOption", "%SkyThemeOption", "%WeatherOption",
		"%MatchTimerStepper", "%SuddenDeathCheck",
		"%GiftsCheck", "%SpecialFreqMeter", "%StartButton",
	]
	for unique_name: String in chain_unique_names:
		var control: Control = lobby.get_node(unique_name) as Control
		assert_ne(control.focus_neighbor_top, NodePath(""), "%s must have an up neighbor" % unique_name)
		assert_ne(control.focus_neighbor_bottom, NodePath(""), "%s must have a down neighbor" % unique_name)
	for stepper: Control in [lobby._block_timer_stepper, lobby._goal_flag_stepper]:
		assert_ne(stepper.focus_neighbor_bottom, NodePath(""), "stepper %s must have a down neighbor" % stepper.name)
	# Opening the GAME Advanced block puts its controls in the loop.
	(lobby.get_node("%GameSection") as UiSection).set_advanced_open(true)
	for unique_name: String in ["%GravityMeter", "%TiltModeOption", "%HoleModeOption", "%TurnBasedCheck", "%MidJoinCheck"]:
		var control: Control = lobby.get_node(unique_name) as Control
		assert_ne(control.focus_neighbor_top, NodePath(""), "%s must have an up neighbor once opened" % unique_name)
		assert_ne(control.focus_neighbor_bottom, NodePath(""), "%s must have a down neighbor once opened" % unique_name)

	assert_false((lobby.get_node("%TeamModeOption") as Control).is_visible_in_tree(), "TeamModeOption stays a hidden source of truth (teams are toggled in the players panel)")

	# ... and so do the GIFTS Advanced (per-gift) and EXPERIMENTS blocks once opened.
	(lobby.get_node("%GiftsSection") as UiSection).set_advanced_open(true)
	var opened: Array[Control] = []
	opened.append_array(lobby._special_checkboxes)
	opened.append_array(lobby._qol_checks)
	for control: Control in opened:
		assert_ne(control.focus_neighbor_top, NodePath(""), "%s must have an up neighbor once opened" % control.name)
		assert_ne(control.focus_neighbor_bottom, NodePath(""), "%s must have a down neighbor once opened" % control.name)


## X / keyboard X (lobby_add_bot) adds a bot for the host while a seat is free,
## never starts the match, and does nothing for a client or a full lobby.
func test_lobby_add_bot_shortcut_adds_a_bot_for_the_host_only() -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = "lobby_add_bot"
	event.pressed = true
	var host: Lobby = _make_lobby(true)
	_fake_of(host).all_peers_ready_value = true
	host._update_host_only_state()
	watch_signals(host)
	var before: int = int(host._ai_count_spin.value)
	host._unhandled_input(event)
	assert_eq(int(host._ai_count_spin.value), before + 1, "X adds a bot")
	assert_signal_not_emitted(host, "start_requested", "X no longer starts the match")
	host._set_bot_count(MatchConfig.PLAYER_COUNT_MAX)
	var full: int = int(host._ai_count_spin.value)
	host._players_panel._refresh_header()
	host._unhandled_input(event)
	assert_eq(int(host._ai_count_spin.value), full, "a full lobby ignores X")
	var client: Lobby = _make_lobby(false)
	var client_before: int = int(client._ai_count_spin.value)
	client._unhandled_input(event)
	assert_eq(int(client._ai_count_spin.value), client_before, "a client ignores X")


func test_real_gamepad_x_y_trigger_lobby_shortcuts() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.all_peers_ready_value = true
	lobby._update_host_only_state()
	watch_signals(lobby)
	var game: UiSection = lobby.get_node("%GameSection") as UiSection
	var y_event: InputEventJoypadButton = _pad_press_release_action_event(JOY_BUTTON_Y)
	assert_true(y_event.is_action_pressed(&"lobby_quick_advanced"))
	lobby._unhandled_input(y_event)
	assert_true(game.advanced.visible, "pad Y opens the focused section's Advanced block")
	lobby._unhandled_input(y_event)
	assert_false(game.advanced.visible, "a second pad Y closes it")
	var x_event: InputEventJoypadButton = _pad_press_release_action_event(JOY_BUTTON_X)
	assert_true(x_event.is_action_pressed(&"lobby_add_bot"))
	var bots_before: int = int(lobby._ai_count_spin.value)
	lobby._unhandled_input(x_event)
	assert_eq(int(lobby._ai_count_spin.value), bots_before + 1, "pad X adds a bot")
	assert_signal_not_emitted(lobby, "start_requested")
	var start_event: InputEventJoypadButton = _pad_press_release_action_event(JOY_BUTTON_START)
	assert_true(start_event.is_action_pressed(&"lobby_confirm"))
	lobby._input(start_event)
	assert_signal_emitted(lobby, "start_requested")
