extends GutTest
## Spec 1.5's contested zones and holes, on the authoritative cell grid
## (spec 2.5).
##
## "Areas where two or more territories from different teams overlap are
## contested. Contested cells become holes after hole_delay = 0.75 s."
## "TEMPORARY (default): a cell stays a hole while contested and closes 2 s
## after the overlap ends. PERMANENT: holes never close."
## "Teams: territories of teammates never create holes between them."

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const TEMPORARY: bool = false
const PERMANENT: bool = true

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _grid: CellGrid = null
var _solver: TerritorySolver = null
var _raster: TerritoryRaster = null


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, CELL)
	_solver = TerritorySolver.new(_tuning)
	_raster = TerritoryRaster.new(_grid, _tuning)


func _home(x: float, z: float, team: int, slot: int = -1) -> InfluenceCircle:
	return InfluenceCircle.new(
		Vector2(x, z), _tuning.home_radius, team, slot if slot >= 0 else team, true, -1
	)


func _block(x: float, z: float, radius: float, team: int) -> InfluenceCircle:
	return InfluenceCircle.new(Vector2(x, z), radius, team, team, false, 0)


## Solves and rasterizes one frame.
func _step(circles: Array[InfluenceCircle], delta: float, permanent: bool = TEMPORARY) -> void:
	var groups: TerritoryGroups = _solver.solve(circles)
	_raster.fill_ownership(circles, groups, true)
	_raster.adopt_fill(_raster, delta, true, permanent)


func _cell_of(point: Vector2) -> Vector2i:
	return _grid.world_to_cell(point)


func _team_at_point(point: Vector2) -> int:
	var cell: Vector2i = _cell_of(point)
	return _raster.team_at(cell.x, cell.y)


## -- Ownership fill ----------------------------------------------------------

func test_a_home_circle_owns_the_cells_under_it() -> void:
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_step(circles, 0.1)
	assert_eq(_team_at_point(Vector2(0.5, 0.5)), 0, "The cell at the centre is owned.")
	assert_eq(_team_at_point(Vector2(3.5, 0.5)), 0, "Well inside home_radius = 6.")
	assert_eq(_team_at_point(Vector2(15.5, 0.5)), -1, "Far outside it is unowned.")
	assert_eq(_raster.group_at_point(Vector2(0.5, 0.5)), 0)


func test_cells_off_the_disk_are_never_owned() -> void:
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0), _block(0.0, 0.0, 40.0, 0)]
	_step(circles, 0.1)
	assert_eq(_raster.group_at_point(Vector2(-19.5, -19.5)), TerritoryGroups.NO_GROUP,
		"The corner of the bounding square is off the disk.")
	assert_eq(_raster.team_at(0, 0), -1)


func test_a_cut_off_tower_loses_its_cells() -> void:
	## home(-10, r6) -- A(-2, r3) -- B(4, r3). B's own cells are out of reach of
	## everything except A.
	var probe: Vector2 = Vector2(4.5, 0.5)
	var linked: Array[InfluenceCircle] = [
		_home(-10.0, 0.0, 0), _block(-2.0, 0.0, 3.0, 0), _block(4.0, 0.0, 3.0, 0)
	]
	_step(linked, 0.1)
	assert_eq(_team_at_point(probe), 0, "Connected through A, B's cells count.")

	var cut: Array[InfluenceCircle] = [linked[0], linked[2]]
	_step(cut, 0.1)
	assert_eq(_team_at_point(probe), -1,
		"Spec 1.5: if a tower is cut off, its influence is gone.")


## -- Teams -------------------------------------------------------------------

func test_teammates_overlap_without_contesting_or_holing() -> void:
	var circles: Array[InfluenceCircle] = [
		_home(-3.0, 0.0, 0, 0), _home(3.0, 0.0, 0, 1)
	]
	var groups: TerritoryGroups = _solver.solve(circles)
	assert_eq(groups.group_count(), 1, "Teammates merge into one group.")

	## Run well past hole_delay: a hole must never appear between teammates.
	for i: int in range(40):
		_raster.fill_ownership(circles, groups, true)
		_raster.adopt_fill(_raster, 0.1, true, TEMPORARY)
		assert_eq(_raster.holes_opened().size(), 0)

	var overlap: Vector2 = Vector2(0.5, 0.5)
	var cell: Vector2i = _cell_of(overlap)
	assert_false(_raster.is_contested(cell.x, cell.y))
	assert_false(_raster.is_hole(cell.x, cell.y))
	assert_eq(_raster.team_at(cell.x, cell.y), 0)


