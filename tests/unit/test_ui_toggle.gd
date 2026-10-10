extends GutTest
## Bontago-1pi.159.5: UiToggle (ui/components/UiToggle.gd): ON / OFF word, state API, ui_accept /
## ui_left / ui_right through the Input Map, row-item contract, disabled still shows state.

var _toggled: Array[bool] = []


func _make() -> UiToggle:
	var toggle: UiToggle = UiToggle.new()
	toggle.toggled.connect(func(on: bool) -> void: _toggled.append(on))
	add_child_autofree(toggle)
	return toggle


func before_each() -> void:
	_toggled.clear()


func _key(keycode: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _action(action: StringName) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func test_state_word_is_on_or_off() -> void:
	assert_eq(UiToggle.state_word_for(true), "ON")
	assert_eq(UiToggle.state_word_for(false), "OFF")
	var toggle: UiToggle = _make()
	assert_eq(toggle.text, "OFF")
	toggle.set_on(true)
	assert_eq(toggle.text, "ON")
	assert_true(toggle.is_on())


func test_word_can_be_hidden_but_state_stays() -> void:
	var toggle: UiToggle = _make()
	toggle.show_word = false
	assert_eq(toggle.text, "")
	toggle.set_on(true)
	assert_true(toggle.is_on())


func test_set_on_emits_and_silent_does_not() -> void:
	var toggle: UiToggle = _make()
	toggle.set_on(true)
	assert_eq(_toggled, [true])
	toggle.set_on_silent(false)
	assert_eq(_toggled, [true], "silent sync does not emit")
	assert_false(toggle.is_on())
	assert_eq(toggle.text, "OFF")


func test_knob_geometry_and_faces_come_from_tokens() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	assert_eq(UiToggle.knob_face_for(true), arcade.mint_color, "on is mint")
	assert_eq(UiToggle.knob_face_for(false), arcade.disc_500_color)
	assert_eq(UiToggle.knob_x_for(false, 52.0, 20.0, 3.0), 3.0)
	assert_eq(UiToggle.knob_x_for(true, 52.0, 20.0, 3.0), 29.0)


func test_row_item_contract_shrink_begin_one_row_height() -> void:
	var toggle: UiToggle = _make()
	await wait_frames(2)
	assert_true(toggle.is_in_group(UiRowItem.GROUP))
	assert_eq(toggle.size.y, float(UiRowItem.metrics().row_height_px))
	assert_eq(toggle.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN)
	assert_gte(toggle.size.x, float(UiRowItem.metrics().toggle_min_width_px))


func test_width_does_not_change_when_flipping() -> void:
	var toggle: UiToggle = _make()
	await wait_frames(2)
	var off_width: float = toggle.get_combined_minimum_size().x
	toggle.set_on(true)
	await wait_frames(2)
	assert_eq(toggle.get_combined_minimum_size().x, off_width)


func test_ui_accept_toggles_the_focused_toggle() -> void:
	var toggle: UiToggle = _make()
	await wait_frames(1)
	toggle.grab_focus()
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	await wait_frames(1)
	assert_true(toggle.is_on())
	assert_eq(_toggled, [true])


func test_ui_left_switches_off_and_ui_right_switches_on() -> void:
	var toggle: UiToggle = _make()
	await wait_frames(1)
	toggle._gui_input(_action(&"ui_right"))
	assert_true(toggle.is_on())
	toggle._gui_input(_action(&"ui_right"))
	assert_true(toggle.is_on(), "right on an on toggle stays on")
	toggle._gui_input(_action(&"ui_left"))
	assert_false(toggle.is_on())
	assert_eq(_toggled, [true, false])


func test_gamepad_dpad_uses_the_same_actions() -> void:
	var toggle: UiToggle = _make()
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_DPAD_RIGHT
	event.pressed = true
	assert_true(event.is_action_pressed(&"ui_right"), "the d-pad is bound to ui_right")
	toggle._gui_input(event)
	assert_true(toggle.is_on())


func test_disabled_ignores_keys_but_keeps_showing_state() -> void:
	var toggle: UiToggle = _make()
	toggle.set_on(true)
	toggle.disabled = true
	toggle._gui_input(_action(&"ui_left"))
	assert_true(toggle.is_on())
	assert_eq(toggle.text, "ON", "disabled still shows its state")
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	assert_almost_eq(toggle.get_theme_color("font_disabled_color").a, arcade.disabled_alpha, 0.001)


func test_caption_becomes_the_tooltip() -> void:
	var toggle: UiToggle = _make()
	toggle.caption = "Sudden death"
	assert_eq(toggle.tooltip_text, "Sudden death")
