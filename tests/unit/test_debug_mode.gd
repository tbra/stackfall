extends GutTest
## Bontago-470.8: debug-mode gating, F1 overlay cycling, sampler, CSV logger and
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

func test_resolve_defaults_off_outside_editor() -> void:
	assert_false(DebugMode.resolve_from(PackedStringArray(), -1, false, false))


func test_resolve_editor_auto_on_and_config_off_switch() -> void:
	assert_true(DebugMode.resolve_from(PackedStringArray(), -1, false, true))
	var cfg: DebugConfig = DebugMode.config()
	var before: bool = cfg.auto_enable_in_editor
	cfg.auto_enable_in_editor = false
	assert_false(DebugMode.resolve_from(PackedStringArray(), -1, false, true))
	cfg.auto_enable_in_editor = before


func test_resolve_cli_and_settings_precedence() -> void:
	assert_true(DebugMode.resolve_from(PackedStringArray(["--debug"]), -1, false, false))
	assert_false(DebugMode.resolve_from(PackedStringArray(["--no-debug", "--debug"]), 1, true, true))
	assert_true(DebugMode.resolve_from(PackedStringArray(), 1, false, false), "user setting on")
	assert_false(DebugMode.resolve_from(PackedStringArray(), 0, true, true), "user setting off beats project/editor")
	assert_true(DebugMode.resolve_from(PackedStringArray(), -1, true, false), "project setting on")


func test_settings_debug_value_round_trips() -> void:
	var path: String = "user://test_debug_settings.cfg"
	Settings.set_config_path_for_test(path)
	assert_eq(Settings.debug_setting(), -1)
	Settings.set_debug_setting(1)
	Settings.set_config_path_for_test(path)
	assert_eq(Settings.debug_setting(), 1, "reloaded from disk")
	DirAccess.remove_absolute(path)
	Settings.set_config_path_for_test("user://settings.cfg")


# --- Gated hotkeys --------------------------------------------------------------

func test_f3_f4_and_f1_ignored_when_debug_off() -> void:
	DebugMode.set_override_for_test(false)
	var net_overlay: NetDebugOverlay = autofree(load("res://ui/NetDebugOverlay.tscn").instantiate())
	add_child_autofree(net_overlay)
	net_overlay._unhandled_input(_key_press(KEY_F3))
	assert_false(net_overlay.visible, "F3 ignored")
	var tuning: TuningPanel = autofree(load("res://ui/TuningPanel.tscn").instantiate())
	add_child_autofree(tuning)
	tuning._unhandled_input(_key_press(KEY_F4))
	assert_false(tuning.visible, "F4 ignored")
	var overlay: PerfOverlay = _make_overlay()
	overlay._unhandled_input(_key_press(KEY_F1))
	assert_eq(overlay.mode(), PerfOverlay.Mode.HIDDEN, "F1 ignored")

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


func test_overlay_cycles_hidden_basic_detailed_hidden() -> void:
	DebugMode.set_override_for_test(true)
	var overlay: PerfOverlay = _make_overlay()
	assert_eq(overlay.mode(), PerfOverlay.Mode.HIDDEN)
	overlay._unhandled_input(_key_press(KEY_F1))
	assert_eq(overlay.mode(), PerfOverlay.Mode.BASIC)
	overlay._unhandled_input(_key_press(KEY_F1))
	assert_eq(overlay.mode(), PerfOverlay.Mode.DETAILED)
	overlay._unhandled_input(_key_press(KEY_F1))
	assert_eq(overlay.mode(), PerfOverlay.Mode.HIDDEN)


func test_overlay_pad_press_needs_back_chord() -> void:
	DebugMode.set_override_for_test(true)
	var overlay: PerfOverlay = _make_overlay()
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.device = -1
	pad.button_index = JOY_BUTTON_RIGHT_STICK
	pad.pressed = true
	overlay._unhandled_input(pad)
	assert_eq(overlay.mode(), PerfOverlay.Mode.HIDDEN, "stick click alone does nothing")
	Input.action_press(&"camera_snap_home")
	overlay._unhandled_input(pad)
	Input.action_release(&"camera_snap_home")
	assert_eq(overlay.mode(), PerfOverlay.Mode.BASIC)


