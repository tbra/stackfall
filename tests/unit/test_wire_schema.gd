extends GutTest
## WireSchema table tests (Bontago-fca.36.6) plus the accept/reject tables of the
## migrated sites (breeze gust, snow state header, weather state).

func _schema() -> Dictionary:
	return {
		"i": WireSchema.int_field(1, 9),
		"n": WireSchema.number_field(-2.0, 2.0),
		"p": WireSchema.number_field(-INF, 5.0, 0.0),
		"s": WireSchema.string_field(4),
		"a": WireSchema.int_array_field(3),
	}


func _good() -> Dictionary:
	return {"i": 3, "n": 1, "p": 2.5, "s": &"abc", "a": PackedInt32Array([1, 2])}


func test_good_payload_is_normalised() -> void:
	var out: Dictionary = WireSchema.sanitize(_good(), _schema())
	assert_eq(out["i"], 3)
	assert_eq(typeof(out["n"]), TYPE_FLOAT, "int number becomes float")
	assert_eq(typeof(out["s"]), TYPE_STRING)
	assert_eq(out.size(), 5)


func test_non_dictionary_payloads_are_rejected() -> void:
	for bad: Variant in [null, "x", 5, [1], PackedInt32Array([1]), 1.5]:
		assert_true(WireSchema.sanitize(bad, _schema()).is_empty(), "rejects %s" % [bad])


func test_missing_and_extra_keys_are_rejected() -> void:
	var extra: Dictionary = _good()
	extra["z"] = 1
	assert_true(WireSchema.sanitize(extra, _schema()).is_empty())
	var missing: Dictionary = _good()
	missing.erase("s")
	assert_true(WireSchema.sanitize(missing, _schema()).is_empty())
	var renamed: Dictionary = _good()
	renamed.erase("s")
	renamed["q"] = "abc"
	assert_true(WireSchema.sanitize(renamed, _schema()).is_empty(), "same size, wrong key")


func test_field_table() -> void:
	var table: Array = [
		["i", 0, false], ["i", 1, true], ["i", 9, true], ["i", 10, false], ["i", 1.0, false], ["i", "3", false], ["i", true, false],
		["n", 2.0, true], ["n", -2.1, false], ["n", INF, false], ["n", -INF, false], ["n", NAN, false], ["n", "1", false], ["n", null, false],
		["p", 0.0, false], ["p", 0.001, true], ["p", 5.0, true], ["p", 5.1, false], ["p", -1.0, false],
		["s", "", true], ["s", "abcd", true], ["s", "abcde", false], ["s", 5, false],
		["a", PackedInt32Array(), true], ["a", PackedInt32Array([1, 2, 3]), true], ["a", PackedInt32Array([1, 2, 3, 4]), false],
		["a", [1, 2], false], ["a", PackedFloat32Array([1.0]), false],
	]
	for row: Array in table:
		var payload: Dictionary = _good()
		payload[row[0]] = row[1]
		var accepted: bool = not WireSchema.sanitize(payload, _schema()).is_empty()
		assert_eq(accepted, bool(row[2]), "%s=%s" % [row[0], row[1]])


# --- Migrated sites ---------------------------------------------------------------------

func test_snow_state_header_table() -> void:
	var tuning: SnowTuning = SnowTuning.new()
	var good: Dictionary = SnowGeometry.make_state(7, 1, PackedInt32Array(), PackedInt32Array())
	assert_false(SnowGeometry.sanitize_state(good, tuning, 10).is_empty())
	var cases: Array = [
		["v", 1], ["v", "2"], ["seed", 1.5], ["c", -1], ["c", tuning.depth_levels + 1],
		["b", PackedFloat32Array()], ["d", [1, 2]],
	]
	for row: Array in cases:
		var state: Dictionary = good.duplicate()
		state[row[0]] = row[1]
		assert_true(SnowGeometry.sanitize_state(state, tuning, 10).is_empty(), "rejects %s=%s" % [row[0], row[1]])
	var oversized: Dictionary = good.duplicate()
	oversized["d"] = PackedInt32Array(range(tuning.max_disc_patches * 2 + 2))
	assert_true(SnowGeometry.sanitize_state(oversized, tuning, 100000).is_empty(), "oversized disc array")
	var extra: Dictionary = good.duplicate()
	extra["x"] = 1
	assert_true(SnowGeometry.sanitize_state(extra, tuning, 10).is_empty())


