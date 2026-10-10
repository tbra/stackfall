extends GutTest
## docs/archive/M3a_PLAN.md P4 "Tests first": every spec 2.8 setting round-trips
## through MatchConfig.to_dict() -> Net.set_lobby_data -> Events.
## net_lobby_data_changed -> from_dict -> sanitize(); a client's controls are
## disabled while the host's are not; an out-of-range value arriving over the
## wire is clamped; Start is gated on Net.all_peers_ready().


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


## Bontago-1pi.53 (E1): the roster title row and rows live in the instanced
## ui/lobby/LobbyPlayersPanel.tscn, so %PlayerList and %PlayerCountLabel resolve
## through %PlayersPanel (unique names are scoped to their own scene).
func _panel_of(lobby: Lobby) -> LobbyPlayersPanel:
	return lobby.get_node("%PlayersPanel") as LobbyPlayersPanel


func _player_list(lobby: Lobby) -> VBoxContainer:
	return _panel_of(lobby).get_node("%PlayerList") as VBoxContainer


func _count_label(lobby: Lobby) -> Label:
	return _panel_of(lobby).get_node("%PlayerCountLabel") as Label


func test_cycle_option_round_trips_through_lobby_data() -> void:
	var lobby: Lobby = _make_lobby(true)
	var option: UiDropdown = lobby.get_node("%SkyThemeOption") as UiDropdown
	assert_eq(option.item_count, MatchConfig.SkyThemeMode.size())
	assert_eq(option.get_item_text(MatchConfig.SkyThemeMode.CYCLE), "Cycle")
	option.select(MatchConfig.SkyThemeMode.CYCLE)
	lobby._on_option_changed(MatchConfig.SkyThemeMode.CYCLE)
	var published: MatchConfig = MatchConfig.from_dict(_fake_of(lobby).lobby_data_value)
	assert_eq(published.sky_theme_mode, MatchConfig.SkyThemeMode.CYCLE)
	Events.net_lobby_data_changed.emit(published.to_dict())
	assert_eq(option.selected, MatchConfig.SkyThemeMode.CYCLE)


## Bontago-59o.18 (U1): DAY is the cycle locked at sunset, so it reads "Sunset";
## the list keeps the enum index order (stored ints and the wire format are
## unchanged) and Cycle is preselected through MatchConfig's new default.
func test_sky_options_are_relabelled_and_cycle_is_the_default() -> void:
	var lobby: Lobby = _make_lobby(true)
	var option: UiDropdown = lobby.get_node("%SkyThemeOption") as UiDropdown
	assert_eq(option.item_count, MatchConfig.SkyThemeMode.size())
	assert_eq(option.get_item_text(MatchConfig.SkyThemeMode.DAY), "Sunset")
	assert_eq(option.get_item_text(MatchConfig.SkyThemeMode.NIGHT), "Night")
	assert_eq(option.get_item_text(MatchConfig.SkyThemeMode.RANDOM), "Random")
	assert_eq(option.get_item_text(MatchConfig.SkyThemeMode.CYCLE), "Cycle")
	assert_eq(option.get_item_text(MatchConfig.SkyThemeMode.DAWN), "Dawn")
	assert_eq(option.selected, int(MatchConfig.SkyThemeMode.CYCLE), "a fresh lobby opens on Cycle")
	assert_eq(lobby.default_config.sky_theme_mode, MatchConfig.SkyThemeMode.CYCLE)
	lobby._on_option_changed(option.selected)
	var published: MatchConfig = MatchConfig.from_dict(_fake_of(lobby).lobby_data_value)
	assert_eq(published.sky_theme_mode, MatchConfig.SkyThemeMode.CYCLE, "the default is what the host publishes")


func test_sky_option_tooltips_explain_locked_time_versus_running_cycle() -> void:
	var lobby: Lobby = _make_lobby(true)
	var option: UiDropdown = lobby.get_node("%SkyThemeOption") as UiDropdown
	assert_true(option.tooltip_text.contains("fixed time"), "the dropdown says the non-cycle options hold one time")
	assert_true(option.tooltip_text.contains("Cycle runs"))
	for mode: int in [MatchConfig.SkyThemeMode.DAY, MatchConfig.SkyThemeMode.NIGHT, MatchConfig.SkyThemeMode.DAWN, MatchConfig.SkyThemeMode.RANDOM]:
		assert_true(option.get_item_tooltip(mode).begins_with("Locked time"), "%s is a locked time" % option.get_item_text(mode))
	assert_true(option.get_item_tooltip(MatchConfig.SkyThemeMode.CYCLE).begins_with("Running cycle"))


func test_sunset_option_keeps_the_day_enum_value_through_lobby_data() -> void:
	var lobby: Lobby = _make_lobby(true)
	var option: UiDropdown = lobby.get_node("%SkyThemeOption") as UiDropdown
	option.select(MatchConfig.SkyThemeMode.DAY)
	lobby._on_option_changed(MatchConfig.SkyThemeMode.DAY)
	var published: MatchConfig = MatchConfig.from_dict(_fake_of(lobby).lobby_data_value)
	assert_eq(published.sky_theme_mode, MatchConfig.SkyThemeMode.DAY, "Sunset is still enum DAY (0)")
	Events.net_lobby_data_changed.emit(published.to_dict())
	assert_eq(option.selected, MatchConfig.SkyThemeMode.DAY)
	assert_eq(option.get_item_text(option.selected), "Sunset")


func test_dawn_option_round_trips_through_lobby_data() -> void:
	var lobby: Lobby = _make_lobby(true)
	var option: UiDropdown = lobby.get_node("%SkyThemeOption") as UiDropdown
	assert_eq(option.item_count, MatchConfig.SkyThemeMode.size())
	assert_eq(option.get_item_text(MatchConfig.SkyThemeMode.DAWN), "Dawn")
	option.select(MatchConfig.SkyThemeMode.DAWN)
	lobby._on_option_changed(MatchConfig.SkyThemeMode.DAWN)
	var published: MatchConfig = MatchConfig.from_dict(_fake_of(lobby).lobby_data_value)
	assert_eq(published.sky_theme_mode, MatchConfig.SkyThemeMode.DAWN)
	Events.net_lobby_data_changed.emit(published.to_dict())
	assert_eq(option.selected, MatchConfig.SkyThemeMode.DAWN)


## Bontago-1pi.15.1: this file's own real-gamepad-B tests below route real
## InputEventJoypadButton events through Input.parse_input_event(), which
## flips the Settings autoload's own active_input_device() to DEVICE_GAMEPAD
## as a side effect -- reset it so a later test file in the same run doesn't
## inherit gamepad mode from this one (tests/unit/test_options_menu.gd's own
## after_each() already does this for its own gamepad tests).
func after_each() -> void:
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


