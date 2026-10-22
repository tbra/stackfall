extends GutTest
## SoakLine is the only place a soak log line is formatted (SOAK_PLAN section 7.1). The golden
## fixture holds one example per tag; tools/ parses the same text, so the bytes matter.

const FIXTURE_PATH: String = "res://tests/unit/soak/fixtures/soak_lines.txt"
const TAGS: Array[String] = [
	"SOAK_CONFIG",
	"SOAK_SAMPLE",
	"SOAK_BODY",
	"SOAK_FUZZ",
	"SOAK_VIOLATION",
	"SOAK_CURVE",
	"SOAK_END",
]

var _config: SoakConfig = load("res://config/soak/soak_config.tres") as SoakConfig


func _golden() -> Dictionary:
	var lines: Dictionary = {}
	for line: String in FileAccess.get_file_as_string(FIXTURE_PATH).split("\n", false):
		var text: String = line.strip_edges()
		if text.is_empty():
			continue
		lines[text.get_slice(" ", 0)] = text
	return lines


## A line as tools/ reads it: the tag, then each token split on its first `=`, in order.
func _parse(line: String) -> Dictionary:
	var tokens: PackedStringArray = line.split(" ")
	var keys: Array[String] = []
	var values: Dictionary = {}
	for i: int in range(1, tokens.size()):
		var at: int = tokens[i].find("=")
		var key: String = tokens[i].substr(0, at)
		keys.append(key)
		values[key] = tokens[i].substr(at + 1)
	return {"tag": tokens[0], "keys": keys, "values": values}


func _violation() -> SoakCheck.Violation:
	var violation: SoakCheck.Violation = SoakCheck.Violation.new()
	violation.invariant = &"physics.below_kill_plane"
	violation.severity = SoakCheck.SEVERITY_FAIL
	violation.subject = "1204"
	violation.value = -41.2
	violation.limit = -39.0
	violation.detail = "owner=3"
	return violation


func test_the_fixture_has_one_line_per_tag() -> void:
	var golden: Dictionary = _golden()
	assert_eq(golden.size(), TAGS.size())
	for tag: String in TAGS:
		assert_true(golden.has(tag), "fixture has %s." % tag)


func test_violation_matches_the_golden_line() -> void:
	var line: String = SoakLine.violation(_violation(), &"host", 353000001, 1766000005000, 312.4)
	assert_eq(line, _golden().get("SOAK_VIOLATION", "missing"))


func test_sample_matches_the_golden_line() -> void:
	# Passed in a scrambled order: the line sorts the keys after `role epoch wall_ms`.
	var fields: Dictionary = {
		"timer": -1.0,
		"state": &"PLAYING",
		"shares": [0.31, 0.28],
		"scores": {0: 41, 1: 39},
		"raster_hash": 123456,
		"orphans": 0,
		"nodes": 9120,
		"mt": 312.4,
		"mon_us": 412,
		"mem_mb": 412.3,
		"bytes_total": 88123456,
		"bodies": 512,
		"awake": 3,
	}
	var line: String = SoakLine.sample(&"host", 353000001, 1766000005000, fields)
	assert_eq(line, _golden().get("SOAK_SAMPLE", "missing"))


func test_body_matches_the_golden_line() -> void:
	var line: String = SoakLine.body(
		&"host", 353000001, 1204, Vector3(-3.125, 0.5, 8.0), Quaternion.IDENTITY, true
	)
	assert_eq(line, _golden().get("SOAK_BODY", "missing"))


func test_fuzz_matches_the_golden_line() -> void:
	var line: String = SoakLine.fuzz(&"client", 17, &"STALE_SEQ", 1)
	assert_eq(line, _golden().get("SOAK_FUZZ", "missing"))


func test_curve_matches_the_golden_line() -> void:
	var stats: Dictionary = {
		"ticks": 5400, "bodies_mean": 1003, "p50_ms": 9.1, "p99_ms": 17.9, "max_ms": 24.0, "over": 212
	}
	var line: String = SoakLine.curve(&"client", 1000, stats, 16.67)
	assert_eq(line, _golden().get("SOAK_CURVE", "missing"))


