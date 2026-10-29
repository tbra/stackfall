class_name HudPlayerLookup
extends RefCounted
## Slot and team lookups for the HUD (colour, name, team, elimination). Stub: every answer is the
## null-object default until the HUD extraction fills it in.

## The match read port; the HUD reassigns it when its own match_context changes.
var context: MatchContext
var _palette: PackedColorArray
var _roster_name: Callable


func _init(match_context: MatchContext, palette: PackedColorArray, roster_name: Callable) -> void:
	context = match_context
	_palette = palette
	_roster_name = roster_name


func team_of_slot(_slot_id: int) -> int:
	return -1


func resolved_team_numbers() -> PackedInt32Array:
	return PackedInt32Array()


func color_for_team(_team_id: int) -> Color:
	return Color.WHITE


func color_for_slot(_slot_id: int) -> Color:
	return Color.WHITE


func is_slot_eliminated(_slot_id: int) -> bool:
	return false


func is_team_eliminated(_team_id: int) -> bool:
	return false


func name_for_slot(_slot_id: int) -> String:
	return ""


func name_for_team(_team_id: int) -> String:
	return ""
