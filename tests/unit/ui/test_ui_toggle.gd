extends GutTest
## UiToggle (ui/components/UiToggle.gd): ON / OFF word, state API, ui_accept /
## ui_left / ui_right through the Input Map, disabled still shows state.

var _toggled: Array[bool] = []


func _make() -> UiToggle:
	var toggle: UiToggle = UiToggle.new()
	toggle.toggled.connect(func(on: bool) -> void: _toggled.append(on))
	add_child_autofree(toggle)
	return toggle


func before_each() -> void:
	_toggled.clear()


func _key(keycode: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _action(action: StringName) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func test_set_on_emits_and_silent_does_not() -> void:
	var toggle: UiToggle = _make()
	toggle.set_on(true)
	assert_eq(_toggled, [true])
	toggle.set_on_silent(false)
	assert_eq(_toggled, [true], "silent sync does not emit")
	assert_false(toggle.is_on())
	assert_eq(toggle.text, "OFF")


func test_ui_accept_toggles_the_focused_toggle() -> void:
	var toggle: UiToggle = _make()
	await wait_frames(1)
	toggle.grab_focus()
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	await wait_frames(1)
	assert_true(toggle.is_on())
	assert_eq(_toggled, [true])


func test_ui_left_switches_off_and_ui_right_switches_on() -> void:
	var toggle: UiToggle = _make()
	await wait_frames(1)
	toggle._gui_input(_action(&"ui_right"))
	assert_true(toggle.is_on())
	toggle._gui_input(_action(&"ui_right"))
	assert_true(toggle.is_on(), "right on an on toggle stays on")
	toggle._gui_input(_action(&"ui_left"))
	assert_false(toggle.is_on())
	assert_eq(_toggled, [true, false])


func test_disabled_ignores_keys_but_keeps_showing_state() -> void:
	var toggle: UiToggle = _make()
	toggle.set_on(true)
	toggle.disabled = true
	toggle._gui_input(_action(&"ui_left"))
	assert_true(toggle.is_on())
	assert_eq(toggle.text, "ON", "disabled still shows its state")
	assert_true(toggle.disabled)
