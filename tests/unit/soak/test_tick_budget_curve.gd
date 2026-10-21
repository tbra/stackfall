extends GutTest
## TickBudgetCurve keeps one fixed-bucket histogram of tick cost per body-count band
## (SOAK_PLAN section 7.2). Costs are recorded in the middle of a bucket so every assertion
## holds whether a statistic reports the bucket's lower edge, middle or upper edge.

const BUDGET_MS: float = 1000.0 / 60.0
const KEYS: Array[String] = ["ticks", "bodies_mean", "p50_ms", "p99_ms", "max_ms", "over"]

var _config: SoakConfig = load("res://config/soak/soak_config.tres") as SoakConfig


func _curve() -> TickBudgetCurve:
	return TickBudgetCurve.new(
		_config.curve_bands,
		_config.curve_band_half_width_fraction,
		BUDGET_MS,
		_config.curve_bucket_ms,
		_config.curve_max_ms
	)


func _fill(curve: TickBudgetCurve, bodies: int, ticks: int, cost_ms: float) -> void:
	for _i: int in ticks:
		curve.record(cost_ms, bodies)


func _ticks(curve: TickBudgetCurve, band: int) -> int:
	return int(curve.band_stats(band).get("ticks", -1))


func test_the_bands_are_the_configured_centres_in_order() -> void:
	assert_eq(_curve().bands(), PackedInt32Array([250, 500, 1000, 1500]))
	var odd: TickBudgetCurve = TickBudgetCurve.new(
		PackedInt32Array([1500, 250, 700]), 0.1, BUDGET_MS, 0.1, 100.0
	)
	assert_eq(odd.bands(), PackedInt32Array([1500, 250, 700]), "Construction order is kept.")


func test_the_over_budget_threshold_is_the_constructor_argument() -> void:
	assert_almost_eq(_curve().budget_ms, BUDGET_MS, 0.0001)


func test_a_band_with_no_tick_has_every_statistic_zero() -> void:
	var stats: Dictionary = _curve().band_stats(1000)
	for key: String in KEYS:
		assert_true(stats.has(key), "band_stats has %s." % key)
		assert_almost_eq(float(stats.get(key, -1.0)), 0.0, 0.0001, "%s of an empty band" % key)


func test_a_tick_is_counted_in_its_own_band_only() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 7, 5.05)
	_fill(curve, 250, 3, 5.05)
	assert_eq(_ticks(curve, 1000), 7)
	assert_eq(_ticks(curve, 250), 3)
	assert_eq(_ticks(curve, 500), 0)
	assert_eq(_ticks(curve, 1500), 0)


func test_bodies_just_inside_the_band_edges_belong_to_it() -> void:
	# Band 1000 with a 0.15 half width spans 850 .. 1150 bodies.
	var curve: TickBudgetCurve = _curve()
	for bodies: int in [851, 1000, 1149]:
		curve.record(5.05, bodies)
	assert_eq(_ticks(curve, 1000), 3)


func test_bodies_just_outside_the_band_edges_do_not_belong_to_it() -> void:
	var curve: TickBudgetCurve = _curve()
	for bodies: int in [849, 1151]:
		curve.record(5.05, bodies)
	assert_eq(_ticks(curve, 1000), 0)


func test_the_band_width_comes_from_the_half_width_fraction() -> void:
	var narrow: TickBudgetCurve = TickBudgetCurve.new(PackedInt32Array([1000]), 0.05, BUDGET_MS, 0.1, 100.0)
	for bodies: int in [940, 960, 1040, 1060]:
		narrow.record(5.05, bodies)
	assert_eq(_ticks(narrow, 1000), 2, "Only 960 and 1040 are within 5 % of 1000.")
	var wide: TickBudgetCurve = TickBudgetCurve.new(PackedInt32Array([1000]), 0.3, BUDGET_MS, 0.1, 100.0)
	for bodies: int in [710, 1290, 690, 1310]:
		wide.record(5.05, bodies)
	assert_eq(_ticks(wide, 1000), 2, "Only 710 and 1290 are within 30 % of 1000.")


func test_a_tick_outside_every_band_is_dropped() -> void:
	var curve: TickBudgetCurve = _curve()
	for bodies: int in [0, 100, 380, 700, 1260, 5000]:
		curve.record(5.05, bodies)
	for band: int in curve.bands():
		assert_eq(_ticks(curve, band), 0, "band %d" % band)


func test_a_band_counts_ticks_across_its_whole_span() -> void:
	var curve: TickBudgetCurve = _curve()
	curve.record(5.05, 430)
	curve.record(5.05, 570)
	curve.record(5.05, 500)
	assert_eq(_ticks(curve, 500), 3)


func test_bodies_mean_is_the_average_tracked_count_of_the_band() -> void:
	var curve: TickBudgetCurve = _curve()
	curve.record(5.05, 980)
	curve.record(5.05, 1000)
	curve.record(5.05, 1020)
	curve.record(5.05, 1000)
	assert_eq(int(curve.band_stats(1000).get("bodies_mean", -1)), 1000)
	var lopsided: TickBudgetCurve = _curve()
	lopsided.record(5.05, 860)
	lopsided.record(5.05, 1140)
	lopsided.record(5.05, 1100)
	lopsided.record(5.05, 940)
	assert_eq(int(lopsided.band_stats(1000).get("bodies_mean", -1)), 1010)


