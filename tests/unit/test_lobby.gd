extends GutTest
## docs/M3a_PLAN.md P4 "Tests first": every spec 2.8 setting round-trips
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


# --- Round trip ----------------------------------------------------------------

func test_host_changing_a_setting_publishes_lobby_data() -> void:
	var lobby: Lobby = _make_lobby(true)
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 6
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	assert_eq(calls.size(), 1)
	assert_eq(int(calls[0].get("player_count")), 6)


func test_every_2_8_setting_round_trips_through_to_dict_and_from_dict() -> void:
	var lobby: Lobby = _make_lobby(true)
	var config: MatchConfig = MatchConfig.new()
	config.map_variant = MatchConfig.MapVariant.RING
	config.map_size = MapDef.MapSize.LARGE
	config.player_count = 7
	config.ai_count = 3
	config.ai_difficulty = MatchConfig.AiDifficulty.HARD
	config.team_mode = MatchConfig.TeamMode.TEAMS_2
	config.block_timer = 9.5
	config.gravity_multiplier = 1.75
	config.goal_flag_count = 3
	config.gifts_enabled = false
	config.special_frequency = 80
	config.tilt_mode = MatchConfig.TiltMode.PHYSICAL_BALANCE
	config.hole_mode = MatchConfig.HoleMode.PERMANENT
	config.match_timer_minutes = 20
	config.sudden_death = true
	config.turn_based = true

	Events.net_lobby_data_changed.emit(config.to_dict())

	assert_eq((lobby.get_node("%MapVariantOption") as OptionButton).selected, MatchConfig.MapVariant.RING)
	assert_eq((lobby.get_node("%MapSizeOption") as OptionButton).selected, int(MapDef.MapSize.LARGE))
	assert_eq(int((lobby.get_node("%PlayerCountSpin") as SpinBox).value), 7)
	assert_eq(int((lobby.get_node("%AiCountSpin") as SpinBox).value), 3)
	assert_eq((lobby.get_node("%AiDifficultyOption") as OptionButton).selected, MatchConfig.AiDifficulty.HARD)
	assert_eq((lobby.get_node("%TeamModeOption") as OptionButton).selected, MatchConfig.TeamMode.TEAMS_2)
	assert_almost_eq((lobby.get_node("%BlockTimerSlider") as HSlider).value, 9.5, 0.01)
	assert_almost_eq((lobby.get_node("%GravitySlider") as HSlider).value, 1.75, 0.01)
	assert_eq(int((lobby.get_node("%GoalFlagSpin") as SpinBox).value), 3)
	assert_false((lobby.get_node("%GiftsCheck") as CheckButton).button_pressed)
	assert_eq(int((lobby.get_node("%SpecialFreqSlider") as HSlider).value), 80)
	assert_eq((lobby.get_node("%TiltModeOption") as OptionButton).selected, MatchConfig.TiltMode.PHYSICAL_BALANCE)
	assert_eq((lobby.get_node("%HoleModeOption") as OptionButton).selected, MatchConfig.HoleMode.PERMANENT)
	assert_eq(int((lobby.get_node("%MatchTimerSpin") as SpinBox).value), 20)
	assert_true((lobby.get_node("%SuddenDeathCheck") as CheckButton).button_pressed)
	assert_true((lobby.get_node("%TurnBasedCheck") as CheckButton).button_pressed)


func test_toggling_turn_based_check_publishes_config_turn_based_true() -> void:
	var lobby: Lobby = _make_lobby(true)
	var check: CheckButton = lobby.get_node("%TurnBasedCheck") as CheckButton
	check.button_pressed = true
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	assert_eq(calls.size(), 1)
	assert_true(bool(calls[0].get("turn_based")))


