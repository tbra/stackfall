extends GutTest
## Bontago-1pi.18.11: WinChecker.claim_at() reads the raster over a cached list of
## in-radius cells (ClaimCells) instead of rescanning the square around each beacon
## every solve. The cache must change cost, never results: every claim below is
## compared with _reference_claim_at, a verbatim copy of the pre-cache implementation
## (docs/QOL_EXPERIMENTS_PLAN.md section 5), on several grid sizes, radii, goal
## layouts and raster contents, including the invalidation cases (radius change, new
## grid geometry, new goal layout, new raster contents under a warm cache).

const NO_TEAM: int = WinChecker.NO_TEAM
const NO_GROUP: int = TerritoryGroups.NO_GROUP
## Radii in metres: 0 is the toggle OFF (flag cell), 70 exceeds every fixture grid.
const RADII: Array[float] = [0.0, 0.5, 1.0, 2.5, 4.0, 7.3, 16.0, 70.0]

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")


func before_each() -> void:
	ClaimCells.clear()


func after_each() -> void:
	ClaimCells.clear()


# --- fixtures ------------------------------------------------------------------

func _home(x: float, z: float, team: int, slot: int) -> InfluenceCircle:
	return InfluenceCircle.new(Vector2(x, z), _tuning.home_radius, team, slot, true, -1)


func _raster_for(field_radius: float, cell_size: float, circles: Array[InfluenceCircle]) -> TerritoryRaster:
	var raster: TerritoryRaster = TerritoryRaster.new(CellGrid.new(field_radius, cell_size), _tuning)
	raster.update(circles, TerritorySolver.new(_tuning).solve(circles), 0.1, true, false)
	return raster


## Two teams facing each other across a contested seam plus a second, separate
## home for team 0 (a second group of the same team).
func _contested_circles() -> Array[InfluenceCircle]:
	return [
		_home(-8.0, 0.0, 0, 0),
		_home(7.0, 1.0, 1, 1),
		_home(-9.0, 11.0, 0, 2),
		InfluenceCircle.new(Vector2(-3.0, 4.0), 3.5, 0, 0, false, -1),
	]


## One team's big territory only (every in-radius cell votes).
func _single_team_circles() -> Array[InfluenceCircle]:
	return [InfluenceCircle.new(Vector2.ZERO, 14.0, 0, 0, true, -1)]


## Three teams, so the vote has several keys and a possible three-way split.
func _three_team_circles() -> Array[InfluenceCircle]:
	return [
		_home(-10.0, -6.0, 0, 0),
		_home(10.0, -6.0, 1, 1),
		_home(0.0, 11.0, 2, 2),
		InfluenceCircle.new(Vector2(0.0, 0.0), 2.5, 2, 2, false, -1),
	]


## [name, field_radius, cell_size, circles] -- sizes from a small grid to a 0.5 m one.
func _fixtures() -> Array[Array]:
	return [
		["contested_20_1.0", 20.0, 1.0, _contested_circles()],
		["single_20_1.0", 20.0, 1.0, _single_team_circles()],
		["three_team_24_1.0", 24.0, 1.0, _three_team_circles()],
		["contested_30_2.0", 30.0, 2.0, _contested_circles()],
		["contested_14_0.5", 14.0, 0.5, _contested_circles()],
		["three_team_16_0.75", 16.0, 0.75, _three_team_circles()],
	]


## Beacon positions: centre, near the seam, near the rim, off the grid corner, and
## off-grid altogether (the in-bounds filter must drop the missing cells).
func _points(field_radius: float) -> Array[Vector2]:
	return [
		Vector2.ZERO,
		Vector2(-3.0, 4.0),
		Vector2(1.0, 0.5),
		Vector2(field_radius * 0.8, field_radius * -0.3),
		Vector2(-field_radius, field_radius),
		Vector2(field_radius + 3.0, 0.0),
	]


