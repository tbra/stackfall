class_name WinChecker
extends RefCounted
## The win condition (spec 2.3, 3.3).
##
## Spec 2.3: "A player or team wins when one connected territory contains
## every goal flag continuously for capture_hold = 3 s." Spec 3.3 says to
## check it against the raster, which is what this does: read the group index
## at each goal flag position; if every goal reads the *same* group index and
## that group is real, that group's team is capturing. "The same group", not
## "the same team", is what makes it one *connected* territory, so a team
## holding two goals with two separate towers does not win.
##
## The hold timer resets the moment the capture breaks, including when the
## capturing group changes identity between solves.
##
## Pure logic: no scene tree (CLAUDE.md).

const NO_TEAM: int = -1

var _goal_positions: PackedVector2Array = PackedVector2Array()
var _capture_hold: float = 3.0

## The group every goal currently sits in, or NO_GROUP. Held across updates so
## that a capture passing from one group to another restarts the hold instead
## of inheriting its predecessor's progress.
var _capturing_group: int = TerritoryGroups.NO_GROUP
var _capturing_team: int = NO_TEAM
var _held: float = 0.0
var _winner: int = NO_TEAM


func _init(
	goal_positions: PackedVector2Array = PackedVector2Array(), capture_hold: float = 3.0
) -> void:
	_goal_positions = goal_positions
	_capture_hold = maxf(capture_hold, 0.0)


func goal_positions() -> PackedVector2Array:
	return _goal_positions


func capture_hold() -> float:
	return _capture_hold


## Advances the capture timer by `delta` seconds against one raster. Called
## once per territory solve (spec 3.7: "Win check: runs every territory
## update"), so delta is 1 / TerritoryTuning.solve_hz.
func update(raster: TerritoryRaster, delta: float) -> void:
	if _winner != NO_TEAM:
		return

	var group: int = _group_holding_every_goal(raster)
	if group == TerritoryGroups.NO_GROUP:
		_clear_capture()
		return

	# DECISION (core/rules/WinChecker.gd): the hold restarts when either the
	# shared group index or the owning team changes. Group indices are handed
	# out afresh by every solve and index into that solve's circle array, so
	# "group 0" this tick and "group 0" last tick are not necessarily the same
	# territory; the team is what makes the comparison meaningful. Watching
	# both catches every break the spec cares about: the goals going unowned or
	# contested, the goals splitting across groups, and a rival taking over.
	# The one case it cannot see is a goal passing between two groups of the
	# *same* team whose indices happen to coincide, which would need the solver
	# to carry stable group identities across solves. That team held the goal
	# throughout either way, so it is not worth the bookkeeping.
	var team: int = _team_at(raster, _goal_positions[0])
	if group != _capturing_group or team != _capturing_team:
		_capturing_group = group
		_capturing_team = team
		_held = 0.0
	_held += delta

	# Tolerates the drift of summing delta many times: 30 additions of 0.1 land
	# on 2.9999999999999996, and a capture that refused to complete on the tick
	# it was due would be a real bug.
	if _held >= _capture_hold or is_equal_approx(_held, _capture_hold):
		_held = _capture_hold
		_winner = _capturing_team


## Team currently holding every goal in one connected group, or NO_TEAM.
func capturing_team() -> int:
	return _capturing_team


## How far through capture_hold the current capture is, 0..1. Drives the goal
## flag's radial progress ring (spec 2.3) and the HUD.
func capture_progress() -> float:
	if _winner != NO_TEAM:
		return 1.0
	if _capture_hold <= 0.0:
		return 1.0 if _capturing_team != NO_TEAM else 0.0
	return clampf(_held / _capture_hold, 0.0, 1.0)


## The winning team, or NO_TEAM until a capture completes. Latches: once a
## team wins, this keeps returning it until reset().
func winner() -> int:
	return _winner


## Replaces the goal flag layout, e.g. when a match starts.
func set_goal_positions(positions: PackedVector2Array) -> void:
	_goal_positions = positions
	_clear_capture()


## Clears the capture timer and the latched winner.
func reset() -> void:
	_clear_capture()
	_winner = NO_TEAM


func _clear_capture() -> void:
	_capturing_group = TerritoryGroups.NO_GROUP
	_capturing_team = NO_TEAM
	_held = 0.0


## The group index shared by every goal flag, or NO_GROUP when they disagree,
## when any goal is unowned or contested, or when there are no goals at all.
##
## Comparing group indices rather than teams is the whole point (spec 2.3, "one
## connected territory"): two towers of the same team holding a goal each are
## two groups, and must not win.
func _group_holding_every_goal(raster: TerritoryRaster) -> int:
	var count: int = _goal_positions.size()
	if count == 0:
		return TerritoryGroups.NO_GROUP

	var group: int = raster.group_at_point(_goal_positions[0])
	# Catches NO_GROUP and CONTESTED, which are both negative.
	if group < 0:
		return TerritoryGroups.NO_GROUP
	for i: int in range(1, count):
		if raster.group_at_point(_goal_positions[i]) != group:
			return TerritoryGroups.NO_GROUP
	return group


func _team_at(raster: TerritoryRaster, point: Vector2) -> int:
	var cell: Vector2i = raster.grid().world_to_cell(point)
	return raster.team_at(cell.x, cell.y)