func test_apply_data_with_turn_based_true_checks_the_box() -> void:
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["turn_based"] = true

	Events.net_lobby_data_changed.emit(data)

	assert_true((lobby.get_node("%TurnBasedCheck") as CheckButton).button_pressed)


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
	assert_almost_eq((lobby.get_node("%BlockTimerSlider") as HSlider).value, MatchConfig.BLOCK_TIMER_MIN, 0.01)
	assert_eq(int((lobby.get_node("%SpecialFreqSlider") as HSlider).value), MatchConfig.SPECIAL_FREQUENCY_MAX)
	assert_eq(int((lobby.get_node("%GoalFlagSpin") as SpinBox).value), MatchConfig.GOAL_FLAG_MIN)


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
	var option: OptionButton = lobby.get_node("%HoleModeOption") as OptionButton
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
	assert_true((client_lobby.get_node("%GiftsCheck") as CheckButton).disabled)
	assert_false((host_lobby.get_node("%GiftsCheck") as CheckButton).disabled)


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


# --- Roster --------------------------------------------------------------------

func test_roster_in_lobby_data_builds_player_rows() -> void:
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["roster"] = [
		{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": true},
		{"peer_id": 2, "slot_id": 1, "name": "Guest", "ready": false},
	]
	Events.net_lobby_data_changed.emit(data)
	var list: VBoxContainer = lobby.get_node("%PlayerList")
	assert_eq(list.get_child_count(), 2)


## M5 P4 (docs/M5_PLAN.md, Bontago-d5c.5): the host's own outbound
## _build_roster() must append one synthetic row per bot seat -- slot_id
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
	assert_eq(str(bot_one.get("name")), "Bot 1 (Normal)")
	assert_eq(str(bot_two.get("name")), "Bot 2 (Normal)")
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


# --- Invite Friends (docs/M3b_PLAN.md P3) -------------------------------------

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
	var list: VBoxContainer = lobby.get_node("%PlayerList")
	assert_eq(list.get_child_count(), 2)
	# lobby._player_rows rather than list.get_child(): _apply_roster()
	# queue_free()s the old rows, which stay in the tree (just pending
	# deletion) until the next idle frame, so querying the container
	# directly a second time in the same frame would still see them.
	var guest_row: HBoxContainer = lobby._player_rows[1] as HBoxContainer
	var guest_label: Label = guest_row.get_child(1) as Label
	assert_true(guest_label.text.ends_with("(not ready)"))

	roster = [
		{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": false},
		{"peer_id": 2, "slot_id": 1, "name": "Guest", "ready": true},
	]
	Events.net_roster_changed.emit(roster)
	guest_row = lobby._player_rows[1] as HBoxContainer
	guest_label = guest_row.get_child(1) as Label
	assert_true(guest_label.text.ends_with("(ready)"), "the ready flag flip must reach the row's label")


# --- Specials checklist (M6 A4, docs/M6_PLAN.md) ------------------------------

func test_every_loaded_special_def_gets_a_checkbox_checked_by_default() -> void:
	var lobby: Lobby = _make_lobby(true)
	var all_defs: Array[SpecialDef] = SpecialDef.load_all_specials()
	assert_eq(lobby._special_checkboxes.size(), all_defs.size())
	assert_eq(lobby._special_ids.size(), all_defs.size())
	for i: int in range(all_defs.size()):
		assert_eq(lobby._special_ids[i], all_defs[i].id)
		assert_true(lobby._special_checkboxes[i].button_pressed, "every box starts checked (all enabled)")
	var checklist: HFlowContainer = lobby.get_node("%SpecialsChecklist")
	assert_eq(checklist.get_child_count(), all_defs.size())


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
	for box: CheckBox in lobby._special_checkboxes:
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

	for box: CheckBox in lobby._special_checkboxes:
		assert_false(box.button_pressed)


func test_apply_data_with_an_empty_list_checks_every_box() -> void:
	var lobby: Lobby = _make_lobby(false)
	if lobby._special_checkboxes.is_empty():
		pass_test("no SpecialDef .tres on disk in this checkout; nothing to check")
		return
	for box: CheckBox in lobby._special_checkboxes:
		box.button_pressed = false
	var data: Dictionary = MatchConfig.new().to_dict()
	data["enabled_specials"] = []

	Events.net_lobby_data_changed.emit(data)

	for box: CheckBox in lobby._special_checkboxes:
		assert_true(box.button_pressed, "empty means every special enabled by default")


func test_specials_checkboxes_are_disabled_for_a_client() -> void:
	var lobby: Lobby = _make_lobby(false)
	if lobby._special_checkboxes.is_empty():
		pass_test("no SpecialDef .tres on disk in this checkout; nothing to gate")
		return
	assert_true(lobby._special_checkboxes[0].disabled)


func test_roster_entry_with_a_steam_persona_name_renders_unchanged() -> void:
	# docs/M3b_PLAN.md P3: once host_online()/join_lobby() default an empty
	# player_name to the Steam persona name, _apply_roster() needs zero
	# special-casing to display it — pin that down rather than just assert it.
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["roster"] = [
		{"peer_id": 1, "slot_id": 0, "name": "SteamFriend#1234", "ready": true},
	]
	Events.net_lobby_data_changed.emit(data)
	var list: VBoxContainer = lobby.get_node("%PlayerList")
	assert_eq(list.get_child_count(), 1)
	var row: HBoxContainer = list.get_child(0) as HBoxContainer
	var label: Label = row.get_child(1) as Label
	assert_true(label.text.begins_with("SteamFriend#1234"), "a Steam persona name should render unchanged")


# --- Focus chain (gamepad/keyboard navigability, Bontago-xtq.32) -------------------

func test_focus_chain_is_a_closed_loop_through_every_row() -> void:
	# ui/Lobby.tscn (unlike ui/OptionsMenu.tscn) carries no static
	# focus_neighbor_* NodePaths -- _wire_focus_chain() builds the chain at
	# runtime once the dynamic specials checklist exists. Mirror
	# test_options_menu.gd's test_focus_chain_is_a_closed_loop_through_every_row().
	var lobby: Lobby = _make_lobby(true)

	var start_button: Control = lobby.get_node("%StartButton") as Control
	var map_variant_option: Control = lobby.get_node("%MapVariantOption") as Control
	var start_bottom: Node = start_button.get_node(start_button.focus_neighbor_bottom)
	assert_eq(start_bottom, map_variant_option, "the chain must wrap from StartButton back to MapVariantOption")

	var top_neighbor: Node = map_variant_option.get_node(map_variant_option.focus_neighbor_top)
	assert_eq(top_neighbor, start_button, "MapVariantOption's up neighbor must close the loop back to StartButton")

	var chain_unique_names: Array[String] = [
		"%MapVariantOption", "%MapSizeOption", "%PlayerCountSpin", "%AiCountSpin",
		"%AiDifficultyOption", "%TeamModeOption", "%BlockTimerSlider", "%GravitySlider",
		"%GoalFlagSpin", "%GiftsCheck", "%SpecialFreqSlider",
		"%TiltModeOption", "%HoleModeOption", "%MatchTimerSpin", "%SuddenDeathCheck",
		"%TurnBasedCheck", "%ReadyCheck", "%InviteFriendsButton", "%StartButton",
	]
	for unique_name: String in chain_unique_names:
		var control: Control = lobby.get_node(unique_name) as Control
		assert_ne(control.focus_neighbor_top, NodePath(""), "%s must have an up neighbor" % unique_name)
		assert_ne(control.focus_neighbor_bottom, NodePath(""), "%s must have a down neighbor" % unique_name)

	if not lobby._special_checkboxes.is_empty():
		for box: CheckBox in lobby._special_checkboxes:
			assert_ne(box.focus_neighbor_top, NodePath(""), "a specials checkbox must have an up neighbor")
			assert_ne(box.focus_neighbor_bottom, NodePath(""), "a specials checkbox must have a down neighbor")
