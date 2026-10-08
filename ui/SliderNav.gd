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

const META_STICK_DIRECTION: StringName = &"slider_nav_stick_direction"
const TUNING: SliderNavTuning = preload("res://config/slider_nav_tuning.tres")


## Configures `slider` once its min/max/step are final. `handle_keys` is false for a slider whose
## owner already steps it itself on ui_left / ui_right (ui/Lobby.gd's one-minute timer sliders).
static func apply(slider: HSlider, handle_keys: bool = true) -> void:
	slider.scrollable = false
	if handle_keys and not slider.gui_input.is_connected(_on_gui_input.bind(slider)):
		slider.gui_input.connect(_on_gui_input.bind(slider))


## The engine Slider's custom step is not exposed to scripts, so the coarse step is applied here:
## one press of ui_left / ui_right moves `coarse_step()` and the event is accepted, so the
## Slider's own one-native-step handling (and its hold-to-repeat) never also runs. A stick
## only counts on its press edge (it re-sends motion while held).
static func _on_gui_input(event: InputEvent, slider: HSlider) -> void:
	if not slider.editable:
		return
	var step: float = coarse_step(slider.min_value, slider.max_value, slider.step)
	if step < 0.0:
		return
	var direction: float = 0.0
	if event is InputEventJoypadMotion:
		direction = _stick_edge(event as InputEventJoypadMotion, slider)
	elif event.is_action_pressed(&"ui_left", true):
		direction = -1.0
	elif event.is_action_pressed(&"ui_right", true):
		direction = 1.0
	if direction == 0.0:
		return
	slider.accept_event()
	slider.value += direction * step


## +1 / -1 on the motion event that pushes the stick past the ui_right / ui_left threshold,
## 0 while it stays pushed, drifts or returns (the stick re-sends motion every frame it is held).
static func _stick_edge(motion: InputEventJoypadMotion, slider: HSlider) -> float:
	var held: float = float(slider.get_meta(META_STICK_DIRECTION, 0.0))
	for action: StringName in [&"ui_left", &"ui_right"]:
		if not motion.is_action(action, true):
			continue
		var direction: float = -1.0 if action == &"ui_left" else 1.0
		if motion.is_action_pressed(action, true):
			slider.set_meta(META_STICK_DIRECTION, direction)
			return direction if held != direction else 0.0
		if held == direction:
			slider.set_meta(META_STICK_DIRECTION, 0.0)
	return 0.0


## The keyboard/gamepad step for a slider with these bounds, or -1.0 (the engine default,
## its own step) when it is not fine-grained.
static func coarse_step(min_value: float, max_value: float, step: float) -> float:
	if step <= 0.0 or TUNING.steps_per_range <= 0:
		return -1.0
	var span: float = max_value - min_value
	if span / step <= float(TUNING.steps_per_range):
		return -1.0
	var multiples: float = ceilf(span / float(TUNING.steps_per_range) / step)
	return multiples * step