func test_different_teams_overlapping_contest_the_cell() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	_step(circles, 0.1)

	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	assert_true(_raster.is_contested(cell.x, cell.y), "Both teams reach this cell.")
	assert_eq(_raster.team_at(cell.x, cell.y), -1, "Neither team owns a contested cell.")
	assert_eq(_raster.group_at(cell.x, cell.y), TerritoryGroups.CONTESTED)

	var mine: Vector2i = _cell_of(Vector2(-8.5, 0.5))
	assert_eq(_raster.team_at(mine.x, mine.y), 0, "Cells only I reach are still mine.")


## -- hole_delay --------------------------------------------------------------

func test_a_contested_cell_becomes_a_hole_past_hole_delay() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	var index: int = _grid.cell_index(cell.x, cell.y)

	var announcements: int = 0
	for i: int in range(76):
		_step(circles, 0.01)
		announcements += Array(_raster.holes_opened()).count(index)

	assert_true(_raster.is_hole(cell.x, cell.y), "Past 0.75 s the cell is a hole.")
	assert_true(_raster.is_hole_index(index))
	assert_eq(announcements, 1, "A cell is announced in holes_opened() exactly once.")


## -- hole_mode ---------------------------------------------------------------

func _open_a_hole(permanent: bool) -> Vector2i:
	var contested: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	for i: int in range(10):
		_step(contested, 0.1, permanent)
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	assert_true(_raster.is_hole(cell.x, cell.y), "Setup: the hole must be open.")
	return cell


func test_temporary_holes_close_after_hole_close_delay() -> void:
	var cell: Vector2i = _open_a_hole(TEMPORARY)
	var index: int = _grid.cell_index(cell.x, cell.y)
	var alone: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0)]

	## 19 x 0.1 = 1.9 s uncontested, just under hole_close_delay = 2.0.
	for i: int in range(19):
		_step(alone, 0.1, TEMPORARY)
	assert_true(_raster.is_hole(cell.x, cell.y), "Still a hole at 1.9 s.")
	assert_eq(_raster.holes_closed().size(), 0)

	## 2.1 s.
	var announcements: int = 0
	for i: int in range(2):
		_step(alone, 0.1, TEMPORARY)
		announcements += Array(_raster.holes_closed()).count(index)
	assert_false(_raster.is_hole(cell.x, cell.y), "Closed at 2.1 s.")
	assert_eq(announcements, 1, "Announced in holes_closed() exactly once.")


func test_permanent_holes_never_close() -> void:
	var cell: Vector2i = _open_a_hole(PERMANENT)
	var alone: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0)]
	for i: int in range(100):
		_step(alone, 0.1, PERMANENT)
		assert_eq(_raster.holes_closed().size(), 0,
			"Under PERMANENT the board only ever erodes.")
	assert_true(_raster.is_hole(cell.x, cell.y))


## -- goal zones never hole ---------------------------------------------------

func _goal_zone_hole_check(permanent: bool) -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.5, 0.5)]), 1.0)
	var inside: Vector2i = _cell_of(Vector2(0.5, 0.5))
	var outside: Vector2i = _cell_of(Vector2(0.5, 3.5))
	assert_true(_raster.is_goal_zone(inside.x, inside.y), "Setup: zone covers the cell.")
	assert_false(_raster.is_goal_zone(outside.x, outside.y), "Setup: far cell is outside.")

	for i: int in range(12):
		_step(circles, 0.1, permanent)
	# Pure timer ticks on the unchanged board take the other entry point.
	for i: int in range(12):
		_raster.advance_time(0.1, permanent)

	assert_true(_raster.is_contested(inside.x, inside.y), "The zone cell is still contested.")
	assert_false(_raster.is_hole(inside.x, inside.y), "A goal zone never becomes a hole.")
	assert_true(_raster.is_hole(outside.x, outside.y), "A contested cell outside it still opens.")


func test_a_contested_goal_zone_cell_never_holes_temporary() -> void:
	_goal_zone_hole_check(TEMPORARY)


func test_a_contested_goal_zone_cell_never_holes_permanent() -> void:
	_goal_zone_hole_check(PERMANENT)


