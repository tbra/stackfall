extends GutTest
## Spec 2.2's contested zones and holes, on the authoritative cell grid
## (spec 3.3, docs/M2_PLAN.md "Raster resolution").
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

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
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
	_raster.update(circles, groups, delta, true, permanent)


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


func test_a_point_beyond_the_grid_reads_as_no_group() -> void:
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_step(circles, 0.1)
	assert_eq(_raster.group_at_point(Vector2(500.0, 0.0)), TerritoryGroups.NO_GROUP)
	assert_eq(_raster.team_at(-1, 0), -1)
	assert_eq(_raster.team_at(9999, 0), -1)


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
		"Spec 2.2: if a tower is cut off, its influence is gone.")


## -- Teams -------------------------------------------------------------------

func test_teammates_overlap_without_contesting_or_holing() -> void:
	var circles: Array[InfluenceCircle] = [
		_home(-3.0, 0.0, 0, 0), _home(3.0, 0.0, 0, 1)
	]
	var groups: TerritoryGroups = _solver.solve(circles)
	assert_eq(groups.group_count(), 1, "Teammates merge into one group.")

	## Run well past hole_delay: a hole must never appear between teammates.
	for i: int in range(40):
		_raster.update(circles, groups, 0.1, true, TEMPORARY)
		assert_eq(_raster.holes_opened().size(), 0)

	var overlap: Vector2 = Vector2(0.5, 0.5)
	var cell: Vector2i = _cell_of(overlap)
	assert_false(_raster.is_contested(cell.x, cell.y))
	assert_false(_raster.is_hole(cell.x, cell.y))
	assert_eq(_raster.team_at(cell.x, cell.y), 0)
	assert_almost_eq(_raster.contested_time(cell.x, cell.y), 0.0, 0.0001)


func test_different_teams_overlapping_contest_the_cell() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	_step(circles, 0.1)

	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	assert_true(_raster.is_contested(cell.x, cell.y), "Both teams reach this cell.")
	assert_eq(_raster.team_at(cell.x, cell.y), -1, "Neither team owns a contested cell.")
	assert_eq(_raster.group_at(cell.x, cell.y), TerritoryGroups.CONTESTED)

	var mine: Vector2i = _cell_of(Vector2(-8.5, 0.5))
	assert_eq(_raster.team_at(mine.x, mine.y), 0, "Cells only I reach are still mine.")


func test_team_share_counts_owned_cells_and_excludes_contested() -> void:
	var alone: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0)]
	_step(alone, 0.1)
	var solo_share: float = _raster.team_share(0)
	assert_gt(solo_share, 0.0)
	assert_lt(solo_share, 1.0)

	_raster.reset()
	var contested: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	_step(contested, 0.1)
	assert_lt(_raster.team_share(0), solo_share,
		"The contested overlap is subtracted from my share, not given to anyone.")
	assert_eq(_raster.team_share(6), 0.0, "A team with no circles owns nothing.")


func test_team_share_is_a_fraction_of_the_in_disk_cells() -> void:
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0), _block(0.0, 0.0, 100.0, 0)]
	_step(circles, 0.1)
	assert_almost_eq(_raster.team_share(0), 1.0, 0.0001,
		"A circle covering the whole disk owns all of it, corners excluded.")


## -- hole_delay --------------------------------------------------------------

func test_a_contested_cell_is_not_a_hole_before_hole_delay() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	## 74 x 0.01 = 0.74 s, just under hole_delay = 0.75.
	for i: int in range(74):
		_step(circles, 0.01)
	assert_almost_eq(_raster.contested_time(cell.x, cell.y), 0.74, 0.005)
	assert_false(_raster.is_hole(cell.x, cell.y), "0.74 s of contest is not yet a hole.")
	assert_eq(_raster.holes_opened().size(), 0)


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


func test_contested_time_is_clamped_to_hole_delay() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	for i: int in range(100):
		_step(circles, 0.1)
	assert_almost_eq(_raster.contested_time(cell.x, cell.y), _tuning.hole_delay, 0.0001)


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