func test_format_basic_has_block_counter_detailed_has_breakdown() -> void:
	var m: Dictionary = {"fps": 60.0, "frame_ms": 16.6, "blocks_total": 12, "blocks_awake": 5,
		"blocks_sleeping": 7, "draw_calls": 321, "territory_ms": 1.5}
	var basic: String = PerfOverlay.format_metrics(m, PerfOverlay.Mode.BASIC)
	assert_string_contains(basic, "blocks 12")
	assert_string_contains(basic, "awake 5")
	assert_false(basic.contains("draw calls"))
	var detailed: String = PerfOverlay.format_metrics(m, PerfOverlay.Mode.DETAILED)
	assert_string_contains(detailed, "draw calls 321")
	assert_string_contains(detailed, "territory")


# --- Sampler / probes -------------------------------------------------------------

func test_probe_is_free_when_disabled_and_drains_when_enabled() -> void:
	PerfProbe.drain()  # other systems may have probed already
	PerfProbe.enabled = false
	assert_eq(PerfProbe.start(), 0)
	PerfProbe.stop(&"x", 0)
	assert_true(PerfProbe.drain().is_empty())
	PerfProbe.enabled = true
	var t: int = PerfProbe.start()
	OS.delay_usec(200)
	PerfProbe.stop(&"x", t)
	var drained: Dictionary = PerfProbe.drain()
	assert_eq(int(drained[&"x"]["calls"]), 1)
	assert_gt(int(drained[&"x"]["usec"]), 0)
	assert_true(PerfProbe.drain().is_empty(), "drain resets")
	PerfProbe.enabled = DebugMode.is_enabled()


func test_sampler_snapshot_has_logger_columns_and_bounded_history() -> void:
	var sampler: PerfSampler = PerfSampler.new()
	sampler.config = _config
	add_child_autofree(sampler)
	var snapshot: Dictionary = sampler.sample_now()
	for column: String in PerfLogger.COLUMNS:
		assert_true(snapshot.has(column), "snapshot lacks %s" % column)
	var capacity: int = int(ceilf(_config.graph_window_s / _config.graph_interval_s))
	for i: int in range(capacity + 25):
		sampler.record_frame(_config.graph_interval_s)
	assert_eq(sampler.history_frame_ms.size(), capacity)
	assert_eq(sampler.history_blocks.size(), capacity)


func test_frame_fps_and_physics_figures_are_self_consistent() -> void:
	var sampler: PerfSampler = PerfSampler.new()
	sampler.config = _config
	add_child_autofree(sampler)
	# 50 frames at 20 ms (=1 s window) with one 40 ms hitch replacing two of them.
	for i: int in range(48):
		sampler.record_frame(0.020)
	sampler.record_frame(0.040)
	sampler.record_frame(0.000)
	for tick: int in range(60):
		sampler.record_physics_tick(4.0 if tick == 10 else 2.0)
	var m: Dictionary = sampler.sample_now()
	assert_almost_eq(float(m["window_s"]), 1.0, 0.001)
	assert_almost_eq(float(m["fps"]), 50.0, 0.01)
	assert_almost_eq(float(m["frame_ms"]) * float(m["fps"]) / 1000.0, 1.0, 0.001, "frame ms * fps = 1 s")
	assert_almost_eq(float(m["frame_ms_max"]), 40.0, 0.001)
	assert_almost_eq(float(m["physics_ms"]), (59.0 * 2.0 + 4.0) / 60.0, 0.001)
	assert_almost_eq(float(m["physics_ms_max"]), 4.0, 0.001)
	var text: String = PerfOverlay.format_metrics(m, PerfOverlay.Mode.BASIC)
	assert_string_contains(text, "50 fps")
	assert_string_contains(text, "frame 20.0 ms avg / 40.0 worst (1 s)")
	assert_string_contains(text, "physics tick 2.03 ms avg / 4.00 worst (1 s)")
	var window_reset: Dictionary = sampler.sample_now()
	assert_almost_eq(float(window_reset["window_s"]), 0.0, 0.001, "accumulators reset")


