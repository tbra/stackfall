extends GutTest
## Bontago-1pi.159.4: UiIconButton (the kick / remove X): square, exactly one row height, never
## smaller than the other items of its row; danger tone paints the glyph alert.


func test_is_a_square_row_height_item() -> void:
	var button: UiIconButton = UiIconButton.new()
	add_child_autofree(button)
	await wait_frames(2)
	var h: float = float(UiRowItem.metrics().row_height_px)
	assert_eq(button.size, Vector2(h, h))
	assert_true(button.is_in_group(UiRowItem.GROUP))


func test_same_height_as_a_block_button_in_one_row() -> void:
	var row: UiRow = UiRow.new().setup("BOT")
	var block: UiBlockButton = UiBlockButton.new()
	block.text = "TEAM 1"
	row.add_item(block)
	var kick: UiIconButton = UiIconButton.new()
	kick.tone = UiIconButton.Tone.DANGER
	row.add_item(kick)
	add_child_autofree(row)
	await wait_frames(2)
	assert_eq(kick.size.y, block.size.y, "the kick X is no smaller than its row neighbours")


func test_danger_tone_uses_the_alert_ink_and_secondary_the_face_ink() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var button: UiIconButton = UiIconButton.new()
	add_child_autofree(button)
	assert_eq(button.get_theme_color("font_color"), MenuStyleFactory.ink_for_face(arcade.disc_600_color))
	button.tone = UiIconButton.Tone.DANGER
	assert_eq(button.get_theme_color("font_color"), arcade.alert_color)
	assert_eq(button.get_theme_color("icon_normal_color"), arcade.alert_color)


func test_default_glyph_is_the_x_and_an_icon_replaces_it() -> void:
	var button: UiIconButton = UiIconButton.new()
	add_child_autofree(button)
	assert_eq(button.text, char(UiIconButton.DEFAULT_GLYPH))
	button.set_icon_texture(PlaceholderTexture2D.new())
	assert_eq(button.text, "")


func test_ui_accept_presses_it_when_focused() -> void:
	var button: UiIconButton = UiIconButton.new()
	var hits: Array[int] = []
	button.pressed.connect(func() -> void: hits.append(1))
	add_child_autofree(button)
	await wait_frames(1)
	button.grab_focus()
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
	assert_eq(hits.size(), 1)