func test_a_hole_stays_open_while_the_overlap_lasts() -> void:
	var cell: Vector2i = _open_a_hole(TEMPORARY)
	var contested: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	for i: int in range(60):
		_step(contested, 0.1, TEMPORARY)
	assert_true(_raster.is_hole(cell.x, cell.y),
		"Spec 2.2: a cell stays a hole while contested.")


## -- Shader bytes ------------------------------------------------------------

func test_owner_bytes_encode_team_plus_one() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	_step(circles, 0.1)
	var bytes: PackedByteArray = _raster.owner_bytes()
	assert_eq(bytes.size(), _grid.cell_count(), "One byte per cell.")

	# Both sample points sit well inside their owner's 6 m home circle rather
	# than near its rim, so which cell they land in does not depend on where
	# CellGrid's cell centres fall.
	var mine: int = _grid.cell_index(_cell_of(Vector2(-6.0, 0.0)).x, _cell_of(Vector2(-6.0, 0.0)).y)
	assert_eq(bytes[mine], 1, "team 0 encodes as 1.")
	var theirs: Vector2i = _cell_of(Vector2(6.0, 0.0))
	assert_eq(bytes[_grid.cell_index(theirs.x, theirs.y)], 2, "team 1 encodes as 2.")
	assert_eq(bytes[0], 0, "Unowned, off-disk corner encodes as 0.")


func test_state_bytes_flag_contested_and_holes() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	var index: int = _grid.cell_index(cell.x, cell.y)

	_step(circles, 0.1)
	var early: PackedByteArray = _raster.state_bytes()
	assert_eq(early.size(), _grid.cell_count())
	assert_eq(early[index] & TerritoryRaster.STATE_CONTESTED, TerritoryRaster.STATE_CONTESTED)
	assert_eq(early[index] & TerritoryRaster.STATE_HOLE, 0, "Not a hole yet.")

	for i: int in range(10):
		_step(circles, 0.1)
	var late: PackedByteArray = _raster.state_bytes()
	assert_eq(late[index] & TerritoryRaster.STATE_HOLE, TerritoryRaster.STATE_HOLE)
	assert_eq(late[0], 0, "An off-disk cell is neither contested nor holed.")


## -- Lifecycle ---------------------------------------------------------------

func test_reset_clears_ownership_holes_and_timers() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	for i: int in range(10):
		_step(circles, 0.1)
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	assert_true(_raster.is_hole(cell.x, cell.y), "Setup.")

	_raster.reset()
	assert_false(_raster.is_hole(cell.x, cell.y))
	assert_almost_eq(_raster.contested_time(cell.x, cell.y), 0.0, 0.0001)
	assert_eq(_raster.team_at(cell.x, cell.y), -1)
	assert_eq(_raster.group_at(cell.x, cell.y), TerritoryGroups.NO_GROUP)
	assert_eq(_raster.team_share(0), 0.0)
	assert_eq(_raster.holes_opened().size(), 0)
	assert_eq(_raster.holes_closed().size(), 0)


func test_the_opened_and_closed_lists_only_describe_the_last_update() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	var announced_over_the_whole_run: int = 0
	for i: int in range(10):
		_step(circles, 0.1)
		announced_over_the_whole_run += _raster.holes_opened().size()
	assert_gt(announced_over_the_whole_run, 0, "Setup: holes did open along the way.")

	_step(circles, 0.1)
	assert_eq(_raster.holes_opened().size(), 0,
		"Nothing new opened this tick, so the list is empty again — the lists "
		+ "are a per-update diff, not a running total.")


func test_an_empty_solve_leaves_the_disk_unowned() -> void:
	var circles: Array[InfluenceCircle] = []
	_step(circles, 0.1)
	assert_eq(_raster.team_share(0), 0.0)
	assert_eq(_raster.group_at_point(Vector2.ZERO), TerritoryGroups.NO_GROUP)


