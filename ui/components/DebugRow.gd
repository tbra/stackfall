class_name DebugRow
extends RefCounted
## One row of a debug panel: cells[0] is the name, the rest values; `warn` tints the row (hot phase, frame over budget).

var cells: PackedStringArray = PackedStringArray()
var warn: bool = false


## A name/value row.
static func pair(name: String, value: String, warn_row: bool = false) -> DebugRow:
	var row: DebugRow = DebugRow.new()
	row.cells = PackedStringArray([name, value])
	row.warn = warn_row
	return row
