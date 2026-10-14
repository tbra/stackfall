extends GutTest
## Bontago-hfa.5 (UI reskin P3): gamepad focus stays visible and reachable on the restyled lobby.
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


func test_every_focus_stop_has_a_visible_focus_style() -> void:
	var lobby: Lobby = _make_lobby()
	await wait_frames(2)
	for stop: Control in lobby._visible_chain(lobby._main_chain):
		assert_ne(stop.focus_mode, Control.FOCUS_NONE, "%s is focusable" % stop.name)
		# The container-based components (UiStepper) draw the Button focus look themselves.
		var style: StyleBox = stop.get_theme_stylebox(&"focus", &"Button")
		assert_not_null(style, "%s has a focus style" % stop.name)
		assert_false(style is StyleBoxEmpty, "%s focus style is drawn, not empty" % stop.name)


func _pad_right() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = JOY_BUTTON_DPAD_RIGHT
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


## Bontago-hfa.11 / 1pi.159.2.1: the lobby's value controls are UiSegmentMeters and UiSteppers, and the
## pad's D-pad right still steps the focused one.
func test_lobby_value_controls_are_components_and_dpad_right_steps_them() -> void:
	var lobby: Lobby = _make_lobby()
	await wait_frames(2)
	for path: String in ["%DiscSizeMeter", "%GravityMeter", "%SpecialFreqMeter"]:
		assert_true(lobby.get_node(path) is UiSegmentMeter, "%s is a UiSegmentMeter" % path)
	for path: String in ["%MatchTimerStepper", "%RoundTimerStepper", "%BlockTimerStepper", "%GoalFlagStepper"]:
		assert_true(lobby.get_node(path) is UiStepper, "%s is a UiStepper" % path)
	var disc: UiSegmentMeter = lobby.get_node("%DiscSizeMeter") as UiSegmentMeter
	disc.value = 1
	disc.grab_focus()
	_pad_right()
	await wait_frames(1)
	assert_gt(disc.value, 1, "D-pad right steps the focused meter")
	var block: UiStepper = lobby.get_node("%BlockTimerStepper") as UiStepper
	var before: int = block.value
	block.grab_focus()
	_pad_right()
	await wait_frames(1)
	assert_eq(block.value, before + 1, "D-pad right steps the focused stepper")


# --- Bontago-1pi.159.23 (L3): selection moves by on-screen position --------------------------

const LAYOUT_SIZE: Vector2 = Vector2(1280.0, 720.0)


func _make_laid_out_lobby(bots: int) -> Lobby:
	var lobby: Lobby = _make_lobby()
	lobby._set_bot_count(bots)
	await wait_frames(3)
	lobby._wire_spatial()
	return lobby


func _target(control: Control, side: Side) -> Control:
	return control.get_node_or_null(control.get_focus_neighbor(side)) as Control


## The panel stops in visual order, grouped per row by their first control.
func _row_diamonds(lobby: Lobby) -> Array[Control]:
	var diamonds: Array[Control] = []
	for row_node: Node in lobby._players_panel._player_rows:
		var row: LobbySeatRow = row_node as LobbySeatRow
		diamonds.append(row.focusable_controls()[0])
	return diamonds


func test_diamond_down_goes_to_the_diamond_below_then_add_bot_and_back() -> void:
	for bots: int in [2, 3, 7]:
		var lobby: Lobby = await _make_laid_out_lobby(bots)
		var diamonds: Array[Control] = _row_diamonds(lobby)
		assert_gt(diamonds.size(), 1, "%d bots: several rows" % bots)
		for i: int in range(diamonds.size() - 1):
			assert_eq(_target(diamonds[i], SIDE_BOTTOM), diamonds[i + 1], "%d bots: down from row %d" % [bots, i])
			assert_eq(_target(diamonds[i + 1], SIDE_TOP), diamonds[i], "%d bots: up from row %d" % [bots, i + 1])
		var add_bot: Control = lobby._players_panel.add_bot_button()
		if add_bot.focus_mode != Control.FOCUS_NONE and add_bot.visible:
			assert_eq(_target(diamonds.back(), SIDE_BOTTOM), add_bot, "%d bots: last row down = Add bot" % bots)
			assert_eq(_target(add_bot, SIDE_TOP), diamonds.back(), "%d bots: Add bot up = last row" % bots)