## Bontago-mp0.3.5 (review r2, item 4): walks a player-row PanelContainer
## (ui/lobby/LobbyPlayersPanel.gd's _build_player_row()) down to its Ready/Not ready badge
## Label -- layout is the row's only child, the badge is layout's 3rd child
## (icon, text_column, badge), and the Label is the badge's own only child.
func _row_badge_label(row: PanelContainer) -> Label:
	var layout: HBoxContainer = row.get_child(0) as HBoxContainer
	var badge: PanelContainer = layout.get_child(2) as PanelContainer
	return badge.get_child(0) as Label


# --- Round trip ----------------------------------------------------------------

func test_host_changing_a_setting_publishes_lobby_data() -> void:
	var lobby: Lobby = _make_lobby(true)
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 6
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	assert_eq(calls.size(), 1)
	assert_eq(int(calls[0].get("player_count")), 6)


## Bontago-1pi.53 (S1b): the segmented Teams control left the settings card; the players
## panel's Teams toggle (signal teams_toggled) writes OFF / TEAMS_4 into the hidden
## %TeamModeOption and publishes exactly like any other host edit (_on_teams_toggled()).
func test_host_toggling_teams_publishes_lobby_data() -> void:
	var lobby: Lobby = _make_lobby(true)
	_panel_of(lobby).teams_toggled.emit(true)
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	assert_eq(calls.size(), 1)
	assert_eq(int(calls[0].get("team_mode")), MatchConfig.TeamMode.TEAMS_4)
	assert_eq((lobby.get_node("%TeamModeOption") as OptionButton).selected, MatchConfig.TeamMode.TEAMS_4)
	_panel_of(lobby).teams_toggled.emit(false)
	assert_eq(calls.size(), 2)
	assert_eq(int(calls[1].get("team_mode")), MatchConfig.TeamMode.OFF)


## A client's Teams toggle never edits or publishes (host only).
func test_a_client_teams_toggle_is_ignored() -> void:
	var lobby: Lobby = _make_lobby(false)
	_panel_of(lobby).teams_toggled.emit(true)
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0)
	assert_eq((lobby.get_node("%TeamModeOption") as OptionButton).selected, MatchConfig.TeamMode.OFF)


## Bontago-1pi.107: the disc-size meter defaults to medium (step 2, 100%), publishes the chosen
## step and pins the map to Round/Medium; the other map pickers are gone from the card.
## Bontago-1pi.159.2.1: a UiSegmentMeter that lights step + 1 cells.
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
	assert_eq(int(calls[0].get("map_variant")), MatchConfig.MapVariant.ROUND)
	assert_eq(int(calls[0].get("map_size")), int(MapDef.MapSize.MEDIUM))
	assert_eq(meter.display_text(), "50%")
	assert_eq(lobby._disc_size_text(), "Tiny - 50%")


## An empty meter is not a size: 0 cells settles on the smallest size (one lit cell).
func test_disc_size_meter_never_rests_on_zero_cells() -> void:
	var lobby: Lobby = _make_lobby(true)
	var meter: UiSegmentMeter = lobby.get_node("%DiscSizeMeter") as UiSegmentMeter
	meter.value = 0
	assert_eq(meter.value, 1)
	assert_eq(int(_fake_of(lobby).set_lobby_data_calls.back().get("disc_size_step")), 0)


## Keyboard / gamepad left-right on the focused meter steps it one cell; a client's is inert.
func test_disc_size_meter_steps_with_ui_left_and_right() -> void:
	var lobby: Lobby = _make_lobby(true)
	var meter: UiSegmentMeter = lobby.get_node("%DiscSizeMeter") as UiSegmentMeter
	var right: InputEventAction = InputEventAction.new()
	right.action = &"ui_right"
	right.pressed = true
	meter._gui_input(right)
	assert_eq(meter.value, MatchConfig.DISC_SIZE_STEP_DEFAULT + 2)
	var left: InputEventAction = InputEventAction.new()
	left.action = &"ui_left"
	left.pressed = true
	meter._gui_input(left)
	meter._gui_input(left)
	assert_eq(meter.value, MatchConfig.DISC_SIZE_STEP_DEFAULT)
	var client: Lobby = _make_lobby(false)
	var client_meter: UiSegmentMeter = client.get_node("%DiscSizeMeter") as UiSegmentMeter
	assert_false(client_meter.editable)
	client_meter._gui_input(right)
	assert_eq(client_meter.value, MatchConfig.DISC_SIZE_STEP_DEFAULT + 1)


## Bontago-1pi.152 / 159.2.1: one ui_right press on the match-timer stepper is one minute step (the
## 1-minute gap is skipped, so Off -> 2), however long the stick ramps afterwards.
func test_match_timer_stepper_one_press_is_one_step() -> void:
	var lobby: Lobby = _make_lobby(true)
	var stepper: UiStepper = lobby.get_node("%MatchTimerStepper") as UiStepper
	var before: int = stepper.value
	var press: InputEventAction = InputEventAction.new()
	press.action = &"ui_right"
	press.pressed = true
	stepper.grab_focus()
	stepper._gui_input(press)
	# One press = one step; the 1-minute gap is skipped by _on_timer_stepper_changed, so at most +2.
	assert_between(stepper.value, before + stepper.step, before + 2 * stepper.step)


func test_remote_lobby_data_moves_the_disc_size_meter() -> void:
	var lobby: Lobby = _make_lobby(false)
	var config: MatchConfig = MatchConfig.new()
	config.disc_size_step = 5
	lobby._apply_data(config.to_dict())
	assert_eq((lobby.get_node("%DiscSizeMeter") as UiSegmentMeter).value, 6)
	assert_eq(lobby._disc_size_text(), "Enormous - 175%")


## Bontago-mp0.3.5 (review r1, item 12): Net.host_game() populates its own
## HOST_PEER_ID entry directly and only emits net_mode_changed (not
## net_roster_changed / a lobby-data publish), so a Lobby opened right after
## hosting used to sit at "0 / N" with no rows until a second peer actually
## joined. ui/Lobby.gd's _ready() now calls _republish_roster_if_host() once
## on its own -- this test drives that exact call against a FakeNet standing
## in for a freshly hosted, peerless-so-far session (the host's own peer_id
## already in slots_by_peer, matching Net.host_game()'s own _peers seed).
func test_republish_roster_if_host_draws_the_hosts_own_row_with_no_other_peers() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.slots_by_peer = {1: 0}
	fake.names_by_peer = {1: "Mira"}
	lobby._republish_roster_if_host()
	var list: VBoxContainer = _player_list(lobby)
	assert_eq(_panel_of(lobby)._player_rows.size(), 1, "the host's own row must appear without waiting for a second peer")
	var count_label: Label = _count_label(lobby)
	# Bontago-1pi.9b: the roster header's new "N players * H/S seats" format
	# (LobbyPlayersPanel.format_roster_header()) replaces the old bare "N / S".
	assert_true(count_label.text.begins_with("1 player "), count_label.text)


