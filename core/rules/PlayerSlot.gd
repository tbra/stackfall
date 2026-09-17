class_name PlayerSlot
extends RefCounted
## One seat in a match: who they are, which team they are on, where their home
## flag stands (spec 2.2, 2.8).
##
## M2 fills these from MatchConfig in hot-seat; M3a fills `peer_id` from the
## MultiplayerAPI and M5 sets `is_bot`. Nothing here assumes a transport or a
## scene tree (CLAUDE.md).

var slot_id: int = -1
## Free-for-all gives every slot its own team, so rule code never branches on
## whether teams are on (see MatchConfig.team_of_slot).
var team_id: int = -1
var display_name: String = ""
var color: Color = Color.WHITE
## Disk-local (x, z) of the home flag, at home_flag_radius_fraction *
## field_radius, evenly spaced around the disk (spec 2.2).
var home_position: Vector2 = Vector2.ZERO
## True for the player sitting at this PC. In hot-seat every slot is local.
var is_local: bool = true
var is_bot: bool = false
## MultiplayerAPI peer id, or 0 in hot-seat. Set in M3a.
var peer_id: int = 0
## False once the home flag has left the disk; its home circle stops existing
## (spec 2.2: "It always exists while the flag is on the disk").
var home_flag_alive: bool = true


func _init(
	p_slot_id: int = -1,
	p_team_id: int = -1,
	p_display_name: String = "",
	p_color: Color = Color.WHITE,
	p_home_position: Vector2 = Vector2.ZERO
) -> void:
	slot_id = p_slot_id
	team_id = p_team_id
	display_name = p_display_name
	color = p_color
	home_position = p_home_position


@warning_ignore_start("unused_parameter")
## Spec 2.2: home flags sit at home_flag_radius_fraction * field_radius,
## spaced evenly around the edge. Slot 0 sits at angle 0 (+x), and slots go
## counter-clockwise from there, so a 2-player match puts the two players
## opposite each other.
static func home_position_for(slot_id: int, slot_count: int, map_def: MapDef) -> Vector2:
	return Vector2.ZERO


## Spec 2.2: one goal flag in the center by default; 2-5 are placed
## symmetrically at goal_flag_radius_fraction * field_radius. Returns
## disk-local positions, `count` long.
static func goal_positions_for(count: int, map_def: MapDef) -> PackedVector2Array:
	return PackedVector2Array()
@warning_ignore_restore("unused_parameter")
