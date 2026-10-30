extends GutTest
## UiChipToggle: state API and signal, disabled keeps state and ignores input, ui_accept toggles.

var _toggled: Array[bool] = []


func _make(text: String = "Black hole") -> UiChipToggle:
	var chip: UiChipToggle = UiChipToggle.new()
	chip.label = text
	chip.toggled.connect(func(on: bool) -> void: _toggled.append(on))
	add_child_autofree(chip)
	return chip


func before_each() -> void:
	_toggled.clear()


func test_state_api_label_and_signal() -> void:
	var chip: UiChipToggle = _make("Bomb")
	assert_eq(chip.text, "Bomb")
	assert_false(chip.is_on())
	chip.button_pressed = true
	assert_true(chip.is_on())
	assert_eq(_toggled, [true])
	chip.set_on_silent(false)
	assert_eq(_toggled, [true])


func test_disabled_chip_keeps_its_state() -> void:
	var chip: UiChipToggle = _make("Cat")
	chip.button_pressed = true
	chip.disabled = true
	assert_true(chip.is_on())
	assert_true(chip.disabled)


func test_ui_accept_toggles_when_focused() -> void:
	var chip: UiChipToggle = _make()
	await wait_frames(1)
	chip.grab_focus()
	var accept: InputEventKey = InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.physical_keycode = KEY_ENTER
	accept.pressed = true
	Input.parse_input_event(accept)
	var release: InputEventKey = accept.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await wait_frames(1)
	assert_true(chip.is_on())


func test_disabled_chip_ignores_accept() -> void:
	var chip: UiChipToggle = _make()
	chip.disabled = true
	await wait_frames(1)
	chip.grab_focus()
	var accept: InputEventKey = InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.physical_keycode = KEY_ENTER
	accept.pressed = true
	Input.parse_input_event(accept)
	Input.flush_buffered_events()
	await wait_frames(1)
	assert_false(chip.is_on())
