extends GutTest
## UI reskin P6: Stackfall Arcade keycaps and pad glyphs. Keys are cream blocks, pad
## face buttons are round caps A mint / B flare / X player-2 / Y rim, shoulders are sand chips; mouse,
## D-pad and stick are block pictograms. Glyphs are display-only, so they never take focus.

const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/hud/InputGlyph.tscn")

var _arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()


func after_each() -> void:
	# The focus test sends a synthetic pad press; do not leak the gamepad device into later scripts.
	Settings._input(InputEventKey.new())


func _glyph_for(event: InputEvent) -> InputGlyph:
	var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	add_child_autofree(glyph)
	glyph.set_event(event)
	return glyph


func _pad_button(index: int) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = index
	return event


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


## the legend is drawn uppercase (mock), the cap is sized to that uppercase text
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
