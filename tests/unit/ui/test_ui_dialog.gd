extends GutTest
## Bontago-1pi.159.41: UiDialog (docs/ui_reskin/components.md "Dialog") -- plate width, actions in
## order with Cancel last, initial focus, glyph hints, focus trap, and keyboard / gamepad parity
## through synthetic events (A or Enter confirms, B or Start closes).

var _dialog: UiDialog = null
var _chosen: Array[StringName] = []
var _canceled: int = 0


func before_each() -> void:
	_chosen = []
	_canceled = 0
	_dialog = UiDialog.new()
	_dialog.title = "Leave match?"
	_dialog.dialog_text = "Leave this match?"
	_dialog.add_action(&"leave", "Leave match", UiBlockButton.Look.DANGER)
	_dialog.add_action(&"other", "Other", UiBlockButton.Look.SECONDARY)
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


func test_starts_hidden_and_plate_is_design_width() -> void:
	assert_false(_dialog.visible)
	var tuning: OptionsVisualTuning = load("res://config/ui/options_visual_tuning.tres") as OptionsVisualTuning
	assert_eq(_dialog.panel.custom_minimum_size.x, float(tuning.dialog_width_px))


func test_open_focuses_first_action_and_orders_cancel_last() -> void:
	_dialog.open()
	assert_true(_dialog.visible)
	assert_eq(_dialog.actions().size(), 2)
	assert_true(_dialog.actions()[0].has_focus(), "the forward action takes initial focus")
	assert_eq(_dialog.cancel_button().get_index(), _dialog.panel.content.get_child_count() - 1)
	assert_eq(_dialog.actions()[0].hint_action, &"", "dialog blocks are text only")
	assert_eq(_dialog.cancel_button().hint_action, &"")


func test_pressing_an_action_hides_and_emits_its_id() -> void:
	_dialog.open()
	_dialog.actions()[1].pressed.emit()
	assert_false(_dialog.visible)
	assert_eq(_chosen, [&"other"] as Array[StringName])
	assert_eq(_canceled, 0)


func test_cancel_block_dismisses() -> void:
	_dialog.open()
	_dialog.cancel_button().pressed.emit()
	assert_false(_dialog.visible)
	assert_eq(_canceled, 1)
	assert_true(_chosen.is_empty())


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


func test_gamepad_start_closes() -> void:
	_dialog.open()
	await _pad_tap(JOY_BUTTON_START)
	assert_false(_dialog.visible)
	assert_eq(_canceled, 1)


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
