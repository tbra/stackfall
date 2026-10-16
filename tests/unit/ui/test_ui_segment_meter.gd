extends GutTest
## UiSegmentMeter: clamped cell value, formatter, silent set, mouse click / drag,
## ui_left / ui_right (key and pad) steps, hold repeat and stick friction (SliderNavTuning numbers),
## muted = ignores input, row-item contract, legacy overlay still counts cells.

var _values: Array[int] = []


func _make(cells: int = 10, start: int = 5) -> UiSegmentMeter:
	var meter: UiSegmentMeter = UiSegmentMeter.new()
	meter.step_count = cells
	meter.value = start
	meter.value_changed.connect(func(v: int) -> void: _values.append(v))
	add_child_autofree(meter)
	return meter


func before_each() -> void:
	_values.clear()


func _action(action: StringName, pressed: bool = true) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _click(x: float, pressed: bool = true) -> InputEventMouseButton:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	click.position = Vector2(x, 4.0)
	return click


func test_never_fewer_than_five_cells_and_value_clamps() -> void:
	var meter: UiSegmentMeter = _make(2, 0)
	assert_eq(meter.step_count, UiSegmentMeter.MIN_STEP_COUNT)
	meter.value = 99
	assert_eq(meter.value, UiSegmentMeter.MIN_STEP_COUNT)
	meter.value = -3
	assert_eq(meter.value, 0)


func test_emits_only_on_change_and_silent_set_does_not() -> void:
	var meter: UiSegmentMeter = _make()
	_values.clear()
	meter.value = 5
	assert_eq(_values.size(), 0, "same value, no emit")
	meter.value = 7
	meter.set_value_silent(2)
	assert_eq(_values, [7])
	assert_eq(meter.value, 2)


func test_ui_left_and_right_step_one_cell() -> void:
	var meter: UiSegmentMeter = _make()
	meter.grab_focus()
	meter._gui_input(_action(&"ui_right"))
	meter._gui_input(_action(&"ui_right", false))
	assert_eq(meter.value, 6)
	meter._gui_input(_action(&"ui_left"))
	meter._gui_input(_action(&"ui_left", false))
	assert_eq(meter.value, 5)
	assert_false(meter.is_processing(), "released")


func test_a_stuck_press_repeats_after_the_delay_while_held() -> void:
	var meter: UiSegmentMeter = _make()
	meter.grab_focus()
	meter._hold.start(1, UiHoldRepeat.SOURCE_KEY)
	assert_eq(meter.value, 6)
	Input.action_press(&"ui_right")
	meter.advance(UiHoldRepeat.TUNING.repeat_delay_sec * 0.5)
	assert_eq(meter.value, 6, "before the delay nothing repeats")
	meter.advance(UiHoldRepeat.TUNING.repeat_delay_sec)
	assert_eq(meter.value, 7, "first repeat after the delay")
	Input.action_release(&"ui_right")
	meter.advance(UiHoldRepeat.TUNING.repeat_interval_sec)
	assert_false(meter.is_processing(), "a missed release stops the repeat")


func test_stick_below_repeat_threshold_gives_one_step_only() -> void:
	var meter: UiSegmentMeter = _make()
	meter.grab_focus()
	var partial: float = (UiHoldRepeat.TUNING.stick_press_threshold + UiHoldRepeat.TUNING.stick_repeat_threshold) * 0.5
	meter.axis_reader = func(_device: int, _axis: int) -> float: return partial
	meter._hold.start(1, UiHoldRepeat.SOURCE_STICK, JOY_AXIS_LEFT_X)
	assert_eq(meter.value, 6)
	meter.advance(UiHoldRepeat.TUNING.stick_repeat_delay_sec * 3.0)
	assert_eq(meter.value, 6, "a partial push never auto-repeats")
	meter.axis_reader = func(_device: int, _axis: int) -> float: return 1.0
	meter.advance(UiHoldRepeat.TUNING.stick_repeat_delay_sec * 2.0)
	assert_gt(meter.value, 6, "full deflection repeats")


func test_mouse_click_and_drag_set_the_cell_under_the_pointer() -> void:
	var meter: UiSegmentMeter = _make(10, 0)
	meter.size = Vector2(300.0, float(UiRowItem.metrics().row_height_px))
	var width: float = meter.well_width()
	meter._gui_input(_click(width * 0.5))
	assert_eq(meter.value, 5)
	var drag: InputEventMouseMotion = InputEventMouseMotion.new()
	drag.position = Vector2(width * 0.9, 4.0)
	meter._gui_input(drag)
	assert_eq(meter.value, 9, "dragging follows the pointer")
	meter._gui_input(_click(width * 0.9, false))
	drag.position = Vector2(width * 0.2, 4.0)
	meter._gui_input(drag)
	assert_eq(meter.value, 9, "after release a move does nothing")


func test_muted_meter_ignores_input() -> void:
	var meter: UiSegmentMeter = _make()
	meter.editable = false
	meter._gui_input(_action(&"ui_right"))
	meter._gui_input(_click(10.0))
	assert_eq(meter.value, 5)
	assert_false(meter.nudge(1))
