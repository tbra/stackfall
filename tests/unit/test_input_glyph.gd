extends GutTest
## Bontago-1pi.10 (owner: "using glyphs to show what different actions are
## mapped to"): ui/InputGlyph.gd's own event -> label mapping, covering one
## representative case per device family so every glyph ui/KeyRebindRow.gd
## can ever build has real text rather than a raw Godot event string.

const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/InputGlyph.tscn")


func _make_glyph() -> InputGlyph:
	var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	add_child_autofree(glyph)
	return glyph


func test_keyboard_key_shows_its_keycode_text() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_W
	glyph.set_event(event)
	assert_eq(glyph.label_text(), "W")


func test_mouse_left_button_shows_lmb() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	glyph.set_event(event)
	assert_eq(glyph.label_text(), "LMB")


func test_mouse_wheel_up_shows_a_readable_label() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	glyph.set_event(event)
	assert_eq(glyph.label_text(), "Wheel Up")


func test_gamepad_face_button_shows_xbox_style_letter() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	glyph.set_event(event)
	assert_eq(glyph.label_text(), "A")


func test_gamepad_shoulder_button_shows_lb_rb() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_RIGHT_SHOULDER
	glyph.set_event(event)
	assert_eq(glyph.label_text(), "RB")


func test_gamepad_trigger_axis_shows_lt_rt() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_TRIGGER_RIGHT
	glyph.set_event(event)
	assert_eq(glyph.label_text(), "RT")


func test_gamepad_dpad_button_reports_its_kind_as_dpad() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_DPAD_UP
	glyph.set_event(event)
	assert_eq(glyph.label_text(), "D-Up")
	assert_eq(glyph._kind, InputGlyph.Kind.DPAD)


func test_gamepad_stick_click_reports_its_kind_as_stick() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_LEFT_STICK
	glyph.set_event(event)
	assert_eq(glyph.label_text(), "L3")
	assert_eq(glyph._kind, InputGlyph.Kind.STICK)


## Owner example: "map long names to short labels (BracketLeft → '[',
## PageUp → 'PgUp', etc.)".
func test_bracket_left_key_shows_a_short_bracket_glyph() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_BRACKETLEFT
	glyph.set_event(event)
	assert_eq(glyph.label_text(), "[")


func test_page_up_key_shows_pgup() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_PAGEUP
	glyph.set_event(event)
	assert_eq(glyph.label_text(), "PgUp")
