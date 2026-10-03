extends GutTest
## Bontago-1pi.18.5 (docs/QOL_EXPERIMENTS_PLAN.md, Q1): the lobby's
## "Experiments" section -- four opt-in QoL toggles in the Advanced rules popup,
## host-editable and read-only for a client. The checkboxes are the single
## source of the four enable flags on the published MatchConfig.qol; the
## numeric parameters stay in the shared config/qol_experiments.tres (F4).

const CHECK_NAMES: Array[String] = [
	"%QolTimerPauseCheck", "%QolBacklogCheck", "%QolGoalRadiusCheck", "%QolGiftSlotCheck",
]

## Snapshot of the shared F4 resource, restored after every test that edits it.
var _shared_before: Dictionary = {}


func before_each() -> void:
	_shared_before = _shared().to_dict()


func after_each() -> void:
	for key: String in _shared_before:
		_shared().set(key, _shared_before[key])


## The shared F4 resource the lobby folds its toggles onto. A function, because
## GDScript rejects assigning a property through the constant itself.
func _shared() -> QolExperiments:
	return Lobby.QOL_SHARED


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


func _check(lobby: Lobby, unique_name: String) -> CheckBox:
	return lobby.get_node(unique_name) as CheckBox


## The four flags in with_toggles() order, as the controls currently show them.
func _flags(lobby: Lobby) -> Array:
	var flags: Array = []
	for unique_name: String in CHECK_NAMES:
		flags.append(_check(lobby, unique_name).button_pressed)
	return flags


func _qol_flags(qol: QolExperiments) -> Array:
	return [qol.timer_pause_enabled, qol.backlog_enabled, qol.goal_radius_enabled, qol.gift_slot_enabled]


func _last_published_qol(lobby: Lobby) -> Dictionary:
	var calls: Array[Dictionary] = _fake_of(lobby).set_lobby_data_calls
	assert_gt(calls.size(), 0, "something must have been published")
	return calls[calls.size() - 1].get("qol", {}) as Dictionary


# --- Defaults ------------------------------------------------------------------

func test_every_experiment_checkbox_exists_and_defaults_off() -> void:
	var lobby: Lobby = _make_lobby(true)
	for unique_name: String in CHECK_NAMES:
		var check: CheckBox = _check(lobby, unique_name)
		assert_not_null(check, "%s must exist" % unique_name)
		assert_false(check.button_pressed, "%s defaults off" % unique_name)
		assert_ne(check.tooltip_text, "", "%s explains itself" % unique_name)
	assert_eq((lobby.get_node("%AdvChipExperiments") as Label).text, "Experiments: 0 on")


func test_default_controls_build_an_explicit_all_off_qol() -> void:
	var lobby: Lobby = _make_lobby(true)
	var config: MatchConfig = lobby._config_from_controls()
	assert_not_null(config.qol, "the lobby never publishes a null qol")
	assert_false(config.qol.any_enabled())
	assert_eq(config.qol.active_ids().size(), 0)


# --- Host edits round-trip to MatchConfig -------------------------------------

func test_each_toggle_publishes_exactly_its_own_flag() -> void:
	var expected_keys: Array[String] = ["timer_pause_enabled", "backlog_enabled", "goal_radius_enabled", "gift_slot_enabled"]
	for i: int in range(CHECK_NAMES.size()):
		var lobby: Lobby = _make_lobby(true)
		var check: CheckBox = _check(lobby, CHECK_NAMES[i])
		assert_false(check.disabled, "the host can change %s" % CHECK_NAMES[i])
		check.button_pressed = true
		assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 1, "one edit is one publish")
		var qol_data: Dictionary = _last_published_qol(lobby)
		for j: int in range(expected_keys.size()):
			assert_eq(bool(qol_data.get(expected_keys[j])), i == j, "%s after toggling %s" % [expected_keys[j], CHECK_NAMES[i]])
		var published: MatchConfig = MatchConfig.from_dict(_fake_of(lobby).set_lobby_data_calls[0])
		assert_not_null(published.qol, "qol survives MatchConfig.from_dict()")
		var flags: Array = _qol_flags(published.qol)
		for j: int in range(flags.size()):
			assert_eq(flags[j], i == j)
		assert_eq(published.qol.active_ids().size(), 1)


