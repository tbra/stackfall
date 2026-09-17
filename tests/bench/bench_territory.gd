extends Node3D
## docs/M2_PLAN.md, P1 acceptance: "bench_territory.gd reports solve+raster
## time for 200 circles on map M, budget <= 8 ms per solve at 10 Hz". Run
## headless:
##   godot --headless --path . res://tests/bench/bench_territory.tscn
## Prints one machine-readable result line per circle count, then quits.
##
## Pure logic, so there is no physics to step: everything happens in _ready.
## The 200-circle row is the graded one; the larger rows are there to show how
## the cost grows towards a full eight-player match.

## The graded configuration.
const GRADED_CIRCLES: int = 200
## Spec 3.3 / docs/M2_PLAN.md: 8 ms of the 100 ms available at solve_hz = 10.
const BUDGET_MS: float = 8.0
## Extra rows for context only, not graded.
const EXTRA_CIRCLES: Array[int] = [400, 600]
const RUNS: int = 20
const SLOT_COUNT: int = 8
## Tall towers reach about this high in practice, which is what sets the
## influence radii the spatial hash has to cope with.
const MAX_BLOCK_HEIGHT: float = 12.0
const RNG_SEED: int = 20260917

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _map: MapDef = preload("res://config/maps/round_medium.tres")


func _ready() -> void:
	var grid: CellGrid = CellGrid.new(_map.field_radius, _map.cell_size)
	print(
		("BENCH_TERRITORY start map=%s field_radius=%.1f cells=%dx%d in_disk_cells=%d "
		+ "hash_cell_size=%.1f max_circles=%d solve_hz=%.0f runs=%d") % [
			_map.id, _map.field_radius, grid.res, grid.res, grid.in_disk_cell_count(),
			_tuning.hash_cell_size, _tuning.max_circles, _tuning.solve_hz, RUNS,
		]
	)

	var passed: bool = _measure(grid, GRADED_CIRCLES, true)
	for count: int in EXTRA_CIRCLES:
		_measure(grid, count, false)

	print("BENCH_TERRITORY result=%s" % ["PASS" if passed else "FAIL"])
	get_tree().quit(0 if passed else 1)


## Times RUNS solve+raster+win-check cycles and prints one row. Returns whether
## the average landed inside the budget.
func _measure(grid: CellGrid, count: int, graded: bool) -> bool:
	var solver: TerritorySolver = TerritorySolver.new(_tuning)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, _tuning)
	var checker: WinChecker = WinChecker.new(
		PackedVector2Array([Vector2.ZERO]), _tuning.capture_hold
	)
	var circles: Array[InfluenceCircle] = _build_circles(count)
	var delta: float = 1.0 / maxf(_tuning.solve_hz, 1.0)

	# One untimed cycle so the first run does not pay for the lazily built
	# in-disk cell list and the scratch buffers growing to size.
	var warm: TerritoryGroups = solver.solve(circles)
	raster.update(circles, warm, delta, false)
	checker.update(raster, delta)

	var solve_us: int = 0
	var raster_us: int = 0
	var win_us: int = 0
	var groups: TerritoryGroups = null
	for run: int in range(RUNS):
		var t0: int = Time.get_ticks_usec()
		groups = solver.solve(circles)
		var t1: int = Time.get_ticks_usec()
		raster.update(circles, groups, delta, false)
		var t2: int = Time.get_ticks_usec()
		checker.update(raster, delta)
		var t3: int = Time.get_ticks_usec()
		solve_us += t1 - t0
		raster_us += t2 - t1
		win_us += t3 - t2

	var solve_ms: float = float(solve_us) / (1000.0 * float(RUNS))
	var raster_ms: float = float(raster_us) / (1000.0 * float(RUNS))
	var win_ms: float = float(win_us) / (1000.0 * float(RUNS))
	var total_ms: float = solve_ms + raster_ms + win_ms
	var within: bool = total_ms <= BUDGET_MS

	print(
		("BENCH_TERRITORY blocks=%d circles=%d graded=%s total_ms=%.3f solve_ms=%.3f "
		+ "raster_ms=%.3f win_ms=%.3f budget_ms=%.1f within_budget=%s groups=%d pairs=%d "
		+ "note=debug_interpreter_timing_is_a_ceiling") % [
			count, circles.size(), graded, total_ms, solve_ms, raster_ms, win_ms, BUDGET_MS,
			within, groups.group_count(), solver.last_pair_count(),
		]
	)
	return within


## One home circle per slot plus `block_count` settled-block circles scattered
## over the disk, area-weighted so the density is even rather than clustered at
## the centre.
func _build_circles(block_count: int) -> Array[InfluenceCircle]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = RNG_SEED

	var circles: Array[InfluenceCircle] = []
	var home_distance: float = _map.field_radius * _map.home_flag_radius_fraction
	for slot: int in range(SLOT_COUNT):
		var angle: float = TAU * float(slot) / float(SLOT_COUNT)
		circles.append(InfluenceCircle.for_home(
			Vector2(cos(angle), sin(angle)) * home_distance, slot, slot, _tuning
		))

	for i: int in range(block_count):
		var angle: float = rng.randf() * TAU
		var distance: float = sqrt(rng.randf()) * _map.field_radius
		var height: float = rng.randf() * MAX_BLOCK_HEIGHT
		circles.append(InfluenceCircle.for_block(
			Vector2(cos(angle), sin(angle)) * distance,
			height,
			i % SLOT_COUNT,
			i % SLOT_COUNT,
			i,
			_tuning,
			_map.field_radius
		))
	return circles
