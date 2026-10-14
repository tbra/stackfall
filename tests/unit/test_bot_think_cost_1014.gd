extends GutTest
## Bontago-1t5.62: the opt-in Hard-bot think cost report. BotThink.stats_record() (per phase microseconds /
## units, the probe callable time), BotThinkCostReport aggregation and rendering, and the
## BotThinkCostCollector registry (off by default, per-slot windows, an all-bots aggregate).

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const HOME_A: Vector2 = Vector2(-10.0, 0.0)
const HOME_B: Vector2 = Vector2(10.0, 0.0)
const CANDIDATE_COUNT: int = 30
const SEED: int = 4242
const BIG_BUDGET_US: int = 60000000
const SURFACE_HEIGHT: float = 0.0
## The phase sum may differ from the measured step total by loop overhead: 5 % or this many microseconds.
const SUM_TOLERANCE_FRACTION: float = 0.05
const SUM_TOLERANCE_FLOOR_US: float = 300.0
const FAKE_SLOT_A: int = 2
const FAKE_SLOT_B: int = 5
const PERCENT_TOLERANCE: float = 0.01
const SMALL_WINDOW: int = 2

var _territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")
var _raster: TerritoryRaster = null
var _slots: Array[PlayerSlot] = []


func before_each() -> void:
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, CELL)
	_raster = TerritoryRaster.new(grid, _territory_tuning)
	_slots = [
		PlayerSlot.new(0, 0, "a", Color.WHITE, HOME_A),
		PlayerSlot.new(1, 1, "b", Color.WHITE, HOME_B),
	]
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(HOME_A, 0, 0, _territory_tuning),
		InfluenceCircle.for_home(HOME_B, 1, 1, _territory_tuning),
	]
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	_raster.update(circles, solver.solve(circles), 0.1, false, false)


func after_each() -> void:
	BotThinkCostCollector.disable()


func _probe(_xz: Vector2) -> Dictionary:
	return {"hit": true, "height": SURFACE_HEIGHT, "own": false}


func _think(collect: bool) -> BotThink:
	var arrays: Dictionary = {
		"xs": PackedFloat32Array([HOME_A.x, HOME_B.x]), "zs": PackedFloat32Array([HOME_A.y, HOME_B.y]),
		"radii": PackedFloat32Array([_territory_tuning.home_radius, _territory_tuning.home_radius]),
		"teams": PackedInt32Array([0, 1]),
	}
	var view: BotWorldView = BotWorldView.build(
		0, 0, arrays, _slots, _raster, PackedVector2Array([Vector2.ZERO]),
		_territory_tuning.goal_zone_radius, _cube, _cube, null, PackedVector2Array(), PackedVector2Array()
	)
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.candidate_count = CANDIDATE_COUNT
	profile.stability_raycast_count = 3
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var think: BotThink = BotThink.new(view, profile, rng)
	think.collect_stats = collect
	return think


func _fake_record(phase_us: Array[int], units: Array[int], probe_call_us: int, ticks: int) -> Dictionary:
	return {
		"phase_us": PackedInt64Array(phase_us), "phase_units": PackedInt64Array(units),
		"total_us": phase_us.reduce(func(a: int, b: int) -> int: return a + b, 0),
		"probe_call_us": probe_call_us, "probe_calls": 4, "build_us": 100, "apply_us": 50, "other_us": 30,
		"ticks": ticks, "latency_us": 20000,
	}


func test_think_stats_record_has_every_phase_and_sums_to_the_total() -> void:
	var think: BotThink = _think(true)
	assert_true(think.step(BIG_BUDGET_US, _probe), "a big budget finishes the think")
	var record: Dictionary = think.stats_record()
	var us: PackedInt64Array = record["phase_us"] as PackedInt64Array
	var units: PackedInt64Array = record["phase_units"] as PackedInt64Array
	assert_eq(us.size(), BotThinkCostReport.PHASE_COUNT, "every phase present")
	assert_eq(units.size(), BotThinkCostReport.PHASE_COUNT)
	for phase: int in [BotThink.Phase.PLAN, BotThink.Phase.SITES, BotThink.Phase.PROBE, BotThink.Phase.RANK, BotThink.Phase.PICK]:
		assert_gt(units[phase], 0, "phase %d ran" % phase)
	var sum: int = 0
	for v: int in us:
		sum += v
	var total: int = record["total_us"] as int
	var tolerance: float = maxf(float(total) * SUM_TOLERANCE_FRACTION, SUM_TOLERANCE_FLOOR_US)
	assert_almost_eq(float(sum), float(total), tolerance, "phase sum within 5 percent of the step total")


