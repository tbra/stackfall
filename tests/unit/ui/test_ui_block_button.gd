extends GutTest
## UiBlockButton (ui/components/UiBlockButton.gd): token faces per variant, the
## five block states, row-height fit, focus + ui_accept / pad A through the Input Map.

var _pressed: int = 0


func _make(look: UiBlockButton.Look = UiBlockButton.Look.SECONDARY, small: bool = true) -> UiBlockButton:
	var button: UiBlockButton = UiBlockButton.new()
	button.text = "GO"
	button.variant = look
	button.small = small
	button.pressed.connect(func() -> void: _pressed += 1)
	add_child_autofree(button)
	return button


func before_each() -> void:
	_pressed = 0


func test_small_button_is_exactly_one_row_height_and_full_size_is_not_a_row_item() -> void:
	var small: UiBlockButton = _make()
	await wait_frames(2)
	assert_eq(small.size.y, float(UiRowItem.metrics().row_height_px))
	assert_true(small.is_in_group(UiRowItem.GROUP))
	var big: UiBlockButton = _make(UiBlockButton.Look.PRIMARY, false)
	await wait_frames(2)
	assert_false(big.is_in_group(UiRowItem.GROUP))
	assert_gt(big.size.y, float(UiRowItem.metrics().row_height_px), "the full-size block keeps its standard padding")


func test_ui_accept_activates_when_focused() -> void:
	var button: UiBlockButton = _make()
	await wait_frames(1)
	button.grab_focus()
	assert_true(button.has_focus())
	var accept: InputEventKey = InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.physical_keycode = KEY_ENTER
	accept.pressed = true
	Input.parse_input_event(accept)
	var release: InputEventKey = accept.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await wait_frames(1)
	assert_eq(_pressed, 1, "ui_accept presses the focused block")


func test_pad_a_is_bound_to_ui_accept() -> void:
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	assert_true(pad.is_action(&"ui_accept"), "pad A is bound to ui_accept")


func test_disabled_keeps_a_block_look_and_stays_focusable_by_mode() -> void:
	var button: UiBlockButton = _make()
	button.disabled = true
	assert_eq(button.focus_mode, Control.FOCUS_ALL)
	assert_true(button.get_theme_stylebox("disabled") is BlockStyleBox)


func test_hint_action_adds_one_trailing_glyph_and_clearing_removes_it() -> void:
	var button: UiBlockButton = _make()
	button.hint_action = &"ui_cancel"
	await get_tree().process_frame
	await get_tree().process_frame
	var flow: InputPromptFlow = UiButtonHint.flow_of(button)
	assert_not_null(flow)
	assert_eq(flow.template, "{ui_cancel}")
	var reserved: float = button.get_minimum_size().x
	button.hint_action = &""
	assert_null(UiButtonHint.flow_of(button))
	await get_tree().process_frame
	assert_lt(button.get_minimum_size().x, reserved, "the glyph's room is released")
