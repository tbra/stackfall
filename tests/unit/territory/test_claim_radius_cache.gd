extends GutTest
## WinChecker.claim_at() reads the raster over a cached list of
## in-radius cells (ClaimCells) instead of rescanning the square around each beacon
## every solve. The cache must change cost, never results: every claim below is
## compared with _reference_claim_at, a per-cell copy of the original uncached
## implementation, on several grid sizes, radii, goal layouts and raster contents
## (including holes inside the radius and new raster contents under a warm cache).

const NO_TEAM: int = WinChecker.NO_TEAM
const NO_GROUP: int = TerritoryGroups.NO_GROUP
## Radii in metres: 0 is the toggle OFF (flag cell), 70 exceeds every fixture grid.
const RADII: Array[float] = [0.0, 0.5, 1.0, 2.5, 4.0, 7.3, 16.0, 70.0]

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")


func before_each() -> void:
	ClaimCells.clear()


func after_each() -> void:
	ClaimCells.clear()


# --- fixtures ------------------------------------------------------------------

func _home(x: float, z: float, team: int, slot: int) -> InfluenceCircle:
	return InfluenceCircle.new(Vector2(x, z), _tuning.home_radius, team, slot, true, -1)


func _raster_for(field_radius: float, cell_size: float, circles: Array[InfluenceCircle]) -> TerritoryRaster:
	var raster: TerritoryRaster = TerritoryRaster.new(CellGrid.new(field_radius, cell_size), _tuning)
	raster.fill_ownership(circles, TerritorySolver.new(_tuning).solve(circles), true)
	raster.adopt_fill(raster, 0.1, true, false)
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


## The uncached per-cell implementation: the oracle.
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


# --- invalidation ---------------------------------------------------------------

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
		raster.fill_ownership(circles, solver.solve(circles), true)
		raster.adopt_fill(raster, 0.1, true, false)
		for radius: float in [3.0, 6.0, 12.0]:
			var want: Vector2i = _reference_claim_at(raster, point, radius)
			assert_eq(WinChecker.claim_at(raster, point, radius), want)
			distinct[want] = true
	assert_gt(distinct.size(), 2, "the layouts really change the claim")
	assert_eq(ClaimCells.build_count(), 3, "three radii at one point, built once across every layout")


# --- holes inside the claim radius ----------------------------------------------

## Punches holes into a settled raster the two ways a real one gets them: forced
## (force_hole_cell, inside a single team's own circle -- the stored team id stays set but
## team_at() reads unowned) and natural (a contested cell whose timer ran out).
func _punch_holes(raster: TerritoryRaster, circles: Array[InfluenceCircle]) -> void:
	var grid: CellGrid = raster.grid()
	for point: Vector2 in [Vector2(-8.0, 0.0), Vector2(-7.0, 1.0), Vector2(-3.0, 4.0), Vector2(7.0, 1.0), Vector2(0.5, 0.5)]:
		var cell: Vector2i = grid.world_to_cell(point)
		raster.force_hole_cell(cell.x, cell.y, 1.0, true)
	var groups: TerritoryGroups = TerritorySolver.new(_tuning).solve(circles)
	for _step: int in range(40):
		raster.fill_ownership(circles, groups, true)
		raster.adopt_fill(raster, 0.1, true, true)


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
