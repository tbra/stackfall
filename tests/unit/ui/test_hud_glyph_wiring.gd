extends GutTest
## Bontago-mp0.124 part B: HUD feedback pictograms (HudFeedbackIconTable) and
## InputGlyph stick/chord glyphs are drawn.

const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/hud/InputGlyph.tscn")


func _make_glyph() -> InputGlyph:
	var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	add_child_autofree(glyph)
	return glyph


func _motion(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func test_stick_direction_glyphs_name_the_direction() -> void:
	var cases: Array = [
		[JOY_AXIS_LEFT_X, -1.0, "left"], [JOY_AXIS_LEFT_X, 1.0, "right"],
		[JOY_AXIS_LEFT_Y, -1.0, "up"], [JOY_AXIS_RIGHT_Y, 1.0, "down"],
	]
	for case: Array in cases:
		var glyph: InputGlyph = _make_glyph()
		glyph.set_event(_motion(case[0] as JoyAxis, case[1] as float))
		assert_true(glyph.label_text().ends_with(case[2] as String), glyph.label_text())