## The implementation before Bontago-1pi.18.11, verbatim: the oracle.
func _reference_claim_at(raster: TerritoryRaster, point: Vector2, claim_radius: float) -> Vector2i:
	var grid: CellGrid = raster.grid()
	var center: Vector2i = grid.world_to_cell(point)
	if claim_radius <= 0.0:
		return Vector2i(raster.group_at(center.x, center.y), raster.team_at(center.x, center.y))
	var reach: int = ceili(claim_radius / grid.cell_size) + 1
	var team_cells: Dictionary = {}
	var group_cells: Dictionary = {}
	var radius_sq: float = claim_radius * claim_radius
	for cy: int in range(center.y - reach, center.y + reach + 1):
		for cx: int in range(center.x - reach, center.x + reach + 1):
			if not grid.in_bounds(cx, cy):
				continue
			if grid.cell_center(cx, cy).distance_squared_to(point) > radius_sq:
				continue
			var group: int = raster.group_at(cx, cy)
			var team: int = raster.team_at(cx, cy)
			if group < 0 or team < 0:
				continue
			team_cells[team] = int(team_cells.get(team, 0)) + 1
			var key: int = team * 1000000 + group
			group_cells[key] = int(group_cells.get(key, 0)) + 1
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
		return Vector2i(NO_GROUP, NO_TEAM)
	var best_group: int = NO_GROUP
	var best_group_count: int = 0
	for key: int in group_cells:
		if key / 1000000 != best_team:
			continue
		var group_count: int = group_cells[key]
		var group_id: int = key % 1000000
		if group_count > best_group_count or (group_count == best_group_count and group_id < best_group):
			best_group = group_id
			best_group_count = group_count
	return Vector2i(best_group, best_team)


## Every in-bounds cell whose centre is within `radius` of `point`, found by testing
## the whole grid (no reach bound), as "cx,cy" strings.
func _brute_force_cells(grid: CellGrid, point: Vector2, radius: float) -> Array[String]:
	var found: Array[String] = []
	for cy: int in range(grid.res):
		for cx: int in range(grid.res):
			if grid.cell_center(cx, cy).distance_squared_to(point) <= radius * radius:
				found.append("%d,%d" % [cx, cy])
	return found


func _cached_cells_as_strings(grid: CellGrid, indices: PackedInt32Array) -> Array[String]:
	var out: Array[String] = []
	for index: int in indices:
		var cell: Vector2i = grid.cell_coords(index)
		out.append("%d,%d" % [cell.x, cell.y])
	return out


# --- cached == uncached ---------------------------------------------------------

func test_claim_at_matches_the_uncached_reference_across_fixtures_points_and_radii() -> void:
	var compared: int = 0
	var claimed: int = 0
	for fixture: Array in _fixtures():
		var raster: TerritoryRaster = _raster_for(fixture[1], fixture[2], fixture[3])
		for point: Vector2 in _points(fixture[1]):
			for radius: float in RADII:
				var want: Vector2i = _reference_claim_at(raster, point, radius)
				var label: String = "%s point=%s radius=%.1f" % [fixture[0], point, radius]
				# Twice: the first call builds the list, the second reads it.
				assert_eq(WinChecker.claim_at(raster, point, radius), want, "cold: " + label)
				assert_eq(WinChecker.claim_at(raster, point, radius), want, "warm: " + label)
				assert_eq(WinChecker.goal_holder(raster, point, radius), NO_TEAM if want.x < 0 else want.y, "holder: " + label)
				compared += 1
				if want.y != NO_TEAM:
					claimed += 1
	assert_gt(compared, 250, "the matrix ran")
	assert_gt(claimed, 40, "enough fixtures produce a real claim (not all NO_TEAM)")


func test_fixtures_exercise_ties_unowned_and_multiple_groups() -> void:
	# The matrix above is only meaningful when it reaches the interesting branches.
	var raster: TerritoryRaster = _raster_for(20.0, 1.0, _contested_circles())
	var tie_or_none: int = 0
	var multi_group: int = 0
	var teams: Dictionary = {}
	for point: Vector2 in _points(20.0):
		for radius: float in RADII:
			var claim: Vector2i = WinChecker.claim_at(raster, point, radius)
			if claim.y == NO_TEAM:
				tie_or_none += 1
			else:
				teams[claim.y] = true
				if claim.x > 0:
					multi_group += 1
	assert_gt(tie_or_none, 0, "some claims resolve to nobody (tie / unowned / off grid)")
	assert_eq(teams.size(), 2, "both teams claim a beacon somewhere")
	assert_gt(multi_group, 0, "a claim lands on a group other than index 0")


func test_cached_cell_list_equals_a_whole_grid_scan() -> void:
	# Guards the reach bound: the (2 * reach + 1)^2 window must not clip any cell
	# the whole grid says is in range, nor admit one it says is out.
	for fixture: Array in _fixtures():
		var grid: CellGrid = CellGrid.new(fixture[1], fixture[2])
		for point: Vector2 in _points(fixture[1]):
			for radius: float in RADII:
				if radius <= 0.0:
					continue
				var got: Array[String] = _cached_cells_as_strings(grid, ClaimCells.indices_for(grid, point, radius))
				var want: Array[String] = _brute_force_cells(grid, point, radius)
				got.sort()
				want.sort()
				assert_eq(got, want, "%s point=%s radius=%.1f" % [fixture[0], point, radius])


