extends GutTest
## SPEC.md audit 'Rule acceptance scenarios' 2, 4, 5 and 8, core-only fixtures.

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0

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


func _cell_of(point: Vector2) -> Vector2i:
	return _grid.world_to_cell(point)


## One v2 (holes_enabled = false) solve+rasterize.
func _solve_v2(circles: Array[InfluenceCircle], delta: float = 0.1) -> void:
	_raster.fill_ownership(circles, _solver.solve(circles), false)
	_raster.adopt_fill(_raster, delta, false, false)


## One legacy (holes_enabled = true) solve+rasterize.
func _solve_legacy(circles: Array[InfluenceCircle], delta: float, permanent: bool = false) -> void:
	_raster.fill_ownership(circles, _solver.solve(circles), true)
	_raster.adopt_fill(_raster, delta, true, permanent)


# --- Scenario 2: collapse without input --------------------------------------
# "move/topple a tower, then issue no placement. Its influence updates
# promptly; disconnected capture progress resets."

func test_scenario_2_a_collapsed_bridge_drops_influence_and_resets_capture_without_a_placement() -> void:
	var goal: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0)])
	var checker: WinChecker = WinChecker.new(goal, _tuning.capture_hold)
	var step: float = 1.0 / _tuning.solve_hz

	# Home at x = -10 (reach 6, i.e. to -4) bridged by a tower at x = -4
	# (radius 5, reach -9..1) that reaches the goal at the origin.
	var home: InfluenceCircle = _home(-10.0, 0.0, 0)
	var bridge: InfluenceCircle = _block(-4.0, 0.0, 5.0, 0)
	var bridged: Array[InfluenceCircle] = [home, bridge]

	# Hold the capture partway, well under capture_hold, through several
	# continuous solves -- no placement call anywhere in this test.
	for i: int in range(10):
		_solve_v2(bridged, step)
		checker.update(_raster, step)
	assert_gt(checker.capture_progress(), 0.0, "Setup: the bridge lets progress accumulate.")
	assert_lt(checker.capture_progress(), 1.0, "Setup: nowhere near capture_hold yet.")
	assert_eq(checker.winner(), WinChecker.NO_TEAM)

	# The tower topples (or is otherwise removed by physics): its circle is
	# simply gone from the next solve, exactly like a real block that stops
	# being settled. No block was placed to trigger this.
	var collapsed: Array[InfluenceCircle] = [home]
	_solve_v2(collapsed, step)
	checker.update(_raster, step)

	assert_eq(_raster.group_at_point(Vector2(0.0, 0.0)), TerritoryGroups.NO_GROUP,
		"The goal is promptly unreachable: home alone (radius 6) does not reach x = 0 (10 m away).")
	assert_almost_eq(checker.capture_progress(), 0.0, 0.0001,
		"Disconnected capture progress resets immediately, on the very next solve.")
	assert_eq(checker.capturing_team(), WinChecker.NO_TEAM)


# --- Scenario 4: goal exclusion versus capture -------------------------------
# "a point inside a goal's no-build zone refuses placement even if owned.
# Influence can still cover its flag base. No physical floor is removed
# solely because it is a goal zone."

const ZONE_RADIUS: float = 3.0

func test_scenario_4_a_goal_zone_blocks_placement_but_not_influence_or_capture() -> void:
	_raster.set_goal_zones(PackedVector2Array([Vector2(0.0, 0.0)]), ZONE_RADIUS)
	var home: InfluenceCircle = _home(0.0, 0.0, 0)
	_solve_v2([home] as Array[InfluenceCircle])

	# Placement: refused inside the zone even though the point is mine.
	assert_eq(_raster.team_at(_cell_of(Vector2.ZERO).x, _cell_of(Vector2.ZERO).y), 0,
		"Setup: the zone sits on my own ground.")
	assert_eq(PlacementRules.validate_point(Vector2.ZERO, _raster, 0), PlacementRules.Result.GOAL_ZONE,
		"A point inside the no-build zone refuses placement even though it is owned.")

	# Influence/capture: the flag's base still counts toward the win check.
	var checker: WinChecker = WinChecker.new(
		PackedVector2Array([Vector2(0.0, 0.0)]), _tuning.capture_hold
	)
	var step: float = 1.0 / _tuning.solve_hz
	var frames: int = int(ceil(_tuning.capture_hold / step)) + 2
	var won: bool = false
	for i: int in range(frames):
		_solve_v2([home] as Array[InfluenceCircle], step)
		checker.update(_raster, step)
		if checker.winner() != WinChecker.NO_TEAM:
			won = true
			break
	assert_true(won, "Influence still covers the flag base, so the zone does not block capture.")
	assert_eq(checker.winner(), 0)

	# No physical floor removed: a goal zone alone never sets the hole bit or
	# leaves the disk unowned around it -- only the legacy contest/hole
	# machinery does that, and it is untouched by set_goal_zones().
	var cell: Vector2i = _cell_of(Vector2.ZERO)
	assert_false(_raster.is_hole(cell.x, cell.y),
		"A goal zone alone must never open a hole (SPEC.md 2.2: zones block placement only).")
	var state: int = _raster.state_bytes()[_grid.cell_index(cell.x, cell.y)]
	assert_eq(state & TerritoryRaster.STATE_HOLE, 0)
	assert_eq(state & TerritoryRaster.STATE_GOAL_ZONE, TerritoryRaster.STATE_GOAL_ZONE)