func test_every_2_8_setting_round_trips_through_to_dict_and_from_dict() -> void:
	var lobby: Lobby = _make_lobby(true)
	var config: MatchConfig = MatchConfig.new()
	config.map_variant = MatchConfig.MapVariant.ROUND
	config.map_size = MapDef.MapSize.LARGE
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
	assert_eq((lobby.get_node("%SkyThemeOption") as UiDropdown).selected, int(MatchConfig.SkyThemeMode.NIGHT))

	assert_eq((lobby.get_node("%MapVariantOption") as OptionButton).selected, MatchConfig.MapVariant.ROUND)
	assert_eq((lobby.get_node("%MapSizeOption") as OptionButton).selected, int(MapDef.MapSize.LARGE))
	assert_eq(int((lobby.get_node("%PlayerCountSpin") as SpinBox).value), 7)
	assert_eq(int((lobby.get_node("%AiCountSpin") as SpinBox).value), 3)
	assert_eq((lobby.get_node("%AiDifficultyOption") as OptionButton).selected, MatchConfig.AiDifficulty.HARD)
	assert_eq((lobby.get_node("%TeamModeOption") as OptionButton).selected, MatchConfig.TeamMode.TEAMS_2)
	assert_almost_eq(lobby._block_timer_seconds(), 9.5, 0.01)
	assert_almost_eq(lobby._gravity_value, 1.25, 0.01)
	assert_eq((lobby.get_node("%GravityMeter") as UiSegmentMeter).value, Lobby._gravity_cells_for(1.25))
	assert_eq((lobby.get_node("%GoalFlagStepper") as UiStepper).value, 3)
	assert_false((lobby.get_node("%GiftsCheck") as UiToggle).button_pressed)
	assert_eq(lobby._special_frequency_value, 80)
	assert_eq((lobby.get_node("%SpecialFreqMeter") as UiSegmentMeter).value, 8)
	assert_eq((lobby.get_node("%TiltModeOption") as UiDropdown).selected, MatchConfig.TiltMode.PHYSICAL_BALANCE)
	assert_eq((lobby.get_node("%HoleModeOption") as UiDropdown).selected, MatchConfig.HoleMode.PERMANENT)
	assert_eq((lobby.get_node("%MatchTimerStepper") as UiStepper).value, 20)
	assert_true((lobby.get_node("%SuddenDeathCheck") as UiToggle).button_pressed)
	assert_true((lobby.get_node("%TurnBasedCheck") as UiToggle).button_pressed)


func test_toggling_turn_based_check_publishes_config_turn_based_true() -> void:
	var lobby: Lobby = _make_lobby(true)
	var check: UiToggle = lobby.get_node("%TurnBasedCheck") as UiToggle
	check.button_pressed = true
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	assert_eq(calls.size(), 1)
	assert_true(bool(calls[0].get("turn_based")))


func test_apply_data_with_turn_based_true_checks_the_box() -> void:
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["turn_based"] = true

	Events.net_lobby_data_changed.emit(data)

	assert_true((lobby.get_node("%TurnBasedCheck") as UiToggle).button_pressed)


func test_mid_join_toggle_defaults_to_the_config_default() -> void:
	var lobby: Lobby = _make_lobby(true)
	var check: UiToggle = lobby.get_node("%MidJoinCheck") as UiToggle
	assert_eq(check.button_pressed, MatchConfig.new().allow_mid_match_join)


func test_toggling_mid_join_check_writes_and_publishes_the_config_field() -> void:
	var lobby: Lobby = _make_lobby(true)
	var check: UiToggle = lobby.get_node("%MidJoinCheck") as UiToggle
	assert_false(check.disabled, "the host can change it")
	check.button_pressed = true
	assert_true(lobby._config_from_controls().allow_mid_match_join)
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	assert_eq(calls.size(), 1)
	assert_true(bool(calls[0].get("allow_mid_match_join")))


func test_client_sees_the_hosts_mid_join_value_read_only() -> void:
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["allow_mid_match_join"] = true
	Events.net_lobby_data_changed.emit(data)
	var check: UiToggle = lobby.get_node("%MidJoinCheck") as UiToggle
	assert_true(check.button_pressed)
	assert_true(check.disabled, "a client cannot change it")
	check.button_pressed = false
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0, "a client edit never publishes")


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


## Bontago-mv0.7 (root cause): config/match_defaults.tres ships hot_seat =
## true (M2's own hot-seat default), and _ready()'s first _apply_data() call
## feeds it that Dictionary verbatim -- before a host ever touches a setting
## control and reaches _config_from_controls()'s own hot_seat = false
## override. A host who presses Start without editing anything used to send
## hot_seat = true into Match.start_match(), which then ran strict
## single-active-slot turn alternation across a real-time networked match
## (windowed repro: the HUD's turn banner cycled through every slot on both
## the host and the client, and the host's own clicks were refused
## REASON_NOT_YOUR_TURN -- read by the owner as "player 1 doesn't work").
func test_default_lobby_data_is_never_hot_seat() -> void:
	var lobby: Lobby = _make_lobby(true)
	assert_false(lobby._last_config.hot_seat, "the lobby is reachable only for networked play")


func test_a_config_that_arrives_with_hot_seat_true_is_forced_false() -> void:
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["hot_seat"] = true

	Events.net_lobby_data_changed.emit(data)

	assert_false(lobby._last_config.hot_seat, "no config this screen shows may ever be hot-seat")
## Territory v2 (docs/TERRITORY_V2_PLAN.md) added MatchConfig.HoleMode.OFF
## (= 2) as the optional no-overlap mode. HoleModeOption must carry a third
## item ("Off") so OptionButton.selected can round-trip it even though it is
## no longer the default (Bontago-cmc.7 reverted the default to TEMPORARY,
## per SPEC.md's 2026-09-20 evidence audit); on a 2-item list, `.selected = 2`
## would be silently ignored and the control would stick on index 0.
func test_hole_mode_option_has_an_off_item_and_defaults_to_temporary() -> void:
	var lobby: Lobby = _make_lobby(true)
	var option: UiDropdown = lobby.get_node("%HoleModeOption") as UiDropdown
	assert_eq(option.item_count, 3, "Temporary/Permanent/Off")
	assert_eq(option.get_item_text(MatchConfig.HoleMode.OFF), "Off")
	assert_eq(option.selected, MatchConfig.HoleMode.TEMPORARY,
		"Bontago-cmc.7: the default MatchConfig.hole_mode is TEMPORARY again.")


## Bontago-cmc.4 (found by package A): publishing after touching an unrelated
## control must not silently change hole_mode away from whatever the lobby is
## currently showing, just because the option list was too short for one of
## the enum's values. Bontago-cmc.7 moved the default back to TEMPORARY; this
## still has to hold for TEMPORARY the same way it held for OFF.
func test_publishing_an_unrelated_change_keeps_hole_mode_at_the_default() -> void:
	var lobby: Lobby = _make_lobby(true)
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 6
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	assert_eq(calls.size(), 1)
	assert_eq(int(calls[0].get("hole_mode")), MatchConfig.HoleMode.TEMPORARY)


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


func test_client_setting_change_does_not_publish() -> void:
	var lobby: Lobby = _make_lobby(false)
	# Even if something bypasses the disabled control (e.g. a test calling the
	# signal handler directly), a non-host must never publish lobby data.
	lobby._on_setting_changed()
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 0)


