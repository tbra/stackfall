extends GutTest
## A gifts switch that is off hides Frequency and the GIFTS Advanced bar from focus,
## the new Experiments master switch hides its Advanced bar and starts matches with no experiment
## active, and it replicates host -> client like the gifts switch.

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


func _start_of(lobby: Lobby) -> Control:
	return lobby.get_node("%StartButton") as Control


## Every stop one focus-down loop visits from the footer's Start button.
func _stops(lobby: Lobby) -> Array[Control]:
	return FocusWalk.loop(_start_of(lobby))


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


## Walks the loop with synthetic pad D-pad-down presses; returns every focused control it lands on.
func _walk_with_pad(lobby: Lobby) -> Array[Control]:
	var first: Control = _start_of(lobby)
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


func test_gifts_off_greys_frequency_and_advanced_and_focus_skips_them() -> void:
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
	assert_true(freq.is_visible_in_tree(), "gifts off: Frequency stays visible")
	assert_false((freq as UiSegmentMeter).editable, "gifts off: Frequency is read-only")
	assert_eq(freq.focus_mode, Control.FOCUS_NONE)
	assert_true(section.advanced_button.visible, "gifts off: Advanced bar stays visible")
	assert_true(section.advanced_button.disabled, "gifts off: Advanced bar disabled")
	assert_false(section.advanced.visible, "gifts off: Advanced block closed")
	var stops: Array[Control] = _stops(lobby)
	assert_false(stops.has(freq) or stops.has(section.advanced_button) or stops.has(chips[0]), "no hidden stop in the chain")
	var walked: Array[Control] = await _walk_with_pad(lobby)
	assert_false(walked.has(freq) or walked.has(section.advanced_button) or walked.has(chips[0]), "pad focus never lands on them")
	assert_true(walked.has(lobby.get_node("%GiftsCheck")), "the gifts switch itself stays a stop")

	(lobby.get_node("%GiftsCheck") as UiToggle).button_pressed = true
	await wait_frames(2)
	assert_true((freq as UiSegmentMeter).editable, "gifts on again: Frequency editable")
	assert_false(section.advanced_button.disabled, "Advanced bar enabled again")
	assert_true(_stops(lobby).has(freq) and _stops(lobby).has(section.advanced_button))


func test_experiments_off_hides_advanced_and_focus_skips_it_keyboard_and_pad() -> void:
	var lobby: Lobby = _make_lobby()
	await wait_frames(2)
	var check: UiToggle = lobby.get_node("%ExperimentsCheck")
	var section: UiSection = lobby.get_node("%ExperimentsSection")
	var chip: UiChipToggle = lobby._qol_checks[0]
	assert_false(check.button_pressed, "default OFF: no experiment runs until the host opts in")
	assert_null(section.advanced_button, "experiments have no Advanced sub-section")
	assert_false(lobby._config_from_controls().experiments_enabled)
	assert_false(chip.is_visible_in_tree(), "default off: options hidden")
	assert_false(_stops(lobby).has(chip))

	# Keyboard path: focus the toggle and press ui_accept.
	check.grab_focus()
	_action_press(&"ui_accept")
	await wait_frames(2)
	assert_true(check.button_pressed, "ui_accept switched it on")
	assert_true(chip.is_visible_in_tree(), "experiments on: options shown")
	assert_true(_stops(lobby).has(chip))
	assert_true(lobby._config_from_controls().experiments_enabled)
	check.button_pressed = false
	await wait_frames(2)
	assert_false(chip.is_visible_in_tree(), "experiments off again: options hidden")
	assert_false(_stops(lobby).has(chip))
	var walked: Array[Control] = await _walk_with_pad(lobby)
	assert_false(walked.has(chip), "pad focus skips the hidden options")
	assert_true(walked.has(check), "the master switch stays a stop")

	check.grab_focus()
	_pad_press(JOY_BUTTON_A)
	await wait_frames(2)
	assert_true(check.button_pressed, "pad A switched it back on")
	assert_true(chip.is_visible_in_tree())
	assert_true(_stops(lobby).has(chip))


func _any_toggle_on(qol: QolExperiments) -> bool:
	return qol.timer_pause_enabled or qol.backlog_enabled or qol.goal_radius_enabled or qol.gift_slot_enabled or qol.gift_loads_next


func test_experiments_off_keeps_the_chip_selection_and_starts_with_none_active() -> void:
	var lobby: Lobby = _make_lobby()
	await wait_frames(1)
	(lobby.get_node("%ExperimentsCheck") as UiToggle).button_pressed = true
	(lobby.get_node("%QolBacklogCheck") as UiChipToggle).button_pressed = true
	(lobby.get_node("%QolGoalRadiusCheck") as UiChipToggle).button_pressed = true
	(lobby.get_node("%QolGiftLoadsNextCheck") as UiChipToggle).button_pressed = true
	assert_true(_any_toggle_on(lobby._config_from_controls().qol), "on: the chips apply")
	(lobby.get_node("%ExperimentsCheck") as UiToggle).button_pressed = false
	var off_config: MatchConfig = lobby._config_from_controls()
	assert_false(off_config.experiments_enabled)
	assert_true((lobby.get_node("%QolBacklogCheck") as UiChipToggle).button_pressed, "chip selection kept")
	# The round trip a real start takes: dict -> from_dict -> sanitize (MatchLifecycle.start_match).
	var started: MatchConfig = MatchConfig.from_dict(off_config.to_dict())
	started.sanitize()
	assert_true(_any_toggle_on(started.qol), "a published, sanitized config still carries the chips")
	started.apply_experiments_switch()
	assert_false(_any_toggle_on(started.qol), "off: no experiment active in the started match")
	assert_true(started.qol.gift_after_next_in_force(), "off: the gift-loads-next chip falls back to the after-next rule")
	(lobby.get_node("%ExperimentsCheck") as UiToggle).button_pressed = true
	var again: MatchConfig = MatchConfig.from_dict(lobby._config_from_controls().to_dict())
	again.sanitize()
	assert_true(again.qol.backlog_enabled and again.qol.goal_radius_enabled, "on again: the previous selection applies")


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

	(host_lobby.get_node("%ExperimentsCheck") as UiToggle).button_pressed = true
	assert_true(await _wait_for(func() -> bool:
		return bool(client.lobby_data().get("experiments_enabled", false))
	), "the host's setting reached the client over ENet")
	var mirrored: UiToggle = client_lobby.get_node("%ExperimentsCheck") as UiToggle
	assert_true(await _wait_for(func() -> bool: return mirrored.button_pressed), "the client lobby mirrors it")
	assert_true(mirrored.disabled, "a client cannot change it")
	assert_true((client_lobby.get_node("%QolBacklogCheck") as Control).is_visible_in_tree(), "and its options show too")

	# A client edit never publishes and the host keeps its value.
	mirrored.button_pressed = false
	client_lobby._on_setting_changed()
	for _i: int in range(30):
		await get_tree().process_frame
	assert_true(bool(host.lobby_data().get("experiments_enabled", false)), "the host's value is unchanged")
	assert_true((host_lobby.get_node("%ExperimentsCheck") as UiToggle).button_pressed)