## -- v2 fill: the argmax field (docs/TERRITORY_V2_PLAN.md, "The formula") -----
##
## Owner clarifications 2026-09-20: "Areas of different players never overlap.
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
	_raster.update(circles, groups, delta, false, false)


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


func test_v2_ties_go_to_the_lower_team_id() -> void:
	## Perfectly symmetric: both kernels score exactly the same at x = 0.
	_step_v2([_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)] as Array[InfluenceCircle])
	assert_eq(_team_at_point(Vector2(0.0, 0.0)), 0,
		"A dead heat is broken by the lower team id, never left contested.")


func test_v2_a_symmetric_border_goes_to_one_team_all_the_way_down() -> void:
	## Two identical homes either side of x = 0: every cell of the x = 0 column
	## is an exact tie, so the whole seam must fall to team 0. If the best
	## score is kept at lower precision than it is computed at, half of these
	## cells round the other way and the seam comes out speckled.
	_step_v2([_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)] as Array[InfluenceCircle])
	var column: int = _cell_of(Vector2(0.0, 0.0)).x
	var seam: int = 0
	for cy: int in range(_grid.res):
		if _raster.team_at(column, cy) < 0:
			continue
		seam += 1
		assert_eq(_raster.team_at(column, cy), 0,
			"Cell (%d, %d) on the tie column" % [column, cy])
	assert_gt(seam, 4, "Setup: the seam is several cells long.")


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
	assert_eq(groups.groups_of_team(1).size(), 1, "Setup: the cluster is one connected group.")
	assert_eq(groups.circles_of(groups.groups_of_team(1)[0]).size(), 5,
		"Setup: all five team-1 circles are anchored.")

	_step_v2(circles)
	assert_eq(_team_at_point(Vector2(3.0, 0.0)), 0,
		"No team-1 circle reaches x = 3; five of them together still do not.")
	assert_eq(_team_at_point(Vector2(7.0, 0.0)), 0,
		"Even where two small circles overlap, each is compared on its own "
		+ "kernel value, so the big stack still wins.")


func test_v2_a_cut_off_tower_loses_its_area_not_just_the_win_check() -> void:
	## Mirrors tests/unit/test_territory_solver.gd's cut-off case, asserting on
	## the raster's owner instead of group membership: home(-10, r6) --
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
		"Spec 2.2: a cut-off tower's influence is gone from the field, not just "
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
	assert_almost_eq(_raster.contested_time(cell.x, cell.y), 0.0, 0.0001,
		"The contest timer never starts, so the legacy hole machinery stays asleep.")
	var states: PackedByteArray = _raster.state_bytes()
	var index: int = _grid.cell_index(cell.x, cell.y)
	assert_eq(states[index] & TerritoryRaster.STATE_CONTESTED, 0)
	assert_eq(states[index] & TerritoryRaster.STATE_HOLE, 0)


func test_v2_team_share_splits_the_shared_region_instead_of_voiding_it() -> void:
	_step_v2([_home(0.0, 0.0, 0)] as Array[InfluenceCircle])
	var solo: float = _raster.team_share(0)
	assert_gt(solo, 0.0)
	assert_lt(solo, 1.0)

	_step_v2([_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)] as Array[InfluenceCircle])
	assert_lt(_raster.team_share(0), solo,
		"The rival takes its half of the shared region, so my share shrinks...")
	assert_gt(_raster.team_share(1), 0.0, "...and turns up on their side of the border.")


func test_v2_leaves_cells_off_the_disk_unowned() -> void:
	_step_v2([_home(0.0, 0.0, 0), _block(0.0, 0.0, 100.0, 0)] as Array[InfluenceCircle])
	assert_eq(_raster.team_at(0, 0), -1, "The corner of the bounding square is off the disk.")
	assert_almost_eq(_raster.team_share(0), 1.0, 0.0001,
		"A circle covering the whole disk owns all of it, corners excluded.")


