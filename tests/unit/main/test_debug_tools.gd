extends GutTest
## DebugTools composition: what a session builds with and without session extras. The sampler is
## shared by the F1 overlay and the logger; the soak monitor and fuzzer follow their own flags.

var _tools: DebugTools = null


func before_each() -> void:
	DebugMode.set_override_for_test(true)
	_tools = DebugTools.new()
	_tools.config = DebugMode.config()


func after_each() -> void:
	DebugMode.clear_override_for_test()


func _build() -> void:
	add_child_autofree(_tools)


func _all(type: Variant) -> Array[Node]:
	var found: Array[Node] = []
	for node: Node in _tools.find_children("*", "", true, false):
		if is_instance_of(node, type):
			found.append(node)
	return found


func test_without_extras_builds_one_demand_driven_sampler_and_one_overlay() -> void:
	_tools.session_extras = false
	_build()
	var samplers: Array[Node] = _all(PerfSampler)
	assert_eq(samplers.size(), 1, "one sampler")
	assert_eq(_all(PerfOverlay).size(), 1, "one F1 overlay")
	if samplers.is_empty():
		return
	assert_true((samplers[0] as PerfSampler).demand_driven, "hidden F1 costs nothing")


func test_without_extras_builds_no_logger_soak_or_fuzzer() -> void:
	_tools.session_extras = false
	_tools.soak_enabled = true
	_tools.soak_fuzz_enabled = true
	_build()
	assert_eq(_all(PerfLogger).size(), 0, "no logger")
	assert_eq(_all(SoakMonitor).size(), 0, "no soak monitor")
	assert_eq(_all(SoakIntentFuzzer).size(), 0, "no fuzzer")


func test_without_extras_builds_the_same_in_a_player_build() -> void:
	DebugMode.set_override_for_test(false)
	_tools.session_extras = false
	_build()
	var samplers: Array[Node] = _all(PerfSampler)
	assert_eq(samplers.size(), 1, "sampler is built with debug off")
	assert_eq(_all(PerfOverlay).size(), 1, "F1 is built with debug off")
	if samplers.is_empty():
		return
	assert_true((samplers[0] as PerfSampler).demand_driven)


func test_overlay_reads_the_sampler_the_tools_built() -> void:
	_build()
	var samplers: Array[Node] = _all(PerfSampler)
	var overlays: Array[Node] = _all(PerfOverlay)
	if samplers.is_empty() or overlays.is_empty():
		fail_test("sampler or overlay not built")
		return
	assert_eq((overlays[0] as PerfOverlay).sampler, samplers[0])


func test_extras_add_the_logger_sharing_the_sampler_and_sample_continuously() -> void:
	_tools.session_extras = true
	_build()
	var samplers: Array[Node] = _all(PerfSampler)
	var overlays: Array[Node] = _all(PerfOverlay)
	var loggers: Array[Node] = _all(PerfLogger)
	assert_eq(samplers.size(), 1, "still one sampler")
	assert_eq(overlays.size(), 1)
	assert_eq(loggers.size(), 1, "one logger")
	if samplers.is_empty() or overlays.is_empty() or loggers.is_empty():
		return
	assert_eq((loggers[0] as PerfLogger).sampler, samplers[0], "logger and overlay share the sampler")
	assert_eq((overlays[0] as PerfOverlay).sampler, samplers[0])
	assert_false((samplers[0] as PerfSampler).demand_driven, "logger needs continuous samples")


func test_extras_without_soak_flag_build_no_soak_monitor_or_fuzzer() -> void:
	_tools.session_extras = true
	_build()
	assert_eq(_all(SoakMonitor).size(), 0)
	assert_eq(_all(SoakIntentFuzzer).size(), 0)


func test_soak_flag_builds_a_monitor_with_role_and_the_shared_sampler() -> void:
	_tools.session_extras = true
	_tools.soak_enabled = true
	_build()
	var monitors: Array[Node] = _all(SoakMonitor)
	var samplers: Array[Node] = _all(PerfSampler)
	assert_eq(monitors.size(), 1, "one soak monitor")
	assert_eq(_all(SoakIntentFuzzer).size(), 0, "fuzzer needs its own flag")
	if monitors.is_empty() or samplers.is_empty():
		return
	var monitor: SoakMonitor = monitors[0] as SoakMonitor
	assert_eq(monitor.sampler, samplers[0], "monitor reads the shared sampler")
	assert_true(monitor.role == &"host" or monitor.role == &"client", "role is set")


func test_fuzz_flag_builds_the_fuzzer() -> void:
	_tools.session_extras = true
	_tools.soak_enabled = true
	_tools.soak_fuzz_enabled = true
	_build()
	assert_eq(_all(SoakIntentFuzzer).size(), 1)
	assert_eq(_all(SoakMonitor).size(), 1)


func test_soak_flags_do_nothing_without_extras_even_when_debug_on() -> void:
	_tools.session_extras = false
	_tools.soak_enabled = true
	_build()
	assert_eq(_all(SoakMonitor).size(), 0)
