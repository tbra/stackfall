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
