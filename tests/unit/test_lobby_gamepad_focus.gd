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
		var style: StyleBox = stop.get_theme_stylebox(&"focus")
		assert_not_null(style, "%s has a focus style" % stop.name)
		assert_false(style is StyleBoxEmpty, "%s focus style is drawn, not empty" % stop.name)


func _pad_right() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = JOY_BUTTON_DPAD_RIGHT
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


## Bontago-hfa.11: the five lobby sliders are SegmentMeters, and the pad still steps the focused one.
func test_lobby_sliders_are_segment_meters_and_dpad_right_still_steps_them() -> void:
	var lobby: Lobby = _make_lobby()
	await wait_frames(2)
	for path: String in ["%DiscSizeSlider", "%GravitySlider", "%SpecialFreqSlider", "%MatchTimerSlider", "%RoundTimerSlider"]:
		var slider: HSlider = lobby.get_node(path) as HSlider
		assert_not_null(slider.get_node_or_null("SegmentMeter"), "%s is drawn as a SegmentMeter" % path)
	var disc: HSlider = lobby.get_node("%DiscSizeSlider") as HSlider
	disc.value = disc.min_value
	disc.grab_focus()
	var meter: SegmentMeter = disc.get_node("SegmentMeter") as SegmentMeter
	assert_not_null(meter)
	var before: int = SegmentMeter.filled_cells(disc, 10)
	_pad_right()
	await wait_frames(1)
	assert_gt(disc.value, disc.min_value, "D-pad right steps the focused slider")
	assert_gt(SegmentMeter.filled_cells(disc, 10), before, "the meter follows the value")