func test_all_four_on_round_trips_and_updates_the_summary_chip() -> void:
	var lobby: Lobby = _make_lobby(true)
	for unique_name: String in CHECK_NAMES:
		_check(lobby, unique_name).button_pressed = true
	var published: MatchConfig = MatchConfig.from_dict(
		_fake_of(lobby).set_lobby_data_calls[_fake_of(lobby).set_lobby_data_calls.size() - 1]
	)
	assert_eq(_qol_flags(published.qol), [true, true, true, true])
	assert_eq((lobby.get_node("%AdvChipExperiments") as Label).text, "Experiments: 4 on")
	_check(lobby, CHECK_NAMES[1]).button_pressed = false
	assert_eq((lobby.get_node("%AdvChipExperiments") as Label).text, "Experiments: 3 on")


func test_all_off_still_publishes_an_explicit_all_off_qol_even_if_f4_left_one_on() -> void:
	# A toggle left on in the F4 panel (the shared resource) must not leak into a
	# lobby match whose host sees every box unchecked.
	_shared().backlog_enabled = true
	_shared().gift_slot_enabled = true
	var lobby: Lobby = _make_lobby(true)
	_check(lobby, CHECK_NAMES[0]).button_pressed = true
	_check(lobby, CHECK_NAMES[0]).button_pressed = false
	assert_eq(_fake_of(lobby).set_lobby_data_calls.size(), 2)
	var qol_data: Dictionary = _last_published_qol(lobby)
	assert_true(qol_data.has("backlog_enabled"), "an explicit qol dict is published, not omitted")
	assert_false(bool(qol_data.get("timer_pause_enabled")))
	assert_false(bool(qol_data.get("backlog_enabled")))
	assert_false(bool(qol_data.get("goal_radius_enabled")))
	assert_false(bool(qol_data.get("gift_slot_enabled")))


func test_publishing_keeps_the_numeric_parameters_and_never_edits_the_shared_resource() -> void:
	_shared().backlog_max = 3
	_shared().pause_event_s = 7.5
	var lobby: Lobby = _make_lobby(true)
	_check(lobby, CHECK_NAMES[1]).button_pressed = true
	var published: MatchConfig = MatchConfig.from_dict(_fake_of(lobby).set_lobby_data_calls[0])
	assert_eq(published.qol.backlog_max, 3, "numeric parameters come from the shared (F4) resource")
	assert_eq(published.qol.pause_event_s, 7.5)
	assert_true(published.qol.backlog_enabled)
	assert_false(_shared().backlog_enabled, "the lobby must never write the shared resource")


func test_editing_another_setting_keeps_the_experiment_flags() -> void:
	var lobby: Lobby = _make_lobby(true)
	_check(lobby, CHECK_NAMES[2]).button_pressed = true
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = 6
	var qol_data: Dictionary = _last_published_qol(lobby)
	assert_true(bool(qol_data.get("goal_radius_enabled")), "an unrelated edit republishes the same toggles")
	assert_eq(_flags(lobby), [false, false, true, false])


# --- Clients are read-only ----------------------------------------------------

func test_client_experiment_checkboxes_are_disabled_and_host_ones_are_not() -> void:
	var host_lobby: Lobby = _make_lobby(true)
	var client_lobby: Lobby = _make_lobby(false)
	for unique_name: String in CHECK_NAMES:
		assert_false(_check(host_lobby, unique_name).disabled, "%s editable for the host" % unique_name)
		assert_true(_check(client_lobby, unique_name).disabled, "%s read-only for a client" % unique_name)