func test_probe_callable_time_is_part_of_probe() -> void:
	var think: BotThink = _think(true)
	think.step(BIG_BUDGET_US, _probe)
	var record: Dictionary = think.stats_record()
	var probe_us: int = (record["phase_us"] as PackedInt64Array)[BotThink.Phase.PROBE]
	assert_gt(record["probe_calls"] as int, 0, "the callable was timed")
	assert_lte(record["probe_call_us"] as int, probe_us, "callable time <= PROBE total")


func test_stats_are_off_by_default() -> void:
	var think: BotThink = _think(false)
	think.step(BIG_BUDGET_US, _probe)
	assert_true(think.stats_record().is_empty(), "no record unless collect_stats")
	assert_null(BotThinkCostCollector.current(), "no collector unless enabled")


func test_report_aggregates_two_records() -> void:
	var report: BotThinkCostReport = BotThinkCostReport.new("t")
	var a: Array[int] = [0, 100, 200, 0, 600, 100, 0, 0]
	var b: Array[int] = [0, 100, 200, 0, 1000, 100, 0, 0]
	var units_a: Array[int] = [0, 1, 30, 0, 30, 30, 0, 1]
	report.add_think(_fake_record(a, units_a, 400, 3))
	report.add_think(_fake_record(b, units_a, 800, 5))
	assert_eq(report.think_count(), 2)
	var probe: Dictionary = report.phase_stats(BotThink.Phase.PROBE)
	assert_almost_eq(probe["mean_us"] as float, 800.0, 0.001)
	assert_almost_eq(probe["max_us"] as float, 1000.0, 0.001)
	assert_almost_eq(probe["p95_us"] as float, 1000.0, 0.001)
	assert_almost_eq(probe["p50_us"] as float, 600.0, 0.001)
	assert_almost_eq(probe["us_per_unit"] as float, 1600.0 / 60.0, 0.001)
	var share_sum: float = 0.0
	for phase: int in range(BotThinkCostReport.PHASE_COUNT):
		share_sum += report.phase_stats(phase)["share_pct"] as float
	assert_almost_eq(share_sum, 100.0, PERCENT_TOLERANCE)
	var split: Dictionary = report.probe_split()
	assert_almost_eq(split["call_mean_us"] as float, 600.0, 0.001)
	assert_almost_eq(split["rest_mean_us"] as float, 200.0, 0.001)
	assert_eq(report.ranking()[0], BotThink.Phase.PROBE, "PROBE is the most expensive phase")
	assert_almost_eq(report.latency_stats()["ticks_mean"] as float, 4.0, 0.001)
	assert_almost_eq(report.outside_stats()["build_mean_us"] as float, 100.0, 0.001)
	var lines: PackedStringArray = report.render_lines()
	assert_true(lines[0].begins_with("BOT_THINK_COST scenario=t summary thinks=2"))
	assert_eq(lines.size(), BotThinkCostReport.PHASE_COUNT + 7, "summary, phases, probe, outside, latency, frame, fill fallback, ranking")
	assert_true(lines[lines.size() - 1].contains("ranking PROBE="))


func test_collector_windows_per_slot_and_aggregate() -> void:
	assert_null(BotThinkCostCollector.current(), "off until enabled")
	var collector: BotThinkCostCollector = BotThinkCostCollector.enable("t", SMALL_WINDOW)
	assert_same(BotThinkCostCollector.current(), collector)
	assert_false(collector.has_data(), "no data before the first think")
	var us: Array[int] = [0, 1, 1, 0, 1, 1, 0, 1]
	for i: int in range(3):
		collector.record_think(FAKE_SLOT_A, _fake_record(us, us, 1, i))
	collector.record_think(FAKE_SLOT_B, _fake_record(us, us, 1, 0))
	collector.record_frame(FAKE_SLOT_A, 100)
	assert_true(collector.has_data())
	assert_eq(collector.for_slot(FAKE_SLOT_A).think_count(), SMALL_WINDOW, "rolling window keeps the last N")
	assert_eq(collector.for_slot(FAKE_SLOT_B).think_count(), 1)
	assert_eq(collector.aggregate().think_count(), SMALL_WINDOW, "aggregate window too")
	assert_eq(collector.slot_ids(), PackedInt32Array([FAKE_SLOT_A, FAKE_SLOT_B]))
	assert_false(collector.for_slot(99).has_data(), "an unknown slot is an empty report")
	BotThinkCostCollector.disable()
	assert_null(BotThinkCostCollector.current())


