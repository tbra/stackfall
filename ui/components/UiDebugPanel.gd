class_name UiDebugPanel
extends PanelContainer
## The shell every debug readout sits in: token plate, heading with the live key chip, sections of aligned rows.
## Stub: the methods build nothing yet.

@export var heading: String = ""
## The Input Map action whose live binding the chip names for the active device.
var toggle_action: StringName = &""
## The chord half (camera_snap_home for F1-F3/F9, pause_menu for F4); shown "Back + Y" on a pad.
var modifier_action: StringName = &""


## Created at first call (order = first-call order); updated in place; empty rows hide the section.
func set_section(_id: StringName, _title: String, _rows: Array[DebugRow]) -> void:
	pass


## Like set_section with right-aligned numeric columns.
func set_table(_id: StringName, _title: String, _headers: PackedStringArray, _rows: Array[DebugRow]) -> void:
	pass


## One free line (status, footer).
func set_note(_id: StringName, _text: String) -> void:
	pass


## Escape hatch for controls the kit has no part for.
func content() -> VBoxContainer:
	return null
