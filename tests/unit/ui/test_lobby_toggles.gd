extends GutTest
## Bontago-1pi.159.53 / .59 / .60: the round-length row reads "Round length" in every game mode (no
## "required" wording anywhere), a gifts switch that is off hides Frequency and the GIFTS Advanced bar,
## the new Experiments master switch hides its Advanced bar and starts matches with no experiment
## active, and it replicates host -> client like the gifts switch.

const ROUND_LENGTH_TEXT: String = "Round length (min)"
const OLD_TIMER_TEXT: String = "Match timer (min)"
const MAX_STOPS: int = 60
const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")


func _make_lobby(is_host: bool = true) -> Lobby:
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


func _visible_timer_row(lobby: Lobby) -> UiRow:
	var rows: Array[UiRow] = []
	for row_name: String in ["%MatchTimerCol", "%RoundTimerCol"]:
		var row: UiRow = lobby.get_node(row_name) as UiRow
		if row.visible:
			rows.append(row)
	assert_eq(rows.size(), 1, "exactly one timer row is shown")
	return rows[0] if not rows.is_empty() else null


func _all_texts(node: Node, out: PackedStringArray) -> void:
	for child: Node in node.get_children():
		var label: Label = child as Label
		if label != null:
			out.append(label.text)
		var button: Button = child as Button
		if button != null:
			out.append(button.text)
		_all_texts(child, out)


func _assert_round_length_everywhere(lobby: Lobby, who: String) -> void:
	for mode: int in MatchConfig.GameMode.values():
		_pick_mode(lobby, mode)
		assert_eq(_visible_timer_row(lobby).label.text, ROUND_LENGTH_TEXT, "%s, mode %d" % [who, mode])
		var texts: PackedStringArray = PackedStringArray()
		_all_texts(lobby, texts)
		for text: String in texts:
			assert_false(text.to_lower().contains("required"), "no 'required' text (%s: %s, mode %d)" % [who, text, mode])
			assert_ne(text, OLD_TIMER_TEXT, "the old caption is gone (%s, mode %d)" % [who, mode])


func test_round_length_label_in_every_mode_and_no_required_text() -> void:
	var lobby: Lobby = _make_lobby()
	await wait_frames(1)
	_assert_round_length_everywhere(lobby, "host")


func test_a_client_lobby_shows_round_length_in_every_mode() -> void:
	var lobby: Lobby = _make_lobby(false)
	await wait_frames(1)
	for mode: int in MatchConfig.GameMode.values():
		var data: Dictionary = MatchConfig.new().to_dict()
		data["game_mode"] = mode
		Events.net_lobby_data_changed.emit(data)
		assert_eq(_visible_timer_row(lobby).label.text, ROUND_LENGTH_TEXT, "client, mode %d" % mode)


func _stops(lobby: Lobby) -> Array[Control]:
	return lobby._visible_chain(lobby._main_chain)