func test_enable_and_controller_setup_start_clean() -> void:
	var us: Array[int] = [0, 1, 1, 0, 1, 1, 0, 1]
	var first: BotThinkCostCollector = BotThinkCostCollector.enable("a", SMALL_WINDOW)
	first.record_think(FAKE_SLOT_A, _fake_record(us, us, 1, 0))
	assert_true(first.has_data())
	var second: BotThinkCostCollector = BotThinkCostCollector.enable("b", SMALL_WINDOW)
	assert_false(second.has_data(), "a new enable() starts empty")
	second.record_think(FAKE_SLOT_A, _fake_record(us, us, 1, 0))
	assert_true(BotThinkCostCollector.enable("c", SMALL_WINDOW, true).has_data(), "keep_data leaves it alone")
	var controller: BotController = BotController.new()
	add_child_autofree(controller)
	controller.setup(FAKE_SLOT_A, MatchConfig.AiDifficulty.HARD, null, null)
	assert_false(BotThinkCostCollector.current().has_data(), "match B's bot setup drops match A's data")


func test_full_window_overwrites_oldest_in_a_ring() -> void:
	var report: BotThinkCostReport = BotThinkCostReport.new("r", SMALL_WINDOW)
	var us: Array[int] = [0, 1, 1, 0, 1, 1, 0, 1]
	for i: int in range(5):
		report.add_think(_fake_record(us, us, 1, i))
		report.add_frame(i)
	assert_eq(report.think_count(), SMALL_WINDOW)
	assert_almost_eq(report.latency_stats()["ticks_mean"] as float, 3.5, 0.001, "keeps the last two (3 and 4)")
	assert_lte(report.frame_count(), SMALL_WINDOW * BotThinkCostReport.SHIPPED_TUNING.frames_per_think)


## Bontago-1t5.67: the zero-targeted FILL fallback counter.
func _fallback_record(zero_targeted: bool) -> Dictionary:
	var think: BotThink = _think(true)
	if zero_targeted:
		var none: BotGenTuning = (load("res://config/bot_gen_tuning.tres") as BotGenTuning).duplicate() as BotGenTuning
		none.tip_share = 0.0
		none.stack_share = 0.0
		none.tower_tip_share = 0.0
		none.tower_stack_share = 0.0
		none.area_tip_share = 0.0
		none.area_stack_share = 0.0
		think.gen_tuning = none
	assert_true(think.step(BIG_BUDGET_US, _probe))
	return think.stats_record()


func test_zero_targeted_think_marks_the_fill_fallback() -> void:
	var record: Dictionary = _fallback_record(true)
	assert_eq(record["fill_fallback"], 1, "fallback ran")
	assert_gt(record["fill_fallback_sites"] as int, 0, "and produced FILL sites")


func test_normal_think_does_not_mark_the_fill_fallback() -> void:
	var record: Dictionary = _fallback_record(false)
	assert_eq(record["fill_fallback"], 0)
	assert_eq(record["fill_fallback_sites"], 0)


func test_report_counts_fill_fallbacks_per_slot_and_aggregate() -> void:
	var collector: BotThinkCostCollector = BotThinkCostCollector.enable("t", 0)
	var phases: Array[int] = [1, 1, 1, 1, 1, 1, 1, 1]
	var units: Array[int] = [1, 1, 1, 1, 1, 1, 1, 1]
	var hit: Dictionary = _fake_record(phases, units, 1, 1)
	hit["fill_fallback"] = 1
	hit["fill_fallback_sites"] = 7
	var miss: Dictionary = _fake_record(phases, units, 1, 1)
	collector.record_think(FAKE_SLOT_A, hit)
	collector.record_think(FAKE_SLOT_A, miss)
	collector.record_think(FAKE_SLOT_B, miss)
	collector.record_think(FAKE_SLOT_B, miss)
	var all: Dictionary = collector.aggregate().fill_fallback_stats()
	assert_eq(all["count"], 1)
	assert_eq(all["thinks"], 4)
	assert_eq(all["sites"], 7)
	assert_almost_eq(all["share_pct"] as float, 25.0, PERCENT_TOLERANCE)
	assert_eq(collector.for_slot(FAKE_SLOT_A).fill_fallback_stats()["count"], 1)
	assert_eq(collector.for_slot(FAKE_SLOT_B).fill_fallback_stats()["count"], 0)
	var found: bool = false
	for line: String in collector.aggregate().render_lines():
		found = found or line.contains("fill_fallback count=1 thinks=4")
	assert_true(found, "BOT_THINK_COST report line")