func test_players_panel_and_settings_column_hop_both_ways() -> void:
	var lobby: Lobby = await _make_laid_out_lobby(3)
	var diamonds: Array[Control] = _row_diamonds(lobby)
	var settings: Array[Control] = lobby._visible_chain(lobby._settings_stops)
	var left: Control = _target(diamonds[0], SIDE_LEFT)
	assert_true(settings.has(left), "left from a row's first control lands in the settings column")
	var back: Control = _target(left, SIDE_RIGHT)
	assert_not_null(back, "right from there goes back")
	assert_true(lobby._players_panel.focus_entries().has(back), "right from the settings stop lands in the players panel")


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


func test_advanced_toggle_keeps_the_wiring_consistent() -> void:
	var lobby: Lobby = await _make_laid_out_lobby(2)
	for open: bool in [true, false, true]:
		lobby._game_section.set_advanced_open(open)
		lobby._gifts_section.set_advanced_open(open)
		await wait_frames(3)
		for stop: Control in lobby._visible_chain(lobby._main_chain):
			for side: Side in [SIDE_TOP, SIDE_BOTTOM]:
				var target: Control = _target(stop, side)
				assert_not_null(target, "%s has a %d neighbour" % [stop.name, side])
				if target != null:
					assert_true(lobby._is_shown(target), "%s -> %s is a shown stop" % [stop.name, target.name])


# --- Bontago-1pi.182: Back is never a stop of the vertical loop ---------------------------------

func _key_down() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_DOWN
	event.physical_keycode = KEY_DOWN
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	var release: InputEventKey = event.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()


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


func test_arrow_key_and_dpad_down_from_add_bot_skip_back() -> void:
	var lobby: Lobby = await _make_laid_out_lobby(2)
	var add_bot: Control = lobby._players_panel.add_bot_button()
	var back: Control = lobby.get_node("%BackButton") as Control
	var expected: Control = _target(add_bot, SIDE_BOTTOM)
	add_bot.grab_focus()
	_key_down()
	await wait_frames(1)
	assert_eq(lobby.get_viewport().gui_get_focus_owner(), expected, "arrow down")
	add_bot.grab_focus()
	_pad_down()
	await wait_frames(1)
	assert_eq(lobby.get_viewport().gui_get_focus_owner(), expected, "d-pad down")
	assert_ne(lobby.get_viewport().gui_get_focus_owner(), back)


func test_left_stick_down_from_add_bot_skips_back() -> void:
	var lobby: Lobby = await _make_laid_out_lobby(2)
	var add_bot: Control = lobby._players_panel.add_bot_button()
	var back: Control = lobby.get_node("%BackButton") as Control
	var expected: Control = _target(add_bot, SIDE_BOTTOM)
	add_bot.grab_focus()
	# The stick drives the same ui_down action Godot's GUI navigation uses.
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_LEFT_Y
	event.axis_value = 1.0
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await wait_frames(1)
	event = event.duplicate() as InputEventJoypadMotion
	event.axis_value = 0.0
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	assert_ne(lobby.get_viewport().gui_get_focus_owner(), back)
	assert_eq(lobby.get_viewport().gui_get_focus_owner(), expected, "left stick down")


# --- Bontago-1pi.159.33: the settings column scrolls with the right stick ---------------------

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


func test_selection_jumps_into_view_after_a_stick_scroll_in_the_settings_column() -> void:
	var lobby: Lobby = _make_lobby()
	# Grow the settings content so the column always overflows its viewport.
	(lobby.get_node("%Settings") as Control).custom_minimum_size.y = TALL_SETTINGS_PX
	await wait_frames(3)
	var scroll: FocusScrollContainer = lobby.get_node("%SettingsScroll") as FocusScrollContainer
	var first: Control = lobby._visible_chain(lobby._settings_stops)[0]
	first.grab_focus()
	scroll.stick_scrolled = false
	scroll.scroll_axis_reader = func() -> float: return 1.0
	for _i: int in 120:
		scroll.scroll_by_stick(1.0 / 60.0)
	await wait_frames(2)
	assert_false(scroll.get_global_rect().encloses(first.get_global_rect()), "the focused row scrolled out of view")
	_pad_down()
	await wait_frames(2)
	var owner: Control = lobby.get_viewport().gui_get_focus_owner()
	assert_ne(owner, first)
	assert_true(scroll.is_ancestor_of(owner), "focus jumped to a row inside the scrolled settings column")
	assert_true(scroll.get_global_rect().intersects(owner.get_global_rect()), "and that row is visible")
