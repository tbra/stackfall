extends GutTest
## Bontago-1pi.142: one pad press / stick flick = one step, holding
## repeats at the tuned rate after the initial delay, stick drift near the threshold never retriggers.

const FRAME: float = 1.0 / 60.0
const HOLD_SECONDS: float = 1.0
const PAD_DEVICE: int = 0
const FLOAT_EPS: float = 0.0001
const PUSH: float = 1.0
const DRIFT_HIGH: float = 0.55
const DRIFT_LOW: float = 0.4
const REST: float = 0.1
const FIELD_MAX: float = 1.0
const FIELD_STEP: float = 0.01
const START_VALUE: float = 0.5

var _slider: HSlider = null
var _repeater: SliderNav.Repeater = null


func before_each() -> void:
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = FIELD_MAX
	_slider.step = FIELD_STEP
	_slider.value = START_VALUE
	add_child_autofree(_slider)
	_slider.grab_focus()


func _wire() -> void:
	SliderNav.apply(_slider)
	_repeater = _slider.get_node(NodePath(SliderNav.NODE_NAME)) as SliderNav.Repeater
	_repeater.axis_reader = _stick_down


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
		_repeater.advance(FRAME)


func test_dpad_press_hold_repeat_timing() -> void:
	_wire()
	var step: float = SliderNav.step_for(_slider)
	_slider.gui_input.emit(_dpad(true))
	assert_almost_eq(_slider.value, START_VALUE + step, FLOAT_EPS, "press steps once immediately")
	_hold(SliderNavTuning.new().repeat_delay_sec * 0.9)
	assert_almost_eq(_slider.value, START_VALUE + step, FLOAT_EPS, "no repeat inside the initial delay")
	var tuning: SliderNavTuning = SliderNav.TUNING
	_hold(HOLD_SECONDS)
	var held_total: float = tuning.repeat_delay_sec * 0.9 + HOLD_SECONDS
	var expected_repeats: int = 1 + int((held_total - tuning.repeat_delay_sec) / tuning.repeat_interval_sec)
	assert_almost_eq(_slider.value, minf(START_VALUE + step * float(1 + expected_repeats), FIELD_MAX), step + FLOAT_EPS, "bounded repeat rate")
	_slider.gui_input.emit(_dpad(false))
	var released: float = _slider.value
	_hold(HOLD_SECONDS)
	assert_eq(_slider.value, released, "release stops the repeat")


func test_tap_never_repeats() -> void:
	_wire()
	_slider.gui_input.emit(_dpad(true))
	_slider.gui_input.emit(_dpad(false))
	var after_tap: float = _slider.value
	_hold(HOLD_SECONDS)
	assert_eq(_slider.value, after_tap)


func test_stick_drift_around_the_threshold_does_not_retrigger() -> void:
	_wire()
	var step: float = SliderNav.step_for(_slider)
	_slider.gui_input.emit(_stick(PUSH))
	for _i: int in 20:
		_slider.gui_input.emit(_stick(DRIFT_LOW))
		_slider.gui_input.emit(_stick(DRIFT_HIGH))
	assert_almost_eq(_slider.value, START_VALUE + step, FLOAT_EPS, "drift between release and press thresholds = still the same push")
	_slider.gui_input.emit(_stick(REST))
	assert_false(_repeater.is_held(), "back near centre releases")
	_slider.gui_input.emit(_stick(PUSH))
	assert_almost_eq(_slider.value, START_VALUE + step * 2.0, FLOAT_EPS, "a fresh flick steps once more")


func test_stick_hold_repeats_after_the_delay_only() -> void:
	_wire()
	var step: float = SliderNav.step_for(_slider)
	_slider.gui_input.emit(_stick(PUSH))
	for _i: int in roundi(SliderNav.TUNING.repeat_delay_sec / FRAME) - 2:
		_slider.gui_input.emit(_stick(PUSH))
		_repeater.advance(FRAME)
	assert_almost_eq(_slider.value, START_VALUE + step, FLOAT_EPS)
	_hold(SliderNav.TUNING.repeat_interval_sec + SliderNav.TUNING.repeat_delay_sec)
	assert_gt(_slider.value, START_VALUE + step + FLOAT_EPS, "held stick repeats")


func test_key_echo_events_do_not_add_steps() -> void:
	_wire()
	var step: float = SliderNav.step_for(_slider)
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.physical_keycode = KEY_RIGHT
	key.pressed = true
	_slider.gui_input.emit(key)
	var echo: InputEventKey = key.duplicate() as InputEventKey
	echo.echo = true
	for _i: int in 10:
		_slider.gui_input.emit(echo)
	assert_almost_eq(_slider.value, START_VALUE + step, FLOAT_EPS, "OS key repeat does not outrun the tuned rate")


func test_missed_release_stops_the_repeat() -> void:
	_wire()
	_slider.gui_input.emit(_dpad(true))
	_hold(SliderNav.TUNING.repeat_delay_sec + SliderNav.TUNING.repeat_interval_sec)
	Input.action_release(&"ui_right")  # physical release the slider never hears about
	var frozen: float = _slider.value
	_hold(HOLD_SECONDS)
	assert_eq(_slider.value, frozen, "no steps once the button is physically up")
	assert_false(_repeater.is_held())
	_slider.gui_input.emit(_stick(PUSH))
	_repeater.axis_reader = func(_d: int, _a: int) -> float: return 0.0
	frozen = _slider.value
	_hold(HOLD_SECONDS)
	assert_eq(_slider.value, frozen, "same for a stick whose axis is back at rest")
