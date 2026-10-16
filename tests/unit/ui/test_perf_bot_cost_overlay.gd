extends GutTest
## the F2 bot think cost overlay (ui/debug/PerfBotCostOverlay.gd): debug gate, F2 and pad chord,
## collector enable/disable, table content and highlight, selector, client / empty lines.

var _overlay: PerfBotCostOverlay = null


func before_each() -> void:
	BotThinkCostCollector.disable()
	DebugMode.set_override_for_test(true)
	_overlay = PerfBotCostOverlay.new()
	_overlay.config = DebugConfig.new()
	add_child_autofree(_overlay)


func after_each() -> void:
	Input.action_release(&"camera_snap_home")
	BotThinkCostCollector.disable()
	DebugMode.clear_override_for_test()


func _f2() -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.device = -1
	event.physical_keycode = KEY_F2
	event.pressed = true
	return event


func _record(phase_us: Array[int]) -> Dictionary:
	var units: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
	return {
		"phase_us": PackedInt64Array(phase_us), "phase_units": PackedInt64Array(units),
		"total_us": 0, "probe_call_us": 100, "probe_calls": 4, "build_us": 100, "apply_us": 50, "other_us": 30,
		"ticks": 3, "latency_us": 20000,
	}


func _feed() -> BotThinkCostCollector:
	var collector: BotThinkCostCollector = BotThinkCostCollector.current()
	var cheap: Array[int] = [10, 10, 10, 10, 400, 10, 10, 10]
	var other: Array[int] = [20, 20, 20, 20, 800, 20, 20, 20]
	collector.record_think(1, _record(cheap))
	collector.record_think(2, _record(other))
	return collector


func test_f2_toggles_only_in_debug_mode() -> void:
	_overlay._unhandled_input(_f2())
	assert_true(_overlay.is_shown())
	_overlay._unhandled_input(_f2())
	assert_false(_overlay.is_shown())
	DebugMode.set_override_for_test(false)
	_overlay._unhandled_input(_f2())
	assert_false(_overlay.is_shown(), "debug off: F2 does nothing")


func test_table_has_every_phase_row_numbers_and_highlight() -> void:
	_overlay.set_shown(true)
	_feed()
	_overlay.refresh()
	var cells: Array[Label] = _overlay.grid_cells()
	assert_eq(cells.size(), (BotThinkCostReport.PHASE_COUNT + 2 + 1) * PerfBotCostOverlay.COLUMN_COUNT)
	var report: BotThinkCostReport = BotThinkCostCollector.current().aggregate()
	var probe: Dictionary = report.phase_stats(BotThink.Phase.PROBE)
	for i: int in range(BotThinkCostReport.PHASE_COUNT):
		var base: int = (i + 1) * PerfBotCostOverlay.COLUMN_COUNT
		assert_eq(cells[base].text, BotThinkCostReport.PHASE_NAMES[i])
		var hot: bool = BotThinkCostReport.PHASE_NAMES[i] == "PROBE"
		assert_eq(cells[base + 1].get_theme_color(&"font_color") == _overlay.config.overlay_warn_color(), hot, "highlight only PROBE (row %d)" % i)
	var probe_base: int = (BotThink.Phase.PROBE + 1) * PerfBotCostOverlay.COLUMN_COUNT
	assert_eq(cells[probe_base + 1].text, "%.1f" % probe["mean_us"])
	assert_eq(cells[probe_base + 1].text, "600.0")
	assert_eq(cells[probe_base + 3].text, "800")
	assert_eq(cells[probe_base + 4].text, "5.00")
	var snapshot_base: int = (BotThinkCostReport.PHASE_COUNT + 1) * PerfBotCostOverlay.COLUMN_COUNT
	assert_eq(cells[snapshot_base].text, PerfBotCostOverlay.ROW_SNAPSHOT)
	assert_eq(cells[snapshot_base + 1].text, "100.0")
	assert_eq(cells[snapshot_base + PerfBotCostOverlay.COLUMN_COUNT].text, PerfBotCostOverlay.ROW_OTHER)
	assert_eq(cells[snapshot_base + PerfBotCostOverlay.COLUMN_COUNT + 1].text, "80.0")
	var footer: PackedStringArray = PerfBotCostOverlay.footer_lines(report)
	assert_eq(footer.size(), 4)
	assert_eq(footer[3], "FILL fallback: 0 of 2 thinks (0.0%, 0 sites)", "FILL fallback line under the table")
	assert_true(footer[0].begins_with("PROBE physics 100.0 us"))
	assert_true(PerfBotCostOverlay.header_text(report, 2, PerfBotCostOverlay.ALL_SLOTS).contains("2 bots"))
