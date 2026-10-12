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


# --- Drawn glyphs (Bontago-1pi.159.30: the paper-and-ink texture art and its seam are gone) ----

## Latin-1 O-umlaut (0xD6): outside the named-key ranges.
const UNMAPPED_KEYCODE: Key = 0xD6 as Key


func _key_event(keycode: Key = KEY_NONE, physical: Key = KEY_NONE) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = physical
	return event


func test_physical_keyboard_binding_is_a_key_cap_with_its_name() -> void:
	var glyph: InputGlyph = _make_glyph()
	glyph.set_event(_key_event(KEY_NONE, KEY_E))
	assert_true(glyph.is_arcade_cap())
	assert_eq(glyph.label_text(), "E")
	assert_eq(glyph.custom_minimum_size, Vector2(InputGlyph.GLYPH_HEIGHT_PX, InputGlyph.GLYPH_HEIGHT_PX))


func test_unmapped_key_is_a_cap_with_a_runtime_label() -> void:
	var glyph: InputGlyph = _make_glyph()
	glyph.set_event(_key_event(UNMAPPED_KEYCODE))
	assert_true(glyph.is_arcade_cap())
	assert_false(glyph.label_text().is_empty(), "the runtime label carries the key name")
	assert_gte(glyph.custom_minimum_size.x, InputGlyph.GLYPH_HEIGHT_PX)


func test_key_bound_with_an_extra_modifier_keeps_its_full_label() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventKey = _key_event(KEY_E)
	event.ctrl_pressed = true
	glyph.set_event(event)
	assert_string_contains(glyph.label_text(), "Ctrl")


func test_unnamed_gamepad_button_keeps_its_label() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_PADDLE1
	glyph.set_event(event)
	assert_true(glyph.label_text().begins_with("Btn"))


func test_set_event_after_overflow_or_listening_replaces_the_badge() -> void:
	var glyph: InputGlyph = _make_glyph()
	glyph.set_overflow_count(2)
	assert_eq(glyph.label_text(), "+2")
	glyph.set_event(_key_event(KEY_NONE, KEY_E))
	assert_eq(glyph.label_text(), "E")
	glyph.set_listening()
	assert_true(glyph.is_arcade_cap())
	glyph.set_event(_key_event(KEY_NONE, KEY_E))
	assert_eq(glyph.label_text(), "E")


func test_each_device_family_draws() -> void:
	var glyph: InputGlyph = _make_glyph()
	var draws: Array[int] = [0]
	glyph.draw.connect(func() -> void: draws[0] += 1)
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	for event: InputEvent in [_key_event(UNMAPPED_KEYCODE), mouse, pad]:
		glyph.set_event(event)
		await wait_process_frames(2)
	assert_gt(draws[0], 0, "the drawn glyph paints")


## Every binding the project ships (Options > Controls draws one glyph per binding of the active
## device) produces a non-empty label.
func test_every_project_binding_has_a_label() -> void:
	var checked: int = 0
	for action: StringName in InputMap.get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			if not (event is InputEventKey or event is InputEventMouseButton
					or event is InputEventJoypadButton or event is InputEventJoypadMotion):
				continue
			var glyph: InputGlyph = _make_glyph()
			glyph.set_event(event)
			assert_false(glyph.label_text().is_empty(), "%s: %s has no label" % [action, event.as_text()])
			checked += 1
	assert_gt(checked, 0, "InputMap should hold bindings")
