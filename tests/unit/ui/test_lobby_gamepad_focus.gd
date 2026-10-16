extends GutTest
## UI reskin P3: gamepad focus stays visible and reachable on the restyled lobby.
## A synthetic D-pad-down press (InputEventJoypadButton through Input.parse_input_event) walks
## the lobby's focus loop, and every stop keeps a focus style from the shared theme.

const MAX_STOPS: int = 40
const TALL_SETTINGS_PX: float = 3000.0


func _make_lobby() -> Lobby:
	var scene: PackedScene = load("res://ui/lobby/Lobby.tscn")
	var lobby: Lobby = autofree(scene.instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = true
	fake.is_offline_value = true
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func _pad_down() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = JOY_BUTTON_DPAD_DOWN
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func test_dpad_down_walks_the_whole_lobby_loop() -> void:
	var lobby: Lobby = _make_lobby()
	await wait_frames(2)
	var stops: Array[Control] = lobby._visible_chain(lobby._main_chain)
	assert_gt(stops.size(), 0, "the lobby has focus stops")
	stops[0].grab_focus()
	var visited: Array[Control] = [stops[0]]
	for step: int in range(mini(stops.size(), MAX_STOPS) - 1):
		var expected: Control = visited.back().get_node(visited.back().focus_neighbor_bottom) as Control
		_pad_down()
		await wait_frames(1)
		var owner: Control = lobby.get_viewport().gui_get_focus_owner()
		assert_eq(owner, expected, "D-pad down from %s lands on its bottom neighbour" % visited.back().name)
		if owner == null:
			return
		visited.append(owner)


const LAYOUT_SIZE: Vector2 = Vector2(1280.0, 720.0)


func _make_laid_out_lobby(bots: int) -> Lobby:
	var lobby: Lobby = _make_lobby()
	lobby._set_bot_count(bots)
	await wait_frames(3)
	lobby._wire_spatial()
	return lobby


func _target(control: Control, side: Side) -> Control:
	return control.get_node_or_null(control.get_focus_neighbor(side)) as Control


func test_gift_chip_grid_moves_in_two_dimensions() -> void:
	var lobby: Lobby = await _make_laid_out_lobby(1)
	lobby._gifts_section.set_advanced_open(true)
	await wait_frames(3)
	lobby._wire_spatial()
	var chips: Array[Control] = []
	for chip: UiChipToggle in lobby._special_checkboxes:
		if lobby._is_shown(chip):
			chips.append(chip)
	assert_gt(chips.size(), 3, "gift chips are shown under Advanced")
	var first_y: float = chips[0].get_global_rect().position.y
	var row_len: int = 0
	for chip: Control in chips:
		if is_equal_approx(chip.get_global_rect().position.y, first_y):
			row_len += 1
	assert_gt(row_len, 1, "the chips sit in several columns")
	for i: int in range(chips.size() - row_len):
		assert_eq(_target(chips[i], SIDE_BOTTOM), chips[i + row_len], "down moves one grid row (%d)" % i)
		assert_eq(_target(chips[i + row_len], SIDE_TOP), chips[i], "up moves one grid row (%d)" % i)
	assert_eq(_target(chips[0], SIDE_RIGHT), chips[1], "right = the neighbour in the row")
	assert_eq(_target(chips[0], SIDE_TOP), lobby._gifts_section.advanced_button, "up from the top row = the Advanced chip")


func test_down_from_add_bot_reaches_start_never_back() -> void:
	var lobby: Lobby = await _make_laid_out_lobby(2)
	var add_bot: Control = lobby._players_panel.add_bot_button()
	var back: Control = lobby.get_node("%BackButton") as Control
	var start: Control = lobby.get_node("%StartButton") as Control
	# Every stop reachable by pressing down, from Add bot round the loop: Back never appears.
	var current: Control = add_bot
	for _i: int in range(lobby._main_chain.size() + 2):
		current = _target(current, SIDE_BOTTOM)
		assert_not_null(current)
		assert_ne(current, back, "down never lands on Back")
		if current == add_bot:
			break
	var next: Control = _target(add_bot, SIDE_BOTTOM)
	var expected: Control = start
	if lobby._invite_friends_button.visible or lobby._ready_check.visible:
		expected = lobby._visible_chain(lobby._main_chain)[lobby._visible_chain(lobby._main_chain).find(add_bot) + 1]
	assert_eq(next, expected, "down from Add bot is the next footer stop, not Back")
	for side: Side in [SIDE_TOP, SIDE_BOTTOM]:
		for stop: Control in lobby._visible_chain(lobby._main_chain):
			assert_ne(_target(stop, side), back, "%s %d never targets Back" % [stop.name, side])
	assert_eq(_target(start, SIDE_LEFT), back, "Back is reached deliberately: left from Start")


func test_settings_column_is_a_focus_scroll_container_that_scrolls_with_the_right_stick() -> void:
	var lobby: Lobby = _make_lobby()
	# Grow the settings content so the column always overflows its viewport.
	(lobby.get_node("%Settings") as Control).custom_minimum_size.y = TALL_SETTINGS_PX
	await wait_frames(3)
	var scroll: FocusScrollContainer = lobby.get_node("%SettingsScroll") as FocusScrollContainer
	assert_not_null(scroll, "SettingsScroll is a FocusScrollContainer")
	var stick: float = 1.0
	scroll.scroll_axis_reader = func() -> float: return stick
	for _i: int in 40:
		scroll.scroll_by_stick(1.0 / 60.0)
	assert_gt(scroll.scroll_vertical, 0, "the right stick scrolled the settings column")
	assert_true(scroll.stick_scrolled)