func test_client_mirrors_the_host_toggles_without_publishing() -> void:
	var host_lobby: Lobby = _make_lobby(true)
	_check(host_lobby, CHECK_NAMES[0]).button_pressed = true
	_check(host_lobby, CHECK_NAMES[3]).button_pressed = true
	var data: Dictionary = _fake_of(host_lobby).set_lobby_data_calls[_fake_of(host_lobby).set_lobby_data_calls.size() - 1]

	var client_lobby: Lobby = _make_lobby(false)
	Events.net_lobby_data_changed.emit(data)

	assert_eq(_flags(client_lobby), [true, false, false, true])
	for unique_name: String in CHECK_NAMES:
		assert_true(_check(client_lobby, unique_name).disabled, "still read-only after the update")
	assert_eq((client_lobby.get_node("%AdvChipExperiments") as Label).text, "Experiments: 2 on")
	assert_eq(_fake_of(client_lobby).set_lobby_data_calls.size(), 0, "mirroring never re-publishes")
	# Even a direct write to a disabled box (bypassing the UI) must not publish.
	_check(client_lobby, CHECK_NAMES[1]).button_pressed = true
	assert_eq(_fake_of(client_lobby).set_lobby_data_calls.size(), 0, "a client edit never publishes")


func test_remote_data_sets_a_hosts_checkboxes_without_republishing() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.set_lobby_data_calls.clear()
	var config: MatchConfig = MatchConfig.new()
	config.qol = QolExperiments.with_toggles(null, false, true, true, false)
	Events.net_lobby_data_changed.emit(config.to_dict())
	assert_eq(_flags(lobby), [false, true, true, false])
	assert_eq(fake.set_lobby_data_calls.size(), 0, "an inbound update must not bounce straight back out")


func test_remote_data_without_qol_clears_the_checkboxes() -> void:
	# An older host (or config/match_defaults.tres) carries no "qol" key: every
	# experiment reads as off, and a stale checked box is cleared.
	var lobby: Lobby = _make_lobby(false)
	var on: MatchConfig = MatchConfig.new()
	on.qol = QolExperiments.with_toggles(null, true, true, true, true)
	Events.net_lobby_data_changed.emit(on.to_dict())
	assert_eq(_flags(lobby), [true, true, true, true])
	var data: Dictionary = MatchConfig.new().to_dict()
	assert_false(data.has("qol"), "a default MatchConfig has no qol key")
	Events.net_lobby_data_changed.emit(data)
	assert_eq(_flags(lobby), [false, false, false, false])


func test_wire_garbage_in_qol_is_ignored_safely() -> void:
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["qol"] = {"backlog_enabled": "yes", "goal_radius_enabled": 1, "gift_slot_enabled": true}
	Events.net_lobby_data_changed.emit(data)
	assert_eq(_flags(lobby), [false, false, false, true], "wrong-typed flags keep the OFF default")


# --- Start carries the toggles ------------------------------------------------

func test_start_requested_config_carries_the_toggles() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.all_peers_ready_value = true
	fake.slots_by_peer = {1: 0}
	_check(lobby, CHECK_NAMES[1]).button_pressed = true
	_check(lobby, CHECK_NAMES[2]).button_pressed = true
	watch_signals(lobby)

	lobby._on_start_pressed()

	assert_signal_emitted(lobby, "start_requested")
	var config: MatchConfig = get_signal_parameters(lobby, "start_requested")[0]
	assert_not_null(config.qol, "the start config always carries qol, so Match keeps it over the F4 snapshot")
	assert_eq(_qol_flags(config.qol), [false, true, true, false])
	assert_true(config.qol != Lobby.QOL_SHARED, "the match gets a copy, never the shared resource")


func test_start_with_every_box_off_still_carries_an_explicit_all_off_qol() -> void:
	_shared().timer_pause_enabled = true
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.all_peers_ready_value = true
	fake.slots_by_peer = {1: 0}
	watch_signals(lobby)

	lobby._on_start_pressed()

	var config: MatchConfig = get_signal_parameters(lobby, "start_requested")[0]
	assert_not_null(config.qol)
	assert_false(config.qol.any_enabled(), "an F4-enabled toggle must not leak past an all-off lobby")