func _pad_press(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _action_press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


## Walks the loop with synthetic pad D-pad-down presses; returns every focus owner it lands on.
func _walk_with_pad(lobby: Lobby) -> Array[Control]:
	var first: Control = _stops(lobby)[0]
	first.grab_focus()
	var seen: Array[Control] = [first]
	for _i: int in range(MAX_STOPS):
		_pad_press(JOY_BUTTON_DPAD_DOWN)
		await wait_frames(1)
		var focus_owner: Control = lobby.get_viewport().gui_get_focus_owner()
		if focus_owner == null or focus_owner == first:
			break
		seen.append(focus_owner)
	return seen


func test_gifts_off_hides_frequency_and_advanced_and_focus_skips_them() -> void:
	var lobby: Lobby = _make_lobby()
	await wait_frames(2)
	var freq: Control = lobby.get_node("%SpecialFreqMeter")
	var section: UiSection = lobby.get_node("%GiftsSection")
	var chips: Array[UiChipToggle] = lobby._special_checkboxes
	assert_true(freq.is_visible_in_tree(), "gifts default on: Frequency shown")
	assert_true(section.advanced_button.visible)
	section.set_advanced_open(true)
	await wait_frames(1)
	assert_true(_stops(lobby).has(chips[0]), "open Advanced: chips are stops")

	(lobby.get_node("%GiftsCheck") as UiToggle).button_pressed = false
	await wait_frames(2)
	assert_false(freq.is_visible_in_tree(), "gifts off: Frequency hidden")
	assert_false(section.advanced_button.visible, "gifts off: Advanced bar hidden")
	assert_false(section.advanced.visible, "gifts off: Advanced block closed")
	var stops: Array[Control] = _stops(lobby)
	assert_false(stops.has(freq) or stops.has(section.advanced_button) or stops.has(chips[0]), "no hidden stop in the chain")
	var walked: Array[Control] = await _walk_with_pad(lobby)
	assert_false(walked.has(freq) or walked.has(section.advanced_button) or walked.has(chips[0]), "pad focus never lands on them")
	assert_true(walked.has(lobby.get_node("%GiftsCheck")), "the gifts switch itself stays a stop")

	(lobby.get_node("%GiftsCheck") as UiToggle).button_pressed = true
	await wait_frames(2)
	assert_true(freq.is_visible_in_tree(), "gifts on again: Frequency restored")
	assert_true(section.advanced_button.visible, "Advanced bar restored")
	assert_true(_stops(lobby).has(freq) and _stops(lobby).has(section.advanced_button))


func test_experiments_off_hides_advanced_and_focus_skips_it_keyboard_and_pad() -> void:
	var lobby: Lobby = _make_lobby()
	await wait_frames(2)
	var check: UiToggle = lobby.get_node("%ExperimentsCheck")
	var section: UiSection = lobby.get_node("%ExperimentsSection")
	assert_true(check.button_pressed, "default ON: current behaviour unchanged")
	assert_true(section.advanced_button.visible)
	assert_true(lobby._config_from_controls().experiments_enabled)
	section.set_advanced_open(true)
	await wait_frames(1)
	var chip: UiChipToggle = lobby._qol_checks[0]
	assert_true(_stops(lobby).has(chip))

	# Keyboard path: focus the toggle and press ui_accept.
	check.grab_focus()
	_action_press(&"ui_accept")
	await wait_frames(2)
	assert_false(check.button_pressed, "ui_accept switched it off")
	assert_false(section.advanced_button.visible)
	assert_false(section.advanced.visible)
	assert_false(_stops(lobby).has(chip) or _stops(lobby).has(section.advanced_button))
	var walked: Array[Control] = await _walk_with_pad(lobby)
	assert_false(walked.has(chip) or walked.has(section.advanced_button), "pad focus skips the hidden Advanced")
	assert_true(walked.has(check), "the master switch stays a stop")
	assert_false(lobby._config_from_controls().experiments_enabled)

	check.grab_focus()
	_pad_press(JOY_BUTTON_A)
	await wait_frames(2)
	assert_true(check.button_pressed, "pad A switched it back on")
	assert_true(section.advanced_button.visible)
	assert_true(_stops(lobby).has(section.advanced_button))


func test_experiments_off_keeps_the_chip_selection_and_starts_with_none_active() -> void:
	var lobby: Lobby = _make_lobby()
	await wait_frames(1)
	(lobby.get_node("%QolBacklogCheck") as UiChipToggle).button_pressed = true
	(lobby.get_node("%QolGoalRadiusCheck") as UiChipToggle).button_pressed = true
	assert_true(lobby._config_from_controls().qol.any_enabled(), "on: the chips apply")
	(lobby.get_node("%ExperimentsCheck") as UiToggle).button_pressed = false
	var off_config: MatchConfig = lobby._config_from_controls()
	assert_false(off_config.experiments_enabled)
	assert_true((lobby.get_node("%QolBacklogCheck") as UiChipToggle).button_pressed, "chip selection kept")
	# The round trip a real start takes: dict -> from_dict -> sanitize (MatchLifecycle.start_match).
	var started: MatchConfig = MatchConfig.from_dict(off_config.to_dict())
	started.sanitize()
	assert_true(started.qol.any_enabled(), "a published, sanitized config still carries the chips")
	started.apply_experiments_switch()
	assert_false(started.qol.any_enabled(), "off: no experiment active in the started match")
	assert_eq(started.qol.active_ids().size(), 0)
	(lobby.get_node("%ExperimentsCheck") as UiToggle).button_pressed = true
	var again: MatchConfig = MatchConfig.from_dict(lobby._config_from_controls().to_dict())
	again.sanitize()
	assert_true(again.qol.backlog_enabled and again.qol.goal_radius_enabled, "on again: the previous selection applies")


func test_match_started_with_experiments_off_has_none_active() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.qol = QolExperiments.with_toggles(null, true, true, true, true)
	config.experiments_enabled = false
	Match.start_match(config)
	assert_not_null(Match.config.qol)
	assert_eq(Match.config.qol.active_ids().size(), 0, "no experiment active")
	Match.abort_match()


func _make_net_side(node_name: String) -> Variant:
	var node: Node = _NET_SCRIPT.new()
	node.name = node_name
	var path: NodePath = NodePath(String(get_path()) + "/" + node_name)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), path)
	add_child_autofree(node)
	return node


func _wait_for(condition: Callable, frames: int = 300) -> bool:
	for _i: int in range(frames):
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func test_over_enet_the_experiments_switch_replicates_and_a_client_cannot_change_it() -> void:
	var host: Variant = _make_net_side("T1014HostNet")
	var client: Variant = _make_net_side("T1014ClientNet")
	var port: int = AgentProbe.free_udp_port()
	assert_eq(host.host_game(port, "Hostie"), OK)
	assert_eq(client.join_game("127.0.0.1", port, "Clienty"), OK)
	assert_true(await _wait_for(func() -> bool: return host.peer_ids().size() == 2 and client.local_slot() == 1))

	var host_lobby: Lobby = autofree((load("res://ui/lobby/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(host_lobby)
	host_lobby.net_provider = host
	host_lobby._update_host_only_state()
	var client_lobby: Lobby = autofree((load("res://ui/lobby/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(client_lobby)
	client_lobby.net_provider = client
	client_lobby._update_host_only_state()

	(host_lobby.get_node("%ExperimentsCheck") as UiToggle).button_pressed = false
	assert_true(await _wait_for(func() -> bool:
		return not bool(client.lobby_data().get("experiments_enabled", true))
	), "the host's setting reached the client over ENet")
	var mirrored: UiToggle = client_lobby.get_node("%ExperimentsCheck") as UiToggle
	assert_true(await _wait_for(func() -> bool: return not mirrored.button_pressed), "the client lobby mirrors it")
	assert_true(mirrored.disabled, "a client cannot change it")
	assert_false((client_lobby.get_node("%ExperimentsSection") as UiSection).advanced_button.visible, "and its Advanced is hidden too")

	# A client edit never publishes and the host keeps its value.
	mirrored.button_pressed = true
	client_lobby._on_setting_changed()
	for _i: int in range(30):
		await get_tree().process_frame
	assert_false(bool(host.lobby_data().get("experiments_enabled", true)), "the host's value is unchanged")
	assert_false((host_lobby.get_node("%ExperimentsCheck") as UiToggle).button_pressed)