## -- v2 fill: the argmax field -----
##
## Design note: "Areas of different players never overlap.
## Where they meet, the border is pushed by the heights of the stacks producing
## the contested area: the taller local stack gets more of the shared region,
## but not all of it, and it is the individual contesting stacks that count,
## never a global per-player value."
##
## kernel_value(c, p) = c.radius - distance(p, c.center); the owner of a point
## is the team of the anchored circle with the largest kernel value there.

## An anchoring (home) circle of an arbitrary radius, so a test can stand in
## for "a tower this tall" without going through BlockRegistry.
func _anchor(x: float, z: float, radius: float, team: int, slot: int = -1) -> InfluenceCircle:
	return InfluenceCircle.new(
		Vector2(x, z), radius, team, slot if slot >= 0 else team, true, -1
	)


## Solves and rasterizes one frame through the v2 (holes_enabled = false) path.
func _step_v2(circles: Array[InfluenceCircle], delta: float = 0.1) -> void:
	var groups: TerritoryGroups = _solver.solve(circles)
	_raster.fill_ownership(circles, groups, false)
	_raster.adopt_fill(_raster, delta, false, false)


func test_v2_two_teams_never_share_a_cell() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	_step_v2(circles)

	var contested: int = 0
	var owned: int = 0
	for index: int in _grid.in_disk_cells():
		var coords: Vector2i = _grid.cell_coords(index)
		if _raster.group_at(coords.x, coords.y) == TerritoryGroups.CONTESTED:
			contested += 1
		if _raster.team_at(coords.x, coords.y) >= 0:
			owned += 1
	assert_eq(contested, 0, "The argmax is a function: no cell is ever contested under v2.")
	assert_gt(owned, 0, "Setup: both circles do claim ground.")

	var overlap: Vector2i = _cell_of(Vector2(0.0, 0.0))
	var team: int = _raster.team_at(overlap.x, overlap.y)
	assert_true(team == 0 or team == 1, "Exactly one of the two owns the shared midpoint.")
	assert_ne(_raster.group_at(overlap.x, overlap.y), TerritoryGroups.NO_GROUP,
		"An owned cell always carries the winning circle's group.")


func test_v2_the_border_is_pushed_by_height_not_split_down_the_middle() -> void:
	## r1 = 8 at x = -5 against r2 = 4 at x = +5, so d = 10 and the kernels
	## cross at (d + r1 - r2) / 2 = 7 from circle 1, i.e. x = +2 -- pushed two
	## metres past the midpoint of the centres, but nowhere near circle 2's own
	## centre.
	var big: float = 8.0
	var small: float = 4.0
	var expected_border: float = -5.0 + (10.0 + big - small) * 0.5
	_step_v2([
		_anchor(-5.0, 0.0, big, 0), _anchor(5.0, 0.0, small, 1)
	] as Array[InfluenceCircle])

	assert_eq(_team_at_point(Vector2(0.0, 0.0)), 0,
		"The midpoint of the two centres belongs to the taller stack, not to nobody.")
	assert_eq(_team_at_point(Vector2(5.0, 0.0)), 1,
		"The shorter stack still owns the ground under itself: not all of the "
		+ "shared region goes to the taller one.")

	## Walk the row of cells through both centres and find where ownership flips.
	var border: float = INF
	var row: int = _cell_of(Vector2(0.0, 0.0)).y
	for cx: int in range(_grid.res):
		var centre: Vector2 = _grid.cell_center(cx, row)
		if centre.x < -5.0 or centre.x > 9.0:
			continue
		if _raster.team_at(cx, row) == 1:
			border = centre.x
			break
	assert_lt(absf(border - expected_border), CELL + 0.001,
		"The border sits where radius - distance ties, within one cell.")