func test_config_matches_the_golden_line() -> void:
	var line: String = SoakLine.config_line(&"host", &"load", _config)
	assert_eq(line, _golden().get("SOAK_CONFIG", "missing"))


func test_end_matches_the_golden_line() -> void:
	var fields: Dictionary = {
		"violations": 0,
		"sim_rate": 60.0,
		"samples": 180,
		"mem_start_mb": 210.2,
		"mem_end_mb": 980.5,
		"bodies_start": 0,
		"bodies_end": 1480,
	}
	var line: String = SoakLine.end(&"host", fields)
	assert_eq(line, _golden().get("SOAK_END", "missing"))


func test_a_warning_violation_says_warn() -> void:
	var violation: SoakCheck.Violation = _violation()
	violation.severity = SoakCheck.SEVERITY_WARN
	var parsed: Dictionary = _parse(SoakLine.violation(violation, &"client", 5, 6, 7.5))
	assert_eq(parsed["values"].get("sev"), "warn")
	assert_eq(parsed["values"].get("role"), "client")
	assert_eq(parsed["values"].get("epoch"), "5")
	assert_eq(parsed["values"].get("wall_ms"), "6")
	assert_eq(parsed["values"].get("mt"), "7.5000")


func test_a_violation_leads_with_its_invariant_and_a_value_may_hold_an_equals_sign() -> void:
	var parsed: Dictionary = _parse(SoakLine.violation(_violation(), &"host", 1, 2, 3.0))
	var keys: Array[String] = parsed["keys"]
	assert_eq(parsed["tag"], "SOAK_VIOLATION")
	assert_gt(keys.size(), 1)
	if keys.size() < 2:
		return
	assert_eq(keys[0], "inv")
	assert_eq(keys[1], "role")
	assert_eq(parsed["values"].get("detail"), "owner=3", "Split on the first = only.")


func test_a_space_in_free_text_becomes_an_underscore() -> void:
	var violation: SoakCheck.Violation = _violation()
	violation.subject = "slot 3"
	violation.detail = "two words here"
	var line: String = SoakLine.violation(violation, &"host", 1, 2, 3.0)
	var parsed: Dictionary = _parse(line)
	assert_eq(parsed["values"].get("subject"), "slot_3")
	assert_eq(parsed["values"].get("detail"), "two_words_here")
	assert_false(line.contains("  "), "No empty token.")
	assert_false(line.contains("\n"), "One line.")


func test_sample_keys_after_the_header_are_sorted() -> void:
	var fields: Dictionary = {"zeta": 1, "alpha": 2, "mid": 3, "beta": 4}
	var parsed: Dictionary = _parse(SoakLine.sample(&"client", 9, 10, fields))
	var keys: Array[String] = parsed["keys"]
	assert_eq(keys.slice(0, 3), ["role", "epoch", "wall_ms"] as Array[String])
	assert_eq(keys.slice(3), ["alpha", "beta", "mid", "zeta"] as Array[String])
	assert_eq(parsed["values"].get("zeta"), "1")
	assert_eq(parsed["values"].get("alpha"), "2")


func test_sample_with_no_extra_fields_is_just_the_header() -> void:
	var parsed: Dictionary = _parse(SoakLine.sample(&"host", 3, 4, {}))
	assert_eq(parsed["tag"], "SOAK_SAMPLE")
	assert_eq(parsed["keys"], ["role", "epoch", "wall_ms"] as Array[String])


func test_end_keys_after_role_are_sorted() -> void:
	var fields: Dictionary = {"violations": 2, "bodies_end": 7, "samples": 9, "mem_end_mb": 1.0}
	var parsed: Dictionary = _parse(SoakLine.end(&"client", fields))
	var keys: Array[String] = parsed["keys"]
	assert_eq(parsed["tag"], "SOAK_END")
	assert_gt(keys.size(), 0)
	if keys.is_empty():
		return
	assert_eq(keys[0], "role")
	assert_eq(keys.slice(1), ["bodies_end", "mem_end_mb", "samples", "violations"] as Array[String])


