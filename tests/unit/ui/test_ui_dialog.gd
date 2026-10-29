extends GutTest
## UiDialog (docs/ui_reskin/components.md "Dialog") -- initial focus, reachability, glyph hints, focus trap, and keyboard / gamepad parity
## through synthetic events (A or Enter confirms, B or Start closes).

var _dialog: UiDialog = null
var _chosen: Array[StringName] = []
var _canceled: int = 0
var _leave: UiBlockButton = null
var _other: UiBlockButton = null


func before_each() -> void:
	_chosen = []
	_canceled = 0
	_dialog = UiDialog.new()
	_dialog.title = "Leave match?"
	_dialog.dialog_text = "Leave this match?"
	_leave = _dialog.add_action(&"leave", "Leave match", UiBlockButton.Look.DANGER)
	_other = _dialog.add_action(&"other", "Other", UiBlockButton.Look.SECONDARY)
	_dialog.action_chosen.connect(func(id: StringName) -> void: _chosen.append(id))
	_dialog.canceled.connect(func() -> void: _canceled += 1)
	add_child_autofree(_dialog)


func _pad(button: JoyButton, pressed: bool) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func _pad_tap(button: JoyButton) -> void:
	_pad(button, true)
	_pad(button, false)
	await get_tree().process_frame
	await get_tree().process_frame


func test_open_focuses_first_action_and_tab_reaches_every_block() -> void:
	_dialog.open()
	await wait_frames(2)
	assert_true(_dialog.visible)
	assert_true(_leave.has_focus(), "the forward action takes initial focus")
	var reached: Array[Control] = [_leave]
	var current: Control = _leave
	for step: int in range(reached.size() + FocusWalk.DEFAULT_CAP):
		var next: Control = current.get_node_or_null(current.focus_next) as Control
		if next == null or reached.has(next):
			assert_eq(next, _leave, "Tab wraps back to the first block")
			break
		reached.append(next)
		current = next
	assert_true(reached.has(_other))
	assert_true(reached.has(_dialog.cancel_button()))
	for control: Control in FocusWalk.live_focusable(_dialog.panel):
		assert_true(reached.has(control), "every live control is on the Tab loop: %s" % control.name)


func test_pad_down_reaches_every_block() -> void:
	_dialog.open()
	await wait_frames(2)
	var stops: Array[Control] = FocusWalk.loop(_leave, SIDE_BOTTOM)
	assert_true(FocusWalk.is_closed(stops, _leave, SIDE_BOTTOM), "D-pad down wraps back to the first block")
	for control: Control in FocusWalk.live_focusable(_dialog.panel):
		assert_true(stops.has(control), "D-pad down reaches %s" % control.name)
	var up: Array[Control] = FocusWalk.loop(_leave, SIDE_TOP)
	assert_eq(up.size(), stops.size(), "D-pad up also visits every block")


func test_pressing_an_action_hides_and_emits_its_id() -> void:
	_dialog.open()
	_other.pressed.emit()
	assert_false(_dialog.visible)
	assert_eq(_chosen, [&"other"] as Array[StringName])
	assert_eq(_canceled, 0)


func test_gamepad_a_confirms_the_focused_action() -> void:
	_dialog.open()
	await _pad_tap(JOY_BUTTON_A)
	assert_eq(_chosen, [&"leave"] as Array[StringName])
	assert_false(_dialog.visible)


func test_gamepad_b_closes() -> void:
	_dialog.open()
	await _pad_tap(JOY_BUTTON_B)
	assert_false(_dialog.visible)
	assert_eq(_canceled, 1)
	assert_true(_chosen.is_empty())


func test_keyboard_escape_closes_and_enter_confirms() -> void:
	_dialog.open()
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(_dialog.visible)
	assert_eq(_canceled, 1)
	_dialog.open()
	var enter: InputEventKey = InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	var enter_up: InputEventKey = enter.duplicate() as InputEventKey
	enter_up.pressed = false
	Input.parse_input_event(enter_up)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_chosen, [&"leave"] as Array[StringName])


func test_focus_is_trapped_inside_the_plate() -> void:
	var outside: Button = Button.new()
	add_child_autofree(outside)
	_dialog.open()
	var last: UiBlockButton = _dialog.cancel_button()
	last.grab_focus()
	var neighbour: Control = last.get_node_or_null(last.get_focus_neighbor(SIDE_BOTTOM)) as Control
	assert_true(neighbour == last or _dialog.panel.is_ancestor_of(neighbour), "no neighbour leaves the plate")
	assert_true(_dialog.panel.is_ancestor_of(last.get_node(last.focus_next)))


func test_scrim_blocks_the_mouse() -> void:
	var scrim: ColorRect = _dialog.get_child(0) as ColorRect
	assert_eq(scrim.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_almost_eq(scrim.color.a, MenuStyleFactory.arcade_tuning().scrim_alpha, 0.001)