func test_cell_list_is_row_major_and_in_bounds() -> void:
	var grid: CellGrid = CellGrid.new(20.0, 1.0)
	var indices: PackedInt32Array = ClaimCells.indices_for(grid, Vector2(18.0, 0.0), 6.0)
	assert_gt(indices.size(), 0)
	var previous: int = -1
	for index: int in indices:
		assert_true(index >= 0 and index < grid.cell_count(), "a valid raster index")
		var cell: Vector2i = grid.cell_coords(index)
		assert_true(grid.in_bounds(cell.x, cell.y), "only cells inside the grid")
		assert_eq(grid.cell_index(cell.x, cell.y), index, "an index round-trips through its cell")
		assert_gt(index, previous, "row-major, no duplicates")
		previous = index


func test_non_positive_radius_caches_nothing_and_reads_the_flag_cell() -> void:
	var raster: TerritoryRaster = _raster_for(20.0, 1.0, _single_team_circles())
	assert_eq(WinChecker.claim_at(raster, Vector2.ZERO, 0.0), _reference_claim_at(raster, Vector2.ZERO, 0.0))
	assert_eq(WinChecker.claim_at(raster, Vector2.ZERO, -3.0), _reference_claim_at(raster, Vector2.ZERO, -3.0))
	assert_eq(ClaimCells.cached_count(), 0, "radius <= 0 never builds a list")


# --- the cache really caches ----------------------------------------------------

func test_repeated_claims_build_each_list_once() -> void:
	var raster: TerritoryRaster = _raster_for(20.0, 1.0, _contested_circles())
	var goals: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2(8.0, 0.0), Vector2(-8.0, 3.0)])
	assert_eq(ClaimCells.build_count(), 0)
	for _solve: int in range(5):
		for goal: Vector2 in goals:
			WinChecker.claim_at(raster, goal, 4.0)
	assert_eq(ClaimCells.build_count(), goals.size(), "one list per goal, built on the first solve only")
	assert_eq(ClaimCells.cached_count(), goals.size())


func test_win_checker_updates_reuse_the_lists_built_on_the_first_update() -> void:
	var raster: TerritoryRaster = _raster_for(20.0, 1.0, _single_team_circles())
	var goals: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2(4.0, 0.0), Vector2(-4.0, 2.0)])
	var checker: WinChecker = WinChecker.new(goals, 1.0)
	checker.set_claim_radius(4.0)
	checker.update(raster, 0.05)
	assert_eq(ClaimCells.build_count(), goals.size())
	for _i: int in range(10):
		checker.update(raster, 0.05)
	assert_eq(ClaimCells.build_count(), goals.size(), "later updates read the cache")


# --- invalidation ---------------------------------------------------------------

func test_radius_change_builds_a_new_list_and_keeps_results_exact() -> void:
	var raster: TerritoryRaster = _raster_for(20.0, 1.0, _contested_circles())
	var point: Vector2 = Vector2(-3.0, 4.0)
	var small: PackedInt32Array = ClaimCells.indices_for(raster.grid(), point, 2.0)
	var big: PackedInt32Array = ClaimCells.indices_for(raster.grid(), point, 8.0)
	assert_eq(ClaimCells.build_count(), 2, "a different radius is a different list")
	assert_lt(small.size(), big.size())
	var checker: WinChecker = WinChecker.new(PackedVector2Array([point]), 1.0)
	for radius: float in [2.0, 8.0, 0.0, 8.0, 3.0, 2.0]:
		checker.set_claim_radius(radius)
		checker.update(raster, 0.05)
		var want: Vector2i = _reference_claim_at(raster, point, radius)
		assert_eq(WinChecker.claim_at(raster, point, radius), want, "radius %.1f after toggling" % radius)
		assert_eq(checker.capturing_team(), want.y if want.x >= 0 else NO_TEAM, "checker follows radius %.1f" % radius)


