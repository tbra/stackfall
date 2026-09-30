class_name GoalControl
extends RefCounted
## Who currently controls each goal flag (spec 2.3), for the goal beacons.
##
## A goal is controlled by a team when the final owned raster cell under the
## goal base belongs to that team. That already encodes the win check's
## per-goal test: TerritorySolver only stamps circles connected to a living
## home circle (a dead home's circles are dropped), and the raster only owns
## cells inside those groups, so "in a controlled component connected to a
## living allied home" is exactly "the raster names a team here".
##
## DECISION (Bontago-470.7): derived locally from the raster on host and client
## alike instead of replicating a per-goal array. The mirror raster
## (TerritoryRaster.apply_replicated_state) carries the owner byte, the
## contested bit and the hole bit per cell, which is all this reads, so host
## and client always agree; no wire change is needed.
##
## Pure logic, no scene tree.

const NEUTRAL: int = -1
const CONTESTED: int = -2


## One entry per goal position: a team id (>= 0), NEUTRAL or CONTESTED.
static func owners(raster: TerritoryRaster, goal_positions: PackedVector2Array) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	for point: Vector2 in goal_positions:
		result.append(owner_at(raster, point))
	return result


static func owner_at(raster: TerritoryRaster, point: Vector2) -> int:
	if raster == null:
		return NEUTRAL
	var cell: Vector2i = raster.grid().world_to_cell(point)
	if raster.is_contested(cell.x, cell.y):
		return CONTESTED
	return raster.team_at(cell.x, cell.y)


## Distinct team ids owning cells on a ring of `samples` points at `radius`
## around `point`, in first-seen order. Used to pick the colors a contested
## beacon flickers between; may be empty.
static func nearby_teams(
	raster: TerritoryRaster, point: Vector2, radius: float, samples: int
) -> PackedInt32Array:
	var teams: PackedInt32Array = PackedInt32Array()
	if raster == null:
		return teams
	var count: int = maxi(samples, 1)
	for i: int in range(count):
		var angle: float = TAU * float(i) / float(count)
		var probe: Vector2 = point + Vector2(cos(angle), sin(angle)) * radius
		var cell: Vector2i = raster.grid().world_to_cell(probe)
		var team: int = raster.team_at(cell.x, cell.y)
		if team >= 0 and not teams.has(team):
			teams.append(team)
	return teams
