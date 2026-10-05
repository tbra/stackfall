extends GutTest
## Bontago-mp0.124 part B: HUD feedback pictograms (HudFeedbackIconTable) and
## InputGlyph stick/chord glyphs (InputGlyphTable) resolve and are used.

const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/InputGlyph.tscn")
const STICK_SIDES: Array[StringName] = [&"left", &"right"]
const STICK_DIRECTIONS: Array[StringName] = [&"up", &"down", &"left", &"right"]


func _make_hud() -> HUD:
	var hud: HUD = autofree((load("res://ui/HUD.tscn") as PackedScene).instantiate())
	add_child_autofree(hud)
	return hud


func _make_glyph() -> InputGlyph:
	var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	add_child_autofree(glyph)
	return glyph


func _motion(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func _button(index: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = index
	return event


func test_every_feedback_icon_resolves() -> void:
	var table: HudFeedbackIconTable = HudFeedbackIconTable.shared()
	for feedback: int in HudFeedbackIconTable.Feedback.values():
		assert_not_null(table.icon_for(feedback as HudFeedbackIconTable.Feedback), "feedback %d" % feedback)


func test_hud_has_no_height_icon() -> void:
	var hud: HUD = _make_hud()
	assert_null(hud.get_node_or_null("%HeightIcon"), "Bontago-1pi.80: label-less held-height icon removed")


func test_hud_capture_icon_follows_the_ring() -> void:
	var hud: HUD = _make_hud()
	assert_eq(hud._capture_icon.texture, HudFeedbackIconTable.shared().capture)
	hud.set_capture(0, 0.5, Color.RED)
	assert_true(hud._capture_icon.is_visible_in_tree())
	hud.set_capture(-1, 0.0, Color.WHITE)
	assert_false(hud._capture_icon.is_visible_in_tree())


func test_hud_reject_and_relocated_use_their_own_icons() -> void:
	var hud: HUD = _make_hud()
	var table: HudFeedbackIconTable = HudFeedbackIconTable.shared()
	hud.show_reject(&"outside_territory")
	assert_eq(hud._reject_icon.texture, table.rejected)
	assert_eq(hud._reject_icon.modulate.a, 1.0)
	hud.show_relocated()
	assert_eq(hud._reject_icon.texture, table.relocated)


func test_stick_direction_glyphs_resolve_and_are_used() -> void:
	var table: InputGlyphTable = InputGlyphTable.shared()
	for side: StringName in STICK_SIDES:
		assert_not_null(table.stick_click(side), "click %s" % side)
		for direction: StringName in STICK_DIRECTIONS:
			assert_not_null(table.stick_direction(side, direction), "%s %s" % [side, direction])
	var cases: Array = [
		[JOY_AXIS_LEFT_X, -1.0, &"left", &"left"], [JOY_AXIS_LEFT_X, 1.0, &"left", &"right"],
		[JOY_AXIS_LEFT_Y, -1.0, &"left", &"up"], [JOY_AXIS_RIGHT_Y, 1.0, &"right", &"down"],
	]
	for case: Array in cases:
		var glyph: InputGlyph = _make_glyph()
		glyph.set_event(_motion(case[0] as JoyAxis, case[1] as float))
		assert_eq(glyph.glyph_texture(), table.stick_direction(case[2] as StringName, case[3] as StringName))


func test_stick_click_uses_click_glyph_and_undirected_axis_keeps_base_stick() -> void:
	var table: InputGlyphTable = InputGlyphTable.shared()
	var glyph: InputGlyph = _make_glyph()
	glyph.set_event(_button(JOY_BUTTON_RIGHT_STICK))
	assert_eq(glyph.glyph_texture(), table.stick_click(&"right"))
	var axis_glyph: InputGlyph = _make_glyph()
	axis_glyph.set_event(_motion(JOY_AXIS_LEFT_X, 0.0))
	assert_ne(axis_glyph.glyph_texture(), null)
	assert_ne(axis_glyph.glyph_texture(), table.stick_direction(&"left", &"left"))


func test_chords_use_combo_art_in_any_order() -> void:
	var table: InputGlyphTable = InputGlyphTable.shared()
	var lb_rb: Array[InputEvent] = [_button(JOY_BUTTON_RIGHT_SHOULDER), _button(JOY_BUTTON_LEFT_SHOULDER)]
	var glyph: InputGlyph = _make_glyph()
	glyph.set_chord(lb_rb)
	assert_eq(glyph.glyph_texture(), table.combos["lb+rb"])
	assert_eq(glyph.label_text(), "RB+LB")
	var rt_stick: Array[InputEvent] = [_motion(JOY_AXIS_TRIGGER_RIGHT, 1.0), _motion(JOY_AXIS_RIGHT_X, 0.0)]
	var glyph2: InputGlyph = _make_glyph()
	glyph2.set_chord(rt_stick)
	assert_eq(glyph2.glyph_texture(), table.combos["rt+stick_right"])
	assert_gt(glyph2.custom_minimum_size.x, InputGlyph.GLYPH_HEIGHT_PX)
	var no_combo: Array[InputEvent] = [_button(JOY_BUTTON_A), _button(JOY_BUTTON_B)]
	var glyph3: InputGlyph = _make_glyph()
	glyph3.set_chord(no_combo)
	assert_not_null(glyph3.glyph_texture(), "unauthored chord falls back to first event's art")
	assert_eq(glyph3.label_text(), "A+B")


func test_keyboard_events_never_use_stick_art() -> void:
	var glyph: InputGlyph = _make_glyph()
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_E
	glyph.set_event(key)
	for side: StringName in STICK_SIDES:
		assert_ne(glyph.glyph_texture(), InputGlyphTable.shared().stick_click(side))
