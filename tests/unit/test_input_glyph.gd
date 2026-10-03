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


# --- Texture art (Bontago-1pi.35: Options menu should use the new glyph art) -----

const GLYPH_ART_ROOT: String = "res://assets/ui/input_glyphs/"
## Latin-1 O-umlaut (0xD6): outside the catalog's printable-ASCII and named-key ranges.
const UNMAPPED_KEYCODE: Key = 0xD6 as Key


func _key_event(keycode: Key = KEY_NONE, physical: Key = KEY_NONE) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = physical
	return event


func _assert_art(glyph: InputGlyph, expected_path: String) -> void:
	var texture: Texture2D = glyph.glyph_texture()
	assert_not_null(texture, "expected art for %s" % expected_path)
	if texture != null:
		assert_eq(texture.resource_path, expected_path)
		assert_false(glyph.uses_blank_shell(), "a mapped glyph is the finished art, not a blank shell")


func test_physical_keyboard_binding_resolves_to_the_catalog_keycap() -> void:
	var glyph: InputGlyph = _make_glyph()
	glyph.set_event(_key_event(KEY_NONE, KEY_E))
	_assert_art(glyph, GLYPH_ART_ROOT + "key_atlas/keycode_%d.png" % KEY_E)
	assert_eq(glyph.label_text(), "E", "the text summary is unchanged")


func test_keycode_keyboard_binding_resolves_to_the_catalog_keycap() -> void:
	var glyph: InputGlyph = _make_glyph()
	glyph.set_event(_key_event(KEY_ESCAPE))
	_assert_art(glyph, GLYPH_ART_ROOT + "key_atlas/keycode_%d.png" % KEY_ESCAPE)


func test_mouse_buttons_resolve_to_mouse_svgs() -> void:
	var expected: Dictionary[int, String] = {
		MOUSE_BUTTON_LEFT: "mouse_left.svg",
		MOUSE_BUTTON_RIGHT: "mouse_right.svg",
		MOUSE_BUTTON_MIDDLE: "mouse_middle.svg",
		MOUSE_BUTTON_WHEEL_UP: "mouse_wheel_up.svg",
		MOUSE_BUTTON_WHEEL_DOWN: "mouse_wheel_down.svg",
		MOUSE_BUTTON_XBUTTON1: "mouse_button_4.svg",
	}
	for button: int in expected:
		var glyph: InputGlyph = _make_glyph()
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = button as MouseButton
		glyph.set_event(event)
		_assert_art(glyph, GLYPH_ART_ROOT + expected[button])


func test_joypad_button_a_resolves_to_gamepad_svg() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	glyph.set_event(event)
	_assert_art(glyph, GLYPH_ART_ROOT + "gamepad_a.svg")
	assert_eq(glyph.label_text(), "A")
	assert_eq(glyph._kind, InputGlyph.Kind.FACE, "the pictogram kind survives for the fallback")


func test_joypad_buttons_and_axes_resolve_to_their_gamepad_svgs() -> void:
	var button_files: Dictionary[int, String] = {
		JOY_BUTTON_DPAD_UP: "gamepad_dpad_up.svg",
		JOY_BUTTON_RIGHT_SHOULDER: "gamepad_rb.svg",
		JOY_BUTTON_LEFT_STICK: "gamepad_stick_left.svg",
		JOY_BUTTON_START: "gamepad_start.svg",
		JOY_BUTTON_MISC1: "gamepad_misc.svg",
	}
	for button: int in button_files:
		var glyph: InputGlyph = _make_glyph()
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button as JoyButton
		glyph.set_event(event)
		_assert_art(glyph, GLYPH_ART_ROOT + button_files[button])
	var axis_files: Dictionary[int, String] = {
		JOY_AXIS_TRIGGER_LEFT: "gamepad_lt.svg",
		JOY_AXIS_TRIGGER_RIGHT: "gamepad_rt.svg",
		JOY_AXIS_RIGHT_X: "gamepad_stick_right.svg",
	}
	for axis: int in axis_files:
		var axis_glyph: InputGlyph = _make_glyph()
		var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
		motion.axis = axis as JoyAxis
		axis_glyph.set_event(motion)
		_assert_art(axis_glyph, GLYPH_ART_ROOT + axis_files[axis])


func test_texture_glyph_keeps_the_consistent_glyph_height() -> void:
	var glyph: InputGlyph = _make_glyph()
	glyph.set_event(_key_event(KEY_NONE, KEY_E))
	assert_eq(glyph.custom_minimum_size, Vector2(InputGlyph.GLYPH_HEIGHT_PX, InputGlyph.GLYPH_HEIGHT_PX))


## The catalog stops at the Godot-named range, so an international remap
## (here Latin-1 O-umlaut) has no keycap: it gets the label-free blank keycap
## plus the real key name as runtime text, widened to fit.
func test_unmapped_key_falls_back_to_the_blank_keycap_with_a_runtime_label() -> void:
	var glyph: InputGlyph = _make_glyph()
	glyph.set_event(_key_event(UNMAPPED_KEYCODE))
	var texture: Texture2D = glyph.glyph_texture()
	assert_not_null(texture)
	assert_eq(texture.resource_path, GLYPH_ART_ROOT + "key_atlas/keycap_blank.svg")
	assert_true(glyph.uses_blank_shell())
	assert_false(glyph.label_text().is_empty(), "the runtime label carries the key name")
	assert_gte(glyph.custom_minimum_size.x, InputGlyph.GLYPH_HEIGHT_PX)