# --- Logger ------------------------------------------------------------------------

func _make_logger(sampler: PerfSampler) -> PerfLogger:
	var logger: PerfLogger = PerfLogger.new()
	logger.config = _config
	logger.sampler = sampler
	logger.auto_open = false
	add_child_autofree(logger)
	return logger


func test_logger_writes_header_and_rows_and_closes() -> void:
	var sampler: PerfSampler = PerfSampler.new()
	sampler.config = _config
	add_child_autofree(sampler)
	var logger: PerfLogger = _make_logger(sampler)
	assert_true(logger.open_log())
	var snapshot: Dictionary = sampler.sample_now()
	logger.write_row(snapshot)
	logger.write_row(snapshot)
	logger.write_row(snapshot)
	logger.close_log()
	assert_eq(logger.rows_written(), 3)
	var file: FileAccess = FileAccess.open(logger.path, FileAccess.READ)
	assert_not_null(file)
	var lines: PackedStringArray = file.get_as_text().strip_edges().split("\n")
	assert_eq(lines.size(), 4, "header + 3 rows")
	assert_eq(lines[0], ",".join(PerfLogger.COLUMNS))
	assert_eq(lines[1].split(",").size(), PerfLogger.COLUMNS.size())
	logger.write_row(snapshot)  # after close: must be a harmless no-op
	assert_eq(logger.rows_written(), 3)


func test_logger_keeps_only_newest_files() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_LOG_DIR)
	for stamp: String in ["2020-01-01_00-00-01", "2020-01-01_00-00-02", "2020-01-01_00-00-03"]:
		var f: FileAccess = FileAccess.open(TEST_LOG_DIR.path_join("%s.csv" % stamp), FileAccess.WRITE)
		f.store_line("x")
		f.close()
	var sampler: PerfSampler = PerfSampler.new()
	sampler.config = _config
	add_child_autofree(sampler)
	var logger: PerfLogger = _make_logger(sampler)
	logger.open_log()
	logger.close_log()
	var names: PackedStringArray = DirAccess.get_files_at(TEST_LOG_DIR)
	assert_eq(names.size(), 2, "keep_files=2 includes the new session file")
	assert_false(names.has("2020-01-01_00-00-01.csv"))


# --- Summary tool ---------------------------------------------------------------------

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


# --- Bontago-1pi.11.36: physics steps per frame and effects child count -----------

func test_physics_step_and_effect_figures_reach_snapshot_overlay_and_columns() -> void:
	var sampler: PerfSampler = PerfSampler.new()
	sampler.config = _config
	add_child_autofree(sampler)
	for steps: int in [1, 1, 3, 1]:
		sampler.record_physics_steps(steps)
	sampler.record_effect_count(12)
	sampler.record_effect_count(4)
	var snapshot: Dictionary = sampler.sample_now()
	sampler.record_frame(0.01)
	assert_eq(int(snapshot["steps_current"]), 1)
	assert_eq(int(snapshot["steps_peak"]), 3)
	assert_eq(int(snapshot["effects_current"]), 4)
	assert_eq(int(snapshot["effects_peak"]), 12)
	assert_eq(int(snapshot["steps_max_setting"]),
		int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame", 8)))
	for column: String in ["steps_current", "steps_peak", "steps_multi_pct", "steps_max_setting", "effects_current", "effects_peak"]:
		assert_true(PerfLogger.COLUMNS.has(column), column)
	var text: String = PerfOverlay.format_metrics(snapshot, PerfOverlay.Mode.BASIC)
	assert_string_contains(text, "3 peak")
	assert_string_contains(text, "12 peak")
	# The window reset: peaks restart, current effects carry over.
	var next: Dictionary = sampler.sample_now()
	assert_eq(int(next["steps_peak"]), 0)
	assert_eq(int(next["effects_peak"]), 4)