func test_weather_wire_table() -> void:
	var weather: MatchWeather = MatchWeather.new()
	var good: Dictionary = {"v": MatchWeather.WIRE_VERSION, "epoch": 1, "seed": 5, "mode": 0, "sched": 0,
		"left": 0.0, "id": "", "phase": WeatherTuning.Phase.RAMP_IN, "t": 0.0, "ev": 0}
	assert_false(weather.sanitize_wire_state(good).is_empty())
	var bad_values: Array = [
		["v", 99], ["epoch", -1], ["seed", 1.0], ["mode", 99], ["sched", 99], ["phase", 99], ["ev", -1],
		["left", -1.0], ["left", NAN], ["left", INF], ["t", 1.0e9], ["t", "0"], ["id", 5],
		["id", "x".repeat(MatchWeather.WIRE_MAX_ID_LENGTH + 1)], ["id", "storm"],
	]
	for row: Array in bad_values:
		var state: Dictionary = good.duplicate()
		state[row[0]] = row[1]
		assert_true(weather.sanitize_wire_state(state).is_empty(), "rejects %s=%s" % [row[0], row[1]])
	var extra: Dictionary = good.duplicate()
	extra["x"] = 1
	assert_true(weather.sanitize_wire_state(extra).is_empty())


func test_weather_ids_have_one_owner() -> void:
	assert_eq(BreezeEffect.QUIET_WEATHER_ID, WeatherIds.STORM)
	var ceiling: WeatherCeilingTuning = WeatherCeilingTuning.new()
	assert_eq(ceiling.storm_id, WeatherIds.STORM)
	assert_true(ceiling.weather_ids.has(WeatherIds.RAIN) and ceiling.weather_ids.has(WeatherIds.SNOW))


func test_breeze_gust_table() -> void:
	var tuning: BreezeTuning = BreezeTuning.new()
	var good: Dictionary = {"id": 1, "x": 1.0, "y": 8.0, "z": -2.0, "a": 1.2, "r": 3.0, "d": 3.0, "s": 0.8}
	assert_false(BreezeNet.sanitize_gust(good, tuning).is_empty(), "valid")
	var missing: Dictionary = good.duplicate()
	missing.erase("d")
	assert_true(BreezeNet.sanitize_gust(missing, tuning).is_empty(), "missing key")
	var bad: Array = [["x", "1"], ["id", 1.0], ["s", null], ["x", NAN], ["y", INF], ["r", 0.0],
		["r", tuning.wire_max_radius_m + 1.0], ["d", tuning.wire_max_duration_s + 1.0],
		["x", tuning.wire_max_coord_m + 1.0], ["s", 1.1], ["id", 0]]
	for row: Array in bad:
		var gust: Dictionary = good.duplicate()
		gust[row[0]] = row[1]
		assert_true(BreezeNet.sanitize_gust(gust, tuning).is_empty(), "rejects %s=%s" % [row[0], row[1]])
	var edge: Dictionary = good.duplicate()
	edge["x"] = tuning.wire_max_coord_m
	edge["r"] = tuning.wire_max_radius_m
	edge["d"] = tuning.wire_max_duration_s
	edge["s"] = 1.0
	assert_false(BreezeNet.sanitize_gust(edge, tuning).is_empty(), "limits are inclusive")


func test_snow_state_maximum_size_is_accepted() -> void:
	var tuning: SnowTuning = SnowTuning.new()
	var blocks: PackedInt32Array = PackedInt32Array()
	# One patch per block: the largest block array the budget allows (5 ints worth per patch).
	for net_id: int in range(1, tuning.max_block_patches + 1):
		SnowGeometry.append_block_record(blocks, net_id, 0, PackedInt32Array([0]), PackedInt32Array([1]))
	var disc: PackedInt32Array = PackedInt32Array()
	for cell: int in range(tuning.max_disc_patches):
		disc.append(cell)
		disc.append(1)
	var state: Dictionary = SnowGeometry.make_state(3, tuning.depth_levels, blocks, disc)
	var out: Dictionary = SnowGeometry.sanitize_state(state, tuning, tuning.max_disc_patches)
	assert_false(out.is_empty(), "maximum-size state")
	assert_eq((out["blocks"] as Dictionary).size(), tuning.max_block_patches)
	assert_eq((out["disc"] as Dictionary).size(), tuning.max_disc_patches)