func test_v2_an_empty_solve_leaves_the_disk_unowned() -> void:
	_step_v2([] as Array[InfluenceCircle])
	assert_eq(_raster.team_share(0), 0.0)
	assert_eq(_raster.group_at_point(Vector2.ZERO), TerritoryGroups.NO_GROUP)


func test_switching_back_to_the_legacy_path_still_contests() -> void:
	## The two fills share the scratch arrays, so a v2 frame must not leave
	## anything behind that stops the legacy frame after it from contesting.
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	_step_v2(circles)
	for i: int in range(10):
		_step(circles, 0.1, TEMPORARY)
	var cell: Vector2i = _cell_of(Vector2(0.0, 0.0))
	assert_true(_raster.is_contested(cell.x, cell.y))
	assert_true(_raster.is_hole(cell.x, cell.y))


func test_the_legacy_path_is_what_update_does_by_default() -> void:
	## holes_enabled defaults to true, so a caller written before v2 keeps
	## exactly the behaviour it had.
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	var groups: TerritoryGroups = _solver.solve(circles)
	for i: int in range(10):
		_raster.update(circles, groups, 0.1)
	var cell: Vector2i = _cell_of(Vector2(0.0, 0.0))
	assert_true(_raster.is_contested(cell.x, cell.y))
	assert_true(_raster.is_hole(cell.x, cell.y))


## -- Goal-flag no-build zones ------------------------------------------------
##
## Owner clarifications 2026-09-20: "Goal flags have their own area of
## influence in which no player may place a block." Orchestrator decision
## 2026-09-20: the zone blocks placement only, never ownership.

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


func test_goal_zones_are_static_and_survive_a_solve() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.0, 0.0)]), ZONE_RADIUS)
	for i: int in range(5):
		_step_v2([_home(0.0, 0.0, 0)] as Array[InfluenceCircle])
	var cell: Vector2i = _cell_of(Vector2(0.0, 0.0))
	assert_true(_raster.is_goal_zone(cell.x, cell.y),
		"Zones are rasterized once per match, not per tick.")


func test_a_goal_zone_does_not_change_who_owns_the_ground() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.0, 0.0)]), ZONE_RADIUS)
	_step_v2([_home(0.0, 0.0, 0)] as Array[InfluenceCircle])
	var cell: Vector2i = _cell_of(Vector2(0.0, 0.0))
	assert_true(_raster.is_goal_zone(cell.x, cell.y), "Setup.")
	assert_eq(_raster.team_at(cell.x, cell.y), 0,
		"A player's area must be able to reach through a goal's zone: winning "
		+ "needs the flag base inside it.")


func test_state_bytes_carry_the_goal_zone_bit_and_only_there() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(-8.0, 0.0)]), ZONE_RADIUS)
	_step_v2([_home(0.0, 0.0, 0)] as Array[InfluenceCircle])

	var states: PackedByteArray = _raster.state_bytes()
	assert_eq(states.size(), _grid.cell_count())
	var inside: Vector2i = _cell_of(Vector2(-8.0, 0.0))
	var outside: Vector2i = _cell_of(Vector2(8.0, 0.0))
	assert_eq(
		states[_grid.cell_index(inside.x, inside.y)] & TerritoryRaster.STATE_GOAL_ZONE,
		TerritoryRaster.STATE_GOAL_ZONE
	)
	assert_eq(states[_grid.cell_index(outside.x, outside.y)] & TerritoryRaster.STATE_GOAL_ZONE, 0)
	assert_eq(states[0], 0, "An off-disk cell carries no state bits at all.")


func test_the_goal_zone_bit_coexists_with_the_legacy_contested_and_hole_bits() -> void:
	## STATE_GOAL_ZONE is bit 2, so both rulesets' bits fit in one byte.
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.0, 0.0)]), ZONE_RADIUS)
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	for i: int in range(10):
		_step(circles, 0.1, TEMPORARY)
	var cell: Vector2i = _cell_of(Vector2(0.0, 0.0))
	var byte: int = _raster.state_bytes()[_grid.cell_index(cell.x, cell.y)]
	assert_eq(byte & TerritoryRaster.STATE_CONTESTED, TerritoryRaster.STATE_CONTESTED)
	assert_eq(byte & TerritoryRaster.STATE_HOLE, TerritoryRaster.STATE_HOLE)
	assert_eq(byte & TerritoryRaster.STATE_GOAL_ZONE, TerritoryRaster.STATE_GOAL_ZONE)


