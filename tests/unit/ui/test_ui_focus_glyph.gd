extends GutTest
## (focus-move hover cue), .49 (d-pad glyph lit arms), .58 (hint glyph padding).

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
