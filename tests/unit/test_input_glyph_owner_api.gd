extends GutTest
## Owner API of InputGlyph (single-source concept G): device-filtered events,
## glyph building with a cap, and the cache signature.

const ACTION: StringName = &"test_glyph_owner_action"
const MAX_ONE: int = 1


func before_each() -> void:
	InputMap.add_action(ACTION)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_ENTER
	InputMap.action_add_event(ACTION, key)
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	InputMap.action_add_event(ACTION, pad)
	Settings.set_active_input_device_for_test(Settings.DEVICE_KEYBOARD_MOUSE)


func after_each() -> void:
	InputMap.erase_action(ACTION)
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


func test_events_filtered_by_device() -> void:
	var kb: Array[InputEvent] = InputGlyph.events_for_action(ACTION, Settings.DEVICE_KEYBOARD_MOUSE)
	var pad: Array[InputEvent] = InputGlyph.events_for_action(ACTION, Settings.DEVICE_GAMEPAD)
	assert_eq(kb.size(), 1)
	assert_true(kb[0] is InputEventKey)
	assert_eq(pad.size(), 1)
	assert_true(pad[0] is InputEventJoypadButton)


func test_default_device_is_active_device() -> void:
	assert_true(InputGlyph.events_for_action(ACTION)[0] is InputEventKey)
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	assert_true(InputGlyph.events_for_action(ACTION)[0] is InputEventJoypadButton)


func test_missing_action_is_empty() -> void:
	assert_true(InputGlyph.events_for_action(&"no_such_action_xyz").is_empty())
	var host: Control = autofree(Control.new()) as Control
	add_child(host)
	assert_true(InputGlyph.build_for_action(host, &"no_such_action_xyz").is_empty())


func test_build_for_action_makes_glyphs_per_device() -> void:
	var host: Control = autofree(Control.new()) as Control
	add_child(host)
	var kb: Array[InputGlyph] = InputGlyph.build_for_action(host, ACTION, MAX_ONE)
	assert_eq(kb.size(), 1)
	assert_eq(kb[0].label_text(), "Enter")
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	var pad: Array[InputGlyph] = InputGlyph.build_for_action(host, ACTION)
	assert_eq(pad.size(), 1)
	assert_eq(pad[0].label_text(), "A")
	assert_eq(host.get_child_count(), 2)


func test_signature_changes_with_device_and_rebind() -> void:
	var before: String = InputGlyph.signature_for_action(ACTION)
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	assert_ne(InputGlyph.signature_for_action(ACTION), before)
	Settings.set_active_input_device_for_test(Settings.DEVICE_KEYBOARD_MOUSE)
	InputMap.action_erase_events(ACTION)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	InputMap.action_add_event(ACTION, key)
	assert_ne(InputGlyph.signature_for_action(ACTION), before)