func test_a_replicated_mirror_learns_the_goal_zones_from_the_state_bytes() -> void:
	var host: TerritoryRaster = _raster
	host.set_goal_zones(PackedVector2Array([Vector2(0.0, 0.0)]), ZONE_RADIUS)
	_step_v2([_home(0.0, 0.0, 0)] as Array[InfluenceCircle])

	var mirror: TerritoryRaster = TerritoryRaster.new(_grid, _tuning)
	mirror.apply_replicated_state(host.owner_bytes(), host.state_bytes())

	var inside: Vector2i = _cell_of(Vector2(0.0, 0.0))
	var outside: Vector2i = _cell_of(Vector2(12.0, 0.0))
	assert_true(mirror.is_goal_zone(inside.x, inside.y),
		"A client's ghost tint has to refuse a goal zone too (M3a: the mirror "
		+ "answers what the host answers).")
	assert_false(mirror.is_goal_zone(outside.x, outside.y))
	assert_eq(mirror.team_at(inside.x, inside.y), 0, "And ownership still mirrors.")


func test_out_of_bounds_cells_are_never_goal_zones() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.0, 0.0)]), ZONE_RADIUS)
	assert_false(_raster.is_goal_zone(-1, 0))
	assert_false(_raster.is_goal_zone(9999, 0))
	assert_false(_raster.is_goal_zone_index(-1))
	assert_false(_raster.is_goal_zone_index(_grid.cell_count()))


func test_setting_the_zones_again_replaces_them() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(-8.0, 0.0)]), ZONE_RADIUS)
	_raster.set_goal_zones(PackedVector2Array([Vector2(8.0, 0.0)]), ZONE_RADIUS)
	var old_cell: Vector2i = _cell_of(Vector2(-8.0, 0.0))
	var new_cell: Vector2i = _cell_of(Vector2(8.0, 0.0))
	assert_false(_raster.is_goal_zone(old_cell.x, old_cell.y), "The old layout is gone.")
	assert_true(_raster.is_goal_zone(new_cell.x, new_cell.y))


func test_reset_clears_the_goal_zones() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.0, 0.0)]), ZONE_RADIUS)
	_raster.reset()
	var cell: Vector2i = _cell_of(Vector2(0.0, 0.0))
	assert_false(_raster.is_goal_zone(cell.x, cell.y),
		"A new match re-stamps its own goal layout.")


## -- Forced holes (M4 P5-HOLE, Bontago-1en.20) -------------------------------
##
## force_hole_cell() opens a cell independent of contest overlap, seeding the
## same _hole/_contested_time/_idle_time bookkeeping a natural hole uses, so
## the unmodified _advance_timers() (run from update(), same as every other
## test in this file) is what actually closes it hole_open_s later.

const HOLE_OPEN_S: float = 2.0


func test_force_hole_cell_opens_immediately() -> void:
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	assert_false(_raster.is_hole(cell.x, cell.y), "Setup: not a hole yet.")

	_raster.force_hole_cell(cell.x, cell.y, HOLE_OPEN_S, TEMPORARY)

	assert_true(_raster.is_hole(cell.x, cell.y))
	assert_has(Array(_raster.holes_opened()), _grid.cell_index(cell.x, cell.y))


func test_force_hole_cell_stays_open_before_hole_open_s() -> void:
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	_raster.force_hole_cell(cell.x, cell.y, HOLE_OPEN_S, TEMPORARY)
	var empty: Array[InfluenceCircle] = []

	## 19 x 0.1 = 1.9 s, just under hole_open_s = 2.0; no circles at all, so
	## the cell is never CONTESTED and _advance_timers() takes its idle branch.
	for i: int in range(19):
		_step(empty, 0.1, TEMPORARY)
	assert_true(_raster.is_hole(cell.x, cell.y), "Still open at 1.9 s.")