func test_p50_and_p99_of_a_flat_band_are_that_cost() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 500, 800, 7.05)
	var stats: Dictionary = curve.band_stats(500)
	assert_almost_eq(float(stats.get("p50_ms", -1.0)), 7.05, 0.1)
	assert_almost_eq(float(stats.get("p99_ms", -1.0)), 7.05, 0.1)
	assert_almost_eq(float(stats.get("max_ms", -1.0)), 7.05, 0.1)


func test_p99_ignores_the_slowest_one_percent() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 999, 1.05)
	curve.record(50.05, 1000)
	var stats: Dictionary = curve.band_stats(1000)
	assert_almost_eq(float(stats.get("p99_ms", -1.0)), 1.05, 0.1, "1 slow tick in 1000 is under 1 %.")
	assert_almost_eq(float(stats.get("max_ms", -1.0)), 50.05, 0.1, "The max still sees it.")


func test_p99_sees_a_slow_tail_of_two_percent() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 980, 1.05)
	_fill(curve, 1000, 20, 50.05)
	var stats: Dictionary = curve.band_stats(1000)
	assert_almost_eq(float(stats.get("p99_ms", -1.0)), 50.05, 0.1)
	assert_almost_eq(float(stats.get("p50_ms", -1.0)), 1.05, 0.1)


func test_percentiles_of_a_known_uniform_distribution() -> void:
	# 100 ticks at 0.05, 0.15 ... 9.95 ms: the 50th smallest is 4.95 and the 99th is 9.85.
	var curve: TickBudgetCurve = _curve()
	for i: int in 100:
		curve.record(0.05 + 0.1 * float(i), 250)
	var stats: Dictionary = curve.band_stats(250)
	assert_eq(int(stats.get("ticks", -1.0)), 100)
	assert_almost_eq(float(stats.get("p50_ms", -1.0)), 4.95, 0.16)
	assert_almost_eq(float(stats.get("p99_ms", -1.0)), 9.85, 0.16)
	assert_almost_eq(float(stats.get("max_ms", -1.0)), 9.95, 0.16)


func test_recording_order_does_not_change_the_statistics() -> void:
	var ascending: TickBudgetCurve = _curve()
	var descending: TickBudgetCurve = _curve()
	for i: int in 100:
		ascending.record(0.05 + 0.1 * float(i), 1500)
		descending.record(0.05 + 0.1 * float(99 - i), 1500)
	assert_eq(ascending.band_stats(1500), descending.band_stats(1500))


func test_percentiles_are_kept_per_band() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 250, 700, 2.05)
	_fill(curve, 1500, 700, 30.05)
	assert_almost_eq(float(curve.band_stats(250).get("p99_ms", -1.0)), 2.05, 0.1)
	assert_almost_eq(float(curve.band_stats(1500).get("p99_ms", -1.0)), 30.05, 0.1)


func test_over_counts_the_ticks_above_the_budget() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 10, 10.05)
	_fill(curve, 1000, 3, 20.05)
	_fill(curve, 1000, 2, 80.05)
	var stats: Dictionary = curve.band_stats(1000)
	assert_eq(int(stats.get("over", -1.0)), 5)
	assert_eq(int(stats.get("ticks", -1.0)), 15)


func test_over_is_zero_when_every_tick_is_cheap() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 50, 16.55)
	assert_eq(int(curve.band_stats(1000).get("over", -1.0)), 0)


func test_over_follows_the_constructor_budget() -> void:
	var strict: TickBudgetCurve = TickBudgetCurve.new(
		_config.curve_bands, 0.15, 5.0, _config.curve_bucket_ms, _config.curve_max_ms
	)
	_fill(strict, 1000, 4, 10.05)
	assert_eq(int(strict.band_stats(1000).get("over", -1.0)), 4)


func test_a_huge_tick_is_clamped_into_the_top_bucket() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 2, 1.0e9)
	var stats: Dictionary = curve.band_stats(1000)
	assert_eq(int(stats.get("ticks", -1.0)), 2, "A huge tick is still counted.")
	var top: float = _config.curve_max_ms
	assert_between(float(stats.get("p99_ms", -1.0)), top - 2.0 * _config.curve_bucket_ms, top + _config.curve_bucket_ms)
	assert_gte(float(stats.get("max_ms", -1.0)), top - 2.0 * _config.curve_bucket_ms)
	assert_eq(int(stats.get("over", -1.0)), 2)


func test_a_tick_at_the_max_cost_lands_in_the_top_bucket() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 20, _config.curve_max_ms)
	var stats: Dictionary = curve.band_stats(1000)
	assert_eq(int(stats.get("ticks", -1.0)), 20)
	assert_between(
		float(stats.get("p99_ms", -1.0)),
		_config.curve_max_ms - 2.0 * _config.curve_bucket_ms,
		_config.curve_max_ms + _config.curve_bucket_ms
	)


