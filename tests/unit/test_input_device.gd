extends GutTest
## Bontago-1pi.10 (owner: "default to only showing mouse/keyboard, switch to
## showing only gamepad options on gamepad input and switch back on mouse/
## keyboard input"): autoload/Settings.gd's own last-used-device tracking.
## Exercised through the real Settings/Events autoloads directly (device
## tracking has no per-instance state to isolate the way the graphics/audio/
## key-override settings in tests/unit/test_settings.gd do -- a fresh
## Settings.new() would just be a second, untested copy of the same
## classification logic). Every test restores Settings.DEFAULT_ACTIVE_DEVICE
## in after_each so this file never leaks a changed active device into
## another test file sharing the process.

# Bontago-1pi.11.45: other files sharing a gate shard can leave the device on
# gamepad, so start every test from the default too, not just restore after.
func before_each() -> void:
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


func after_each() -> void:
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


func test_defaults_to_keyboard_mouse() -> void:
	assert_eq(Settings.active_input_device(), Settings.DEVICE_KEYBOARD_MOUSE)


func test_a_real_keyboard_event_switches_from_gamepad_to_keyboard_mouse() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)

	var key_event: InputEventKey = InputEventKey.new()
	key_event.keycode = KEY_W
	key_event.pressed = true
	Input.parse_input_event(key_event)
	Input.flush_buffered_events()

	assert_eq(Settings.active_input_device(), Settings.DEVICE_KEYBOARD_MOUSE)


func test_a_real_mouse_button_switches_from_gamepad_to_keyboard_mouse() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)

	var mouse_event: InputEventMouseButton = InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_LEFT
	mouse_event.pressed = true
	Input.parse_input_event(mouse_event)
	Input.flush_buffered_events()

	assert_eq(Settings.active_input_device(), Settings.DEVICE_KEYBOARD_MOUSE)


func test_a_real_gamepad_button_switches_to_gamepad() -> void:
	var joy_event: InputEventJoypadButton = InputEventJoypadButton.new()
	joy_event.device = -1
	joy_event.button_index = JOY_BUTTON_A
	joy_event.pressed = true
	Input.parse_input_event(joy_event)
	Input.flush_buffered_events()

	assert_eq(Settings.active_input_device(), Settings.DEVICE_GAMEPAD)


## Bontago-1pi.10: these four call Settings._input(event) directly rather
## than through Input.parse_input_event() -- a real InputEventMouseMotion fed
## through the global Input singleton has its own `relative` recomputed from
## whatever screen position a previous test last warped the (shared,
## process-wide) mouse to, which made this deadzone check flaky depending on
## which other test files ran first in the same batch. Calling the callback
## directly exercises exactly the pure classification logic this test cares
## about, the same "call the callback directly for a unit-level check"
## convention ui/KeyRebindRow.gd's own tests already use for row._input().
func test_tiny_mouse_motion_does_not_switch_from_gamepad() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)

	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(0.2, 0.1)
	Settings._input(motion)

	assert_eq(Settings.active_input_device(), Settings.DEVICE_GAMEPAD, "tiny mouse jitter must not flip the active device")


func test_large_mouse_motion_switches_from_gamepad_to_keyboard_mouse() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)

	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(20.0, 0.0)
	Settings._input(motion)

	assert_eq(Settings.active_input_device(), Settings.DEVICE_KEYBOARD_MOUSE)


func test_small_joypad_motion_does_not_switch_from_keyboard_mouse() -> void:
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.device = -1
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 0.05
	Settings._input(motion)

	assert_eq(Settings.active_input_device(), Settings.DEVICE_KEYBOARD_MOUSE, "resting stick drift must not flip the active device")


func test_large_joypad_motion_switches_to_gamepad() -> void:
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.device = -1
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 0.9
	Settings._input(motion)

	assert_eq(Settings.active_input_device(), Settings.DEVICE_GAMEPAD)


func test_input_device_changed_signal_emits_only_on_an_actual_change() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_KEYBOARD_MOUSE)
	watch_signals(Events)

	var key_event: InputEventKey = InputEventKey.new()
	key_event.keycode = KEY_A
	key_event.pressed = true
	Input.parse_input_event(key_event)
	Input.flush_buffered_events()
	assert_signal_not_emitted(Events, "input_device_changed", "the device was already keyboard/mouse")

	var joy_event: InputEventJoypadButton = InputEventJoypadButton.new()
	joy_event.device = -1
	joy_event.button_index = JOY_BUTTON_B
	joy_event.pressed = true
	Input.parse_input_event(joy_event)
	Input.flush_buffered_events()
	assert_signal_emitted(Events, "input_device_changed")
