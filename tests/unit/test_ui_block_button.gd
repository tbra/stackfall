extends GutTest
## Bontago-1pi.159.4: UiBlockButton (ui/components/UiBlockButton.gd): token faces per variant, the
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


func test_faces_come_from_the_tokens() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	assert_eq(UiBlockButton.face_for(UiBlockButton.Look.PRIMARY), arcade.flare_color)
	assert_eq(UiBlockButton.face_for(UiBlockButton.Look.SECONDARY), arcade.disc_600_color)
	assert_eq(UiBlockButton.face_for(UiBlockButton.Look.MINT), arcade.mint_color)
	assert_eq(UiBlockButton.face_for(UiBlockButton.Look.RIM), arcade.rim_color)


func test_all_five_states_are_block_styles_and_labels_use_ink_on_bright_faces() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var button: UiBlockButton = _make(UiBlockButton.Look.PRIMARY)
	for state: String in UiBlockButton.STATES:
		assert_true(button.get_theme_stylebox(state) is BlockStyleBox, "%s is a block" % state)
	assert_eq(button.get_theme_color("font_color"), arcade.ink_color, "ink on the flare face, never cream")
	assert_true((button.get_theme_stylebox("pressed") as BlockStyleBox).pressed)
	assert_true((button.get_theme_stylebox("disabled") as BlockStyleBox).disabled)


func test_small_button_is_exactly_one_row_height_and_full_size_is_not_a_row_item() -> void:
	var small: UiBlockButton = _make()
	await wait_frames(2)
	assert_eq(small.size.y, float(UiRowItem.metrics().row_height_px))
	assert_true(small.is_in_group(UiRowItem.GROUP))
	var big: UiBlockButton = _make(UiBlockButton.Look.PRIMARY, false)
	await wait_frames(2)
	assert_false(big.is_in_group(UiRowItem.GROUP))
	assert_gt(big.size.y, float(UiRowItem.metrics().row_height_px), "the full-size block keeps its standard padding")


func test_pressed_state_keeps_the_minimum_height() -> void:
	var button: UiBlockButton = _make()
	var normal: StyleBox = button.get_theme_stylebox("normal")
	var pressed: StyleBox = button.get_theme_stylebox("pressed")
	assert_eq(normal.get_minimum_size().y, pressed.get_minimum_size().y, "the ledge trades for the drop")


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


func test_static_style_works_on_a_plain_button() -> void:
	var plain: Button = autofree(Button.new()) as Button
	UiBlockButton.style(plain, UiBlockButton.Look.MINT, true)
	assert_true(plain.get_theme_stylebox("normal") is BlockStyleBox)
