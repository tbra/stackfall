extends Node
## Bontago-1pi.18.8 (QoL Q4, docs/QOL_EXPERIMENTS_PLAN.md section 6 and risk
## "claim_at cost at multiplier 4, five goals, 20 Hz solve"): what the bigger goal
## claim radius costs. WinChecker.update() runs once per territory solve and calls
## claim_at() once per goal (plus once more for the capturing team). Since
## Bontago-1pi.18.11 each goal's in-radius cell indices are cached (ClaimCells) and
## tallied in one pass (TerritoryRaster.tally_owned_cells), so an update reads only
## those cells; the cold first solve that builds the cache is not timed here. The
## worst case is still the toggle's ceiling multiplier with the most goals.
## Run headless (pure logic, no physics, nothing to render):
##   godot --headless --path . res://tests/bench/bench_claim_radius.tscn
## Prints one machine-readable row per (goal count, multiplier), then a result line
## graded on the worst row (GOAL_FLAG_MAX goals, QolExperiments.GOAL_RADIUS_MULTIPLIER_MAX)
## against config/BenchBudgets.gd claim_radius_update_budget_ms, and exits 0 / 1.
## Multiplier 0.0 is the toggle OFF row (radius 0: the single flag cell, today's rule).
## Run it alone on an idle machine before trusting a number; see the budget's DECISION.
##
## The raster is the worst case for the loop: one big home circle owned by one team
## covers every goal, so every in-radius cell is a real group cell and votes (the
## dictionary updates are the expensive part), plus a second team's small home so
## the vote has more than one key near the rim.

const MULTIPLIERS: Array[float] = [0.0, 1.0, 2.0, 3.0, QolExperiments.GOAL_RADIUS_MULTIPLIER_MAX]
const GOAL_COUNTS: Array[int] = [1, MatchConfig.GOAL_FLAG_MAX]
const WARMUP_RUNS: int = 10
const RUNS: int = 200
const US_PER_MS: float = 1000.0
const MS_PER_S: float = 1000.0
const P95: float = 0.95
## The big owner covers this fraction of the field radius (all goals sit inside it).
const BIG_CIRCLE_FRACTION: float = 0.9
## The rival's home sits this fraction of the field radius from the centre, towards +x.
const RIVAL_OFFSET_FRACTION: float = 0.6

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _map: MapDef = preload("res://config/maps/round_large.tres")
var _budgets: BenchBudgets = preload("res://config/bench_budgets.tres")


func _ready() -> void:
	var grid: CellGrid = CellGrid.new(_map.field_radius, _map.cell_size)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, _tuning)
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, _map.field_radius * BIG_CIRCLE_FRACTION, 0, 0, true, -1),
		InfluenceCircle.new(Vector2(_map.field_radius * RIVAL_OFFSET_FRACTION, 0.0), _tuning.home_radius, 1, 1, true, -1),
	]
	raster.update(circles, TerritorySolver.new(_tuning).solve(circles), 0.1, true, false)
	var delta: float = 1.0 / maxf(_tuning.solve_hz, 1.0)
	print("BENCH_CLAIM_RADIUS start map=%s cell_size=%.1f goal_zone_radius=%.1f solve_hz=%.0f runs=%d budget_ms=%.3f" % [
		_map.id, _map.cell_size, _tuning.goal_zone_radius, _tuning.solve_hz, RUNS, _budgets.claim_radius_update_budget_ms])
	var graded_ms: float = 0.0
	for goals: int in GOAL_COUNTS:
		for multiplier: float in MULTIPLIERS:
			var row: Dictionary = _measure(raster, goals, multiplier, delta)
			print(("BENCH_CLAIM_RADIUS row goals=%d mult=%.1f radius=%.1f claimed_team=%d "
				+ "update_avg_ms=%.4f update_p95_ms=%.4f update_max_ms=%.4f claim_at_avg_us=%.2f solve_interval_pct=%.2f") % [
				goals, multiplier, row["radius"], row["team"], row["avg_ms"], row["p95_ms"], row["max_ms"], row["claim_us"],
				float(row["avg_ms"]) / (MS_PER_S / maxf(_tuning.solve_hz, 1.0)) * 100.0])
			if goals == MatchConfig.GOAL_FLAG_MAX and is_equal_approx(multiplier, QolExperiments.GOAL_RADIUS_MULTIPLIER_MAX):
				graded_ms = float(row["avg_ms"])
	var passed: bool = graded_ms <= _budgets.claim_radius_update_budget_ms
	print("BENCH_CLAIM_RADIUS result=%s graded_avg_ms=%.4f budget_ms=%.3f (goals=%d mult=%.1f)" % [
		"PASS" if passed else "FAIL", graded_ms, _budgets.claim_radius_update_budget_ms,
		MatchConfig.GOAL_FLAG_MAX, QolExperiments.GOAL_RADIUS_MULTIPLIER_MAX])
	get_tree().quit(0 if passed else 1)


## Times RUNS WinChecker.update() calls (one solve's win check) and RUNS bare
## claim_at() calls for `goals` beacons at `multiplier` times the goal zone radius.
func _measure(raster: TerritoryRaster, goals: int, multiplier: float, delta: float) -> Dictionary:
	var positions: PackedVector2Array = PlayerSlot.goal_positions_for(goals, _map)
	var radius: float = _tuning.goal_zone_radius * multiplier
	var checker: WinChecker = WinChecker.new(positions, _tuning.capture_hold)
	checker.set_claim_radius(radius)
	for _i: int in range(WARMUP_RUNS):
		checker.reset()
		checker.update(raster, delta)
	var samples: PackedFloat64Array = PackedFloat64Array()
	for _i: int in range(RUNS):
		checker.reset()
		var start: int = Time.get_ticks_usec()
		checker.update(raster, delta)
		samples.append(float(Time.get_ticks_usec() - start) / US_PER_MS)
	var claim_start: int = Time.get_ticks_usec()
	var claim: Vector2i = Vector2i.ZERO
	for _i: int in range(RUNS):
		claim = WinChecker.claim_at(raster, positions[0], radius)
	var claim_us: float = float(Time.get_ticks_usec() - claim_start) / float(RUNS)
	var total: float = 0.0
	for sample: float in samples:
		total += sample
	var sorted: PackedFloat64Array = samples.duplicate()
	sorted.sort()
	return {
		"radius": radius,
		"team": claim.y,
		"avg_ms": total / float(RUNS),
		"p95_ms": sorted[mini(int(float(RUNS) * P95), RUNS - 1)],
		"max_ms": sorted[RUNS - 1],
		"claim_us": claim_us,
	}