func test_force_hole_cell_closes_via_advance_timers_after_hole_open_s() -> void:
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	var index: int = _grid.cell_index(cell.x, cell.y)
	_raster.force_hole_cell(cell.x, cell.y, HOLE_OPEN_S, TEMPORARY)
	var empty: Array[InfluenceCircle] = []

	## 21 x 0.1 = 2.1 s, just past hole_open_s = 2.0.
	var announcements: int = 0
	for i: int in range(21):
		_step(empty, 0.1, TEMPORARY)
		announcements += Array(_raster.holes_closed()).count(index)

	assert_false(_raster.is_hole(cell.x, cell.y), "Closed past hole_open_s = 2.0 s.")
	assert_eq(announcements, 1, "Announced in holes_closed() exactly once.")


func test_force_hole_cell_never_closes_under_permanent_holes() -> void:
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	_raster.force_hole_cell(cell.x, cell.y, HOLE_OPEN_S, PERMANENT)
	var empty: Array[InfluenceCircle] = []

	for i: int in range(100):
		_step(empty, 0.1, PERMANENT)
		assert_eq(_raster.holes_closed().size(), 0, "Under PERMANENT the board only ever erodes.")
	assert_true(_raster.is_hole(cell.x, cell.y))


func test_force_hole_cell_appears_in_the_opened_change_set_exactly_once() -> void:
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	var index: int = _grid.cell_index(cell.x, cell.y)

	_raster.force_hole_cell(cell.x, cell.y, HOLE_OPEN_S, TEMPORARY)
	assert_eq(Array(_raster.holes_opened()).count(index), 1)

	## Re-forcing an already-open cell (holes_opened() is only cleared by the
	## next update(), not by force_hole_cell() itself) must not append it a
	## second time -- the same "announced once" contract a natural hole keeps.
	_raster.force_hole_cell(cell.x, cell.y, HOLE_OPEN_S, TEMPORARY)
	assert_eq(Array(_raster.holes_opened()).count(index), 1,
		"Re-forcing an already-open cell must not re-announce it.")


## -- A punched hole inside a single team's own circle (SHOULD-FIX, review
## 2026-09-23) --------------------------------------------------------------
##
## Unlike the tests above, force_hole_cell() here lands on a cell a single
## uncontested team already owns (a natural hole never does: it only opens on
## a CONTESTED cell, _team_ids == -1). _stamp() keeps re-stamping that team
## onto the cell every solve (unmodified, per this package's own "do not
## touch update()/_fill_legacy()/_argmax()" contract) so _advance_timers()
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


func test_a_punched_hole_inside_a_single_teams_circle_still_closes_after_hole_open_s() -> void:
	var circles: Array[InfluenceCircle] = [_home(0.0, 0.0, 0)]
	_step(circles, 0.1)
	var cell: Vector2i = _cell_of(Vector2(0.5, 0.5))
	var index: int = _grid.cell_index(cell.x, cell.y)
	_raster.force_hole_cell(cell.x, cell.y, HOLE_OPEN_S, TEMPORARY)

	## 21 x 0.1 = 2.1 s, just past hole_open_s = 2.0, the circle never leaving.
	var announcements: int = 0
	for i: int in range(21):
		_step(circles, 0.1, TEMPORARY)
		announcements += Array(_raster.holes_closed()).count(index)

	assert_false(_raster.is_hole(cell.x, cell.y),
		"The natural hole_open_s close-timer is unaffected by the read-side fix.")
	assert_eq(announcements, 1, "Announced in holes_closed() exactly once.")
	assert_eq(_raster.team_at(cell.x, cell.y), 0,
		"Once closed, the cell reads as team 0's again -- the circle never left.")