func test_new_grid_geometry_builds_new_lists() -> void:
	var point: Vector2 = Vector2(1.0, 1.0)
	var coarse: CellGrid = CellGrid.new(20.0, 2.0)
	var fine: CellGrid = CellGrid.new(20.0, 1.0)
	var wide: CellGrid = CellGrid.new(40.0, 1.0)
	var coarse_cells: PackedInt32Array = ClaimCells.indices_for(coarse, point, 6.0)
	var fine_cells: PackedInt32Array = ClaimCells.indices_for(fine, point, 6.0)
	var wide_cells: PackedInt32Array = ClaimCells.indices_for(wide, point, 6.0)
	assert_eq(ClaimCells.build_count(), 3, "cell size and grid edge each key the cache")
	assert_ne(coarse_cells.size(), fine_cells.size())
	assert_eq(fine_cells.size(), _brute_force_cells(fine, point, 6.0).size())
	assert_eq(wide_cells.size(), _brute_force_cells(wide, point, 6.0).size())
	# A second grid with the same geometry shares the list: the list depends on
	# geometry alone, so a rebuilt-but-identical map costs nothing.
	var twin: CellGrid = CellGrid.new(20.0, 1.0)
	ClaimCells.indices_for(twin, point, 6.0)
	assert_eq(ClaimCells.build_count(), 3)


func test_new_goal_layout_builds_only_the_new_goals() -> void:
	var raster: TerritoryRaster = _raster_for(20.0, 1.0, _three_team_circles())
	var layout_a: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(5.0, 5.0)])
	var layout_b: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(-5.0, 5.0), Vector2(9.0, -2.0)])
	for goal: Vector2 in layout_a:
		assert_eq(WinChecker.claim_at(raster, goal, 3.0), _reference_claim_at(raster, goal, 3.0))
	assert_eq(ClaimCells.build_count(), 2)
	for goal: Vector2 in layout_b:
		assert_eq(WinChecker.claim_at(raster, goal, 3.0), _reference_claim_at(raster, goal, 3.0))
	assert_eq(ClaimCells.build_count(), 4, "the shared goal at the origin is reused, two new ones built")
	# The checker swaps layouts the same way (its update may stop at the first
	# unclaimed goal, so only the results, not the build count, are asserted).
	var checker: WinChecker = WinChecker.new(layout_a, 1.0)
	checker.set_claim_radius(3.0)
	checker.update(raster, 0.05)
	checker.set_goal_positions(layout_b)
	checker.update(raster, 0.05)
	assert_lte(ClaimCells.build_count(), 4, "no list beyond the two layouts' goals")


func test_changing_raster_contents_under_a_warm_cache_is_never_stale() -> void:
	# Only geometry is cached; ownership is read fresh on every call.
	var tuning: TerritoryTuning = _tuning
	var grid: CellGrid = CellGrid.new(20.0, 1.0)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	var solver: TerritorySolver = TerritorySolver.new(tuning)
	var point: Vector2 = Vector2(2.0, 1.0)
	var layouts: Array[Array] = [
		[_home(2.0, 1.0, 0, 0)],
		[_home(2.0, 1.0, 1, 1)],
		[_home(-9.0, 1.0, 0, 0), _home(11.0, 1.0, 1, 1)],
		[_home(-6.0, 1.0, 0, 0), _home(10.0, 1.0, 1, 1)],
		[_home(-12.0, -12.0, 0, 0)],
	]
	var distinct: Dictionary = {}
	for layout: Array in layouts:
		var circles: Array[InfluenceCircle] = []
		for circle: Variant in layout:
			circles.append(circle as InfluenceCircle)
		raster.update(circles, solver.solve(circles), 0.1, true, false)
		for radius: float in [3.0, 6.0, 12.0]:
			var want: Vector2i = _reference_claim_at(raster, point, radius)
			assert_eq(WinChecker.claim_at(raster, point, radius), want)
			distinct[want] = true
	assert_gt(distinct.size(), 2, "the layouts really change the claim")
	assert_eq(ClaimCells.build_count(), 3, "three radii at one point, built once across every layout")


func test_clear_drops_lists_and_a_cold_cache_gives_the_same_answer() -> void:
	var raster: TerritoryRaster = _raster_for(20.0, 1.0, _contested_circles())
	var point: Vector2 = Vector2(-3.0, 4.0)
	var warm: Vector2i = WinChecker.claim_at(raster, point, 4.0)
	assert_eq(ClaimCells.cached_count(), 1)
	ClaimCells.clear()
	assert_eq(ClaimCells.cached_count(), 0)
	assert_eq(ClaimCells.build_count(), 0)
	assert_eq(WinChecker.claim_at(raster, point, 4.0), warm)
	assert_eq(ClaimCells.build_count(), 1, "rebuilt on demand")


