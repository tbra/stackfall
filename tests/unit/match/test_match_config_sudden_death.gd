extends GutTest
## MatchConfig.sudden_death_seconds: default, sanitize() clamp and step snap, wire round trip.


func _sanitized(seconds: int) -> int:
	var config: MatchConfig = MatchConfig.new()
	config.sudden_death_seconds = seconds
	config.sanitize()
	return config.sudden_death_seconds


func test_default_is_two_minutes() -> void:
	assert_eq(MatchConfig.new().sudden_death_seconds, 120)


func test_default_survives_sanitize() -> void:
	assert_eq(_sanitized(MatchConfig.new().sudden_death_seconds), 120)


func test_below_range_clamps_to_minimum() -> void:
	assert_eq(_sanitized(0), 30)
	assert_eq(_sanitized(-90), 30)
	assert_eq(_sanitized(29), 30)


func test_above_range_clamps_to_maximum() -> void:
	assert_eq(_sanitized(301), 300)
	assert_eq(_sanitized(100000), 300)


func test_bounds_are_kept() -> void:
	assert_eq(_sanitized(30), 30)
	assert_eq(_sanitized(300), 300)


func test_every_step_value_is_kept() -> void:
	for seconds: int in range(30, 301, 30):
		assert_eq(_sanitized(seconds), seconds, "step value %d" % seconds)


func test_off_step_values_snap_to_nearest_step() -> void:
	assert_eq(_sanitized(44), 30)
	assert_eq(_sanitized(46), 60)
	assert_eq(_sanitized(119), 120)
	assert_eq(_sanitized(134), 120)
	assert_eq(_sanitized(136), 150)
	assert_eq(_sanitized(299), 300)


func test_sanitized_result_is_always_on_the_step_grid() -> void:
	for seconds: int in range(-10, 400, 7):
		var result: int = _sanitized(seconds)
		assert_eq(result % 30, 0, "%d -> %d" % [seconds, result])
		assert_between(result, 30, 300)


func test_round_trip_through_dict() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.sudden_death = true
	config.sudden_death_seconds = 210
	var copy: MatchConfig = MatchConfig.from_dict(config.to_dict())
	assert_eq(copy.sudden_death_seconds, 210)
	assert_true(copy.sudden_death)


func test_round_trip_keeps_each_bound() -> void:
	for seconds: int in [30, 300]:
		var config: MatchConfig = MatchConfig.new()
		config.sudden_death_seconds = seconds
		assert_eq(MatchConfig.from_dict(config.to_dict()).sudden_death_seconds, seconds)


func test_old_dict_without_the_key_keeps_default() -> void:
	var data: Dictionary = MatchConfig.new().to_dict()
	data.erase("sudden_death_seconds")
	var copy: MatchConfig = MatchConfig.from_dict(data)
	assert_eq(copy.sudden_death_seconds, 120)


func test_empty_dict_keeps_default() -> void:
	assert_eq(MatchConfig.from_dict({}).sudden_death_seconds, 120)


func test_out_of_range_wire_value_is_clamped_by_sanitize() -> void:
	var data: Dictionary = MatchConfig.new().to_dict()
	data["sudden_death_seconds"] = 9999
	var copy: MatchConfig = MatchConfig.from_dict(data)
	copy.sanitize()
	assert_eq(copy.sudden_death_seconds, 300)