# --- Start gating --------------------------------------------------------------

func test_start_button_disabled_until_all_peers_ready() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.all_peers_ready_value = false
	lobby._update_host_only_state()
	assert_true((lobby.get_node("%StartButton") as Button).disabled)
	fake.all_peers_ready_value = true
	lobby._update_host_only_state()
	assert_false((lobby.get_node("%StartButton") as Button).disabled)


func test_start_button_hidden_for_a_client() -> void:
	var lobby: Lobby = _make_lobby(false)
	assert_false((lobby.get_node("%StartButton") as Button).visible)


## Review finding #1 (Bontago-xtq.32 redo #3): the Back pill's own
## _on_back_pressed() only emits back_requested (line 365-366) -- this pins
## that the button press actually reaches the signal, since nothing in this
## file exercised %BackButton before. game/Main.gd owns the listener (no
## node paths into game/Main.gd, this file's own header), so that side is
## covered separately by tests/unit/test_main.gd.
func test_back_button_emits_back_requested() -> void:
	var lobby: Lobby = _make_lobby(true)
	watch_signals(lobby)
	(lobby.get_node("%BackButton") as Button).pressed.emit()
	assert_signal_emitted(lobby, "back_requested")


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


## Bontago-mv0.7: config/match_defaults.tres ships player_count = 4, but a
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


func test_start_does_not_shrink_player_count_below_connected_peers() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.all_peers_ready_value = true
	fake.slots_by_peer = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4}  # 5 connected peers
	watch_signals(lobby)

	lobby._on_start_pressed()

	var config: MatchConfig = get_signal_parameters(lobby, "start_requested")[0]
	assert_eq(config.player_count, 5, "every connected peer must get a slot, not just match_defaults' 4")


