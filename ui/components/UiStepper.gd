class_name UiStepper
extends HBoxContainer
## STUB (Bontago-1pi.159.4 C1a): the typed public API of the design system's Stepper (-/+ blocks
## around a Bungee value, dim at the limits). Built in C1b.
## TODO(C1b): -/+ UiBlockButtons, value label, hold repeat, ui_left / ui_right, row item STEPPER.

@warning_ignore("unused_signal")
signal value_changed(value: int)

@export var min_value: int = 0
@export var max_value: int = 100
@export var step: int = 1
@export var value: int = 0
## Display only (e.g. "%.1f s"); never changes the stored int.
var formatter: Callable = Callable()


func set_value_silent(_new_value: int) -> void:
	pass  # TODO(C1b)


## [param current] moved one step in [param direction] (-1 / +1), clamped. TODO(C1b)
static func clamp_step(current: int, _direction: int, _lo: int = 0, _hi: int = 0, _step: int = 1) -> int:
	return current
