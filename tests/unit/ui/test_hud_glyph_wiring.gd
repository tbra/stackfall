extends GutTest
## Bontago-mp0.124 part B: HUD feedback pictograms (HudFeedbackIconTable) and
## InputGlyph stick/chord glyphs are drawn.

const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/hud/InputGlyph.tscn")


func _make_hud() -> HUD:
	var hud: HUD = autofree((load("res://ui/hud/HUD.tscn") as PackedScene).instantiate())
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


func test_stick_direction_glyphs_name_the_direction() -> void:
	var cases: Array = [
		[JOY_AXIS_LEFT_X, -1.0, "left"], [JOY_AXIS_LEFT_X, 1.0, "right"],
		[JOY_AXIS_LEFT_Y, -1.0, "up"], [JOY_AXIS_RIGHT_Y, 1.0, "down"],
	]
	for case: Array in cases:
		var glyph: InputGlyph = _make_glyph()
		glyph.set_event(_motion(case[0] as JoyAxis, case[1] as float))
		assert_true(glyph.label_text().ends_with(case[2] as String), glyph.label_text())


func test_stick_click_and_undirected_axis_are_stick_pictograms() -> void:
	var glyph: InputGlyph = _make_glyph()
	glyph.set_event(_button(JOY_BUTTON_RIGHT_STICK))
	assert_eq(glyph.label_text(), "R3")
	assert_false(glyph.is_arcade_cap(), "the stick is a pictogram")
	var axis_glyph: InputGlyph = _make_glyph()
	axis_glyph.set_event(_motion(JOY_AXIS_LEFT_X, 0.0))
	assert_eq(axis_glyph.label_text(), "L Stick")


func test_keyboard_events_are_key_caps() -> void:
	var glyph: InputGlyph = _make_glyph()
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_E
	glyph.set_event(key)
	assert_true(glyph.is_arcade_cap())
	assert_eq(glyph.label_text(), "E")
