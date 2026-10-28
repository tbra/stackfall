class_name WinChecker
extends RefCounted
## The win condition (spec 1.5, 2.5).
##
## Spec 1.5: "A player or team wins when one connected territory contains
## every goal flag continuously for capture_hold = 3 s." Spec 2.5 says to
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
## 0 = sample the flag's own cell (the rule). > 0 = decide each
## goal over the cells within this radius (see claim_at).
var _claim_radius: float = 0.0

## The group every goal currently sits in, or NO_GROUP. Held across updates so
## that a capture passing from one group to another restarts the hold instead
## of inheriting its predecessor's progress.
var _capturing_group: int = TerritoryGroups.NO_GROUP
var _capturing_team: int = NO_TEAM
var _held: float = 0.0
var _winner: int = NO_TEAM
## Sudden death (Classic): per-goal latched owner, NO_TEAM = unclaimed. See begin_sudden_death().
var _sudden_death: bool = false
var _latched: PackedInt32Array = PackedInt32Array()


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
## once per territory solve (spec 2.4: "Win check: runs every territory
## update"), so delta is 1 / TerritoryTuning.solve_hz.
func update(raster: TerritoryRaster, delta: float) -> void:
	if _winner != NO_TEAM:
		return
	if _sudden_death:
		_latch_goals(raster)
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
	return NO_TEAM if _sudden_death else _capturing_team


## How far through capture_hold the current capture is, 0..1. Drives the goal
## flag's radial progress ring (spec 1.5) and the HUD.
func capture_progress() -> float:
	if _sudden_death:
		return 0.0
	if _winner != NO_TEAM:
		return 1.0
	if _capture_hold <= 0.0:
		return 1.0 if _capturing_team != NO_TEAM else 0.0
	return clampf(_held / _capture_hold, 0.0, 1.0)


## The winning team, or NO_TEAM until a capture completes. Latches: once a
## team wins, this keeps returning it until reset().
func winner() -> int:
	return _winner


## Starts sudden death: the hold timer is dropped and every goal is claimed instantly,
## staying with its last claimer. Latches the goals held right now (so a single goal
## held at this moment wins at once, `winner()` is set here).
func begin_sudden_death(raster: TerritoryRaster) -> void:
	_sudden_death = true
	_clear_capture()
	_latched.resize(_goal_positions.size())
	_latched.fill(NO_TEAM)
	_latch_goals(raster)


func is_sudden_death() -> bool:
	return _sudden_death


## The team that latched goal `goal_index`, or NO_TEAM.
func latched_team(goal_index: int) -> int:
	return _latched[goal_index] if goal_index >= 0 and goal_index < _latched.size() else NO_TEAM


## Releases latches held by teams not in `alive_teams` (an eliminated team cannot win
## and does not block the others, who reclaim the goal by holding it).
func release_teams_not_in(alive_teams: PackedInt32Array) -> void:
	for i: int in range(_latched.size()):
		if _latched[i] != NO_TEAM and not alive_teams.has(_latched[i]):
			_latched[i] = NO_TEAM


## Client mirror of the latches, display only: never touches the winner.
func set_latched(teams: PackedInt32Array) -> void:
	_latched = teams.duplicate()


## Clears the capture timer and the latched winner.
func reset() -> void:
	_clear_capture()
	_winner = NO_TEAM
	_sudden_death = false
	_latched = PackedInt32Array()


## Sudden-death step: a goal held now (goal_holder: a contested, hole or unowned cell
## holds for nobody) is latched to its holder, replacing any earlier owner; one team
## latching every goal wins. The one-connected-territory rule does not apply here.
func _latch_goals(raster: TerritoryRaster) -> void:
	var count: int = _goal_positions.size()
	if count == 0:
		return
	for i: int in range(count):
		var holder: int = goal_holder(raster, _goal_positions[i], _claim_radius)
		if holder != NO_TEAM:
			_latched[i] = holder
	var owner_team: int = _latched[0]
	for i: int in range(1, count):
		if _latched[i] != owner_team:
			return
	_winner = owner_team


func _clear_capture() -> void:
	_capturing_group = TerritoryGroups.NO_GROUP
	_capturing_team = NO_TEAM
	_held = 0.0


## The group index shared by every goal flag (x), or NO_GROUP when they disagree,
## when any goal is unowned or contested, or when there are no goals at all; and
## the team claiming the first goal (y, NO_TEAM alongside NO_GROUP).
##
## Comparing group indices rather than teams is the whole point (spec 1.5, "one
## connected territory"): two towers of the same team holding a goal each are
## two groups, and must not win.
##
## goal 0 is evaluated once and its team returned with its
## group, so update() does not repeat the (radius-sized) claim_at() for it.
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


## The per-goal test of spec 1.5, shared with other objectives (Capture the
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
## DECISION (QoL "bigger claim radius"): with a radius, every
## cell whose centre lies within it votes if it is in a real group and owned;
## the team owning the most such cells claims the goal (group = that team's most
## common group, lowest index on a tie). A tie between teams, or no owned cell,
## claims nothing -- the same as contested/unowned today.
static func claim_at(raster: TerritoryRaster, point: Vector2, claim_radius: float) -> Vector2i:
	var grid: CellGrid = raster.grid()
	if claim_radius <= 0.0:
		var center: Vector2i = grid.world_to_cell(point)
		return Vector2i(raster.group_at(center.x, center.y), raster.team_at(center.x, center.y))
	# which cells are in range depends only on the grid, the
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