func test_v2_individual_stacks_count_never_a_team_sum() -> void:
	## One big team-0 circle against a cluster of five small team-1 ones whose
	## radii sum to more than the big one's. The cluster must not win ground
	## none of its circles individually reaches.
	var circles: Array[InfluenceCircle] = [
		_anchor(0.0, 0.0, 10.0, 0),
		_anchor(10.0, 0.0, 2.0, 1),
		_block(8.0, 0.0, 2.0, 1),
		_block(6.0, 0.0, 2.0, 1),
		_block(6.0, 3.0, 2.0, 1),
		_block(6.0, -3.0, 2.0, 1),
	]
	var groups: TerritoryGroups = _solver.solve(circles)
	var team_one_groups: Array[int] = []
	for group: int in range(groups.group_count()):
		if groups.team_of(group) == 1:
			team_one_groups.append(group)
	assert_eq(team_one_groups.size(), 1, "Setup: the cluster is one connected group.")
	assert_eq(groups.circles_of(team_one_groups[0]).size(), 5,
		"Setup: all five team-1 circles are anchored.")

	_step_v2(circles)
	assert_eq(_team_at_point(Vector2(3.0, 0.0)), 0,
		"No team-1 circle reaches x = 3; five of them together still do not.")
	assert_eq(_team_at_point(Vector2(7.0, 0.0)), 0,
		"Even where two small circles overlap, each is compared on its own "
		+ "kernel value, so the big stack still wins.")


func test_v2_a_cut_off_tower_loses_its_area_not_just_the_win_check() -> void:
	## Mirrors tests/unit/territory/test_territory_solver.gd's cut-off case, asserting on
	## the raster's team instead of group membership: home(-10, r6) --
	## A(-2, r3) -- B(4, r7), with B the tall one, plus a rival whose circle
	## reaches B's outskirts. B does not reach home on its own (14 > 6 + 7),
	## so removing A really does cut it off.
	var home: InfluenceCircle = _home(-10.0, 0.0, 0)
	var a: InfluenceCircle = _block(-2.0, 0.0, 3.0, 0)
	var b: InfluenceCircle = _block(4.0, 0.0, 7.0, 0)
	var rival: InfluenceCircle = _home(14.0, 0.0, 1)

	_step_v2([home, a, b, rival] as Array[InfluenceCircle])
	assert_eq(_team_at_point(Vector2(4.0, 0.0)), 0,
		"Setup: connected through A, B owns its own ground.")
	assert_eq(_team_at_point(Vector2(9.0, 0.0)), 0,
		"Setup: B out-scores the rival at x = 9 (7 - 5 beats 6 - 5).")

	_step_v2([home, b, rival] as Array[InfluenceCircle])
	assert_eq(_team_at_point(Vector2(4.0, 0.0)), -1,
		"Spec 1.5: a cut-off tower's influence is gone from the field, not just "
		+ "from the win check.")
	assert_eq(_team_at_point(Vector2(9.0, 0.0)), 1,
		"And the ground it held falls to whoever else reaches it.")


func test_v2_never_opens_a_hole_or_runs_a_contest_timer() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	var cell: Vector2i = _cell_of(Vector2(0.0, 0.0))
	## Far past hole_delay and hole_close_delay.
	for i: int in range(60):
		_step_v2(circles)
		assert_eq(_raster.holes_opened().size(), 0, "No hole ever opens under v2.")
		assert_eq(_raster.holes_closed().size(), 0)
	assert_false(_raster.is_hole(cell.x, cell.y))
	assert_false(_raster.is_contested(cell.x, cell.y))
	var states: PackedByteArray = _raster.state_bytes()
	var index: int = _grid.cell_index(cell.x, cell.y)
	assert_eq(states[index] & TerritoryRaster.STATE_CONTESTED, 0)
	assert_eq(states[index] & TerritoryRaster.STATE_HOLE, 0)


## -- Goal-flag no-build zones ------------------------------------------------
##
## Design note: "Goal flags have their own area of influence in which no player
## may place a block." The zone blocks placement only, never ownership.

const ZONE_RADIUS: float = 3.0


func test_set_goal_zones_marks_exactly_the_cells_within_the_radius() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.0, 0.0)]), ZONE_RADIUS)

	var marked: int = 0
	for index: int in _grid.in_disk_cells():
		var coords: Vector2i = _grid.cell_coords(index)
		var distance: float = _grid.cell_center(coords.x, coords.y).length()
		var inside: bool = distance <= ZONE_RADIUS
		assert_eq(_raster.is_goal_zone(coords.x, coords.y), inside,
			"Cell %d sits %.2f m from the flag" % [index, distance])
		if inside:
			marked += 1
	assert_gt(marked, 0, "Setup: the zone covers some cells.")


## -- Forced holes ------------------------------------------------------------
##
## force_hole_cell() opens a cell independent of contest overlap, seeding the
## same _hole/_contested_time/_idle_time bookkeeping a natural hole uses, so
## the unmodified _advance_timers() (run from adopt_fill(), same as every other
## test in this file) is what actually closes it hole_open_s later.