func test_start_picks_up_an_f4_numeric_edit_made_while_the_lobby_was_open() -> void:
	var lobby: Lobby = _make_lobby(true)
	var fake: FakeNet = _fake_of(lobby)
	fake.all_peers_ready_value = true
	fake.slots_by_peer = {1: 0}
	_check(lobby, CHECK_NAMES[1]).button_pressed = true
	_shared().backlog_max = 3
	watch_signals(lobby)

	lobby._on_start_pressed()

	var config: MatchConfig = get_signal_parameters(lobby, "start_requested")[0]
	assert_true(config.qol.backlog_enabled)
	assert_eq(config.qol.backlog_max, 3)


# --- Focus (keyboard / gamepad) -----------------------------------------------

func test_experiment_checkboxes_are_in_the_popup_focus_loop_and_visible_when_open() -> void:
	var lobby: Lobby = _make_lobby(true)
	lobby.debug_open_advanced_rules_popup()
	var close_button: Control = lobby.get_node("%AdvancedPopupClose") as Control
	var mid_join: Control = lobby.get_node("%MidJoinCheck") as Control
	for unique_name: String in CHECK_NAMES:
		var check: CheckBox = _check(lobby, unique_name)
		assert_true(check.is_visible_in_tree(), "%s is visible once the popup is open" % unique_name)
		assert_eq(check.focus_mode, Control.FOCUS_ALL, "%s is focusable" % unique_name)
		assert_ne(check.focus_neighbor_top, NodePath(""), "%s must have an up neighbor" % unique_name)
		assert_ne(check.focus_neighbor_bottom, NodePath(""), "%s must have a down neighbor" % unique_name)
	# Forward order: Mid-join -> the four experiments (in order) -> Done.
	var current: Control = mid_join
	for unique_name: String in CHECK_NAMES:
		current = current.get_node(current.focus_neighbor_bottom) as Control
		assert_eq(current, _check(lobby, unique_name), "next stop after the previous one is %s" % unique_name)
	assert_eq(current.get_node(current.focus_neighbor_bottom), close_button, "the last experiment leads to Done")
	# Backward order mirrors it.
	assert_eq(close_button.get_node(close_button.focus_neighbor_top), _check(lobby, CHECK_NAMES[3]))
	assert_eq(_check(lobby, CHECK_NAMES[0]).get_node(_check(lobby, CHECK_NAMES[0]).focus_neighbor_top), mid_join)


func test_experiment_checkboxes_stay_out_of_the_main_screen_loop() -> void:
	# They live in the popup, so a Tab on the main screen must never land on a
	# control the popup has not opened yet (no invisible focus stops).
	var lobby: Lobby = _make_lobby(true)
	for unique_name: String in CHECK_NAMES:
		assert_false(lobby._main_chain.has(_check(lobby, unique_name)), "%s is not in the main loop" % unique_name)
		assert_true(lobby._popup_chain.has(_check(lobby, unique_name)), "%s is in the popup loop" % unique_name)
	assert_false((lobby.get_node("%AdvancedPopup") as Control).visible, "the popup starts closed")


func test_popup_loop_stays_closed_with_the_experiments_added() -> void:
	var lobby: Lobby = _make_lobby(true)
	var start: Control = lobby.get_node("%TiltModeOption") as Control
	var current: Control = start
	var steps: int = 0
	var visited: Array[Control] = []
	while steps < lobby._popup_chain.size() + 2:
		current = current.get_node(current.focus_neighbor_bottom) as Control
		visited.append(current)
		steps += 1
		if current == start:
			break
	assert_eq(current, start, "the popup chain wraps back to its own start")
	for unique_name: String in CHECK_NAMES:
		assert_true(visited.has(_check(lobby, unique_name)), "%s is on the loop" % unique_name)
