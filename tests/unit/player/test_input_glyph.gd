extends GutTest
## Bontago-1pi.10 (owner: "using glyphs to show what different actions are
## mapped to"): ui/hud/InputGlyph.gd's own event -> label mapping, covering one
## representative case per device family so every glyph ui/menus/KeyRebindRow.gd
## can ever build has real text rather than a raw Godot event string.

const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/hud/InputGlyph.tscn")


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


func test_gamepad_face_button_shows_xbox_style_letter() -> void:
	var glyph: InputGlyph = _make_glyph()
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	glyph.set_event(event)
	assert_eq(glyph.label_text(), "A")


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