const HOLE_OPEN_S: float = 2.0


func test_force_hole_cell_refuses_a_goal_zone_cell() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.5, 0.5)]), 1.0)
	var inside: Vector2i = _cell_of(Vector2(0.5, 0.5))
	var outside: Vector2i = _cell_of(Vector2(0.5, 5.5))

	_raster.force_hole_cell(inside.x, inside.y, HOLE_OPEN_S, PERMANENT)
	_raster.force_hole_cell(outside.x, outside.y, HOLE_OPEN_S, PERMANENT)

	assert_false(_raster.is_hole(inside.x, inside.y), "A goal zone is never punched through.")
	assert_true(_raster.is_hole(outside.x, outside.y), "A cell outside it still opens.")
	assert_eq(_raster.holes_opened().size(), 1)


func test_force_hole_cell_opens_immediately() -> void:
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	assert_false(_raster.is_hole(cell.x, cell.y), "Setup: not a hole yet.")

	_raster.force_hole_cell(cell.x, cell.y, HOLE_OPEN_S, TEMPORARY)

	assert_true(_raster.is_hole(cell.x, cell.y))
	assert_has(Array(_raster.holes_opened()), _grid.cell_index(cell.x, cell.y))


## -- A punched hole inside a single team's own circle -------------------------
##
## Unlike the tests above, force_hole_cell() here lands on a cell a single
## uncontested team already owns (a natural hole never does: it only opens on
## a CONTESTED cell, _team_ids == -1). _stamp() keeps re-stamping that team
## onto the cell every solve (unmodified, per this package's own "do not
## touch fill_ownership()/_fill_stamp()/_argmax()" contract) so _advance_timers()
## can still tell a still-contested cell apart from an idle one; team_at() /
## team_share() mask it back to unowned at the read side instead.

func test_a_punched_hole_inside_a_single_teams_circle_reads_as_unowned() -> void:
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_step(circles, 0.1)
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	assert_eq(_raster.team_at(cell.x, cell.y), 0,
		"Setup: uncontested, owned by team 0 before the punch.")

	var total: int = _grid.in_disk_cell_count()
	var share_before: float = _raster.team_share(0)
	_raster.force_hole_cell(cell.x, cell.y, HOLE_OPEN_S, TEMPORARY)

	assert_eq(_raster.team_at(cell.x, cell.y), -1,
		"A punched hole reads as unowned even though team 0's circle still covers it.")
	assert_almost_eq(share_before - _raster.team_share(0), 1.0 / float(total), 0.0001,
		"team_share(0) drops by exactly the one punched cell, not the whole circle.")

	## The circle keeps covering the cell every solve afterwards too --
	## _stamp() has no idea the cell is a hole (see the class DECISION) -- so
	## this is not a one-tick fluke.
	for i: int in range(5):
		_step(circles, 0.1, TEMPORARY)
		assert_eq(_raster.team_at(cell.x, cell.y), -1,
			"Still unowned after re-solving with the same circle in place.")

	var owners: PackedByteArray = _raster.owner_bytes()
	assert_eq(owners[_grid.cell_index(cell.x, cell.y)], 0,
		"owner_bytes() draws it unowned too -- no team tint over a hole.")


## -- tally_owned_cells -------------------------------------------------------
##
## The one-pass, by-index vote WinChecker.claim_at() reads over its cached claim
## cells. It must count exactly the cells the per-cell coordinate readers count
## (group_at() >= 0 and team_at() >= 0, so a punched hole is not counted), key
## them team * stride + group, and ignore off-grid indices.

const TALLY_STRIDE: int = 1000000


func _all_indices() -> PackedInt32Array:
	var indices: PackedInt32Array = PackedInt32Array()
	for index: int in range(_grid.cell_count()):
		indices.append(index)
	return indices


## The per-cell oracle: the coordinate readers, one call each per cell.
func _reference_tally(indices: PackedInt32Array, stride: int) -> Dictionary:
	var out: Dictionary = {}
	for index: int in indices:
		if index < 0 or index >= _grid.cell_count():
			continue
		var cell: Vector2i = _grid.cell_coords(index)
		var group: int = _raster.group_at(cell.x, cell.y)
		var team: int = _raster.team_at(cell.x, cell.y)
		if group < 0 or team < 0:
			continue
		var key: int = team * stride + group
		out[key] = int(out.get(key, 0)) + 1
	return out