## Fix 1's UI mirror (docs/AGENT_WORKFLOW.md dispatch: "lobby spin clamps to
## peers"). The authoritative clamp is test_start_clamps_player_count_to_
## connected_peers() above; this is display-only, so the spin never *shows* a
## count the match is about to override the instant Start is pressed.
func test_roster_change_mirrors_the_player_count_spin_to_the_peer_count() -> void:
	var lobby: Lobby = _make_lobby(true)
	var roster: Array[Dictionary] = [
		{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": true},
		{"peer_id": 2, "slot_id": 1, "name": "Guest", "ready": false},
	]

	Events.net_roster_changed.emit(roster)

	assert_eq(int((lobby.get_node("%PlayerCountSpin") as SpinBox).value), 2)


func test_ready_toggle_calls_set_local_ready() -> void:
	var lobby: Lobby = _make_lobby(false)
	# Setting button_pressed itself fires `toggled` (BaseButton.set_pressed()),
	# so this alone is one press, not two.
	(lobby.get_node("%ReadyCheck") as CheckButton).button_pressed = true
	assert_eq(_fake_of(lobby).set_local_ready_calls, [true])


## Bontago-1pi.89 (replaces Bontago-1pi.73's entry-reset test): the Ready toggle is a view of
## Net's per-peer flag. The lobby never resets or writes the flag on entry (Net clears it when
## the session returns to the lobby); it shows whatever Net holds, on entry and on every roster
## event, without a press (no write into Net). Every route is covered in test_lobby_ready_sync.
func test_ready_toggle_shows_net_flag_and_never_writes_it() -> void:
	for is_host: bool in [true, false]:
		var lobby: Lobby = _make_lobby(is_host)
		var fake: FakeNet = _fake_of(lobby)
		var toggle: CheckButton = lobby.get_node("%ReadyCheck") as CheckButton
		fake.slots_by_peer = {fake.local_peer_id_value: 0}
		fake.ready_by_peer = {fake.local_peer_id_value: true}
		lobby._sync_ready_toggle_from_net()
		assert_true(toggle.button_pressed, "host=%s: the flag Net holds is shown" % is_host)
		fake.ready_by_peer[fake.local_peer_id_value] = false
		Events.net_roster_changed.emit(fake.roster_payload())
		assert_false(toggle.button_pressed, "host=%s: a roster event moves the toggle" % is_host)
		assert_eq(fake.reset_ready_flags_calls, 0, "host=%s: the lobby never resets Net's flags" % is_host)
		assert_eq(fake.set_local_ready_calls, [], "host=%s: showing the flag is not a press" % is_host)


# --- Roster --------------------------------------------------------------------

func test_roster_in_lobby_data_builds_player_rows() -> void:
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["roster"] = [
		{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": true},
		{"peer_id": 2, "slot_id": 1, "name": "Guest", "ready": false},
	]
	Events.net_lobby_data_changed.emit(data)
	var list: VBoxContainer = _player_list(lobby)
	assert_eq(list.get_child_count(), 3, "two seat rows plus the host's dashed open-seat row (Bontago-hfa.11)")


## M5 P4 (docs/archive/M5_PLAN.md, Bontago-d5c.5): the host's own outbound
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
	# Bontago-1pi.62: each bot carries the host-assigned themed name, also in bot_names.
	var names: Array = calls[calls.size() - 1].get("bot_names") as Array
	assert_eq(names.size(), 2)
	assert_ne(names[0], names[1])
	assert_eq(str(bot_one.get("name")), "%s (Normal)" % names[0])
	assert_eq(str(bot_two.get("name")), "%s (Normal)" % names[1])
	assert_true(bool(bot_one.get("ready")))
	assert_true(bool(bot_two.get("ready")))


## The Start gate must stay peer-only: bot rows are always ready, but a
## lobby with connected humans who haven't checked Ready still can't Start.
func test_bot_rows_do_not_affect_all_peers_ready() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.slots_by_peer = {1: 0, 2: 1, 3: 2, 4: 3}
	fake.all_peers_ready_value = false
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 6
	(lobby.get_node("%AiCountSpin") as SpinBox).value = 2
	lobby._update_host_only_state()
	assert_true((lobby.get_node("%StartButton") as Button).disabled,
		"bot rows are always ready, but that must not open the gate for not-ready humans")


func test_build_roster_has_no_bot_rows_when_ai_count_is_zero() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.slots_by_peer = {1: 0, 2: 1}
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 2
	(lobby.get_node("%AiCountSpin") as SpinBox).value = 0

	var calls: Array[Dictionary] = fake.set_lobby_data_calls
	var roster: Array = calls[calls.size() - 1].get("roster") as Array
	assert_eq(roster.size(), 2, "no bot rows when ai_count is 0")


## Bontago-1pi.9b: owner playtest -- "the right panel lists 'players+bots'/
## 'players'" -- %PlayerCountLabel must always spell out humans, bots and
## seats separately instead of one ambiguous "N / S" count.
func test_roster_header_shows_players_bots_and_seats_separately() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.slots_by_peer = {1: 0, 2: 1, 3: 2}  # 3 connected humans
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 8
	(lobby.get_node("%AiCountSpin") as SpinBox).value = 2

	var count_label: Label = _count_label(lobby)
	assert_eq(count_label.text, "3 players · 2 bots · 5/8 seats")


## A lobby with no bots requested shouldn't announce "0 bots". Sets seats to
## 5 (not match_defaults.tres' own default of 4) so the SpinBox's own
## value_changed actually fires and republishes/re-applies the roster --
## setting it to its already-current value would be a silent no-op.
func test_roster_header_omits_bots_when_ai_count_is_zero() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.slots_by_peer = {1: 0, 2: 1}
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 5

	var count_label: Label = _count_label(lobby)
	assert_eq(count_label.text, "2 players · 2/8 seats")


## Bontago-1pi.9b: owner playtest -- "I can add bots up to the player limit"
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


# --- Invite Friends (docs/archive/M3b_PLAN.md P3) -------------------------------------

func test_invite_friends_button_hidden_when_not_a_steam_session() -> void:
	var lobby: Lobby = _make_lobby(true)
	_fake_of(lobby).is_steam_session_value = false
	lobby._update_host_only_state()
	assert_false((lobby.get_node("%InviteFriendsButton") as Button).visible)


func test_invite_friends_button_visible_when_host_is_a_steam_session() -> void:
	var lobby: Lobby = _make_lobby(true)
	_fake_of(lobby).is_steam_session_value = true
	lobby._update_host_only_state()
	assert_true((lobby.get_node("%InviteFriendsButton") as Button).visible)


func test_invite_friends_button_hidden_for_a_client_even_in_a_steam_session() -> void:
	var lobby: Lobby = _make_lobby(false)
	_fake_of(lobby).is_steam_session_value = true
	lobby._update_host_only_state()
	assert_false((lobby.get_node("%InviteFriendsButton") as Button).visible)


func test_invite_friends_button_calls_invite_friends() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.is_steam_session_value = true
	lobby._update_host_only_state()
	lobby._on_invite_friends_pressed()
	assert_eq(fake.invite_friends_calls, 1)


func test_roster_changed_signal_updates_ready_label_without_a_lobby_data_round_trip() -> void:
	# Bontago-mv0.6: toggling Ready must not need Net to republish the whole
	# lobby Dictionary (test_roster_in_lobby_data_builds_player_rows above
	# covers that path already) — Events.net_roster_changed alone must move
	# the label.
	var lobby: Lobby = _make_lobby(false)
	var roster: Array[Dictionary] = [
		{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": false},
		{"peer_id": 2, "slot_id": 1, "name": "Guest", "ready": false},
	]
	Events.net_roster_changed.emit(roster)
	var list: VBoxContainer = _player_list(lobby)
	assert_eq(list.get_child_count(), 3, "two seat rows plus the host's dashed open-seat row (Bontago-hfa.11)")
	# the panel's _player_rows rather than list.get_child(): the render
	# queue_free()s the old rows, which stay in the tree (just pending
	# deletion) until the next idle frame, so querying the container
	# directly a second time in the same frame would still see them.
	# Bontago-mp0.3.5 (review r2, item 4): each row is now a PanelContainer
	# pill (ui/lobby/LobbyPlayersPanel.gd's _build_player_row()) -- layout/badge/badge_label
	# walk to the Ready/Not ready badge Label the same way that function
	# builds it (layout child 0, badge child 2 of layout, label child 0 of
	# badge), instead of the old row.get_child(1) plain trailing-text Label.
	var guest_row: PanelContainer = _panel_of(lobby)._player_rows[1] as PanelContainer
	var guest_badge_label: Label = _row_badge_label(guest_row)
	assert_eq(guest_badge_label.get_parent().tooltip_text, "Not ready")

	roster = [
		{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": false},
		{"peer_id": 2, "slot_id": 1, "name": "Guest", "ready": true},
	]
	Events.net_roster_changed.emit(roster)
	guest_row = _panel_of(lobby)._player_rows[1] as PanelContainer
	guest_badge_label = _row_badge_label(guest_row)
	assert_eq(guest_badge_label.get_parent().tooltip_text, "Ready", "the ready flag flip must reach the row's badge")


# --- Specials checklist (M6 A4, docs/archive/M6_PLAN.md) ------------------------------

func test_every_selectable_special_def_gets_a_checkbox_checked_by_default() -> void:
	var lobby: Lobby = _make_lobby(true)
	# Bontago-1pi.160: the checklist lists the selectable roster (disabled gifts such as Cat are absent).
	var all_defs: Array[SpecialDef] = SpecialDef.load_selectable_specials()
	assert_eq(lobby._special_checkboxes.size(), all_defs.size())
	assert_eq(lobby._special_ids.size(), all_defs.size())
	for i: int in range(all_defs.size()):
		assert_eq(lobby._special_ids[i], all_defs[i].id)
		assert_true(lobby._special_checkboxes[i].button_pressed, "every box starts checked (all enabled)")
	var checklist: GridContainer = lobby.get_node("%SpecialsChecklist")
	assert_eq(checklist.get_child_count(), all_defs.size())


func test_no_checklist_entry_is_a_disabled_gift() -> void:
	# Bontago-1pi.160 (owner 2026-10-10): disabled gifts are not listed in the lobby at all.
	var lobby: Lobby = _make_lobby(true)
	for id: StringName in lobby._special_ids:
		var def: SpecialDef = SpecialDef.find_by_id(id)
		assert_not_null(def, "%s resolves in the catalogue" % id)
		if def != null:
			assert_true(def.enabled_by_default, "%s is listed but enabled_by_default == false" % id)
	assert_false(lobby._special_ids.has(&"cat"), "cat is disabled by default and must not be listed")


func test_all_boxes_checked_publishes_an_empty_enabled_specials_array() -> void:
	# MatchConfig.enabled_specials's own convention: empty means "every special
	# enabled by default" -- so the default all-checked state must not publish
	# the full id list, which would be a different (if equivalent) Dictionary
	# shape than every config this screen has ever produced before this
	# package existed.
	var lobby: Lobby = _make_lobby(true)
	if lobby._special_ids.is_empty():
		pass_test("no SpecialDef .tres on disk in this checkout; nothing to uncheck")
		return
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 5  # force one publish
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	var published: Array = calls[calls.size() - 1].get("enabled_specials") as Array
	assert_true(published.is_empty())


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


func test_apply_data_with_a_wire_list_checks_exactly_the_matching_boxes() -> void:
	var lobby: Lobby = _make_lobby(false)
	if lobby._special_ids.size() < 2:
		pass_test("fewer than 2 SpecialDef .tres on disk in this checkout; nothing to distinguish")
		return
	var kept_id: StringName = lobby._special_ids[0]
	var data: Dictionary = MatchConfig.new().to_dict()
	data["enabled_specials"] = [kept_id]

	Events.net_lobby_data_changed.emit(data)

	assert_true(lobby._special_checkboxes[0].button_pressed, "the named id must be checked")
	for i: int in range(1, lobby._special_ids.size()):
		assert_false(lobby._special_checkboxes[i].button_pressed, "every other id must be unchecked")


func test_apply_data_with_the_sentinel_unchecks_every_box() -> void:
	var lobby: Lobby = _make_lobby(false)
	if lobby._special_checkboxes.is_empty():
		pass_test("no SpecialDef .tres on disk in this checkout; nothing to uncheck")
		return
	var data: Dictionary = MatchConfig.new().to_dict()
	data["enabled_specials"] = [Lobby.ALL_DISABLED_SENTINEL]

	Events.net_lobby_data_changed.emit(data)

	for box: UiChipToggle in lobby._special_checkboxes:
		assert_false(box.button_pressed)


func test_apply_data_with_an_empty_list_checks_every_box() -> void:
	var lobby: Lobby = _make_lobby(false)
	if lobby._special_checkboxes.is_empty():
		pass_test("no SpecialDef .tres on disk in this checkout; nothing to check")
		return
	for box: UiChipToggle in lobby._special_checkboxes:
		box.button_pressed = false
	var data: Dictionary = MatchConfig.new().to_dict()
	data["enabled_specials"] = []

	Events.net_lobby_data_changed.emit(data)

	for box: UiChipToggle in lobby._special_checkboxes:
		assert_true(box.button_pressed, "empty means every special enabled by default")


func test_specials_checkboxes_are_disabled_for_a_client() -> void:
	var lobby: Lobby = _make_lobby(false)
	if lobby._special_checkboxes.is_empty():
		pass_test("no SpecialDef .tres on disk in this checkout; nothing to gate")
		return
	assert_true(lobby._special_checkboxes[0].disabled)


func test_roster_entry_with_a_steam_persona_name_renders_unchanged() -> void:
	# docs/archive/M3b_PLAN.md P3: once host_online()/join_lobby() default an empty
	# player_name to the Steam persona name, the panel's roster render needs zero
	# special-casing to display it — pin that down rather than just assert it.
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["roster"] = [
		{"peer_id": 1, "slot_id": 0, "name": "SteamFriend#1234", "ready": true},
	]
	Events.net_lobby_data_changed.emit(data)
	var list: VBoxContainer = _player_list(lobby)
	assert_eq(list.get_child_count(), 2, "one seat row plus the dashed open-seat row (Bontago-hfa.11)")
	# Bontago-mp0.3.5 (review r2, item 4): row is now the PanelContainer pill
	# ui/lobby/LobbyPlayersPanel.gd's _build_player_row() builds -- layout child 0, name Label
	# is text_column (layout child 1)'s own child 0.
	var row: PanelContainer = list.get_child(0) as PanelContainer
	var layout: HBoxContainer = row.get_child(0) as HBoxContainer
	var text_column: VBoxContainer = layout.get_child(1) as VBoxContainer
	var name_label: Label = text_column.get_child(0) as Label
	assert_true(name_label.text.begins_with("SteamFriend#1234"), "a Steam persona name should render unchanged")


# --- Focus chain (gamepad/keyboard navigability, Bontago-xtq.32) -------------------

## Bontago-1pi.53 (S1b): the Advanced rules popup, its summary bar and the chips are gone --
## their content lives in the sections' Advanced blocks.
func test_the_advanced_rules_popup_bar_and_chips_are_gone() -> void:
	var lobby: Lobby = _make_lobby(true)
	for unique_name: String in [
		"%AdvancedPopup", "%AdvancedPopupClose", "%AdvancedPopupCard", "%AdvRulesBar", "%AdvRulesBarPanel",
		"%AdvRulesChips", "%AdvChipSpecials", "%AdvChipExperiments", "%AdvancedRulesLabel",
	]:
		assert_null(lobby.get_node_or_null(unique_name), "%s is deleted" % unique_name)


## The Players/AI steppers, the default-difficulty dropdown and the segmented Teams control left
## the settings card (seats and teams are managed in the players panel); their hidden
## sources of truth stay, outside every layout container and never a focus stop.
func test_legacy_seat_and_team_controls_are_hidden_sources_only() -> void:
	var lobby: Lobby = _make_lobby(true)
	for unique_name: String in ["%TeamOffButton", "%Team2Button", "%Team3Button", "%Team4Button", "%TeamsSegmented", "%TeamsTrack", "%PlayersSubLabel", "%AiSubLabel"]:
		assert_null(lobby.get_node_or_null(unique_name), "%s is deleted" % unique_name)
	var shown: Array[Control] = lobby._visible_chain(lobby._main_chain)
	for unique_name: String in ["%PlayerCountSpin", "%AiCountSpin", "%AiDifficultyOption", "%TeamModeOption"]:
		var source: Control = lobby.get_node(unique_name) as Control
		assert_false(source.is_visible_in_tree(), "%s stays hidden" % unique_name)
		assert_false(shown.has(source), "%s is never a focus stop" % unique_name)
		assert_false((lobby.get_node("%SettingsCard") as Control).is_ancestor_of(source), "%s is not in the settings card" % unique_name)


## Bontago-1pi.53 (S1b): ui_cancel backs out of the lobby (synthetic action through
## _unhandled_input(), the way Esc would reach it) -- the popup case is gone.
func test_ui_cancel_backs_out_of_the_lobby() -> void:
	var lobby: Lobby = _make_lobby(true)
	watch_signals(lobby)
	var event: InputEventAction = InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	lobby._unhandled_input(event)
	assert_signal_emitted(lobby, "back_requested")


# --- Gamepad parity (Bontago-1pi.15.1: "gamepad works in some menus but not
# all; B never goes back in any menu") ------------------------------------------
#
# Real InputEventJoypadButton, checked against the real InputMap via the
# event's own is_action_pressed() (not a synthetic InputEventAction) -- proves
# tools/bootstrap_project.gd's ui_cancel gamepad-B binding actually reaches
# this screen, the same real-binding technique test_pause_menu.gd's own
# _pad_press()/test_gamepad_start_toggles_visibility() already uses.

func test_opening_grabs_focus_somewhere() -> void:
	var lobby: Lobby = _make_lobby(true)
	assert_not_null(get_viewport().gui_get_focus_owner(), "the lobby must land focus somewhere as soon as it opens.")
	assert_true((lobby.get_node("%DiscSizeMeter") as Control).has_focus())


## Bontago-1pi.15.1 fix: pressing B on the lobby screen used to do nothing at all unless a
## popup was open; _unhandled_input() backs out through _on_back_pressed().
func test_gamepad_b_on_the_main_screen_emits_back_requested() -> void:
	var lobby: Lobby = _make_lobby(true)
	watch_signals(lobby)

	var event: InputEventJoypadButton = _pad_press_release_action_event(JOY_BUTTON_B)
	assert_true(event.is_action_pressed(&"ui_cancel"), "gamepad B should map to ui_cancel")
	lobby._unhandled_input(event)

	assert_signal_emitted(lobby, "back_requested", "gamepad B must back all the way out of the lobby.")


## Bontago-1pi.53 (S1b): with an Advanced block open B still leaves the lobby in one press (no
## modal to close first).
func test_gamepad_b_backs_out_even_with_an_advanced_block_open() -> void:
	var lobby: Lobby = _make_lobby(true)
	(lobby.get_node("%GameSection") as UiSection).set_advanced_open(true)
	(lobby.get_node("%GiftsSection") as UiSection).set_advanced_open(true)
	watch_signals(lobby)

	lobby._unhandled_input(_pad_press_release_action_event(JOY_BUTTON_B))

	assert_signal_emit_count(lobby, "back_requested", 1)


func _pad_press_release_action_event(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	event.pressed = true
	return event


## Bontago-1pi.53 (S1a/S1b): the tilt / hole / sudden-death / turn-based chips left the
## Advanced rules bar (their controls moved into the GAME and ROUND sections, where
## the setting itself is on screen) and the bar itself is gone: the section headers
## summarise the live controls (the GIFTS header counts the enabled gifts) without any
## Advanced block needing to be open, and the moved controls must still publish.
func test_section_summaries_reflect_current_settings() -> void:
	var lobby: Lobby = _make_lobby(true)
	(lobby.get_node("%TiltModeOption") as UiDropdown).selected = MatchConfig.TiltMode.PHYSICAL_BALANCE
	(lobby.get_node("%HoleModeOption") as UiDropdown).select(MatchConfig.HoleMode.OFF)
	(lobby.get_node("%HoleModeOption") as UiDropdown).item_selected.emit(MatchConfig.HoleMode.OFF)
	(lobby.get_node("%MatchTimerStepper") as UiStepper).value = 15
	(lobby.get_node("%SuddenDeathCheck") as UiToggle).button_pressed = true
	(lobby.get_node("%TurnBasedCheck") as UiToggle).button_pressed = true
	if not lobby._special_checkboxes.is_empty():
		lobby._special_checkboxes[0].button_pressed = false
	lobby._update_section_summaries()
	var published: MatchConfig = MatchConfig.from_dict(_fake_of(lobby).lobby_data_value)
	assert_eq(published.tilt_mode, MatchConfig.TiltMode.PHYSICAL_BALANCE)
	assert_eq(published.hole_mode, MatchConfig.HoleMode.OFF)
	assert_true(published.sudden_death)
	assert_true(published.turn_based)
	assert_true((lobby.get_node("%GameSection") as UiSection).get_summary().begins_with("Classic"), "GAME summary leads with the mode")
	assert_true((lobby.get_node("%RoundSection") as UiSection).get_summary().begins_with("15 min"), "ROUND summary leads with the timer")
	if not lobby._special_checkboxes.is_empty():
		var expected: String = Lobby.SUMMARY_GIFT_COUNT_FORMAT % [lobby._special_checkboxes.size() - 1, lobby._special_checkboxes.size()]
		assert_true((lobby.get_node("%GiftsSection") as UiSection).get_summary().ends_with(expected), "GIFTS counts the enabled gifts (%s)" % expected)


## Bontago-1pi.53 (S1b): the per-gift checklist is the GIFTS section's Advanced block; its
## checkboxes are focus stops (in the one main loop, in visual order) only while it is open.
func test_gift_checkboxes_join_the_main_loop_only_while_the_gifts_advanced_block_is_open() -> void:
	var lobby: Lobby = _make_lobby(true)
	if lobby._special_checkboxes.is_empty():
		pass_test("no SpecialDef .tres on disk in this checkout; nothing to focus")
		return
	var gifts: UiSection = lobby.get_node("%GiftsSection") as UiSection
	assert_true(gifts.advanced.is_ancestor_of(lobby.get_node("%SpecialsChecklist")), "the checklist is GIFTS Advanced")
	for box: UiChipToggle in lobby._special_checkboxes:
		assert_false(lobby._visible_chain(lobby._main_chain).has(box), "closed: a gift checkbox is not a stop")
	gifts.advanced_button.button_pressed = true
	var shown: Array[Control] = lobby._visible_chain(lobby._main_chain)
	var previous: Control = gifts.advanced_button
	for box: UiChipToggle in lobby._special_checkboxes:
		assert_true(shown.has(box), "open: a gift checkbox is a stop")
		assert_eq(previous.get_node(previous.focus_neighbor_bottom), box, "gift checkboxes follow the chip in order")
		previous = box
	assert_eq(lobby._special_checkboxes[0].get_node(lobby._special_checkboxes[0].focus_neighbor_top), gifts.advanced_button)


func test_focus_chain_is_a_closed_loop_through_every_row() -> void:
	# ui/Lobby.tscn (unlike ui/OptionsMenu.tscn) carries no static
	# focus_neighbor_* NodePaths -- _wire_focus_chain() builds the chain at
	# runtime once the dynamic specials checklist exists. Mirror
	# test_options_menu.gd's test_focus_chain_is_a_closed_loop_through_every_row().
	var lobby: Lobby = _make_lobby(true)

	var start_button: Control = lobby.get_node("%StartButton") as Control
	# Bontago-1pi.61: section headers are static; the loop starts at the GAME mode.
	var first_stop: Control = lobby.get_node("%GameModeOption") as Control
	var start_bottom: Node = start_button.get_node(start_button.focus_neighbor_bottom)
	assert_eq(start_bottom, first_stop, "the chain must wrap from StartButton back to the game mode")

	var top_neighbor: Node = first_stop.get_node(first_stop.focus_neighbor_top)
	assert_eq(top_neighbor, start_button, "the game mode's up neighbor must close the loop back to StartButton")
	var second_option: Control = lobby.get_node("%DiscSizeMeter") as Control
	assert_eq(first_stop.get_node(first_stop.focus_neighbor_bottom), second_option, "the map picker follows the mode picker")

	# Bontago-1pi.53 (S1b): the hidden sources of truth (%TeamModeOption, the seat spins and
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
	assert_false((lobby.get_node("%MapVariantOption") as Control).visible, "MapVariantOption stays hidden behind the combined dropdown")
	assert_false((lobby.get_node("%MapSizeOption") as Control).visible, "MapSizeOption stays hidden behind the combined dropdown")

	# ... and so do the GIFTS Advanced (per-gift) and EXPERIMENTS blocks once opened.
	(lobby.get_node("%GiftsSection") as UiSection).set_advanced_open(true)
	(lobby.get_node("%ExperimentsSection") as UiSection).set_advanced_open(true)
	var opened: Array[Control] = []
	opened.append_array(lobby._special_checkboxes)
	opened.append_array(lobby._qol_checks)
	for control: Control in opened:
		assert_ne(control.focus_neighbor_top, NodePath(""), "%s must have an up neighbor once opened" % control.name)
		assert_ne(control.focus_neighbor_bottom, NodePath(""), "%s must have a down neighbor once opened" % control.name)


## Bontago-1pi.53 (S1a): the Steam-only invite button is a focus stop only while it is
## shown; the loop is rewired when the transport (hence its visibility) changes.
func test_invite_button_joins_the_loop_when_a_steam_session_shows_it() -> void:
	var lobby: Lobby = _make_lobby(true)
	var invite: Control = lobby.get_node("%InviteFriendsButton") as Control
	assert_false(invite.visible)
	assert_eq(invite.focus_neighbor_bottom, NodePath(""), "hidden: not wired")
	_fake_of(lobby).is_steam_session_value = true
	lobby._update_host_only_state()
	assert_true(invite.visible)
	assert_ne(invite.focus_neighbor_bottom, NodePath(""), "shown: wired into the loop")
	assert_eq(invite.get_node(invite.focus_neighbor_top), lobby.get_node("%BackButton"))


func test_round_mode_and_timer_are_primary_settings() -> void:
	var lobby: Lobby = _make_lobby(true)
	# Bontago-1pi.53 (S1a): the mode picker moved to GAME; the timer is ROUND's first control.
	var game_section: UiSection = lobby.get_node("%GameSection") as UiSection
	var round_section: UiSection = lobby.get_node("%RoundSection") as UiSection
	assert_true(game_section.is_ancestor_of(lobby.get_node("%GameModeOption")), "game mode is in GAME")
	assert_true(round_section.is_ancestor_of(lobby.get_node("%MatchTimerStepper")), "the timer is in ROUND")
	assert_eq(round_section.name, "RoundSection")
	assert_true((lobby.get_node("%MatchTimerCol") as Control).visible)
	assert_false((lobby.get_node("%RoundTimerCol") as Control).visible)
	# Bontago-1pi.61: headers are not stops; ROUND's first stop follows GAME's Advanced chip.
	var timer_control: Control = lobby.get_node("%MatchTimerStepper") as Control
	assert_eq(timer_control.get_node(timer_control.focus_neighbor_top), game_section.advanced_button)
	lobby._refresh_timer_control(MatchConfig.GameMode.ELIMINATION)
	assert_false((lobby.get_node("%MatchTimerCol") as Control).visible)
	assert_true((lobby.get_node("%RoundTimerCol") as Control).visible)
	var round_control: Control = lobby.get_node("%RoundTimerStepper") as Control
	assert_eq(round_control.get_node(round_control.focus_neighbor_top), game_section.advanced_button)


func _y_event() -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = "lobby_quick_advanced"
	event.pressed = true
	return event


## Bontago-1pi.53 (S1b): Y toggles the Advanced block of the section holding focus.
func test_lobby_quick_y_toggles_the_advanced_block_of_the_focused_section() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game: UiSection = lobby.get_node("%GameSection") as UiSection
	var gifts: UiSection = lobby.get_node("%GiftsSection") as UiSection
	assert_true((lobby.get_node("%DiscSizeMeter") as Control).has_focus(), "fixture: focus starts in GAME")
	lobby._unhandled_input(_y_event())
	assert_true(game.is_advanced_open(), "Y opens the focused section's Advanced block")
	assert_false(gifts.is_advanced_open())
	lobby._unhandled_input(_y_event())
	assert_false(game.is_advanced_open(), "a second Y closes it")
	(lobby.get_node("%GiftsCheck") as Control).grab_focus()
	lobby._unhandled_input(_y_event())
	assert_true(gifts.is_advanced_open(), "focus in GIFTS: Y opens GIFTS Advanced")
	assert_false(game.is_advanced_open())
	lobby._unhandled_input(_y_event())
	assert_false(gifts.is_advanced_open())


## Focus in a section without an Advanced block (ROUND) or outside every section (Back) falls
## back to the first section that has one, GAME.
func test_lobby_quick_y_falls_back_to_the_first_advanced_section() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game: UiSection = lobby.get_node("%GameSection") as UiSection
	lobby._block_timer_stepper.grab_focus()
	lobby._unhandled_input(_y_event())
	assert_true(game.is_advanced_open(), "ROUND has no Advanced block: Y toggles GAME's")
	lobby._unhandled_input(_y_event())
	(lobby.get_node("%BackButton") as Control).grab_focus()
	lobby._unhandled_input(_y_event())
	assert_true(game.is_advanced_open(), "focus outside the sections: Y toggles GAME's")


## Y on a focused Advanced control closes the block and keeps focus on a visible stop (the
## section's chip) instead of dropping it with the hidden control.
func test_lobby_quick_y_closing_a_block_keeps_focus_on_its_chip() -> void:
	var lobby: Lobby = _make_lobby(true)
	var game: UiSection = lobby.get_node("%GameSection") as UiSection
	game.set_advanced_open(true)
	(lobby.get_node("%GravityMeter") as Control).grab_focus()
	assert_true((lobby.get_node("%GravityMeter") as Control).has_focus(), "fixture: focus is inside the block")
	lobby._unhandled_input(_y_event())
	assert_false(game.is_advanced_open())
	assert_true(game.advanced_button.has_focus(), "focus moved to the Advanced chip, not lost")


func test_lobby_quick_x_obeys_ready_and_host_gates() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	var event: InputEventAction = InputEventAction.new()
	event.action = "lobby_quick_start"
	event.pressed = true
	watch_signals(lobby)
	fake.all_peers_ready_value = false
	lobby._update_host_only_state()
	lobby._unhandled_input(event)
	assert_signal_not_emitted(lobby, "start_requested")
	fake.all_peers_ready_value = true
	lobby._update_host_only_state()
	lobby._unhandled_input(event)
	assert_signal_emitted(lobby, "start_requested")


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
	assert_true(game.is_advanced_open(), "pad Y opens the focused section's Advanced block")
	lobby._unhandled_input(y_event)
	assert_false(game.is_advanced_open(), "a second pad Y closes it")
	var x_event: InputEventJoypadButton = _pad_press_release_action_event(JOY_BUTTON_X)
	assert_true(x_event.is_action_pressed(&"lobby_quick_start"))
	lobby._unhandled_input(x_event)
	assert_signal_emitted(lobby, "start_requested")


## Bontago-1pi.94: a click on a lobby cycle selector publishes the next value (same index a
## dropdown pick sent), a right click the previous, and a client's copy is inert.
func test_host_clicking_the_weather_selector_cycles_and_publishes() -> void:
	var lobby: Lobby = _make_lobby(true)
	var option: UiDropdown = lobby.get_node("%WeatherOption") as UiDropdown
	var start: int = option.selected
	option.pressed.emit()
	var calls: Array[Dictionary] = (lobby.net_provider as FakeNet).set_lobby_data_calls
	assert_eq(calls.size(), 1)
	assert_eq(int(calls[0].get("weather_mode")), (start + 1) % option.item_count)
	var right: InputEventMouseButton = InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	option.gui_input.emit(right)
	assert_eq(option.selected, start, "right click steps back")


func test_a_client_cannot_cycle_the_hole_mode_selector() -> void:
	var lobby: Lobby = _make_lobby(false)
	var option: UiDropdown = lobby.get_node("%HoleModeOption") as UiDropdown
	assert_true(option.disabled)
	option.pressed.emit()
	assert_eq(option.selected, MatchConfig.HoleMode.TEMPORARY)
