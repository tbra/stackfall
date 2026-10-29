class_name HudShares
extends RefCounted
## Territory share rows under an existing HUD container. Stub: builds nothing until the HUD
## extraction fills it in.

var _container: Control
var _lookup: HudPlayerLookup
var _arcade: ArcadeVisualTuning
var _tuning: HUDVisualTuning


func _init(container: Control, lookup: HudPlayerLookup, arcade: ArcadeVisualTuning, tuning: HUDVisualTuning) -> void:
	_container = container
	_lookup = lookup
	_arcade = arcade
	_tuning = tuning


func refresh(_shares: PackedFloat32Array, _mode_state: Dictionary, _active_slot: int) -> void:
	pass


func row_count() -> int:
	return 0
