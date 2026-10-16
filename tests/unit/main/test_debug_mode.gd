extends GutTest
## debug-mode gating, F1 overlay cycling, sampler, CSV logger and
## the perf_log_summary.py tool.

const TEST_LOG_DIR: String = "user://test_perf_logs"

var _config: DebugConfig = null


func before_each() -> void:
	_config = DebugConfig.new()
	_config.log_dir = TEST_LOG_DIR
	_config.log_flush_every_rows = 2
	_config.log_keep_files = 2
	_clear_test_logs()


func after_each() -> void:
	DebugMode.clear_override_for_test()
	_clear_test_logs()


func _clear_test_logs() -> void:
	if not DirAccess.dir_exists_absolute(TEST_LOG_DIR):
		return
	for file_name: String in DirAccess.get_files_at(TEST_LOG_DIR):
		DirAccess.remove_absolute(TEST_LOG_DIR.path_join(file_name))


func _key_press(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.device = -1
	event.physical_keycode = keycode
	event.pressed = true
	return event


# --- Debug flag ---------------------------------------------------------------

func test_resolve_cli_and_settings_precedence() -> void:
	assert_true(DebugMode.resolve_from(PackedStringArray(["--debug"]), -1, false, false))
	assert_false(DebugMode.resolve_from(PackedStringArray(["--no-debug", "--debug"]), 1, true, true))
	assert_true(DebugMode.resolve_from(PackedStringArray(), 1, false, false), "user setting on")
	assert_false(DebugMode.resolve_from(PackedStringArray(), 0, true, true), "user setting off beats project/editor")
	assert_true(DebugMode.resolve_from(PackedStringArray(), -1, true, false), "project setting on")


func test_f3_f4_and_f1_ignored_when_debug_off() -> void:
	DebugMode.set_override_for_test(false)
	var net_overlay: NetDebugOverlay = autofree(load("res://ui/debug/NetDebugOverlay.tscn").instantiate())
	add_child_autofree(net_overlay)
	net_overlay._unhandled_input(_key_press(KEY_F3))
	assert_false(net_overlay.visible, "F3 ignored")
	var tuning: TuningPanel = autofree(load("res://ui/debug/TuningPanel.tscn").instantiate())
	add_child_autofree(tuning)
	tuning._unhandled_input(_key_press(KEY_F4))
	assert_false(tuning.visible, "F4 ignored")
	var overlay: PerfOverlay = _make_overlay()
	overlay._unhandled_input(_key_press(KEY_F1))
	assert_false(_overlay_panel(overlay).visible, "F1 ignored")

	DebugMode.set_override_for_test(true)
	net_overlay._unhandled_input(_key_press(KEY_F3))
	assert_true(net_overlay.visible, "F3 works in debug mode")
	tuning._unhandled_input(_key_press(KEY_F4))
	assert_true(tuning.visible, "F4 works in debug mode")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_f12_screenshot_action_is_not_gated_by_debug_mode() -> void:
	DebugMode.set_override_for_test(false)
	assert_true(_key_press(KEY_F12).is_action_pressed(&"screenshot_capture"))
	assert_true(InputMap.has_action(&"perf_overlay_toggle"))
	assert_true(_key_press(KEY_F1).is_action_pressed(&"perf_overlay_toggle"))


func test_perf_overlay_action_has_pad_binding() -> void:
	var has_pad: bool = false
	for event: InputEvent in InputMap.action_get_events(&"perf_overlay_toggle"):
		has_pad = has_pad or event is InputEventJoypadButton
	assert_true(has_pad, "every action needs a gamepad binding")


# --- Overlay ---------------------------------------------------------------------

func _make_overlay() -> PerfOverlay:
	var sampler: PerfSampler = PerfSampler.new()
	sampler.config = _config
	add_child_autofree(sampler)
	var overlay: PerfOverlay = PerfOverlay.new()
	overlay.config = _config
	overlay.sampler = sampler
	add_child_autofree(overlay)
	return overlay


## The overlay's panel is its only child; it is visible exactly while the overlay is not HIDDEN.
func _overlay_panel(overlay: PerfOverlay) -> PanelContainer:
	return overlay.get_child(0) as PanelContainer


func test_overlay_pad_press_needs_back_chord() -> void:
	DebugMode.set_override_for_test(true)
	var overlay: PerfOverlay = _make_overlay()
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.device = -1
	pad.button_index = JOY_BUTTON_RIGHT_STICK
	pad.pressed = true
	overlay._unhandled_input(pad)
	assert_false(_overlay_panel(overlay).visible, "stick click alone does nothing")
	Input.action_press(&"camera_snap_home")
	overlay._unhandled_input(pad)
	Input.action_release(&"camera_snap_home")
	assert_true(_overlay_panel(overlay).visible)


func _make_logger(sampler: PerfSampler) -> PerfLogger:
	var logger: PerfLogger = PerfLogger.new()
	logger.config = _config
	logger.sampler = sampler
	logger.auto_open = false
	add_child_autofree(logger)
	return logger


func test_summary_tool_reports_percentiles_and_spikes() -> void:
	var sampler: PerfSampler = PerfSampler.new()
	sampler.config = _config
	add_child_autofree(sampler)
	var logger: PerfLogger = _make_logger(sampler)
	logger.open_log()
	for i: int in range(10):
		var row: Dictionary = sampler.sample_now().duplicate()
		row["time_s"] = float(i)
		row["frame_ms_max"] = 50.0 if i == 7 else 10.0
		row["node_count"] = 100 + i * 20
		logger.write_row(row)
	logger.close_log()
	var out: Array = []
	var code: int = OS.execute("python", [
		ProjectSettings.globalize_path("res://tools/perf_log_summary.py"),
		ProjectSettings.globalize_path(logger.path), "--json"], out, true)
	if code == -1:
		pending("python not available")
		return
	assert_eq(code, 0, "summary tool exit code")
	var parsed: Variant = JSON.parse_string(str(out[0]))
	assert_true(parsed is Dictionary, "summary prints JSON")
	var summary: Dictionary = parsed
	assert_eq(int(summary["rows"]), 10)
	assert_eq(int(summary["spike_count"]), 1)
	assert_almost_eq(float(summary["metrics"]["frame_ms_max"]["max"]), 50.0, 0.01)
	assert_true(bool(summary["trends"]["node_count"]["warn"]), "growing node count flagged")


# --- physics steps per frame and effects child count -----------
