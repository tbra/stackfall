class_name UiChipToggle
extends Button
## STUB (Bontago-1pi.159.4 C1a): the typed public API of the design system's ChipToggle (mint block
## with an ink check box when on, disc-700 with an empty box when off). Built in C1b.
## TODO(C1b): block faces, check box, disabled + tooltip via set_available(false).

@export var label: String = ""
@export var chip_icon: Texture2D = null


func set_on(_on: bool) -> void:
	pass  # TODO(C1b)


func is_on() -> bool:
	return false  # TODO(C1b)


## Shows the chip disabled (e.g. a gift that is switched off) with its tooltip. TODO(C1b)
func set_available(_available: bool) -> void:
	pass
