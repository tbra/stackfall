extends GutTest
## Owner API of InputGlyph (single-source concept G): device-filtered events,
## glyph building with a cap, and the cache signature.

const ACTION: StringName = &"test_glyph_owner_action"
func before_each() -> void:
	InputMap.add_action(ACTION)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_ENTER
	InputMap.action_add_event(ACTION, key)
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	InputMap.action_add_event(ACTION, pad)
	Settings._input(InputEventKey.new())


func after_each() -> void:
	InputMap.erase_action(ACTION)
	Settings._input(InputEventKey.new())


func test_events_filtered_by_device() -> void:
	var kb: Array[InputEvent] = InputGlyph.events_for_action(ACTION, Settings.DEVICE_KEYBOARD_MOUSE)
	var pad: Array[InputEvent] = InputGlyph.events_for_action(ACTION, Settings.DEVICE_GAMEPAD)
	assert_eq(kb.size(), 1)
	assert_true(kb[0] is InputEventKey)
	assert_eq(pad.size(), 1)
	assert_true(pad[0] is InputEventJoypadButton)


func test_signature_changes_with_device_and_rebind() -> void:
	var before: String = InputGlyph.signature_for_action(ACTION)
	Settings._input(InputEventJoypadButton.new())
	assert_ne(InputGlyph.signature_for_action(ACTION), before)
	Settings._input(InputEventKey.new())
	InputMap.action_erase_events(ACTION)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	InputMap.action_add_event(ACTION, key)
	assert_ne(InputGlyph.signature_for_action(ACTION), before)