func test_a_rare_huge_tick_does_not_move_the_percentiles() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 1000, 5.05)
	curve.record(1.0e6, 1000)
	var stats: Dictionary = curve.band_stats(1000)
	assert_almost_eq(float(stats.get("p99_ms", -1.0)), 5.05, 0.1)
	assert_eq(int(stats.get("ticks", -1.0)), 1001)


func test_the_bucket_width_sets_the_resolution() -> void:
	var coarse: TickBudgetCurve = TickBudgetCurve.new(PackedInt32Array([1000]), 0.15, BUDGET_MS, 5.0, 100.0)
	_fill(coarse, 1000, 200, 12.5)
	assert_almost_eq(float(coarse.band_stats(1000).get("p99_ms", -1.0)), 12.5, 5.0)
	var fine: TickBudgetCurve = TickBudgetCurve.new(PackedInt32Array([1000]), 0.15, BUDGET_MS, 0.01, 100.0)
	_fill(fine, 1000, 200, 12.505)
	assert_almost_eq(float(fine.band_stats(1000).get("p99_ms", -1.0)), 12.505, 0.011)


func test_the_max_cost_sets_the_top_bucket() -> void:
	var small: TickBudgetCurve = TickBudgetCurve.new(PackedInt32Array([1000]), 0.15, BUDGET_MS, 0.1, 10.0)
	_fill(small, 1000, 200, 500.0)
	assert_between(float(small.band_stats(1000).get("p99_ms", -1.0)), 9.7, 10.1)


func test_a_tick_exactly_on_a_band_edge_belongs_to_the_band() -> void:
	# "Within" the fraction is inclusive: a 25 % band around 100 spans 75 .. 125 bodies.
	var curve: TickBudgetCurve = TickBudgetCurve.new(PackedInt32Array([100]), 0.25, BUDGET_MS, 0.1, 100.0)
	for bodies: int in [75, 125]:
		curve.record(5.05, bodies)
	assert_eq(_ticks(curve, 100), 2)
	for bodies: int in [74, 126]:
		curve.record(5.05, bodies)
	assert_eq(_ticks(curve, 100), 2, "One body further out is in no band.")


func test_a_tick_exactly_on_the_budget_is_not_over() -> void:
	# Over budget is "above" the threshold; 16 ms and 8 ms are exact in binary.
	var curve: TickBudgetCurve = TickBudgetCurve.new(PackedInt32Array([1000]), 0.15, 16.0, 0.1, 100.0)
	_fill(curve, 1000, 5, 16.0)
	assert_eq(int(curve.band_stats(1000).get("over", -1)), 0)
	_fill(curve, 1000, 3, 16.5)
	assert_eq(int(curve.band_stats(1000).get("over", -1)), 3)


func test_two_ticks_split_the_median_and_the_tail() -> void:
	var curve: TickBudgetCurve = _curve()
	curve.record(1.05, 1000)
	curve.record(50.05, 1000)
	var stats: Dictionary = curve.band_stats(1000)
	assert_lt(float(stats.get("p50_ms", 99.0)), 30.0, "The median is not the slow tick.")
	assert_almost_eq(float(stats.get("p99_ms", 0.0)), 50.05, 0.1, "The tail of two is the slow tick.")


func test_one_tick_is_every_percentile() -> void:
	var curve: TickBudgetCurve = _curve()
	curve.record(8.05, 250)
	var stats: Dictionary = curve.band_stats(250)
	assert_almost_eq(float(stats.get("p50_ms", 0.0)), 8.05, 0.1)
	assert_almost_eq(float(stats.get("p99_ms", 0.0)), 8.05, 0.1)
	assert_almost_eq(float(stats.get("max_ms", 0.0)), 8.05, 0.1)


func test_ticks_cheaper_than_one_bucket_read_back_as_that_cheap() -> void:
	# 60 ticks of 0.05 ms and 40 of 5 ms: the median is one of the cheap ones.
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 60, 0.05)
	_fill(curve, 1000, 40, 5.05)
	assert_almost_eq(float(curve.band_stats(1000).get("p50_ms", 99.0)), 0.05, 0.1)


func test_a_clamped_tick_reads_back_in_the_bucket_holding_the_cap() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 50, 1.0e9)
	var p99: float = float(curve.band_stats(1000).get("p99_ms", 0.0))
	assert_between(p99, _config.curve_max_ms - 0.6 * _config.curve_bucket_ms, _config.curve_max_ms + _config.curve_bucket_ms)


func test_a_histogram_with_a_single_bucket_still_reports() -> void:
	# max_ms equal to one bucket leaves a single bucket; everything lands in it.
	var curve: TickBudgetCurve = TickBudgetCurve.new(PackedInt32Array([1000]), 0.15, BUDGET_MS, 0.1, 0.1)
	_fill(curve, 1000, 100, 50.0)
	var stats: Dictionary = curve.band_stats(1000)
	assert_eq(int(stats.get("ticks", -1)), 100)
	assert_between(float(stats.get("p99_ms", 0.0)), 0.04, 0.11)
