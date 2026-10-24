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
	_sfx.release_audio()


func _press(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame


## Pooled players still holding a stream after release_audio() are the ones a cue played on.
func _hover_voices(sfx: Node) -> int:
	var count: int = 0
	for child: Node in sfx.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player != null and player.stream != null:
			count += 1
	return count


func test_programmatic_focus_is_silent() -> void:
	_b.grab_focus()
	await get_tree().process_frame
	assert_eq(_hover_voices(_sfx), 0)


func test_ui_down_focus_move_plays_one_hover() -> void:
	await _press(&"ui_down")
	assert_true(_b.has_focus(), "ui_down moved focus")
	assert_eq(_hover_voices(_sfx), 1)


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
	Sfx.release_audio()
	scroll._move_selection(1)
	await get_tree().process_frame
	assert_true(rows[1].has_focus())
	assert_eq(_hover_voices(Sfx), 1, "first repeat move")
	scroll._move_selection(1)
	await get_tree().process_frame
	assert_true(rows[2].has_focus())
	assert_eq(_hover_voices(Sfx), 2, "second repeat move")
