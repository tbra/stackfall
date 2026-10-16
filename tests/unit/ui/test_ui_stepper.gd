extends GutTest
## UiStepper: clamp + step, dim at limits, formatter, silent set, -/+ clicks, key
## and pad steps, hold repeat and stick friction (SliderNavTuning numbers), row-item width/height.

var _values: Array[int] = []


func _make(lo: int = 0, hi: int = 10, start: int = 5) -> UiStepper:
	var stepper: UiStepper = UiStepper.new()
	stepper.min_value = lo
	stepper.max_value = hi
	stepper.value = start
	stepper.value_changed.connect(func(v: int) -> void: _values.append(v))
	add_child_autofree(stepper)
	return stepper


func before_each() -> void:
	_values.clear()


func _action(action: StringName, pressed: bool = true) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func test_value_clamps_and_emits_only_on_change() -> void:
	var stepper: UiStepper = _make()
	_values.clear()
	stepper.value = 99
	assert_eq(stepper.value, 10)
	stepper.value = 10
	assert_eq(_values, [10], "no second emit for the same value")


func test_ui_left_and_right_step_by_step() -> void:
	var stepper: UiStepper = _make()
	stepper.step = 2
	await wait_frames(1)
	stepper.grab_focus()
	stepper._gui_input(_action(&"ui_right"))
	assert_eq(stepper.value, 7)
	stepper._gui_input(_action(&"ui_right", false))
	stepper._gui_input(_action(&"ui_left"))
	assert_eq(stepper.value, 5)
	stepper._gui_input(_action(&"ui_left", false))
	assert_false(stepper.is_processing())


func test_hold_repeats_after_the_delay_then_every_interval() -> void:
	var stepper: UiStepper = _make(0, 100, 50)
	await wait_frames(1)
	stepper.grab_focus()
	var tuning: SliderNavTuning = UiHoldRepeat.TUNING
	Input.action_press(&"ui_right")
	stepper._gui_input(_action(&"ui_right"))
	assert_eq(stepper.value, 51)
	stepper.advance(tuning.repeat_delay_sec - 0.01)
	assert_eq(stepper.value, 51, "no repeat before the delay")
	stepper.advance(0.02)
	assert_eq(stepper.value, 52)
	stepper.advance(tuning.repeat_interval_sec)
	assert_eq(stepper.value, 53)
	Input.action_release(&"ui_right")
	stepper.advance(tuning.repeat_interval_sec)
	assert_false(stepper.is_processing(), "a missed release event cannot keep it stepping")


func test_stick_friction_one_push_one_step_and_repeat_only_near_full() -> void:
	var stepper: UiStepper = _make(0, 100, 50)
	await wait_frames(1)
	stepper.grab_focus()
	var tuning: SliderNavTuning = UiHoldRepeat.TUNING
	var axis: Array[float] = [tuning.stick_press_threshold + 0.05]
	stepper.axis_reader = func(_device: int, _a: int) -> float: return axis[0]
	var push: InputEventJoypadMotion = InputEventJoypadMotion.new()
	push.axis = JOY_AXIS_LEFT_X
	push.axis_value = axis[0]
	stepper._gui_input(push)
	assert_eq(stepper.value, 51, "the press steps once")
	stepper.advance(10.0)
	assert_eq(stepper.value, 51, "a partial push never auto-repeats")
	axis[0] = 1.0
	stepper.advance(tuning.stick_repeat_delay_sec + 0.01)
	assert_eq(stepper.value, 52, "full deflection repeats after the stick delay")
	axis[0] = tuning.stick_release_threshold - 0.05
	stepper.advance(0.01)
	assert_false(stepper.is_processing(), "below the release threshold lets go")


func test_disabled_blocks_input() -> void:
	var stepper: UiStepper = _make()
	stepper.disabled = true
	assert_true(stepper.minus_button.disabled)
	assert_true(stepper.plus_button.disabled)
	stepper._gui_input(_action(&"ui_right"))
	assert_eq(stepper.value, 5)
