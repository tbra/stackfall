extends GutTest
## Bontago-hfa.5 (UI reskin P3): gamepad focus stays visible and reachable on the restyled lobby.
## A synthetic D-pad-down press (InputEventJoypadButton through Input.parse_input_event) walks
## the lobby's focus loop, and every stop keeps a focus style from the shared theme.

const MAX_STOPS: int = 40


func _make_lobby() -> Lobby:
	var scene: PackedScene = load("res://ui/Lobby.tscn")
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
