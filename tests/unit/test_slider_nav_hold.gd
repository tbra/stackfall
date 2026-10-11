extends GutTest
## Bontago-1pi.142 / 159.10 (on the shared UiHoldRepeat, via UiSegmentMeter): one pad press / stick flick = one step, holding
## repeats at the tuned rate after the initial delay, stick drift near the threshold never retriggers.

const FRAME: float = 1.0 / 60.0
const HOLD_SECONDS: float = 1.0
const PAD_DEVICE: int = 0
const PUSH: float = 1.0
const DRIFT_HIGH: float = 0.55
const DRIFT_LOW: float = 0.4
const REST: float = 0.1
const CELLS: int = 100
const START_VALUE: int = 50

var _meter: UiSegmentMeter = null


func before_each() -> void:
	_meter = UiSegmentMeter.new()
	_meter.step_count = CELLS
	add_child_autofree(_meter)
	_meter.set_value_silent(START_VALUE)
	_meter.grab_focus()


func _wire() -> void:
	_meter.axis_reader = _stick_down


func _stick(value: float) -> InputEventJoypadMotion:
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.device = PAD_DEVICE
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = value
	return motion


func after_each() -> void:
	Input.action_release(&"ui_right")


func _dpad(pressed: bool) -> InputEventJoypadButton:
	if pressed:
		Input.action_press(&"ui_right")
	else:
		Input.action_release(&"ui_right")
	var button: InputEventJoypadButton = InputEventJoypadButton.new()
	button.device = PAD_DEVICE
	button.button_index = JOY_BUTTON_DPAD_RIGHT
	button.pressed = pressed
	return button


func _stick_down(_device: int, _axis: int) -> float:
	return PUSH


func _hold(seconds: float) -> void:
	for _i: int in roundi(seconds / FRAME):
		_meter.advance(FRAME)


func test_dpad_press_hold_repeat_timing() -> void:
	_wire()
	var step: int = 1
	_meter._gui_input(_dpad(true))
	assert_eq(_meter.value, START_VALUE + step, "press steps once immediately")
	_hold(UiHoldRepeat.TUNING.repeat_delay_sec * 0.9)
	assert_eq(_meter.value, START_VALUE + step, "no repeat inside the initial delay")
	var tuning: SliderNavTuning = UiHoldRepeat.TUNING
	_hold(HOLD_SECONDS)
	var held_total: float = tuning.repeat_delay_sec * 0.9 + HOLD_SECONDS
	var expected_repeats: int = 1 + int((held_total - tuning.repeat_delay_sec) / tuning.repeat_interval_sec)
	assert_almost_eq(_meter.value, mini(START_VALUE + step * (1 + expected_repeats), CELLS), step, "bounded repeat rate")
	_meter._gui_input(_dpad(false))
	var released: int = _meter.value
	_hold(HOLD_SECONDS)
	assert_eq(_meter.value, released, "release stops the repeat")


func test_tap_never_repeats() -> void:
	_wire()
	_meter._gui_input(_dpad(true))
	_meter._gui_input(_dpad(false))
	var after_tap: int = _meter.value
	_hold(HOLD_SECONDS)
	assert_eq(_meter.value, after_tap)


func test_stick_drift_around_the_threshold_does_not_retrigger() -> void:
	_wire()
	var step: int = 1
	_meter._gui_input(_stick(PUSH))
	for _i: int in 20:
		_meter._gui_input(_stick(DRIFT_LOW))
		_meter._gui_input(_stick(DRIFT_HIGH))
	assert_eq(_meter.value, START_VALUE + step, "drift between release and press thresholds = still the same push")
	_meter._gui_input(_stick(REST))
	assert_false(_meter.is_holding(), "back near centre releases")
	_meter._gui_input(_stick(PUSH))
	assert_eq(_meter.value, START_VALUE + step * 2, "a fresh flick steps once more")


func test_stick_hold_repeats_after_the_delay_only() -> void:
	_wire()
	var step: int = 1
	_meter._gui_input(_stick(PUSH))
	for _i: int in roundi(UiHoldRepeat.TUNING.repeat_delay_sec / FRAME) - 2:
		_meter._gui_input(_stick(PUSH))
		_meter.advance(FRAME)
	assert_eq(_meter.value, START_VALUE + step)
	_hold(UiHoldRepeat.TUNING.repeat_interval_sec + UiHoldRepeat.TUNING.repeat_delay_sec)
	assert_gt(_meter.value, START_VALUE + step, "held stick repeats")


func test_key_echo_events_do_not_add_steps() -> void:
	_wire()
	var step: int = 1
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.physical_keycode = KEY_RIGHT
	key.pressed = true
	_meter._gui_input(key)
	var echo: InputEventKey = key.duplicate() as InputEventKey
	echo.echo = true
	for _i: int in 10:
		_meter._gui_input(echo)
	assert_eq(_meter.value, START_VALUE + step, "OS key repeat does not outrun the tuned rate")


func test_missed_release_stops_the_repeat() -> void:
	_wire()
	_meter._gui_input(_dpad(true))
	_hold(UiHoldRepeat.TUNING.repeat_delay_sec + UiHoldRepeat.TUNING.repeat_interval_sec)
	Input.action_release(&"ui_right")  # physical release the slider never hears about
	var frozen: int = _meter.value
	_hold(HOLD_SECONDS)
	assert_eq(_meter.value, frozen, "no steps once the button is physically up")
	assert_false(_meter.is_holding())
	_meter._gui_input(_stick(PUSH))
	_meter.axis_reader = func(_d: int, _a: int) -> float: return 0.0
	frozen = _meter.value
	_hold(HOLD_SECONDS)
	assert_eq(_meter.value, frozen, "same for a stick whose axis is back at rest")