func _assert_tally_matches(indices: PackedInt32Array, label: String, stride: int = TALLY_STRIDE) -> Dictionary:
	var got: Dictionary[int, int] = _raster.tally_owned_cells(indices, stride)
	var want: Dictionary = _reference_tally(indices, stride)
	assert_eq(got.size(), want.size(), label + ": same (team, group) keys")
	for key: int in want:
		assert_eq(got.get(key, -1), want[key], "%s: count for key %d" % [label, key])
	return got


func _tally_total(tally: Dictionary) -> int:
	var total: int = 0
	for key: int in tally:
		total += int(tally[key])
	return total


func test_tally_matches_the_coordinate_readers_after_a_solve() -> void:
	var circles: Array[InfluenceCircle] = [_home(-8.0, 0.0, 0), _home(8.0, 0.0, 1), _block(-4.0, 3.0, 3.0, 0)]
	_step(circles, 0.1, TEMPORARY)
	var tally: Dictionary = _assert_tally_matches(_all_indices(), "whole grid")
	assert_gt(tally.size(), 1, "Setup: more than one (team, group) key.")
	var owned: int = 0
	for cy: int in range(_grid.res):
		for cx: int in range(_grid.res):
			if _raster.team_at(cx, cy) >= 0 and _raster.group_at(cx, cy) >= 0:
				owned += 1
	assert_gt(owned, 0, "Setup: something is owned.")
	assert_eq(_tally_total(tally), owned, "The tally counts every owned cell once.")


func test_tally_does_not_count_a_punched_hole_inside_a_teams_own_circle() -> void:
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_step(circles, 0.1)
	var before: Dictionary = _assert_tally_matches(_all_indices(), "before the punch")
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	_raster.force_hole_cell(cell.x, cell.y, HOLE_OPEN_S, TEMPORARY)
	var after: Dictionary = _assert_tally_matches(_all_indices(), "after the punch")
	assert_eq(_tally_total(after), _tally_total(before) - 1,
		"Exactly the punched cell leaves the tally: team_at() reads a hole as unowned.")


func test_tally_ignores_indices_off_the_grid() -> void:
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_step(circles, 0.1)
	var centre: Vector2i = _cell_of(Vector2.ZERO)
	var valid: PackedInt32Array = PackedInt32Array([_grid.cell_index(centre.x, centre.y), _grid.cell_index(centre.x + 1, centre.y)])
	var with_junk: PackedInt32Array = PackedInt32Array([-7, -1])
	with_junk.append_array(valid)
	with_junk.append_array(PackedInt32Array([_grid.cell_count(), _grid.cell_count() + 99, 2147483647]))
	var clean: Dictionary[int, int] = _raster.tally_owned_cells(valid, TALLY_STRIDE)
	var junk: Dictionary[int, int] = _raster.tally_owned_cells(with_junk, TALLY_STRIDE)
	assert_eq(_tally_total(clean), 2, "Setup: both valid cells are owned.")
	assert_eq(_tally_total(junk), 2, "Off-grid indices vote for nobody, like group_at()'s off-grid answer.")
	assert_eq(junk.size(), clean.size())


func test_tally_counts_interleaved_teams_and_repeated_indices_like_the_oracle() -> void:
	# Alternating owners break the run-length counting every cell and bring a key
	# back after another one; duplicates count once per occurrence.
	var circles: Array[InfluenceCircle] = [_home(-8.0, 0.0, 0), _home(8.0, 0.0, 1)]
	_step(circles, 0.1, TEMPORARY)
	var left: Vector2i = _cell_of(Vector2(-8.0, 0.0))
	var right: Vector2i = _cell_of(Vector2(8.0, 0.0))
	var indices: PackedInt32Array = PackedInt32Array()
	for step: int in range(6):
		indices.append(_grid.cell_index(left.x + step, left.y))
		indices.append(_grid.cell_index(right.x - step, right.y))
	indices.append(_grid.cell_index(left.x, left.y))
	indices.append(_grid.cell_index(left.x, left.y))
	var tally: Dictionary = _assert_tally_matches(indices, "interleaved")
	assert_eq(tally.size(), 2, "Setup: both teams vote.")
	assert_eq(_tally_total(tally), indices.size(), "Setup: every listed cell is owned, duplicates included.")
