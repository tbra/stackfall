class_name UiDropdown
extends Button
## STUB (Bontago-1pi.159.4 C1a): the typed public API of the design system's Dropdown. It will
## absorb ui/CycleSelector.gd (click-to-cycle for short lists, owner decision 1pi.94) and a popup
## list for long ones. Built in C2 (which also deletes CycleSelector).
## TODO(C2): items, select(), click-to-cycle, popup, row item DROPDOWN.

@warning_ignore("unused_signal")
signal item_selected(index: int)

var selected: int = -1


func add_item(_label: String, _id: int = -1) -> void:
	pass  # TODO(C2)


func select(_index: int) -> void:
	pass  # TODO(C2)
