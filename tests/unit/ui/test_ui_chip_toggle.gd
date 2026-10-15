extends GutTest
## Bontago-1pi.159.5: UiChipToggle: mint + tick box when on, disc-700 + empty box when off, disabled
## with tooltip via set_available(false), ui_accept toggles, row height.

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
	chip.set_on(true)
	assert_true(chip.is_on())
	assert_eq(_toggled, [true])
	chip.set_on_silent(false)
	assert_eq(_toggled, [true])


func test_unavailable_chip_is_disabled_with_an_inline_reason_and_keeps_its_state() -> void:
	var chip: UiChipToggle = _make("Cat")
	chip.set_on(true)
	chip.set_available(false, "Switched off for this match")
	assert_true(chip.disabled)
	assert_false(chip.is_available())
	assert_eq(chip.unavailable_reason(), "Switched off for this match")
	assert_eq(chip.tooltip_text, "", "no tooltip")
	assert_true(chip.is_on())
	assert_true((chip.get_theme_stylebox("disabled") as BlockStyleBox).disabled)
	chip.set_available(true)
	assert_false(chip.disabled)


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


func test_unavailable_chip_ignores_accept() -> void:
	var chip: UiChipToggle = _make()
	chip.set_available(false)
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
