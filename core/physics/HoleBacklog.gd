class_name HoleBacklog
extends RefCounted
## Hole cells waiting to be applied to the disc, drained at a bounded rate per
## tick (from Field.gd:679-761). No scene tree.
## Interface stub: P4-Iholes fills the bodies.


func want(_opened: PackedInt32Array, _closed: PackedInt32Array, _in_disk: PackedInt32Array) -> void:
	pass


## Cells that opened during this drain; Field emits hole_cells_applied with them.
# STUB: filled by P4-Iholes
func drain(_budget: int) -> PackedInt32Array:
	return PackedInt32Array()


func is_applied(_cell: int) -> bool:
	return false


func applied_count() -> int:
	return 0


func clear() -> void:
	pass
