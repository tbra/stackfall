extends GutTest
## Bontago-hfa.8 (UI reskin P6): Stackfall Arcade keycaps and pad glyphs. Keys are cream blocks, pad
## face buttons are round caps A mint / B flare / X player-2 / Y rim, shoulders are sand chips; mouse,
## D-pad and stick are block pictograms. Glyphs are display-only, so they never take focus.

const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/InputGlyph.tscn")

var _arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()


func after_each() -> void:
	# The focus test sends a synthetic pad press; do not leak the gamepad device into later scripts.
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


func _glyph_for(event: InputEvent) -> InputGlyph:
	var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	add_child_autofree(glyph)
	glyph.set_event(event)
	return glyph


func _pad_button(index: int) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = index
	return event


func test_keyboard_key_is_a_cream_cap() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_E
	var glyph: InputGlyph = _glyph_for(event)
	assert_true(glyph.is_arcade_cap())
	assert_eq(glyph.arcade_face_color(), _arcade.cream_color)
	assert_not_null(glyph.glyph_texture(), "the resolved art seam is unchanged")


func test_long_key_label_widens_the_cap_instead_of_shrinking_the_legend() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ENTER
	var glyph: InputGlyph = _glyph_for(event)
	assert_gt(glyph.custom_minimum_size.x, InputGlyph.GLYPH_HEIGHT_PX)
	assert_eq(glyph.custom_minimum_size.y, InputGlyph.GLYPH_HEIGHT_PX)


func test_pad_face_buttons_use_the_arcade_tokens() -> void:
	var expected: Dictionary[int, Color] = {
		JOY_BUTTON_A: _arcade.mint_color,
		JOY_BUTTON_B: _arcade.flare_color,
		JOY_BUTTON_X: _arcade.player_2_color,
		JOY_BUTTON_Y: _arcade.rim_color,
	}
	for index: int in expected:
		var glyph: InputGlyph = _glyph_for(_pad_button(index))
		assert_true(glyph.is_arcade_cap(), "button %d" % index)
		assert_eq(glyph.arcade_face_color(), expected[index], "button %d" % index)
		assert_eq(glyph.custom_minimum_size.x, InputGlyph.GLYPH_HEIGHT_PX, "round cap stays square")


func test_shoulder_is_a_sand_chip() -> void:
	var glyph: InputGlyph = _glyph_for(_pad_button(JOY_BUTTON_LEFT_SHOULDER))
	assert_true(glyph.is_arcade_cap())
	assert_eq(glyph.arcade_face_color(), _arcade.sand_color)


func test_pictograms_are_not_caps() -> void:
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	assert_false(_glyph_for(mouse).is_arcade_cap())
	assert_false(_glyph_for(_pad_button(JOY_BUTTON_DPAD_UP)).is_arcade_cap())
	assert_false(_glyph_for(_pad_button(JOY_BUTTON_LEFT_STICK)).is_arcade_cap())


func test_authored_combo_is_a_sand_chip_drawn_in_code() -> void:
	var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	add_child_autofree(glyph)
	var events: Array[InputEvent] = [_pad_button(JOY_BUTTON_LEFT_SHOULDER), _pad_button(JOY_BUTTON_RIGHT_SHOULDER)]
	glyph.set_chord(events)
	assert_true(glyph.is_arcade_cap(), "LB+RB is a chip, not the paper art")
	assert_eq(glyph.label_text(), "LB+RB")
	assert_eq(glyph.arcade_face_color(), _arcade.sand_color)
	assert_gt(glyph.custom_minimum_size.x, InputGlyph.GLYPH_HEIGHT_PX)


func test_pictograms_share_the_glyph_box_and_are_never_caps() -> void:
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	for button: int in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_XBUTTON1]:
		mouse.button_index = button as MouseButton
		var glyph: InputGlyph = _glyph_for(mouse)
		assert_eq(glyph.custom_minimum_size, Vector2(InputGlyph.GLYPH_HEIGHT_PX, InputGlyph.GLYPH_HEIGHT_PX), "mouse %d" % button)
	for index: int in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_LEFT_STICK]:
		var pad: InputGlyph = _glyph_for(_pad_button(index))
		assert_eq(pad.custom_minimum_size, Vector2(InputGlyph.GLYPH_HEIGHT_PX, InputGlyph.GLYPH_HEIGHT_PX))


func test_pictograms_actually_paint_without_errors() -> void:
	# Drawing runs inside the render loop; a frame proves _draw() does not push errors for any kind.
	var holder: HBoxContainer = HBoxContainer.new()
	add_child_autofree(holder)
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_WHEEL_LEFT
	var stick: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_RIGHT_Y
	stick.axis_value = 1.0
	for event: InputEvent in [mouse, stick, _pad_button(JOY_BUTTON_DPAD_RIGHT), _pad_button(JOY_BUTTON_RIGHT_STICK)]:
		var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
		glyph.pad_style = InputGlyph.PadStyle.PLAYSTATION
		holder.add_child(glyph)
		glyph.set_event(event)
		glyph.force_update_transform()
		glyph.queue_redraw()
	await wait_frames(2)
	assert_eq(holder.get_child_count(), 4)


