class_name FieldFlags
extends Node3D
## The home and goal flags and the beacon body of a Field (from Field.gd:947-1140),
## as a child node. Field sets the typed properties below before add_child, then
## calls place(). Interface stub: P4-Iflags fills the bodies.

var map_def: MapDef
var visuals: TerritoryVisuals
## Beacon friction is tuning.disk_friction.
var tuning: PhysicsTuning
var home_flag_scene: PackedScene
var goal_flag_scene: PackedScene


## Team/slot colours, indexed by slot. Field feeds this from place_flags and
## set_overlay_source; it takes effect at the next goal-control refresh.
# STUB: filled by P4-Iflags
func set_colors(_colors: PackedColorArray) -> void:
	pass


# STUB: filled by P4-Iflags
func place(_slot_count: int, _goal_count: int, _goal_zone_radius: float, _capture_hold_s: float, _counts_up: bool) -> void:
	pass


# STUB: filled by P4-Iflags
func clear() -> void:
	pass


# STUB: filled by P4-Iflags
func home_flags() -> Array[HomeFlag]:
	var none: Array[HomeFlag] = []
	return none


# STUB: filled by P4-Iflags
func goal_flags() -> Array[GoalFlag]:
	var none: Array[GoalFlag] = []
	return none


# STUB: filled by P4-Iflags
func set_sync(_on: bool) -> void:
	pass