func test_key_bound_with_an_extra_modifier_uses_the_blank_keycap_and_its_full_label() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventKey = _key_event(KEY_E)
	event.ctrl_pressed = true
	glyph.set_event(event)
	assert_true(glyph.uses_blank_shell(), "the plain E keycap would drop the Ctrl")
	assert_eq(glyph.glyph_texture().resource_path, GLYPH_ART_ROOT + "key_atlas/keycap_blank.svg")
	assert_string_contains(glyph.label_text(), "Ctrl")


func test_modifier_key_itself_still_uses_its_catalog_keycap() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventKey = _key_event(KEY_CTRL)
	event.ctrl_pressed = true
	glyph.set_event(event)
	_assert_art(glyph, GLYPH_ART_ROOT + "key_atlas/keycode_%d.png" % KEY_CTRL)


func test_unnamed_gamepad_button_uses_the_blank_button_with_its_label() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_PADDLE1
	glyph.set_event(event)
	assert_true(glyph.uses_blank_shell())
	assert_eq(glyph.glyph_texture().resource_path, GLYPH_ART_ROOT + "gamepad_button_blank.svg")
	assert_true(glyph.label_text().begins_with("Btn"))


func test_overflow_and_listening_badges_draw_no_texture() -> void:
	var glyph: InputGlyph = _make_glyph()
	glyph.set_event(_key_event(KEY_NONE, KEY_E))
	glyph.set_overflow_count(2)
	assert_null(glyph.glyph_texture(), "set_overflow_count replaces the previous event's art")
	glyph.set_event(_key_event(KEY_NONE, KEY_E))
	glyph.set_listening()
	assert_null(glyph.glyph_texture())


func test_set_event_replaces_a_previous_blank_shell() -> void:
	var glyph: InputGlyph = _make_glyph()
	glyph.set_event(_key_event(UNMAPPED_KEYCODE))
	assert_true(glyph.uses_blank_shell())
	glyph.set_event(_key_event(KEY_NONE, KEY_E))
	assert_false(glyph.uses_blank_shell())


func test_missing_assets_fall_back_to_the_draw_path() -> void:
	var missing: InputGlyph = _make_glyph()
	missing.asset_root = "res://assets/ui/input_glyphs_does_not_exist/"
	var draws: Array[int] = [0]
	missing.draw.connect(func() -> void: draws[0] += 1)

	missing.set_event(_key_event(KEY_NONE, KEY_E))
	assert_null(missing.glyph_texture(), "no art -> _draw() primitives")
	assert_eq(missing._kind, InputGlyph.Kind.KEY)
	assert_eq(missing.label_text(), "E")

	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	missing.set_event(mouse)
	assert_null(missing.glyph_texture())
	assert_eq(missing._kind, InputGlyph.Kind.MOUSE)

	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	missing.set_event(pad)
	assert_null(missing.glyph_texture())
	assert_eq(missing._kind, InputGlyph.Kind.FACE)

	await wait_process_frames(2)
	assert_gt(draws[0], 0, "the fallback glyph still draws")


func test_art_glyph_draws() -> void:
	var glyph: InputGlyph = _make_glyph()
	var draws: Array[int] = [0]
	glyph.draw.connect(func() -> void: draws[0] += 1)
	glyph.set_event(_key_event(UNMAPPED_KEYCODE))
	await wait_process_frames(2)
	assert_gt(draws[0], 0, "the blank-keycap glyph draws without error")


func test_glyph_textures_and_catalog_are_cached_across_glyphs() -> void:
	var first: InputGlyph = _make_glyph()
	var second: InputGlyph = _make_glyph()
	first.set_event(_key_event(KEY_NONE, KEY_E))
	second.set_event(_key_event(KEY_NONE, KEY_E))
	assert_same(first.glyph_texture(), second.glyph_texture())
	assert_true(InputGlyph._key_atlas_cache.has(InputGlyph.GLYPH_ASSET_ROOT), "catalog parsed once and kept")


func test_every_mapped_art_file_exists() -> void:
	var files: Array[String] = [InputGlyph.BLANK_KEYCAP_FILE, InputGlyph.BLANK_GAMEPAD_BUTTON_FILE, InputGlyph.KEY_CATALOG_FILE]
	files.append_array(InputGlyph.MOUSE_GLYPH_FILES.values())
	files.append_array(InputGlyph.JOYPAD_BUTTON_GLYPH_FILES.values())
	files.append_array(InputGlyph.JOYPAD_AXIS_GLYPH_FILES.values())
	for file: String in files:
		assert_true(ResourceLoader.exists(InputGlyph.GLYPH_ASSET_ROOT + file), "missing art: %s" % file)


## Every binding the project ships (Options > Controls draws one glyph per
## binding of the active device) resolves to art -- nothing falls back to the
## _draw() primitives while the assets are present.
func test_every_project_binding_resolves_to_art() -> void:
	var checked: int = 0
	for action: StringName in InputMap.get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			if not (event is InputEventKey or event is InputEventMouseButton
					or event is InputEventJoypadButton or event is InputEventJoypadMotion):
				continue
			var glyph: InputGlyph = _make_glyph()
			glyph.set_event(event)
			assert_not_null(glyph.glyph_texture(), "%s: %s has no art" % [action, event.as_text()])
			checked += 1
	assert_gt(checked, 0, "InputMap should hold bindings")
