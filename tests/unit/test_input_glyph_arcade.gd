extends GutTest
## Bontago-hfa.8 (UI reskin P6): Stackfall Arcade keycaps and pad glyphs. Keys are cream blocks, pad
## face buttons are round caps A mint / B flare / X player-2 / Y rim, shoulders are sand chips; mouse,
## D-pad and stick keep their pictograms. Glyphs are display-only, so they never take focus.

const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/InputGlyph.tscn")

var _arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()


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


func test_pictograms_keep_their_art() -> void:
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	assert_false(_glyph_for(mouse).is_arcade_cap())
	assert_false(_glyph_for(_pad_button(JOY_BUTTON_DPAD_UP)).is_arcade_cap())
	assert_false(_glyph_for(_pad_button(JOY_BUTTON_LEFT_STICK)).is_arcade_cap())


func test_combo_art_is_not_replaced_by_a_cap() -> void:
	var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	add_child_autofree(glyph)
	var events: Array[InputEvent] = [_pad_button(JOY_BUTTON_LEFT_SHOULDER), _pad_button(JOY_BUTTON_RIGHT_SHOULDER)]
	glyph.set_chord(events)
	assert_false(glyph.is_arcade_cap(), "authored LB+RB art stays")


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
