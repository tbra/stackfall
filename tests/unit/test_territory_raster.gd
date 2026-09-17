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
	_raster.update(circles, groups, delta, permanent)


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
		_raster.update(circles, groups, 0.1, TEMPORARY)
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

	var mine: int = _grid.cell_index(_cell_of(Vector2(-8.5, 0.5)).x, _cell_of(Vector2(-8.5, 0.5)).y)
	assert_eq(bytes[mine], 1, "team 0 encodes as 1.")
	var theirs: Vector2i = _cell_of(Vector2(8.5, 0.5))
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
