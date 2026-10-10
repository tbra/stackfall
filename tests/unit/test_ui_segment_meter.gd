extends GutTest
## Bontago-1pi.159.7: UiSegmentMeter: clamped cell value, formatter, silent set, mouse click / drag,
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


func test_pure_helpers() -> void:
	assert_eq(UiSegmentMeter.step_value(5, 1, 10), 6)
	assert_eq(UiSegmentMeter.step_value(10, 1, 10), 10)
	assert_eq(UiSegmentMeter.step_value(0, -1, 10), 0)
	assert_eq(UiSegmentMeter.value_from_x(50.0, 100.0, 10), 5)
	assert_eq(UiSegmentMeter.value_from_x(-4.0, 100.0, 10), 0)
	assert_eq(UiSegmentMeter.value_from_x(400.0, 100.0, 10), 10)
	assert_eq(UiSegmentMeter.value_from_x(5.0, 0.0, 10), 0)


func test_formatter_changes_the_readout_only() -> void:
	var meter: UiSegmentMeter = _make(10, 4)
	assert_eq(meter.display_text(), "4")
	meter.formatter = func(v: int) -> String: return "%d%%" % (v * 10)
	assert_eq(meter.display_text(), "40%")
	assert_eq(meter.value, 4)
	assert_almost_eq(meter.ratio(), 0.4, 0.001)
	meter.set_ratio(1.0)
	assert_eq(meter.value, 10)


func test_ui_left_and_right_step_one_cell() -> void:
	var meter: UiSegmentMeter = _make()
	meter.grab_focus()
	meter._gui_input(_action(&"ui_right"))
	meter._gui_input(_action(&"ui_right", false))
	assert_eq(meter.value, 6)
	meter._gui_input(_action(&"ui_left"))
	meter._gui_input(_action(&"ui_left", false))
	assert_eq(meter.value, 5)
	assert_false(meter.is_holding(), "released")


func test_pad_dpad_through_the_input_map_steps_the_focused_meter() -> void:
	var meter: UiSegmentMeter = _make()
	meter.grab_focus()
	await wait_frames(2)
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_DPAD_RIGHT
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await wait_frames(2)
	assert_eq(meter.value, 6, "d-pad right steps one cell")
	var release: InputEventJoypadButton = InputEventJoypadButton.new()
	release.button_index = JOY_BUTTON_DPAD_RIGHT
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await wait_frames(2)
	assert_false(meter.is_holding())


func test_a_stuck_press_repeats_after_the_delay_while_held() -> void:
	var meter: UiSegmentMeter = _make()
	meter.grab_focus()
	meter._start(1, -1)
	assert_eq(meter.value, 6)
	Input.action_press(&"ui_right")
	meter.advance(SliderNav.TUNING.repeat_delay_sec * 0.5)
	assert_eq(meter.value, 6, "before the delay nothing repeats")
	meter.advance(SliderNav.TUNING.repeat_delay_sec)
	assert_eq(meter.value, 7, "first repeat after the delay")
	Input.action_release(&"ui_right")
	meter.advance(SliderNav.TUNING.repeat_interval_sec)
	assert_false(meter.is_holding(), "a missed release stops the repeat")


func test_stick_below_repeat_threshold_gives_one_step_only() -> void:
	var meter: UiSegmentMeter = _make()
	meter.grab_focus()
	var partial: float = (SliderNav.TUNING.stick_press_threshold + SliderNav.TUNING.stick_repeat_threshold) * 0.5
	meter.axis_reader = func(_device: int, _axis: int) -> float: return partial
	meter._start(1, JOY_AXIS_LEFT_X)
	assert_eq(meter.value, 6)
	meter.advance(SliderNav.TUNING.stick_repeat_delay_sec * 3.0)
	assert_eq(meter.value, 6, "a partial push never auto-repeats")
	meter.axis_reader = func(_device: int, _axis: int) -> float: return 1.0
	meter.advance(SliderNav.TUNING.stick_repeat_delay_sec * 2.0)
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


func test_row_item_contract_expands_one_row_height() -> void:
	var meter: UiSegmentMeter = _make()
	await wait_frames(2)
	assert_true(meter.is_in_group(UiRowItem.GROUP))
	assert_eq(meter.custom_minimum_size.y, float(UiRowItem.metrics().row_height_px))
	assert_eq(meter.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "a meter fills its column")
	assert_gte(meter.custom_minimum_size.x, float(UiRowItem.metrics().meter_min_width_px))


func test_legacy_overlay_still_counts_cells_like_the_component() -> void:
	var slider: HSlider = autofree(HSlider.new()) as HSlider
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.value = 50.0
	assert_eq(SegmentMeter.filled_cells(slider, 10), 5)