func test_the_cache_is_bounded_and_still_exact_past_its_capacity() -> void:
	var raster: TerritoryRaster = _raster_for(20.0, 1.0, _contested_circles())
	for i: int in range(ClaimCells.MAX_CACHED_LISTS * 2 + 7):
		var point: Vector2 = Vector2(float(i % 17) - 8.0, float(i / 17) - 3.0) + Vector2(0.01 * float(i), 0.0)
		assert_eq(WinChecker.claim_at(raster, point, 3.0), _reference_claim_at(raster, point, 3.0), "point %d" % i)
		assert_lte(ClaimCells.cached_count(), ClaimCells.MAX_CACHED_LISTS, "never grows past the bound")


# --- the raster's one-pass tally (the claim_at read path) ------------------------

## Punches holes into a settled raster the two ways a real one gets them: forced
## (force_hole_cell, inside a single team's own circle -- the raw owner stays set but
## team_at() reads unowned) and natural (a contested cell whose timer ran out).
func _punch_holes(raster: TerritoryRaster, circles: Array[InfluenceCircle]) -> void:
	var grid: CellGrid = raster.grid()
	for point: Vector2 in [Vector2(-8.0, 0.0), Vector2(-7.0, 1.0), Vector2(-3.0, 4.0), Vector2(7.0, 1.0), Vector2(0.5, 0.5)]:
		var cell: Vector2i = grid.world_to_cell(point)
		raster.force_hole_cell(cell.x, cell.y, 1.0, true)
	var groups: TerritoryGroups = TerritorySolver.new(_tuning).solve(circles)
	for _step: int in range(40):
		raster.update(circles, groups, 0.1, true, true)


## The per-cell votes over `indices` through the coordinate readers: the oracle for
## TerritoryRaster.tally_owned_cells().
func _per_cell_tally(raster: TerritoryRaster, indices: PackedInt32Array) -> Dictionary:
	var grid: CellGrid = raster.grid()
	var out: Dictionary = {}
	for index: int in indices:
		var cell: Vector2i = grid.cell_coords(index)
		var group: int = raster.group_at(cell.x, cell.y)
		var team: int = raster.team_at(cell.x, cell.y)
		if group < 0 or team < 0:
			continue
		var key: int = team * WinChecker.GROUP_KEY_STRIDE + group
		out[key] = int(out.get(key, 0)) + 1
	return out


## Compares the tally over every cached claim list of a fixture with the oracle;
## returns how many lists held at least one vote.
func _tally_matches_per_cell_votes(raster: TerritoryRaster, field_radius: float, label: String) -> int:
	var voting: int = 0
	for point: Vector2 in _points(field_radius):
		for radius: float in RADII:
			if radius <= 0.0:
				continue
			var indices: PackedInt32Array = ClaimCells.indices_for(raster.grid(), point, radius)
			var got: Dictionary[int, int] = raster.tally_owned_cells(indices, WinChecker.GROUP_KEY_STRIDE)
			var want: Dictionary = _per_cell_tally(raster, indices)
			var where: String = "%s point=%s radius=%.1f" % [label, point, radius]
			assert_eq(got.size(), want.size(), "keys: " + where)
			for key: int in want:
				assert_eq(got.get(key, -1), want[key], "key %d: %s" % [key, where])
			if not want.is_empty():
				voting += 1
	return voting


func test_raster_tally_over_the_cached_cells_equals_the_per_cell_votes() -> void:
	var voting: int = 0
	for fixture: Array in _fixtures():
		voting += _tally_matches_per_cell_votes(_raster_for(fixture[1], fixture[2], fixture[3]), fixture[1], fixture[0])
	assert_gt(voting, 40, "enough cached lists cast votes for the comparison to mean something")


func test_raster_tally_matches_the_per_cell_votes_with_holes_in_range() -> void:
	var voting: int = 0
	var raw_owned_holes: int = 0
	for fixture: Array in _fixtures():
		var circles: Array[InfluenceCircle] = fixture[3]
		var raster: TerritoryRaster = _raster_for(fixture[1], fixture[2], circles)
		_punch_holes(raster, circles)
		var grid: CellGrid = raster.grid()
		for index: int in range(grid.cell_count()):
			var cell: Vector2i = grid.cell_coords(index)
			if raster.is_hole_index(index) and raster.team_at(cell.x, cell.y) == -1 and raster.group_at(cell.x, cell.y) >= 0:
				raw_owned_holes += 1
		voting += _tally_matches_per_cell_votes(raster, fixture[1], fixture[0] + " with holes")
	assert_gt(voting, 40)
	assert_gt(raw_owned_holes, 0, "some holes sit on cells that still have a real group (the team_at() mask must hide them)")


