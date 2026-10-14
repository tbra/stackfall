extends GutTest
## Bontago-1t5.63: the F2 bot think cost overlay (ui/PerfBotCostOverlay.gd): debug gate, F2 and pad chord,
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


func _pad_toggle() -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_LEFT_STICK
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


func test_pad_press_needs_back_held() -> void:
	_overlay._unhandled_input(_pad_toggle())
	assert_false(_overlay.is_shown(), "bare left-stick click is ignored")
	Input.action_press(&"camera_snap_home")
	_overlay._unhandled_input(_pad_toggle())
	assert_true(_overlay.is_shown(), "Back held: chord toggles")
	DebugMode.set_override_for_test(false)
	_overlay._unhandled_input(_pad_toggle())
	assert_true(_overlay.is_shown(), "debug off: no toggle")


func test_show_enables_collector_and_hide_disables_it() -> void:
	assert_null(BotThinkCostCollector.current())
	_overlay.set_shown(true)
	assert_not_null(BotThinkCostCollector.current())
	_overlay.set_shown(false)
	assert_null(BotThinkCostCollector.current())


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
		assert_eq(cells[base + 1].get_theme_color(&"font_color") == _overlay.hot_color(), hot, "highlight only PROBE (row %d)" % i)
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
	assert_eq(footer[3], "FILL fallback: 0 of 2 thinks (0.0%, 0 sites)", "Bontago-1t5.67 line under the table")
	assert_true(footer[0].begins_with("PROBE physics 100.0 us"))
	assert_true(PerfBotCostOverlay.header_text(report, 2, PerfBotCostOverlay.ALL_SLOTS).contains("2 bots"))


func test_selector_switches_between_all_and_one_slot() -> void:
	_overlay.set_shown(true)
	_feed()
	_overlay.refresh()
	var probe_mean_cell: int = (BotThink.Phase.PROBE + 1) * PerfBotCostOverlay.COLUMN_COUNT + 1
	assert_eq(_overlay.grid_cells()[probe_mean_cell].text, "600.0")
	_overlay.step_selection(1)
	assert_eq(_overlay.selected_slot, 1)
	assert_eq(_overlay.grid_cells()[probe_mean_cell].text, "400.0")
	_overlay.step_selection(1)
	assert_eq(_overlay.selected_slot, 2)
	assert_eq(_overlay.grid_cells()[probe_mean_cell].text, "800.0")
	_overlay.step_selection(1)
	assert_eq(_overlay.selected_slot, PerfBotCostOverlay.ALL_SLOTS, "wraps back to all bots")
	_overlay.step_selection(-1)
	assert_eq(_overlay.selected_slot, 2)


func test_empty_host_and_client_lines() -> void:
	_overlay.client_override = 0
	_overlay.set_shown(true)
	assert_eq(_status_text(), PerfBotCostOverlay.EMPTY_LINE)
	_overlay.client_override = 1
	_overlay.refresh()
	assert_eq(_status_text(), PerfBotCostOverlay.CLIENT_LINE)


func _status_text() -> String:
	for label: Label in _overlay.find_children("*", "Label", true, false):
		if label.visible and (label.text == PerfBotCostOverlay.EMPTY_LINE or label.text == PerfBotCostOverlay.CLIENT_LINE):
			return label.text
	return ""
