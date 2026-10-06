extends GutTest
## Bontago-1pi.94: the shared click-to-cycle control. Click / ui_accept = next, right click =
## previous, both wrap; focus navigation, pad and echo never change the value; the signal
## carries the same index an OptionButton emitted.

var _selector: CycleSelector = null
var _picked: Array[int] = []


func before_each() -> void:
	_picked.clear()
	_selector = autofree(CycleSelector.new()) as CycleSelector
	for label: String in ["A", "B", "C"]:
		_selector.add_item(label)
	_selector.item_selected.connect(func(index: int) -> void: _picked.append(index))
	add_child(_selector)


func _right_click() -> InputEventMouseButton:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	return click


func _action(action: StringName, echo: bool = false) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func test_click_advances_once_and_wraps() -> void:
	assert_eq(_selector.selected, 0)
	_selector.pressed.emit()
	assert_eq(_selector.selected, 1)
	assert_eq(_selector.text, "B")
	_selector.pressed.emit()
	_selector.pressed.emit()
	assert_eq(_selector.selected, 0, "wraps forward")
	assert_eq(_picked, [1, 2, 0], "the signal carries the new index, once per click")


func test_right_click_goes_back_and_wraps() -> void:
	_selector.gui_input.emit(_right_click())
	assert_eq(_selector.selected, 2, "0 wraps back to the last item")
	_selector.gui_input.emit(_right_click())
	assert_eq(_selector.selected, 1)
	assert_eq(_picked, [2, 1])


func test_a_right_button_release_does_nothing() -> void:
	var release: InputEventMouseButton = _right_click()
	release.pressed = false
	_selector.gui_input.emit(release)
	assert_eq(_selector.selected, 0)
	assert_eq(_picked.size(), 0)


func test_focus_navigation_pad_and_echo_never_change_the_value() -> void:
	for action: StringName in [&"ui_left", &"ui_right", &"ui_up", &"ui_down"]:
		_selector.gui_input.emit(_action(action))
	for button: JoyButton in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]:
		var pad: InputEventJoypadButton = InputEventJoypadButton.new()
		pad.button_index = button
		pad.pressed = true
		_selector.gui_input.emit(pad)
	var held: InputEventKey = InputEventKey.new()
	held.keycode = KEY_RIGHT
	held.pressed = true
	held.echo = true
	_selector.gui_input.emit(held)
	var accept_echo: InputEventKey = InputEventKey.new()
	accept_echo.keycode = KEY_ENTER
	accept_echo.pressed = true
	accept_echo.echo = true
	_selector.gui_input.emit(accept_echo)
	assert_eq(_selector.selected, 0)
	assert_eq(_picked.size(), 0)


func test_setting_selected_from_code_does_not_emit_and_ignores_out_of_range() -> void:
	_selector.selected = 2
	assert_eq(_selector.selected, 2)
	assert_eq(_selector.text, "C")
	_selector.selected = 7
	assert_eq(_selector.selected, 2, "out of range is ignored like OptionButton")
	assert_eq(_picked.size(), 0)


func test_disabled_items_are_skipped_in_both_directions() -> void:
	_selector.set_item_disabled(1, true)
	_selector.pressed.emit()
	assert_eq(_selector.selected, 2)
	_selector.gui_input.emit(_right_click())
	assert_eq(_selector.selected, 0)
	assert_eq(_picked, [2, 0])


func test_a_disabled_selector_ignores_clicks() -> void:
	_selector.disabled = true
	_selector.pressed.emit()
	_selector.gui_input.emit(_right_click())
	assert_eq(_selector.selected, 0)


func test_icon_and_item_tooltip_follow_the_selection() -> void:
	var texture: Texture2D = PlaceholderTexture2D.new()
	_selector.set_item_icon(1, texture)
	_selector.set_item_tooltip(1, "second")
	_selector.pressed.emit()
	assert_eq(_selector.icon, texture)
	assert_eq(_selector.tooltip_text, "second")
	assert_eq(_selector.get_item_tooltip(1), "second")


func test_without_auto_advance_it_only_reports_the_activation() -> void:
	_selector.auto_advance = false
	var seen: Array[bool] = []
	_selector.cycled.connect(func(backwards: bool) -> void: seen.append(backwards))
	_selector.pressed.emit()
	_selector.gui_input.emit(_right_click())
	assert_eq(seen, [false, true])
	assert_eq(_selector.selected, 0)
	assert_eq(_picked.size(), 0)