# --- Scenario 5: point legality ----------------------------------------------
# "a wide piece centered at a legal ray hit is not rejected only because a
# corner crosses a territory border."

func test_scenario_5_a_wide_piece_centred_on_a_legal_point_is_accepted_despite_a_corner_crossing_the_border() -> void:
	# Home 0 at x = -10, home 1 at x = -2, both radius 6: circles span
	# [-16, -4] and [-8, 4], so [-8, -4] is contested and x < -8 is team 0's
	# exclusive ground, with a solid margin either side of every boundary
	# below so this is not a cell-quantization edge case. A 4-long piece
	# (offsets 0..3 from its own origin, matching a "bar4"'s own local
	# layout) with its origin at a legal point (x = -9.2, comfortably inside
	# my exclusive ground) reaches two cubes into the contested band at
	# x = -7.2 and x = -6.2.
	_solve_legacy([_home(-10.0, 0.0, 0), _home(-2.0, 0.0, 1)] as Array[InfluenceCircle], 0.1)
	var origin: Vector2 = Vector2(-9.2, 0.0)
	assert_eq(_raster.team_at(_cell_of(origin).x, _cell_of(origin).y), 0, "Setup: the origin point is mine alone.")

	# Old rule (kept for the bench/legacy row only): the whole footprint has
	# to validate, so a corner past the border rejects the entire piece.
	var bar4: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0)]
	var footprint: PackedInt32Array = PlacementRules.footprint_cells(
		bar4, Basis.IDENTITY, origin, 1.0, _grid
	)
	assert_eq(PlacementRules.validate(footprint, _raster, 0), PlacementRules.Result.CONTESTED,
		"Setup: the old whole-footprint rule would have rejected this piece (two of its four "
		+ "cubes land in the contested band between the two homes).")

	# New rule, used in live play under every hole_mode: only the origin
	# point the ray hit matters.
	assert_eq(PlacementRules.validate_point(origin, _raster, 0), PlacementRules.Result.VALID,
		"A wide piece with a legal origin point is accepted; its shape never enters the check.")


# --- Scenario 8: overlap mode -------------------------------------------------
# "opposing influence opens a hole according to explicit provisional tuning.
# Temporary restoration and permanent erosion are tested separately. No test
# should mistake v2's winner-takes-point border for an overlap hole."

func test_scenario_8_overlap_opens_a_hole_after_hole_delay_under_temporary() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	var cell: Vector2i = _cell_of(Vector2(0.0, 0.0))
	var elapsed: float = 0.0
	var step: float = 0.1
	while elapsed < _tuning.hole_delay + step:
		_solve_legacy(circles, step, false)
		elapsed += step
	assert_true(_raster.is_hole(cell.x, cell.y), "Contest past hole_delay opens a hole under TEMPORARY.")


func test_scenario_8_temporary_restores_and_permanent_erodes_separately() -> void:
	# Temporary: open a hole, stop contesting, and confirm it closes after
	# hole_close_delay.
	var contested: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	var alone: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0)]
	var cell: Vector2i = _cell_of(Vector2(0.0, 0.0))
	for i: int in range(15):
		_solve_legacy(contested, 0.1, false)
	assert_true(_raster.is_hole(cell.x, cell.y), "Setup: the hole is open.")
	for i: int in range(int(ceil((_tuning.hole_close_delay + 0.1) / 0.1))):
		_solve_legacy(alone, 0.1, false)
	assert_false(_raster.is_hole(cell.x, cell.y), "TEMPORARY: restored after hole_close_delay uncontested.")

	# Permanent: the same setup on a fresh raster never closes.
	_raster.reset()
	for i: int in range(15):
		_solve_legacy(contested, 0.1, true)
	assert_true(_raster.is_hole(cell.x, cell.y), "Setup: the hole is open.")
	for i: int in range(int(ceil((_tuning.hole_close_delay + 0.1) / 0.1))):
		_solve_legacy(alone, 0.1, true)
	assert_true(_raster.is_hole(cell.x, cell.y), "PERMANENT: the board only ever erodes.")


# --- Additional acceptance points named in --------------------
