class_name TerritoryGroups
extends RefCounted
## TerritorySolver's output: the connected, home-anchored groups (spec 2.2,
## 3.3). One group is one "single continuous controlled area" in the win
## condition's words, so both the raster and WinChecker read it.
##
## Groups are stored as parallel arrays rather than objects, because the
## raster writes a group index into every cell it fills and that index is
## compared millions of times per match.
##
## Pure logic: no scene tree (CLAUDE.md).

## Written into a raster cell that no group covers.
const NO_GROUP: int = -1
## Written into a raster cell covered by groups of two or more teams
## (spec 2.2, "Contested zones").
const CONTESTED: int = -2

## team_ids[g] is the team that owns group g.
var team_ids: PackedInt32Array = PackedInt32Array()
## circle_indices[g] indexes into the circle array handed to
## TerritorySolver.solve(), in ascending order.
var circle_indices: Array[PackedInt32Array] = []


func group_count() -> int:
	return team_ids.size()


func team_of(group: int) -> int:
	if group < 0 or group >= team_ids.size():
		return -1
	return team_ids[group]


func circles_of(group: int) -> PackedInt32Array:
	if group < 0 or group >= circle_indices.size():
		return PackedInt32Array()
	return circle_indices[group]


## Every group belonging to a team. A team can hold several disconnected
## groups; only one of them has to contain the goal flags to win.
@warning_ignore_start("unused_parameter")
func groups_of_team(team_id: int) -> PackedInt32Array:
	return PackedInt32Array()
@warning_ignore_restore("unused_parameter")


## Adds a group. Only TerritorySolver calls this.
func add_group(team_id: int, circles: PackedInt32Array) -> int:
	team_ids.append(team_id)
	circle_indices.append(circles)
	return team_ids.size() - 1


func clear() -> void:
	team_ids = PackedInt32Array()
	circle_indices = []
