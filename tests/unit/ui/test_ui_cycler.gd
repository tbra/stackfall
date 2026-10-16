extends GutTest
## UiCycler: wrap both ways, disabled items skipped, one signal per step,
## ui_left / ui_right, stick friction around the deadzone, square buttons, hugs content.

var _picked: Array[int] = []


func _make(count: int = 4, start: int = 0) -> UiCycler:
	var cycler: UiCycler = UiCycler.new()
	for i: int in count:
		cycler.add_item("Item %d" % i)
	cycler.select(start)
	cycler.item_selected.connect(func(i: int) -> void: _picked.append(i))
	add_child_autofree(cycler)
	return cycler


func before_each() -> void:
	_picked.clear()


func _action(action: StringName, pressed: bool = true) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func test_wraps_both_ways_and_emits_once_per_step() -> void:
	var cycler: UiCycler = _make(3, 2)
	assert_true(cycler.nudge(1))
	assert_eq(cycler.selected(), 0, "past the last wraps to the first")
	assert_true(cycler.nudge(-1))
	assert_eq(cycler.selected(), 2, "before the first wraps to the last")
	assert_eq(_picked, [0, 2])


func test_disabled_items_are_skipped() -> void:
	var cycler: UiCycler = _make(4, 0)
	cycler.set_item_disabled(1, true)
	cycler.set_item_disabled(3, true)
	cycler.nudge(1)
	assert_eq(cycler.selected(), 2)
	cycler.nudge(1)
	assert_eq(cycler.selected(), 0, "wraps over the disabled tail")
	cycler.nudge(-1)
	assert_eq(cycler.selected(), 2)


func test_ui_left_and_right_keys_step() -> void:
	var cycler: UiCycler = _make(3, 0)
	await wait_frames(1)
	cycler.grab_focus()
	cycler._gui_input(_action(&"ui_left"))
	assert_eq(cycler.selected(), 2)
	cycler._gui_input(_action(&"ui_left", false))
	cycler._gui_input(_action(&"ui_right"))
	assert_eq(cycler.selected(), 0)
	cycler._gui_input(_action(&"ui_right", false))
	assert_false(cycler.is_processing())
	assert_eq(_picked, [2, 0])


func test_clicking_the_buttons_cycles() -> void:
	var cycler: UiCycler = _make(3, 0)
	await wait_frames(2)
	cycler.next_button.button_down.emit()
	assert_eq(cycler.selected(), 1)
	cycler.next_button.button_up.emit()
	cycler.prev_button.button_down.emit()
	assert_eq(cycler.selected(), 0)
	cycler.prev_button.button_up.emit()
	assert_false(cycler.is_processing())


func test_hold_repeats_after_the_delay() -> void:
	var cycler: UiCycler = _make(5, 0)
	await wait_frames(1)
	cycler.grab_focus()
	var tuning: SliderNavTuning = UiHoldRepeat.TUNING
	Input.action_press(&"ui_right")
	cycler._gui_input(_action(&"ui_right"))
	cycler.advance(tuning.repeat_delay_sec - 0.01)
	assert_eq(cycler.selected(), 1, "no repeat before the delay")
	cycler.advance(0.02)
	assert_eq(cycler.selected(), 2)
	Input.action_release(&"ui_right")
	cycler.advance(tuning.repeat_interval_sec)
	assert_false(cycler.is_processing())


func test_stick_around_the_deadzone_steps_exactly_once() -> void:
	var cycler: UiCycler = _make(5, 0)
	await wait_frames(1)
	cycler.grab_focus()
	var tuning: SliderNavTuning = UiHoldRepeat.TUNING
	var axis: Array[float] = [tuning.stick_press_threshold + 0.05]
	cycler.axis_reader = func(_device: int, _a: int) -> float: return axis[0]
	var push: InputEventJoypadMotion = InputEventJoypadMotion.new()
	push.axis = JOY_AXIS_LEFT_X
	push.axis_value = axis[0]
	cycler._gui_input(push)
	assert_eq(cycler.selected(), 1, "the press steps once")
	# Jitter between the release and press thresholds must not retrigger.
	for jitter: float in [tuning.stick_release_threshold + 0.02, tuning.stick_press_threshold + 0.02]:
		axis[0] = jitter
		push.axis_value = jitter
		cycler._gui_input(push)
		cycler.advance(0.01)
	assert_eq(cycler.selected(), 1, "hysteresis: still one step")
	assert_eq(_picked.size(), 1)
	axis[0] = tuning.stick_release_threshold - 0.05
	push.axis_value = axis[0]
	cycler._gui_input(push)
	assert_false(cycler.is_processing())


func test_disabled_blocks_input() -> void:
	var cycler: UiCycler = _make(3, 0)
	cycler.disabled = true
	assert_true(cycler.prev_button.disabled)
	cycler._gui_input(_action(&"ui_right"))
	assert_eq(cycler.selected(), 0)
