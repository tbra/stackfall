class_name SliderNav
extends RefCounted
## Shared menu-slider behaviour (Bontago-1pi.119 / 1pi.123).
##
## 119 (owner playtest: sliders too sensitive on gamepad): a slider whose own step is fine
## (volume, rumble, move speed: 100+ native steps) moves by a coarser, consistent step on
## keyboard / gamepad ui_left / ui_right -- range / SliderNavTuning.steps_per_range, rounded up
## to a multiple of the slider's step. A gui_input handler applies it, so
## drag and click stay at full resolution. Sliders that are already coarse are left alone.
##
## 123 (owner playtest: scrolling over a slider changes it): `scrollable = false` makes the
## slider ignore the mouse wheel, so the event bubbles to the enclosing ScrollContainer and
## scrolls the menu. Sliders change only by drag, click, keys or gamepad.

const FLOAT_SLACK: float = 0.0001  # DECISION: guards ceil against 0.1 / 0.01 = 10.000000000000002
const TUNING: SliderNavTuning = preload("res://config/slider_nav_tuning.tres")


## Meta set by SegmentMeter.attach: how many cells the slider is drawn as; one press moves one cell.
const META_SEGMENT_COUNT: StringName = &"slider_nav_segment_count"
const NODE_NAME: StringName = &"SliderNavRepeater"


## Configures `slider` once its min/max/step are final. `handle_keys` is false for a slider whose
## owner already steps it itself on ui_left / ui_right (ui/Lobby.gd's one-minute timer sliders).
static func apply(slider: HSlider, handle_keys: bool = true) -> void:
	slider.scrollable = false
	if handle_keys and slider.get_node_or_null(NodePath(NODE_NAME)) == null:
		slider.add_child(Repeater.new(slider))


## One press moves one step and the event is accepted, so the Slider's own one-native-step
## handling (and any echo) never also runs. Holding repeats after `repeat_delay_sec` every
## `repeat_interval_sec`, driven here and not by OS/engine echo. A stick presses past the ui
## deadzone and releases only below `stick_release_threshold` (hysteresis), so drift around the
## press threshold never retriggers.
class Repeater extends Node:
	var _slider: HSlider = null
	var _direction: float = 0.0
	var _stick_axis: int = -1
	var _stick_device: int = 0
	## Reads a stick axis; tests replace it (headless Input has no real pad state).
	var axis_reader: Callable = Input.get_joy_axis
	var _held_for: float = 0.0
	var _next_due: float = 0.0

	func _init(slider: HSlider) -> void:
		name = SliderNav.NODE_NAME
		_slider = slider
		set_process(false)
		slider.gui_input.connect(on_gui_input)
		slider.focus_exited.connect(release)
		slider.visibility_changed.connect(release)

	func release() -> void:
		_direction = 0.0
		_stick_axis = -1
		set_process(false)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
			release()

	## True while the held button/key/stick is still physically down (a missed release event
	## -- window focus loss, modal, overlay -- must not leave the slider stepping forever).
	func _still_held() -> bool:
		if _stick_axis >= 0:
			var value: float = float(axis_reader.call(_stick_device, _stick_axis))
			return absf(value) >= SliderNav.TUNING.stick_release_threshold and signf(value) == _direction
		return Input.is_action_pressed(&"ui_left" if _direction < 0.0 else &"ui_right")

	func is_held() -> bool:
		return _direction != 0.0

	func on_gui_input(event: InputEvent) -> void:
		if not _slider.editable:
			return
		if SliderNav.step_for(_slider) < 0.0:
			return
		if event is InputEventJoypadMotion:
			_on_stick(event as InputEventJoypadMotion)
			return
		for action: StringName in [&"ui_left", &"ui_right"]:
			var direction: float = -1.0 if action == &"ui_left" else 1.0
			if event.is_action_pressed(action, true):
				_slider.accept_event()
				if not (event is InputEventKey and (event as InputEventKey).echo):
					_start(direction, -1)
				return
			if event.is_action_released(action) and _direction == direction and _stick_axis < 0:
				release()

	func _on_stick(motion: InputEventJoypadMotion) -> void:
		if _stick_axis == motion.axis:
			var released: bool = absf(motion.axis_value) < SliderNav.TUNING.stick_release_threshold
			if released or signf(motion.axis_value) != _direction:
				release()
			else:
				_slider.accept_event()
				return
		for action: StringName in [&"ui_left", &"ui_right"]:
			if motion.is_action(action, true) and motion.is_action_pressed(action, true):
				_slider.accept_event()
				_stick_device = motion.device
				_start(-1.0 if action == &"ui_left" else 1.0, motion.axis)
				return

	func _start(direction: float, stick_axis: int) -> void:
		_direction = direction
		_stick_axis = stick_axis
		_held_for = 0.0
		_next_due = SliderNav.TUNING.repeat_delay_sec
		_step()
		set_process(true)

	func _step() -> void:
		var step: float = SliderNav.step_for(_slider)
		if step > 0.0:
			_slider.value += _direction * step

	## Advances the hold timer; at most one repeat step per call.
	func advance(delta: float) -> void:
		if _direction == 0.0:
			return
		if not _slider.has_focus() or not _slider.is_visible_in_tree():
			release()
			return
		if not _still_held():
			release()
			return
		_held_for += delta
		if _held_for >= _next_due:
			_next_due += SliderNav.TUNING.repeat_interval_sec
			_step()

	func _process(delta: float) -> void:
		advance(delta)


## The step for ui_left / ui_right on `slider`: one SegmentMeter cell when it wears a meter,
## else range / steps_per_range; -1.0 when the slider's own step is already that coarse.
static func step_for(slider: HSlider) -> float:
	var divisions: int = int(slider.get_meta(META_SEGMENT_COUNT, TUNING.steps_per_range))
	return coarse_step(slider.min_value, slider.max_value, slider.step, divisions)


## The keyboard/gamepad step for a slider with these bounds, or -1.0 (the engine default,
## its own step) when it is not fine-grained.
static func coarse_step(min_value: float, max_value: float, step: float, divisions: int = -1) -> float:
	var count: int = TUNING.steps_per_range if divisions < 0 else divisions
	if step <= 0.0 or count <= 0:
		return -1.0
	var span: float = max_value - min_value
	if span / step <= float(count):
		return -1.0
	var multiples: float = ceilf(span / float(count) / step - FLOAT_SLACK)
	return multiples * step
