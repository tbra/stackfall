class_name UiTabs
extends HBoxContainer
## STUB (Bontago-1pi.159.4 C1a): the typed public API of the design system's Tabs (rim notch on the
## active tab; HORIZONTAL top tabs, VERTICAL side tabs). Built in C1b.
## TODO(C1b): UiTab buttons, LB/RB (menu_tab_previous/next) when handle_shoulders, ui_left/right.

enum Orientation { HORIZONTAL, VERTICAL }

@warning_ignore("unused_signal")
signal tab_changed(id: StringName)

@export var orientation: Orientation = Orientation.HORIZONTAL
@export var handle_shoulders: bool = true
var current: StringName = &""


func add_tab(_id: StringName, _label: String) -> void:
	pass  # TODO(C1b)


func set_tab_visible(_id: StringName, _shown: bool) -> void:
	pass  # TODO(C1b)


func set_tab_disabled(_id: StringName, _disabled: bool) -> void:
	pass  # TODO(C1b)


## The index after [param current_index] moved [param direction] among [param count] tabs. TODO(C1b)
static func next_index(current_index: int, _direction: int, _count: int) -> int:
	return current_index
