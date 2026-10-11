extends GutTest
## Bontago-1pi.152 / 159.10 (on UiSegmentMeter + UiHoldRepeat): a slow stick push moves a meter exactly one step (no 0 -> 100 run); only a
## near-full hold auto-repeats, slower than the d-pad.

const FRAME: float = 1.0 / 60.0
const CELLS: int = 100
const START_VALUE: int = 50
const EPS: float = 0.0001
const RAMP_STEP: float = 0.01
const RAMP_COUNT: int = 100
const LOW: float = 0.15
const HIGH: float = 0.35
const OSCILLATIONS: int = 30
const PARTIAL: float = 0.6
const FULL: float = 1.0
const HOLD_SECONDS: float = 3.0
const SEGMENTS: int = 10

var _meter: UiSegmentMeter = null
var _axis: float = 0.0
var _origin: int = START_VALUE


func before_each() -> void:
	_meter = UiSegmentMeter.new()
	_meter.step_count = CELLS
	add_child_autofree(_meter)
	_meter.set_value_silent(START_VALUE)
	_meter.grab_focus()
	_meter.axis_reader = _read_axis
	_axis = 0.0
	_origin = START_VALUE


func _read_axis(_device: int, _axis_index: int) -> float:
	return _axis


func _push(value: float) -> void:
	_axis = value
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = value
	_meter._gui_input(motion)


func _hold(seconds: float) -> void:
	for _i: int in roundi(seconds / FRAME):
		_meter.advance(FRAME)


func _steps() -> float:
	return float(_meter.value - _origin)


func test_slow_ramp_is_one_step() -> void:
	for i: int in RAMP_COUNT + 1:
		_push(float(i) * RAMP_STEP)
	assert_almost_eq(_steps(), 1.0, EPS)


func test_slow_ramp_left_is_one_step() -> void:
	for i: int in RAMP_COUNT + 1:
		_push(-float(i) * RAMP_STEP)
	assert_almost_eq(_steps(), -1.0, EPS)


func test_oscillation_in_the_deadzone_band_never_steps() -> void:
	for _i: int in OSCILLATIONS:
		_push(LOW)
		_push(HIGH)
	assert_almost_eq(_steps(), 0.0, EPS)


func test_oscillation_after_the_press_adds_nothing() -> void:
	_push(FULL)
	for _i: int in OSCILLATIONS:
		_push(LOW)
		_push(HIGH)
	assert_almost_eq(_steps(), 1.0, EPS, "low/high wobble below the press threshold adds no steps")


func test_partial_push_hold_is_one_step() -> void:
	_push(PARTIAL)
	_hold(HOLD_SECONDS)
	assert_almost_eq(_steps(), 1.0, EPS)


func test_full_hold_repeats_at_the_stick_rate() -> void:
	_origin = 0
	_meter.set_value_silent(_origin)  # headroom: the meter must not clamp at max during the hold
	_push(FULL)
	var tuning: SliderNavTuning = UiHoldRepeat.TUNING
	_hold(tuning.stick_repeat_delay_sec - 0.1)
	assert_almost_eq(_steps(), 1.0, EPS, "no repeat inside the stick delay")
	_hold(HOLD_SECONDS - (tuning.stick_repeat_delay_sec - 0.1))
	var expected: int = 1 + 1 + int((HOLD_SECONDS - tuning.stick_repeat_delay_sec) / tuning.stick_repeat_interval_sec)
	assert_almost_eq(_steps(), float(expected), 1.0 + EPS, "repeats every stick interval")
	assert_gt(_steps(), 2.0)


func test_release_and_new_push_is_one_more_step() -> void:
	_push(FULL)
	_push(0.0)
	_push(FULL)
	assert_almost_eq(_steps(), 2.0, EPS)


func test_stick_tuning_orders() -> void:
	var tuning: SliderNavTuning = UiHoldRepeat.TUNING
	assert_gt(tuning.stick_press_threshold, tuning.stick_release_threshold)
	assert_gt(tuning.stick_repeat_threshold, tuning.stick_press_threshold)
	assert_gt(tuning.stick_repeat_delay_sec, tuning.repeat_delay_sec)
	assert_gt(tuning.stick_repeat_interval_sec, tuning.repeat_interval_sec)
