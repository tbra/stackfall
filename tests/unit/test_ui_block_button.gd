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


func test_danger_is_a_secondary_block_with_an_alert_label() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var button: UiBlockButton = _make(UiBlockButton.Look.DANGER)
	assert_eq(UiBlockButton.face_for(UiBlockButton.Look.DANGER), arcade.disc_600_color)
	for item: String in MenuStyleFactory.BUTTON_FONT_COLOR_ITEMS:
		assert_eq(button.get_theme_color(item), arcade.alert_color, item)
	var secondary: UiBlockButton = _make(UiBlockButton.Look.SECONDARY)
	assert_ne(secondary.get_theme_color("font_color"), arcade.alert_color)


# --- Bontago-1pi.159.42: the trailing input hint ------------------------------------------------

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


func test_hint_survives_a_restyle_and_sits_right_of_the_label() -> void:
	var button: UiBlockButton = _make()
	button.hint_action = &"ui_accept"
	button.variant = UiBlockButton.Look.PRIMARY
	await get_tree().process_frame
	await get_tree().process_frame
	var flow: InputPromptFlow = UiButtonHint.flow_of(button)
	assert_not_null(flow)
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var glyph_left: float = flow.position.x
	var label_right: float = (button.size.x - UiButtonHint.content_width(button) - flow.size.x * flow.scale.x - float(arcade.space_2_px)) * 0.5 + UiButtonHint.content_width(button)
	assert_almost_eq(glyph_left, label_right + float(arcade.space_2_px), 1.5, "glyph trails the label by space_2")


func test_hint_tint_follows_the_button_state() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	assert_eq(UiButtonHint.tint_for(BaseButton.DRAW_NORMAL, arcade), Color.WHITE)
	assert_eq(UiButtonHint.tint_for(BaseButton.DRAW_HOVER, arcade), Color.WHITE)
	assert_almost_eq(UiButtonHint.tint_for(BaseButton.DRAW_DISABLED, arcade).a, arcade.disabled_alpha, 0.001)
	assert_lt(UiButtonHint.tint_for(BaseButton.DRAW_PRESSED, arcade).r, 1.0, "pressed darkens")
	var button: UiBlockButton = _make()
	button.hint_action = &"ui_cancel"
	button.disabled = true
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(UiButtonHint.flow_of(button).modulate.a, arcade.disabled_alpha, 0.001)


func test_hint_scales_into_a_small_button_and_centres_on_the_label_line() -> void:
	var button: UiBlockButton = _make()
	button.small = true
	button.hint_action = &"ui_cancel"
	await get_tree().process_frame
	await get_tree().process_frame
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var flow: InputPromptFlow = UiButtonHint.flow_of(button)
	var shown_height: float = flow.size.y * flow.scale.y
	assert_lte(shown_height, button.size.y, "the glyph never overflows the small button")
	assert_lte(flow.position.x + flow.size.x * flow.scale.x, button.size.x + 1.0, "nor its right edge")
	var line_centre: float = (button.get_theme_stylebox("normal").content_margin_top + button.size.y - button.get_theme_stylebox("normal").content_margin_bottom) * 0.5
	var body: float = maxf(flow.size.y - float(arcade.drop_sm_px), 1.0) * flow.scale.y
	assert_almost_eq(flow.position.y + body * 0.5, line_centre, 1.5, "vertically centred with the label")


func test_buttons_of_one_look_share_never_mutated_styleboxes() -> void:
	UiBlockButton.invalidate_style_cache()
	var first: UiBlockButton = _make(UiBlockButton.Look.PRIMARY)
	var second: UiBlockButton = _make(UiBlockButton.Look.PRIMARY)
	var other: UiBlockButton = _make(UiBlockButton.Look.MINT)
	for state: String in UiBlockButton.STATES:
		assert_same(first.get_theme_stylebox(state), second.get_theme_stylebox(state), "same look shares %s" % state)
		assert_ne(first.get_theme_stylebox(state), other.get_theme_stylebox(state), "another variant does not")
	var big: UiBlockButton = _make(UiBlockButton.Look.PRIMARY, false)
	assert_ne(big.get_theme_stylebox("normal"), first.get_theme_stylebox("normal"), "size is part of the key")
	var icon: UiIconButton = UiIconButton.new()
	add_child_autofree(icon)
	var icon_box: StyleBox = icon.get_theme_stylebox("normal")
	assert_eq(icon_box.content_margin_left, 0.0)
	assert_ne(icon_box, _make(UiBlockButton.Look.SECONDARY).get_theme_stylebox("normal"), "icon blocks keep their own zero-margin boxes")
	var icon_two: UiIconButton = UiIconButton.new()
	add_child_autofree(icon_two)
	assert_same(icon_box, icon_two.get_theme_stylebox("normal"))
	icon_two.tone = UiIconButton.Tone.DANGER
	assert_same(icon_box, icon_two.get_theme_stylebox("normal"), "tone only changes ink")


func test_a_hint_reserves_room_on_a_private_copy_not_the_shared_box() -> void:
	UiBlockButton.invalidate_style_cache()
	var plain: UiBlockButton = _make(UiBlockButton.Look.PRIMARY)
	var shared_right: float = plain.get_theme_stylebox("normal").content_margin_right
	var hinted: UiBlockButton = _make(UiBlockButton.Look.PRIMARY)
	hinted.hint_action = &"ui_cancel"
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(hinted.get_theme_stylebox("normal").content_margin_right, shared_right, "the hinted button reserved room")
	assert_ne(hinted.get_theme_stylebox("normal"), plain.get_theme_stylebox("normal"))
	assert_eq(plain.get_theme_stylebox("normal").content_margin_right, shared_right, "the shared box is untouched")
	assert_eq(_make(UiBlockButton.Look.PRIMARY).get_theme_stylebox("normal").content_margin_right, shared_right)
	hinted.hint_action = &""
	assert_almost_eq(hinted.get_theme_stylebox("normal").content_margin_right, shared_right, 0.01, "clearing the hint gives the room back")


func test_invalidating_the_cache_rebuilds_for_the_next_button() -> void:
	var before: UiBlockButton = _make()
	UiBlockButton.invalidate_style_cache()
	var after: UiBlockButton = _make()
	assert_ne(before.get_theme_stylebox("normal"), after.get_theme_stylebox("normal"))
