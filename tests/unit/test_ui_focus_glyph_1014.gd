extends GutTest
## Bontago-1pi.159.48 (focus-move hover cue), .49 (d-pad glyph lit arms), .58 (hint glyph padding).

const SFX_SCRIPT: GDScript = preload("res://autoload/Sfx.gd")

var _sfx: Node = null
var _a: Button = null
var _b: Button = null


func before_each() -> void:
	_sfx = SFX_SCRIPT.new()
	add_child_autofree(_sfx)
	var host: VBoxContainer = VBoxContainer.new()
	add_child_autofree(host)
	_a = Button.new()
	_b = Button.new()
	host.add_child(_a)
	host.add_child(_b)
	_a.focus_neighbor_bottom = _a.get_path_to(_b)
	_b.focus_neighbor_right = _b.get_path_to(_a)
	_a.grab_focus()
	await get_tree().process_frame


func _press(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame


func test_programmatic_focus_is_silent() -> void:
	var before: int = _sfx.focus_hover_count
	_b.grab_focus()
	await get_tree().process_frame
	assert_eq(_sfx.focus_hover_count, before)


func test_ui_down_focus_move_plays_one_hover() -> void:
	var before: int = _sfx.focus_hover_count
	await _press(&"ui_down")
	assert_true(_b.has_focus(), "ui_down moved focus")
	assert_eq(_sfx.focus_hover_count, before + 1)


func test_ui_right_focus_move_plays_one_hover() -> void:
	_b.grab_focus()
	await get_tree().process_frame
	var before: int = _sfx.focus_hover_count
	await _press(&"ui_right")
	assert_true(_a.has_focus(), "ui_right moved focus")
	assert_eq(_sfx.focus_hover_count, before + 1)


func test_dpad_lit_arms_mirror() -> void:
	var offsets: Array[float] = []
	var lengths: Array[float] = []
	for button: int in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		var glyph: InputGlyph = InputGlyph.new()
		add_child_autofree(glyph)
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button
		glyph.set_event(event)
		glyph.size = Vector2(InputGlyph.SHAPE_WIDTH_PX, InputGlyph.GLYPH_HEIGHT_PX)
		var lit: Rect2 = glyph.dpad_lit_rect()
		assert_gt(lit.size.x, 0.0)
		var side: float = minf(glyph.size.x, glyph.size.y - float(MenuStyleFactory.arcade_tuning().drop_sm_px))
		var mid: Vector2 = Vector2(glyph.size.x * 0.5, side * 0.5)
		offsets.append(lit.get_center().distance_to(mid))
		lengths.append(maxf(lit.size.x, lit.size.y))
	for i: int in range(1, 4):
		assert_almost_eq(offsets[i], offsets[0], 0.001, "lit arm centre equidistant from the hub")
		assert_almost_eq(lengths[i], lengths[0], 0.001)


func test_hint_glyph_padding_is_token_driven() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var button: UiBlockButton = UiBlockButton.new()
	button.text = "ADD BOT"
	button.hint_action = &"lobby_add_bot"
	add_child_autofree(button)
	await get_tree().process_frame
	var flow: InputPromptFlow = UiButtonHint.flow_of(button)
	assert_not_null(flow)
	var drawn: float = flow.get_combined_minimum_size().y * flow.scale.y
	assert_lte(drawn, button.size.y - float(arcade.space_3_px) + float(arcade.drop_sm_px) + 0.5, "cap keeps token padding")


func test_held_stick_repeat_in_scroll_container_plays_one_hover_per_move() -> void:
	var scroll: FocusScrollContainer = FocusScrollContainer.new()
	scroll.size = Vector2(200, 200)
	var column: VBoxContainer = VBoxContainer.new()
	scroll.add_child(column)
	var rows: Array[Button] = []
	for i: int in range(3):
		var row: Button = Button.new()
		row.text = "row %d" % i
		column.add_child(row)
		rows.append(row)
	add_child_autofree(scroll)
	await get_tree().process_frame
	rows[0].grab_focus()
	await get_tree().process_frame
	var before: int = Sfx.focus_hover_count
	scroll._move_selection(1)
	await get_tree().process_frame
	assert_true(rows[1].has_focus())
	assert_eq(Sfx.focus_hover_count, before + 1, "first repeat move")
	scroll._move_selection(1)
	await get_tree().process_frame
	assert_true(rows[2].has_focus())
	assert_eq(Sfx.focus_hover_count, before + 2, "second repeat move")
