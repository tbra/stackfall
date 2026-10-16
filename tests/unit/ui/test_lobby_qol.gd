extends GutTest
## The lobby's
## "Experiments" section -- four opt-in QoL toggles. (S1b): they are the
## EXPERIMENTS section's Advanced block of the lobby's settings column (the Advanced rules
## popup is gone); the header summary reads "n on". Host-editable and read-only for a
## client. The checkboxes are the single
## source of the four enable flags on the published MatchConfig.qol; the
## numeric parameters stay in the shared config/match/qol_experiments.tres (F4).

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


func _check(lobby: Lobby, unique_name: String) -> UiChipToggle:
	return lobby.get_node(unique_name) as UiChipToggle


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

func test_each_toggle_publishes_exactly_its_own_flag() -> void:
	var expected_keys: Array[String] = ["timer_pause_enabled", "backlog_enabled", "goal_radius_enabled", "gift_slot_enabled"]
	for i: int in range(CHECK_NAMES.size()):
		var lobby: Lobby = _make_lobby(true)
		var check: UiChipToggle = _check(lobby, CHECK_NAMES[i])
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


func test_wire_garbage_in_qol_is_ignored_safely() -> void:
	var lobby: Lobby = _make_lobby(false)
	var data: Dictionary = MatchConfig.new().to_dict()
	data["qol"] = {"backlog_enabled": "yes", "goal_radius_enabled": 1, "gift_slot_enabled": true}
	Events.net_lobby_data_changed.emit(data)
	assert_eq(_flags(lobby), [false, false, false, true], "wrong-typed flags keep the OFF default")


# --- Gift-after-next trial chip --------------------------

const AFTER_NEXT_CHIP: String = "%QolGiftAfterNextCheck"


func test_the_host_publishes_the_gift_after_next_chip_and_a_client_mirrors_it() -> void:
	var host_lobby: Lobby = _make_lobby(true)
	_check(host_lobby, AFTER_NEXT_CHIP).button_pressed = false
	var calls: Array[Dictionary] = _fake_of(host_lobby).set_lobby_data_calls
	assert_eq(calls.size(), 1)
	var data: Dictionary = calls[0]
	assert_false(bool((data["qol"] as Dictionary)["gift_queue_after_next"]))
	assert_false(MatchConfig.from_dict(data).qol.gift_after_next_in_force())
	var client_lobby: Lobby = _make_lobby(false)
	assert_true(_check(client_lobby, AFTER_NEXT_CHIP).disabled, "read-only for a client")
	Events.net_lobby_data_changed.emit(data)
	assert_false(_check(client_lobby, AFTER_NEXT_CHIP).button_pressed, "the client shows the host's choice")
	assert_eq(_fake_of(client_lobby).set_lobby_data_calls.size(), 0, "mirroring never re-publishes")
	_check(host_lobby, AFTER_NEXT_CHIP).button_pressed = true
	assert_true(bool((calls[1]["qol"] as Dictionary)["gift_queue_after_next"]))


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


func test_experiment_checkboxes_join_the_main_loop_once_the_section_opens() -> void:
	var lobby: Lobby = _make_lobby(true)
	var section: UiSection = lobby.get_node("%ExperimentsSection") as UiSection
	section.advanced_button.button_pressed = true
	assert_true(section.advanced.visible, "the chip of the Experiments section opens its checks")
	for unique_name: String in CHECK_NAMES:
		var check: UiChipToggle = _check(lobby, unique_name)
		assert_true(check.is_visible_in_tree(), "%s is visible once the section is open" % unique_name)
		assert_eq(check.focus_mode, Control.FOCUS_ALL, "%s is focusable" % unique_name)
		assert_ne(check.focus_neighbor_top, NodePath(""), "%s must have an up neighbor" % unique_name)
		assert_ne(check.focus_neighbor_bottom, NodePath(""), "%s must have a down neighbor" % unique_name)
	# Forward order: the chip -> the four experiments (in order) -> the next stop.
	var current: Control = section.advanced_button
	for unique_name: String in CHECK_NAMES:
		current = current.get_node(current.focus_neighbor_bottom) as Control
		assert_eq(current, _check(lobby, unique_name), "next stop after the previous one is %s" % unique_name)
	var after: Control = current.get_node(current.focus_neighbor_bottom) as Control
	assert_false(CHECK_NAMES.has("%" + String(after.name)), "the loop leaves the experiments after the last one")
	# Backward order mirrors it.
	var first: UiChipToggle = _check(lobby, CHECK_NAMES[0])
	assert_eq(first.get_node(first.focus_neighbor_top), section.advanced_button)
	assert_eq(after.get_node(after.focus_neighbor_top), _check(lobby, CHECK_NAMES[3]))
