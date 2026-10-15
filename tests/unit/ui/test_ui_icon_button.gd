extends GutTest
## UiIconButton (the kick / remove X): square, exactly one row height, never
## smaller than the other items of its row; danger tone paints the glyph alert.


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
