extends GutTest
## / 159.10 (on the shared UiHoldRepeat, via UiSegmentMeter): one pad press / stick flick = one step, holding
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
