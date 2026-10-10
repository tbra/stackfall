class_name UiToggle
extends Button
## STUB (Bontago-1pi.159.4 C1a): the typed public API of the design system's Toggle (knob in a
## disc-900 well, mint when on, ON/OFF word, docs/UI_COMPONENTS_PLAN.md section 3.2). Built in C1b.
## TODO(C1b): well + knob + ON/OFF label, states, ui_left = off / ui_right = on, row item TOGGLE.

@export var caption: String = ""
@export var show_word: bool = true


func set_on(_on: bool) -> void:
	pass  # TODO(C1b)


func is_on() -> bool:
	return false  # TODO(C1b)


## The ON / OFF word shown for [param on]. TODO(C1b)
static func state_word_for(_on: bool) -> String:
	return ""
