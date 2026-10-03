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
## claim_at() tallies cells under team * GROUP_KEY_STRIDE + group; groups are indices
## into one solve's circle array, far below this.
const GROUP_KEY_STRIDE: int = 1000000

var _goal_positions: PackedVector2Array = PackedVector2Array()
var _capture_hold: float = 3.0
## Bontago-1pi.18.1: 0 = sample the flag's own cell (the rule). > 0 = decide each
## goal over the cells within this radius (see claim_at).
var _claim_radius: float = 0.0

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


func set_claim_radius(radius: float) -> void:
	_claim_radius = maxf(radius, 0.0)


func capture_hold() -> float:
	return _capture_hold


## Advances the capture timer by `delta` seconds against one raster. Called
## once per territory solve (spec 3.7: "Win check: runs every territory
## update"), so delta is 1 / TerritoryTuning.solve_hz.
func update(raster: TerritoryRaster, delta: float) -> void:
	if _winner != NO_TEAM:
		return

	# x = the group every goal shares (NO_GROUP when they disagree), y = the team
	# claiming goal 0 -- read from the same claim_at() as the group, not a second one.
	var claim: Vector2i = _claim_holding_every_goal(raster)
	var group: int = claim.x
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
	var team: int = claim.y
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


## The group index shared by every goal flag (x), or NO_GROUP when they disagree,
## when any goal is unowned or contested, or when there are no goals at all; and
## the team claiming the first goal (y, NO_TEAM alongside NO_GROUP).
##
## Comparing group indices rather than teams is the whole point (spec 2.3, "one
## connected territory"): two towers of the same team holding a goal each are
## two groups, and must not win.
##
## Bontago-1pi.18.11: goal 0 is evaluated once and its team returned with its
## group, so update() no longer repeats the (radius-sized) claim_at() for it.
func _claim_holding_every_goal(raster: TerritoryRaster) -> Vector2i:
	var none: Vector2i = Vector2i(TerritoryGroups.NO_GROUP, NO_TEAM)
	var count: int = _goal_positions.size()
	if count == 0:
		return none

	var first: Vector2i = claim_at(raster, _goal_positions[0], _claim_radius)
	# Catches NO_GROUP and CONTESTED, which are both negative.
	if first.x < 0:
		return none
	for i: int in range(1, count):
		if claim_at(raster, _goal_positions[i], _claim_radius).x != first.x:
			return none
	return first


## The per-goal test of spec 2.3, shared with other objectives (Capture the
## Flag scores each beacon with it): the team holding the goal at `point`, or
## NO_TEAM. A goal is held only when its cell is in a real solver group (the
## solver only forms groups anchored to a living home, so this is the "unbroken
## path to a living allied home" rule) and is owned in the final raster;
## unowned, contested, hole and off-disk reads hold for nobody.
static func goal_holder(raster: TerritoryRaster, point: Vector2, claim_radius: float = 0.0) -> int:
	var claim: Vector2i = claim_at(raster, point, claim_radius)
	return NO_TEAM if claim.x < 0 else claim.y


## Who claims the goal at `point`: x = group index (negative = none), y = team
## (NO_TEAM when none). claim_radius <= 0 reads the single flag cell, exactly the
## original rule.
##
## DECISION (Bontago-1pi.18.1, QoL "bigger claim radius"): with a radius, every
## cell whose centre lies within it votes if it is in a real group and owned;
## the team owning the most such cells claims the goal (group = that team's most
## common group, lowest index on a tie). A tie between teams, or no owned cell,
## claims nothing -- the same as contested/unowned today.
static func claim_at(raster: TerritoryRaster, point: Vector2, claim_radius: float) -> Vector2i:
	var grid: CellGrid = raster.grid()
	if claim_radius <= 0.0:
		var center: Vector2i = grid.world_to_cell(point)
		return Vector2i(raster.group_at(center.x, center.y), raster.team_at(center.x, center.y))
	# Bontago-1pi.18.11: which cells are in range depends only on the grid, the
	# point and the radius, so their indices are cached (ClaimCells) and each solve
	# only tallies the raster over them in one pass, with exactly the votes
	# group_at()/team_at() would give cell by cell (see TerritoryRaster.
	# tally_owned_cells). One tally per (team, group); the team totals are summed
	# from it below.
	var indices: PackedInt32Array = ClaimCells.indices_for(grid, point, claim_radius)
	var group_cells: Dictionary[int, int] = raster.tally_owned_cells(indices, GROUP_KEY_STRIDE)
	var team_cells: Dictionary = {}
	for key: int in group_cells:
		var key_team: int = key / GROUP_KEY_STRIDE
		team_cells[key_team] = int(team_cells.get(key_team, 0)) + int(group_cells[key])
	var best_team: int = NO_TEAM
	var best_count: int = 0
	var tied: bool = false
	for team: int in team_cells:
		var count: int = team_cells[team]
		if count > best_count:
			best_team = team
			best_count = count
			tied = false
		elif count == best_count:
			tied = true
	if best_team == NO_TEAM or tied:
		return Vector2i(TerritoryGroups.NO_GROUP, NO_TEAM)
	var best_group: int = TerritoryGroups.NO_GROUP
	var best_group_count: int = 0
	for key: int in group_cells:
		if key / GROUP_KEY_STRIDE != best_team:
			continue
		var group_count: int = group_cells[key]
		var group_id: int = key % GROUP_KEY_STRIDE
		if group_count > best_group_count or (group_count == best_group_count and group_id < best_group):
			best_group = group_id
			best_group_count = group_count
	return Vector2i(best_group, best_team)
