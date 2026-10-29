extends GutTest
## The sandbox hint bar (ui/hud/SandboxHintBar.gd) draws every entry's binding from the live Input
## Map and swaps to gamepad names when the active device changes.

var _bar: SandboxHintBar = null


func before_each() -> void:
	DebugMode.set_override_for_test(true)
	# The active device is global and earlier suites may leave it on the gamepad: start from keyboard.
	# A release alone classifies as keyboard and leaves no key held for later tests.
	var release: InputEventKey = InputEventKey.new()
	release.physical_keycode = KEY_A
	release.pressed = false
	Input.parse_input_event(release)
	await wait_process_frames(2)
	_bar = SandboxHintBar.new()
	add_child_autofree(_bar)


func after_each() -> void:
	DebugMode.clear_override_for_test()


func _glyph_texts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for node: Node in _bar.find_children("*", "InputGlyph", true, false):
		out.append((node as InputGlyph).label_text())
	return out


func _expected(gamepad: bool) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for entry: Dictionary in SandboxHintBar.ENTRIES:
		var events: Array[InputEvent] = InputGlyph.events_of_family(entry["action"] as StringName, gamepad)
		var glyph: InputGlyph = InputGlyph.new()
		glyph.set_event(events[0])
		out.append(glyph.label_text())
		glyph.free()
	return out


func test_keyboard_bar_shows_the_input_map_keys() -> void:
	assert_eq(_glyph_texts(), _expected(false))


func test_gamepad_press_switches_the_bar_to_pad_names() -> void:
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	Input.parse_input_event(press)
	await wait_process_frames(2)
	assert_eq(Settings.active_input_device(), Settings.DEVICE_GAMEPAD)
	assert_eq(_glyph_texts(), _expected(true))
	press.pressed = false
	Input.parse_input_event(press)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_A
	key.pressed = false
	Input.parse_input_event(key)
	await wait_process_frames(2)
	assert_eq(_glyph_texts(), _expected(false), "back to keyboard names")
