extends GutTest
## The trimmed sky shader declares none of the golden's retired uniforms, still declares every
## other sky-material uniform the golden pins, and the shared include lost the dead overhead
## cloud functions.

const GOLDEN_PATH: String = "res://tests/unit/sky/fixtures/sky_cycle_golden.json"
const SHADER_PATH: String = "res://shaders/sky/sunset_clouds.gdshader"
const INCLUDE_PATH: String = "res://shaders/include/cloud_common.gdshaderinc"
const DOME_PATH: String = "res://config/sky/sky_dome.tres"
const REMOVED_FUNCTIONS: Array[String] = ["sky_cloud_cards", "procedural_upper_clouds"]
const UNIFORM_PATTERN: String = "(?m)^\\s*(?:global\\s+)?uniform\\s+\\S+\\s+(\\w+)"


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _declared(source: String) -> Dictionary:
	var out: Dictionary = {}
	var regex: RegEx = RegEx.new()
	regex.compile(UNIFORM_PATTERN)
	for hit: RegExMatch in regex.search_all(source):
		out[hit.get_string(1)] = true
	return out


func _golden() -> Dictionary:
	return JSON.parse_string(_read(GOLDEN_PATH)) as Dictionary


func test_no_retired_uniform_is_declared() -> void:
	var declared: Dictionary = _declared(_read(SHADER_PATH))
	var retired: Array = _golden()["retired_uniforms"] as Array
	assert_gt(retired.size(), 0, "golden lists retired uniforms")
	for name_variant: Variant in retired:
		assert_false(declared.has(str(name_variant)), "still declared: %s" % str(name_variant))


func test_every_live_golden_uniform_is_declared() -> void:
	var declared: Dictionary = _declared(_read(SHADER_PATH))
	var retired: Array = _golden()["retired_uniforms"] as Array
	var states: Dictionary = _golden()["states"] as Dictionary
	var checked: int = 0
	for state: Variant in states.values():
		for key: Variant in ((state as Dictionary)["sky"] as Dictionary).keys():
			if retired.has(key):
				continue
			checked += 1
			assert_true(declared.has(str(key)), "missing from the shader: %s" % str(key))
	assert_gt(checked, 0)


func test_include_lost_the_dead_functions() -> void:
	var source: String = _read(INCLUDE_PATH)
	for function_name: String in REMOVED_FUNCTIONS:
		assert_false(source.contains(function_name + "("), "include still has %s" % function_name)


func test_dome_material_stores_no_retired_parameter() -> void:
	var source: String = _read(DOME_PATH)
	for name_variant: Variant in _golden()["retired_uniforms"] as Array:
		assert_false(source.contains("shader_parameter/%s =" % str(name_variant)), "stored: %s" % str(name_variant))
	assert_false(source.contains("cloud_cards_atlas"), "atlas ext_resource dropped")
