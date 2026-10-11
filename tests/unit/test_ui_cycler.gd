extends GutTest
## Bontago-1pi.159.28: UiCycler: wrap both ways, disabled items skipped, one signal per step,
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


func test_first_item_is_selected_and_select_is_silent() -> void:
	var cycler: UiCycler = _make(3, 0)
	assert_eq(cycler.selected(), 0)
	cycler.select(2)
	assert_eq(cycler.selected(), 2)
	assert_eq(cycler.value_label.text, "Item 2")
	assert_eq(_picked.size(), 0)


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


func test_one_enabled_item_cannot_move_and_dims_the_buttons() -> void:
	var cycler: UiCycler = _make(2, 0)
	cycler.set_item_disabled(1, true)
	assert_false(cycler.nudge(1))
	assert_true(cycler.prev_button.disabled)
	assert_true(cycler.next_button.disabled)
	assert_eq(_picked.size(), 0)


func test_empty_and_clear() -> void:
	var cycler: UiCycler = _make(2, 1)
	cycler.clear()
	assert_eq(cycler.selected(), UiCycler.NONE)
	assert_false(cycler.nudge(1))
	assert_eq(cycler.value_label.text, "")


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
	assert_false(cycler.is_holding())
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
	assert_false(cycler.is_holding())


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
	assert_false(cycler.is_holding())


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
	assert_false(cycler.is_holding())


func test_buttons_are_square_and_it_hugs_its_content() -> void:
	var cycler: UiCycler = _make(3, 0)
	await wait_frames(2)
	var h: float = float(UiRowItem.metrics().row_height_px)
	assert_eq(cycler.size.y, h)
	assert_eq(cycler.prev_button.size, Vector2(h, h))
	assert_eq(cycler.next_button.size, Vector2(h, h))
	assert_eq(cycler.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN)
	assert_true(cycler.is_in_group(UiRowItem.GROUP))
	assert_lt(cycler.size.x, h * float(UiRowItem.metrics().stepper_width_units) * 2.0)


func test_disabled_blocks_input() -> void:
	var cycler: UiCycler = _make(3, 0)
	cycler.disabled = true
	assert_true(cycler.prev_button.disabled)
	cycler._gui_input(_action(&"ui_right"))
	assert_eq(cycler.selected(), 0)


func test_cycling_through_every_item_keeps_the_size_constant() -> void:
	var cycler: UiCycler = UiCycler.new()
	var icon: Texture2D = PlaceholderTexture2D.new()
	cycler.add_item("A")
	cycler.add_item("A much longer value", false, icon)
	cycler.add_item("Mid", false, icon)
	add_child_autofree(cycler)
	await wait_frames(2)
	var start: Vector2 = cycler.size
	var arrow_x: float = cycler.next_button.position.x
	for _step: int in range(cycler.get_item_count() * 2):
		cycler.nudge(1)
		await wait_frames(1)
		assert_eq(cycler.size, start, "size is stable at item %d" % cycler.selected())
		assert_eq(cycler.next_button.position.x, arrow_x, "the > block never moves")


func test_value_area_has_padding_each_side_of_the_widest_item() -> void:
	var cycler: UiCycler = _make(3, 0)
	var pad: float = float(UiRowItem.metrics().cycler_value_padding_px)
	var font: Font = cycler.value_label.get_theme_font(&"font")
	var text_w: float = font.get_string_size("Item 0", HORIZONTAL_ALIGNMENT_LEFT, -1.0, cycler.value_label.get_theme_font_size(&"font_size")).x
	assert_gte(cycler.value_box.custom_minimum_size.x, ceilf(text_w) + pad * 2.0)


func test_min_value_width_widens_the_value_area_and_icons_are_stored() -> void:
	var cycler: UiCycler = UiCycler.new()
	var icon: Texture2D = PlaceholderTexture2D.new()
	cycler.add_item("A", false, icon, "tip")
	cycler.min_value_width = 300.0
	assert_eq(cycler.value_box.custom_minimum_size.x, 300.0)
	assert_eq(cycler.get_item_icon(0), icon)
	assert_eq(cycler.get_item_tooltip(0), "tip")
	assert_true(cycler.value_icon.visible)
	cycler.free()