func test_claim_at_over_a_replicated_mirror_matches_the_reference() -> void:
	var host: TerritoryRaster = _raster_for(20.0, 1.0, _contested_circles())
	_punch_holes(host, _contested_circles())
	var mirror: TerritoryRaster = TerritoryRaster.new(CellGrid.new(20.0, 1.0), _tuning)
	mirror.apply_replicated_state(host.owner_bytes(), host.state_bytes())
	var claimed: int = 0
	for point: Vector2 in _points(20.0):
		for radius: float in RADII:
			var want: Vector2i = _reference_claim_at(mirror, point, radius)
			assert_eq(WinChecker.claim_at(mirror, point, radius), want, "mirror point=%s radius=%.1f" % [point, radius])
			if want.y != NO_TEAM:
				claimed += 1
	assert_gt(claimed, 0, "the mirror produces real claims")


func test_claim_at_never_writes_to_the_raster() -> void:
	var raster: TerritoryRaster = _raster_for(20.0, 1.0, _contested_circles())
	var revision: int = raster.content_revision()
	var owners: PackedByteArray = raster.owner_bytes().duplicate()
	var states: PackedByteArray = raster.state_bytes().duplicate()
	for point: Vector2 in _points(20.0):
		for radius: float in RADII:
			WinChecker.claim_at(raster, point, radius)
	assert_eq(raster.content_revision(), revision)
	assert_eq(raster.owner_bytes(), owners)
	assert_eq(raster.state_bytes(), states)


func test_claims_stay_exact_with_holes_inside_the_radius() -> void:
	var compared: int = 0
	var changed: int = 0
	for fixture: Array in _fixtures():
		var circles: Array[InfluenceCircle] = fixture[3]
		var raster: TerritoryRaster = _raster_for(fixture[1], fixture[2], circles)
		var intact: Dictionary = {}
		for point: Vector2 in _points(fixture[1]):
			for radius: float in RADII:
				intact[[point, radius]] = WinChecker.claim_at(raster, point, radius)
		_punch_holes(raster, circles)
		for point: Vector2 in _points(fixture[1]):
			for radius: float in RADII:
				var want: Vector2i = _reference_claim_at(raster, point, radius)
				var label: String = "%s point=%s radius=%.1f" % [fixture[0], point, radius]
				assert_eq(WinChecker.claim_at(raster, point, radius), want, "holes: " + label)
				compared += 1
				if want != intact[[point, radius]]:
					changed += 1
	assert_gt(compared, 250, "the hole matrix ran")
	assert_gt(changed, 0, "the holes change at least one claim, so the hole branch is exercised")


# --- WinChecker.update still agrees with the per-goal reference -----------------

func test_win_checker_capture_matches_the_reference_for_every_radius_and_goal_set() -> void:
	var goal_sets: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2.ZERO]),
		PackedVector2Array([Vector2(-8.0, 0.0), Vector2(-6.0, 3.0)]),
		PackedVector2Array([Vector2(-8.0, 0.0), Vector2(7.0, 1.0)]),
		PackedVector2Array([Vector2(-8.0, 0.0), Vector2(-9.0, 11.0)]),
		PackedVector2Array([Vector2(-8.0, 0.0), Vector2(-7.0, 2.0), Vector2(-9.0, -2.0), Vector2(-6.0, 1.0), Vector2(-10.0, 0.0)]),
	]
	var captured: int = 0
	for fixture: Array in _fixtures():
		var raster: TerritoryRaster = _raster_for(fixture[1], fixture[2], fixture[3])
		for goals: PackedVector2Array in goal_sets:
			for radius: float in RADII:
				var checker: WinChecker = WinChecker.new(goals, 1000.0)
				checker.set_claim_radius(radius)
				checker.update(raster, 0.05)
				var first: Vector2i = _reference_claim_at(raster, goals[0], radius)
				var expect_team: int = NO_TEAM
				if first.x >= 0:
					var same: bool = true
					for i: int in range(1, goals.size()):
						if _reference_claim_at(raster, goals[i], radius).x != first.x:
							same = false
							break
					if same:
						expect_team = first.y
				assert_eq(checker.capturing_team(), expect_team, "%s goals=%d radius=%.1f" % [fixture[0], goals.size(), radius])
				if expect_team != NO_TEAM:
					captured += 1
	assert_gt(captured, 10, "the matrix includes real captures")
