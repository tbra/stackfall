class_name UiHoldRepeat
extends RefCounted
## The shared pad / key / mouse hold-repeat of the menu value controls (UiStepper, UiSegmentMeter;
## Bontago-1pi.159.10, folded from the per-control copies of 1pi.159.5 / 159.7 and the old
## SliderNav.Repeater of 1pi.119 / 1pi.142 / 1pi.152).
##
## One press moves one step and the event is accepted. Holding repeats after
## SliderNavTuning.repeat_delay_sec every repeat_interval_sec, driven by [method advance] and not by
## OS / engine echo. A stick presses past stick_press_threshold and releases only below
## stick_release_threshold (hysteresis), so drift never retriggers; it auto-repeats only near full
## deflection (stick_repeat_threshold) at the slower stick delay / interval.

const TUNING: SliderNavTuning = preload("res://config/slider_nav_tuning.tres")
const DIR_NONE: int = 0
const SOURCE_KEY: int = 0
const SOURCE_STICK: int = 1
const SOURCE_MOUSE: int = 2

## Reads a stick axis; tests replace it (headless Input has no real pad state).
var axis_reader: Callable = Input.get_joy_axis
var direction: int = DIR_NONE
var source: int = SOURCE_KEY

var _step: Callable = Callable()
var _stick_axis: int = -1
var _stick_device: int = 0
var _held_for: float = 0.0
var _next_due: float = 0.0


## [param step_callable] takes the direction (-1 / +1) and moves the control one step.
func _init(step_callable: Callable) -> void:
	_step = step_callable


func is_holding() -> bool:
	return direction != DIR_NONE


func release() -> void:
	direction = DIR_NONE
	_stick_axis = -1


## Starts a hold and steps once. [param stick_axis] is only meaningful for SOURCE_STICK.
func start(new_direction: int, new_source: int, stick_axis: int = -1, device: int = 0) -> void:
	direction = new_direction
	source = new_source
	_stick_axis = stick_axis
	_stick_device = device
	_held_for = 0.0
	_next_due = TUNING.stick_repeat_delay_sec if new_source == SOURCE_STICK else TUNING.repeat_delay_sec
	_step.call(direction)


## Feeds a ui_left / ui_right key or pad-button event; returns true when the event is consumed.
func handle_action_event(event: InputEvent) -> bool:
	for action: StringName in [&"ui_left", &"ui_right"]:
		var dir: int = -1 if action == &"ui_left" else 1
		if event.is_action_pressed(action, true):
			if not (event is InputEventKey and (event as InputEventKey).echo):
				start(dir, SOURCE_KEY)
			return true
		if event.is_action_released(action) and direction == dir and source == SOURCE_KEY:
			release()
	return false


## Feeds a stick motion; returns true when the event is consumed (one push = one step).
func handle_stick(motion: InputEventJoypadMotion) -> bool:
	if source == SOURCE_STICK and _stick_axis == motion.axis and direction != DIR_NONE:
		var released: bool = absf(motion.axis_value) < TUNING.stick_release_threshold
		if released or signf(motion.axis_value) != float(direction):
			release()
		else:
			return true
	for action: StringName in [&"ui_left", &"ui_right"]:
		if motion.is_action(action, true) and motion.is_action_pressed(action, true):
			if absf(motion.axis_value) >= TUNING.stick_press_threshold and direction == DIR_NONE:
				start(-1 if action == &"ui_left" else 1, SOURCE_STICK, motion.axis, motion.device)
			return true
	return false


## Advances the hold timer; at most one repeat step per call. [param alive] is the owner's "still
## allowed to step" (visible, enabled, focused); [param mouse_down] is whether the held block is
## still pressed (SOURCE_MOUSE). Returns false once the hold has ended.
func advance(delta: float, alive: bool, mouse_down: bool = false) -> bool:
	if direction == DIR_NONE:
		return false
	if not alive or not _still_held(mouse_down):
		release()
		return false
	var interval: float = TUNING.repeat_interval_sec
	if source == SOURCE_STICK:
		interval = TUNING.stick_repeat_interval_sec
		if absf(float(axis_reader.call(_stick_device, _stick_axis))) < TUNING.stick_repeat_threshold:
			_held_for = 0.0
			_next_due = TUNING.stick_repeat_delay_sec
			return true
	_held_for += delta
	if _held_for >= _next_due:
		_next_due += interval
		_step.call(direction)
	return true


## True while the held key / button / stick is still physically down (a missed release event --
## window focus loss, modal, overlay -- must not leave the control stepping forever).
func _still_held(mouse_down: bool) -> bool:
	match source:
		SOURCE_STICK:
			var deflection: float = float(axis_reader.call(_stick_device, _stick_axis))
			return absf(deflection) >= TUNING.stick_release_threshold and signf(deflection) == float(direction)
		SOURCE_MOUSE:
			return mouse_down
	return Input.is_action_pressed(&"ui_left" if direction < 0 else &"ui_right")
