extends GutTest
## Bontago-1pi.11.55 slice A: StartupPump autoload helpers.

const PumpScript: GDScript = preload("res://autoload/StartupPump.gd")
const SMALL_SCRIPT: String = "res://autoload/Rumble.gd"
const MISSING_PATH: String = "res://autoload/__missing_startup_pump__.gd"
const HANG_GUARD_MS: int = 5000

var _pumps: int = 0
var _status_calls: int = 0


func _count_pump() -> void:
	_pumps += 1


func _slow_status(path: String) -> int:
	_status_calls += 1
	if _status_calls <= 3:
		return ResourceLoader.THREAD_LOAD_IN_PROGRESS
	return ResourceLoader.load_threaded_get_status(path)


func _stuck_status(_path: String) -> int:
	return ResourceLoader.THREAD_LOAD_IN_PROGRESS


func test_path_list_order_star_stripping_and_self_exclusion() -> void:
	var paths: PackedStringArray = PumpScript.autoload_script_paths()
	assert_false(paths.has("res://autoload/StartupPump.gd"), "self excluded")
	assert_gt(paths.size(), 0)
	var expected: PackedStringArray = PackedStringArray()
	for prop: Dictionary in ProjectSettings.get_property_list():
		var key: String = prop["name"]
		if key.begins_with("autoload/"):
			var value: String = String(ProjectSettings.get_setting(key)).trim_prefix("*")
			if value.ends_with(".gd") and value != "res://autoload/StartupPump.gd":
				expected.append(value)
	assert_eq(paths, expected)
	for path: String in paths:
		assert_false(path.begins_with("*"))
	assert_eq(paths[0], "res://autoload/Events.gd", "autoload order preserved")


func test_pump_until_loaded_returns_script() -> void:
	_pumps = 0
	_status_calls = 0
	var out: Array[Resource] = PumpScript.pump_until_loaded(
		PackedStringArray([SMALL_SCRIPT]), _count_pump, 1, 1000, _slow_status
	)
	assert_eq(_pumps, 3, "the pump Callable runs once per in-progress poll")
	assert_eq(out.size(), 1)
	assert_true(out[0] is GDScript)
	assert_eq(out[0].resource_path, SMALL_SCRIPT)


func test_missing_path_returns_without_hanging() -> void:
	var t0: int = Time.get_ticks_msec()
	var out: Array[Resource] = PumpScript.pump_until_loaded(
		PackedStringArray([MISSING_PATH]), _count_pump, 1
	)
	assert_lt(Time.get_ticks_msec() - t0, HANG_GUARD_MS)
	assert_eq(out.size(), 0)
	# The engine logs two lines for the failed request (err + found conditions); they carry no
	# stable text to match, so only the count is pinned.
	assert_engine_error_count(2, "the engine reports the failed threaded request (err + found)")


func test_wait_cap_ends_a_stuck_wait() -> void:
	_pumps = 0
	var t0: int = Time.get_ticks_msec()
	var out: Array[Resource] = PumpScript.pump_until_loaded(
		PackedStringArray([SMALL_SCRIPT]), _count_pump, 1, 30, _stuck_status
	)
	assert_lt(Time.get_ticks_msec() - t0, HANG_GUARD_MS)
	assert_gt(_pumps, 0)
	assert_eq(out.size(), 0, "a path that never finishes is skipped silently")


func test_headless_init_does_nothing() -> void:
	assert_eq(DisplayServer.get_name(), "headless")
	var node: Node = PumpScript.new()
	assert_eq(node.get("_held").size(), 0)
	node.free()
