extends GutTest
## SoakConfig and its soak_config.tres: the file lists every exported field explicitly (tools/
## reads it as text), the values load into a SoakConfig, and the tick budget the monitor checks
## follows the engine's physics rate rather than a literal 60.

const CONFIG_SCRIPT_PATH: String = "res://config/soak/SoakConfig.gd"
const CONFIG_RESOURCE_PATH: String = "res://config/soak/soak_config.tres"


func _exported_property_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var source: String = FileAccess.get_file_as_string(CONFIG_SCRIPT_PATH)
	var regex: RegEx = RegEx.new()
	regex.compile("(?m)^@export[^\\n]*?\\bvar\\s+(\\w+)")
	for hit: RegExMatch in regex.search_all(source):
		names.append(hit.get_string(1))
	return names


func _resource_text_property_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var text: String = FileAccess.get_file_as_string(CONFIG_RESOURCE_PATH)
	var in_resource: bool = false
	var regex: RegEx = RegEx.new()
	regex.compile("^(\\w+)\\s*=")
	for line: String in text.split("\n"):
		if line.strip_edges() == "[resource]":
			in_resource = true
			continue
		if not in_resource:
			continue
		var found: RegExMatch = regex.search(line)
		if found != null:
			names.append(found.get_string(1))
	return names


func test_soak_config_tres_lists_every_exported_field() -> void:
	var exported: PackedStringArray = _exported_property_names()
	var listed: PackedStringArray = _resource_text_property_names()
	assert_gt(exported.size(), 0, "the scan finds SoakConfig's exported fields")
	for field: String in exported:
		assert_true(field in listed, "soak_config.tres lists %s explicitly" % field)


func test_soak_config_tres_sets_no_field_the_script_does_not_export() -> void:
	var exported: PackedStringArray = _exported_property_names()
	for field: String in _resource_text_property_names():
		if field == "script":
			continue  # the Resource's own script reference, not a SoakConfig field
		assert_true(field in exported, "soak_config.tres key %s is an exported SoakConfig field" % field)


func test_soak_config_tres_loads_as_a_soak_config() -> void:
	var config: SoakConfig = load(CONFIG_RESOURCE_PATH) as SoakConfig
	assert_not_null(config, "soak_config.tres loads as a SoakConfig")
	if config == null:
		return
	assert_gt(config.duration_s, 0.0, "a run has a positive duration")
	assert_gt(config.sample_interval_s, 0.0, "samples have a positive interval")
	assert_eq(config.curve_bands.size(), 4, "the default tick-cost curve has four bands")


func _budget_ids(hz: int, tick_ms: float) -> Array[StringName]:
	var config: SoakConfig = load(CONFIG_RESOURCE_PATH) as SoakConfig
	var frame_ms: float = 1000.0 / float(hz)
	var curve: TickBudgetCurve = TickBudgetCurve.new(config.curve_bands, config.curve_band_half_width_fraction, frame_ms * config.tick_budget_fraction, config.curve_bucket_ms, config.curve_max_ms)
	var band: int = config.curve_bands[0]
	for _i: int in range(config.curve_min_ticks):
		curve.record(tick_ms, band)
	var ids: Array[StringName] = []
	for v: SoakCheck.Violation in SoakCheck.budget(&"client", curve, float(hz), hz, 0.0, 0, config):
		ids.append(v.invariant)
	return ids


func test_tick_budget_follows_the_physics_rate_it_is_given() -> void:
	# Ticks at 25 ms are over the 16.7 ms frame of a 60 Hz engine but under the 33.3 ms frame of a
	# 30 Hz one. A literal 60 Hz budget would report them at 30 Hz as well. The engine's own rate
	# is passed in by the monitor.
	var native_hz: int = Engine.physics_ticks_per_second
	assert_true(&"budget.client_tick_p99" in _budget_ids(native_hz, 25.0),
		"25 ms ticks break the budget at the engine's physics rate")
	assert_false(&"budget.client_tick_p99" in _budget_ids(30, 25.0),
		"25 ms ticks fit a 30 Hz frame budget")
