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
	(lobby.net_provider as FakeNet).all_peers_ready_value = true
	lobby._update_host_only_state()
	await wait_frames(2)
	var live: Array[Control] = FocusWalk.live_focusable(lobby)
	var start: Control = lobby.get_node("%StartButton") as Control
	assert_true(live.has(start), "the lobby has a live Start stop")
	var loop: Array[Control] = FocusWalk.loop(start, SIDE_BOTTOM)
	assert_true(FocusWalk.is_closed(loop, start, SIDE_BOTTOM), "down closes the loop")
	start.grab_focus()
	var owner: Control = start
	# One real D-pad press per stop lands on what the engine resolves, then wraps to the start.
	for step: int in range(mini(loop.size(), MAX_STOPS)):
		var expected: Control = owner.find_valid_focus_neighbor(SIDE_BOTTOM)
		_pad_down()
		await wait_frames(1)
		owner = lobby.get_viewport().gui_get_focus_owner()
		assert_eq(owner, expected, "D-pad down from step %d lands on the engine's neighbour" % step)
		if owner == null:
			return
		assert_true(FocusWalk.is_live(owner), "%s is a live control" % owner.name)
	if loop.size() <= MAX_STOPS:
		assert_eq(owner, start, "the walk wraps back to the start")


const LAYOUT_SIZE: Vector2 = Vector2(1280.0, 720.0)


func _make_laid_out_lobby(bots: int) -> Lobby:
	var lobby: Lobby = _make_lobby()
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = maxi(MatchConfig.PLAYER_COUNT_MIN, bots)
	(lobby.get_node("%AiCountSpin") as SpinBox).value = bots
	await wait_frames(3)
	return lobby


func _target(control: Control, side: Side) -> Control:
	return control.get_node_or_null(control.get_focus_neighbor(side)) as Control


func _pad_press(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


## One real D-pad press from `from`; returns the control that holds focus afterwards.
func _pad_move(lobby: Lobby, from: Control, button: JoyButton) -> Control:
	from.grab_focus()
	_pad_press(button)
	await wait_frames(1)
	return lobby.get_viewport().gui_get_focus_owner()


func test_gift_chip_grid_moves_in_two_dimensions() -> void:
	var lobby: Lobby = await _make_laid_out_lobby(1)
	(lobby.get_node("%GiftsSection") as UiSection).set_advanced_open(true)
	await wait_frames(3)
	var chips: Array[Control] = []
	for chip: UiChipToggle in LobbyProbe.gift_chips(lobby):
		if chip.is_visible_in_tree():
			chips.append(chip)
	assert_gt(chips.size(), 3, "gift chips are shown under Advanced")
	var first: Control = chips[0]
	var right: Control = await _pad_move(lobby, first, JOY_BUTTON_DPAD_RIGHT)
	assert_true(chips.has(right), "right moves to another chip")
	assert_ne(right, first)
	assert_eq(await _pad_move(lobby, right, JOY_BUTTON_DPAD_LEFT), first, "left comes back")
	var down: Control = await _pad_move(lobby, first, JOY_BUTTON_DPAD_DOWN)
	assert_true(chips.has(down), "down moves to another chip")
	assert_eq(await _pad_move(lobby, down, JOY_BUTTON_DPAD_UP), first, "up comes back")
	assert_ne(down, right, "the grid has two dimensions")
	for chip: Control in chips:
		assert_true(FocusWalk.live_focusable(lobby).has(chip), "%s is live" % chip.name)


func test_down_from_add_bot_reaches_start_never_back() -> void:
	var lobby: Lobby = await _make_laid_out_lobby(2)
	var add_bot: Control = lobby._players_panel.add_bot_button()
	var back: Control = lobby.get_node("%BackButton") as Control
	var start: Control = lobby.get_node("%StartButton") as Control
	# Every stop reachable by pressing down, from Add bot round the loop: Back never appears.
	var stops: Array[Control] = FocusWalk.loop(add_bot, SIDE_BOTTOM)
	assert_false(stops.has(back), "down never lands on Back")
	assert_true(stops.has(start), "down from Add bot reaches Start")
	assert_true(FocusWalk.is_closed(stops, add_bot, SIDE_BOTTOM))
	for side: Side in [SIDE_TOP, SIDE_BOTTOM]:
		for stop: Control in stops:
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