func test_value_types_are_written_as_the_plan_says() -> void:
	var fields: Dictionary = {
		"a_int": -7,
		"b_float": 0.5,
		"c_true": true,
		"d_false": false,
		"e_vec": Vector3(1.0, -2.5, 3.0),
		"f_quat": Quaternion(0.0, 0.5, 0.0, 1.0),
		"g_text": "two words",
		"h_ints": [1, 2, 3],
		"i_floats": [0.5, 1.0],
		"j_dict": {0: 41, 1: 39},
		"k_round": 0.00006,
	}
	var values: Dictionary = _parse(SoakLine.sample(&"host", 1, 2, fields))["values"]
	assert_eq(values.get("a_int"), "-7")
	assert_eq(values.get("b_float"), "0.5000")
	assert_eq(values.get("c_true"), "1")
	assert_eq(values.get("d_false"), "0")
	assert_eq(values.get("e_vec"), "1.0000,-2.5000,3.0000")
	assert_eq(values.get("f_quat"), "0.00000000,0.50000000,0.00000000,1.00000000")
	assert_eq(values.get("g_text"), "two_words")
	assert_eq(values.get("h_ints"), "1;2;3")
	assert_eq(values.get("i_floats"), "0.5000;1.0000")
	assert_eq(values.get("j_dict"), "0:41;1:39")
	assert_eq(values.get("k_round"), "0.0001", "Floats round to four places.")


func test_body_encodes_rest_as_zero_or_one() -> void:
	var asleep: Dictionary = _parse(
		SoakLine.body(&"client", 4, 9, Vector3.ZERO, Quaternion.IDENTITY, false)
	)["values"]
	assert_eq(asleep.get("rest"), "0")
	assert_eq(asleep.get("id"), "9")
	assert_eq(asleep.get("p"), "0.0000,0.0000,0.0000")
	assert_eq(asleep.get("q"), "0.00000000,0.00000000,0.00000000,1.00000000")
	assert_eq(asleep.get("role"), "client")


func test_fuzz_carries_the_kind_name_and_slot() -> void:
	var values: Dictionary = _parse(SoakLine.fuzz(&"client", 3, &"FLOOD", 6))["values"]
	assert_eq(values.get("seq"), "3")
	assert_eq(values.get("kind"), "FLOOD")
	assert_eq(values.get("slot"), "6")


func test_curve_writes_every_statistic_and_the_budget() -> void:
	var stats: Dictionary = {
		"ticks": 10, "bodies_mean": 250, "p50_ms": 1.5, "p99_ms": 2.5, "max_ms": 3.5, "over": 1
	}
	var parsed: Dictionary = _parse(SoakLine.curve(&"host", 250, stats, 8.0))
	var values: Dictionary = parsed["values"]
	assert_eq(parsed["tag"], "SOAK_CURVE")
	assert_eq(values.get("band"), "250")
	assert_eq(values.get("ticks"), "10")
	assert_eq(values.get("bodies_mean"), "250")
	assert_eq(values.get("p50_ms"), "1.5000")
	assert_eq(values.get("p99_ms"), "2.5000")
	assert_eq(values.get("max_ms"), "3.5000")
	assert_eq(values.get("budget_ms"), "8.0000")
	assert_eq(values.get("over"), "1")


func test_config_line_lists_every_field_in_declaration_order() -> void:
	var names: Array[String] = []
	for property: Dictionary in _config.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			names.append(str(property["name"]))
	assert_gt(names.size(), 30, "SoakConfig has its tolerances as script variables.")
	var parsed: Dictionary = _parse(SoakLine.config_line(&"host", &"authority", _config))
	var keys: Array[String] = parsed["keys"]
	assert_eq(keys.slice(0, 2), ["role", "scenario"] as Array[String])
	assert_eq(keys.slice(2), names, "Every SoakConfig field, in declaration order.")
	assert_eq(parsed["values"].get("scenario"), "authority")


func test_config_line_follows_the_config_it_is_given() -> void:
	var config: SoakConfig = _config.duplicate() as SoakConfig
	config.duration_s = 12.5
	config.body_count_slack = 3
	config.curve_bands = PackedInt32Array([10, 20, 30])
	var values: Dictionary = _parse(SoakLine.config_line(&"client", &"load", config))["values"]
	assert_eq(values.get("duration_s"), "12.5000")
	assert_eq(values.get("body_count_slack"), "3")
	assert_eq(values.get("curve_bands"), "10;20;30")
	assert_eq(values.get("role"), "client")