func test_playstation_style_uses_symbol_legends_on_the_same_cap_colours() -> void:
	var expected: Dictionary[int, String] = {
		JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
		JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
	}
	for index: int in expected:
		var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
		glyph.pad_style = InputGlyph.PadStyle.PLAYSTATION
		add_child_autofree(glyph)
		glyph.set_event(_pad_button(index))
		assert_eq(glyph.label_text(), expected[index], "button %d" % index)
		assert_eq(glyph.resolved_pad_style(), InputGlyph.PadStyle.PLAYSTATION)
	var cross: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	cross.pad_style = InputGlyph.PadStyle.PLAYSTATION
	add_child_autofree(cross)
	cross.set_event(_pad_button(JOY_BUTTON_A))
	assert_eq(cross.arcade_face_color(), _arcade.mint_color, "the cap keeps its position colour")
	assert_eq(cross.custom_minimum_size.x, InputGlyph.GLYPH_HEIGHT_PX, "still a round cap")
	var trigger: InputEventJoypadMotion = InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 1.0
	cross.set_event(trigger)
	assert_eq(cross.label_text(), "R2")


func test_xbox_style_is_the_default_and_joy_names_select_the_family() -> void:
	assert_eq(InputGlyph.style_for_joy_name("PS5 Controller"), InputGlyph.PadStyle.PLAYSTATION)
	assert_eq(InputGlyph.style_for_joy_name("Sony DualSense"), InputGlyph.PadStyle.PLAYSTATION)
	assert_eq(InputGlyph.style_for_joy_name("DualShock 4"), InputGlyph.PadStyle.PLAYSTATION)
	assert_eq(InputGlyph.style_for_joy_name("Xbox 360 Controller"), InputGlyph.PadStyle.XBOX)
	assert_eq(InputGlyph.style_for_joy_name(""), InputGlyph.PadStyle.XBOX)
	var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	glyph.pad_style = InputGlyph.PadStyle.XBOX
	add_child_autofree(glyph)
	glyph.set_event(_pad_button(JOY_BUTTON_B))
	assert_eq(glyph.label_text(), "B")


func test_unauthored_chord_is_a_chip_with_the_joined_label() -> void:
	var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	add_child_autofree(glyph)
	var events: Array[InputEvent] = [_pad_button(JOY_BUTTON_A), _pad_button(JOY_BUTTON_X)]
	glyph.set_chord(events)
	assert_true(glyph.is_arcade_cap())
	assert_eq(glyph.label_text(), "A+X")
	assert_eq(glyph.arcade_face_color(), _arcade.sand_color)
	assert_gt(glyph.custom_minimum_size.x, InputGlyph.GLYPH_HEIGHT_PX)


func test_listening_and_overflow_badges() -> void:
	var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	add_child_autofree(glyph)
	glyph.set_listening()
	assert_eq(glyph.arcade_face_color(), _arcade.rim_color, "listening is rim gold")
	glyph.set_overflow_count(2)
	assert_eq(glyph.arcade_face_color(), _arcade.disc_600_color)


func test_missing_art_still_draws_an_arcade_cap() -> void:
	var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	glyph.asset_root = "res://assets/ui/input_glyphs_does_not_exist/"
	add_child_autofree(glyph)
	glyph.set_event(_pad_button(JOY_BUTTON_B))
	assert_null(glyph.glyph_texture())
	assert_true(glyph.is_arcade_cap())


func test_glyph_never_takes_focus_and_a_synthetic_pad_press_does_not_move_it() -> void:
	var holder: VBoxContainer = VBoxContainer.new()
	add_child_autofree(holder)
	var button: Button = Button.new()
	holder.add_child(button)
	var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	holder.add_child(glyph)
	glyph.set_event(_pad_button(JOY_BUTTON_A))
	button.grab_focus()
	assert_eq(glyph.focus_mode, Control.FOCUS_NONE)
	assert_eq(glyph.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	Input.parse_input_event(_pad_button(JOY_BUTTON_DPAD_DOWN))
	await wait_frames(2)  # let the queued press land (and after_each reset the device) before the next test
	assert_true(button.has_focus(), "the cap is not a focus stop")


## Bontago-1pi.149: the legend is drawn uppercase (mock), the cap is sized to that uppercase text
## (so PGUP, ESC, ENTER, SPACE, CTRL still fit) and label_text() keeps the as_text() form.
func test_key_legends_are_uppercase_and_every_long_name_fits_its_cap() -> void:
	for code: Key in [KEY_PAGEUP, KEY_ESCAPE, KEY_ENTER, KEY_SPACE, KEY_CTRL, KEY_BACKSPACE, KEY_TAB]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		var glyph: InputGlyph = _glyph_for(event)
		var legend: String = glyph.label_text().to_upper()
		var needed: float = glyph._label_width(legend, InputGlyph.ARCADE_LEGEND_FONT_SIZE)
		assert_gte(glyph.custom_minimum_size.x, needed + float(_arcade.space_2_px) * 2.0,
			"%s: the cap is at least as wide as its uppercase legend plus padding" % legend)
	var esc: InputEventKey = InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	assert_eq(_glyph_for(esc).label_text(), "Esc", "the as_text() form is unchanged")
