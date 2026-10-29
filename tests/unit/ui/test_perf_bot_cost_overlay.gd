extends GutTest
## the F9 bot think cost overlay (ui/debug/PerfBotCostOverlay.gd): F9 and pad chord (both work with
## debug off), collector enable/disable, cell text and the hot row through the kept statics, the
## selector chord, and the client / empty lines from the injected match context.

var _overlay: PerfBotCostOverlay = null
var _context: FakeMatchContext = null


func before_each() -> void:
	BotThinkCostCollector.disable()
	DebugMode.set_override_for_test(true)
	_context = FakeMatchContext.new()
	_overlay = PerfBotCostOverlay.new()
	_overlay.config = DebugConfig.new()
	# set() so a missing property fails the behaviour tests, not the parse of this file
	_overlay.set(&"match_context", _context)
	add_child_autofree(_overlay)


func after_each() -> void:
	Input.action_release(&"camera_snap_home")
	BotThinkCostCollector.disable()
	DebugMode.clear_override_for_test()


func _f9() -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.device = -1
	event.physical_keycode = KEY_F9
	event.pressed = true
	return event


func _pad_toggle() -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_LEFT_STICK
	event.pressed = true
	return event


func _arrow(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _texts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for node: Node in _overlay.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	return out


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


## Row accessors: the cells and the hot flag (DebugRow.warn on the kit, "hot" on the older Dictionary row).
func _cells(row: Variant) -> PackedStringArray:
	if row is DebugRow:
		return (row as DebugRow).cells
	return (row as Dictionary)["cells"] as PackedStringArray


func _is_hot(row: Variant) -> bool:
	if row is DebugRow:
		return (row as DebugRow).warn
	return bool((row as Dictionary)["hot"])


func test_f9_toggles_with_debug_off() -> void:
	DebugMode.set_override_for_test(false)
	_overlay._unhandled_input(_f9())
	assert_true(_overlay.is_shown(), "debug off: F9 still opens the panel")
	_overlay._unhandled_input(_f9())
	assert_false(_overlay.is_shown())


func test_pad_chord_toggles_with_debug_off_and_bare_press_does_not() -> void:
	DebugMode.set_override_for_test(false)
	_overlay._unhandled_input(_pad_toggle())
	assert_false(_overlay.is_shown(), "a bare left-stick click is ignored")
	Input.action_press(&"camera_snap_home")
	_overlay._unhandled_input(_pad_toggle())
	assert_true(_overlay.is_shown())


func test_collector_runs_only_while_shown() -> void:
	assert_null(BotThinkCostCollector.current(), "hidden: no collector")
	_overlay.set_shown(true)
	assert_not_null(BotThinkCostCollector.current())
	_overlay.set_shown(false)
	assert_null(BotThinkCostCollector.current(), "hidden again: collector off")


func test_table_rows_text_and_hot_flag_on_probe_only() -> void:
	_overlay.set_shown(true)
	_feed()
	var report: BotThinkCostReport = BotThinkCostCollector.current().aggregate()
	var rows: Array = PerfBotCostOverlay.table_rows(report)
	assert_eq(rows.size(), BotThinkCostReport.PHASE_COUNT + 2)
	var probe: Dictionary = report.phase_stats(BotThink.Phase.PROBE)
	for i: int in range(BotThinkCostReport.PHASE_COUNT):
		var phase_name: String = BotThinkCostReport.PHASE_NAMES[i]
		assert_eq(_cells(rows[i])[0], phase_name)
		assert_eq(_is_hot(rows[i]), phase_name == "PROBE", "hot only on PROBE (%s)" % phase_name)
	var probe_cells: PackedStringArray = _cells(rows[BotThink.Phase.PROBE])
	assert_eq(probe_cells[1], "%.1f" % probe["mean_us"])
	assert_eq(probe_cells[1], "600.0")
	assert_eq(probe_cells[3], "800")
	assert_eq(probe_cells[4], "5.00")
	var snapshot_index: int = BotThinkCostReport.PHASE_COUNT
	var snapshot: PackedStringArray = _cells(rows[snapshot_index])
	assert_eq(snapshot[0], PerfBotCostOverlay.ROW_SNAPSHOT)
	assert_eq(snapshot[1], "100.0")
	assert_false(_is_hot(rows[snapshot_index]))
	var other: PackedStringArray = _cells(rows[snapshot_index + 1])
	assert_eq(other[0], PerfBotCostOverlay.ROW_OTHER)
	assert_eq(other[1], "80.0")
	assert_false(_is_hot(rows[snapshot_index + 1]))


func test_shown_panel_displays_the_probe_cost() -> void:
	_overlay.set_shown(true)
	_feed()
	_overlay.refresh()
	assert_true(_texts().has("600.0"), "the PROBE mean reaches a visible label")
	assert_true(_texts().has("PROBE"))


func test_footer_and_header_text() -> void:
	_overlay.set_shown(true)
	_feed()
	var report: BotThinkCostReport = BotThinkCostCollector.current().aggregate()
	var footer: PackedStringArray = PerfBotCostOverlay.footer_lines(report)
	assert_eq(footer.size(), 4)
	assert_eq(footer[3], "FILL fallback: 0 of 2 thinks (0.0%, 0 sites)", "FILL fallback line under the table")
	assert_true(footer[0].begins_with("PROBE physics 100.0 us"))
	assert_true(PerfBotCostOverlay.header_text(report, 2, PerfBotCostOverlay.ALL_SLOTS).contains("2 bots"))
	assert_true(PerfBotCostOverlay.header_text(report, 2, 1).contains("slot 1"))


func test_client_sees_the_host_only_line_from_the_context() -> void:
	_context.net_is_client_value = true
	_overlay.set_shown(true)
	assert_true(_texts().has(PerfBotCostOverlay.CLIENT_LINE))
	assert_false(_texts().has(PerfBotCostOverlay.EMPTY_LINE))


func test_host_without_data_sees_the_empty_line() -> void:
	_context.net_is_client_value = false
	_overlay.set_shown(true)
	assert_true(_texts().has(PerfBotCostOverlay.EMPTY_LINE))
	assert_false(_texts().has(PerfBotCostOverlay.CLIENT_LINE))


func test_selector_chord_steps_slots_and_needs_back_held() -> void:
	_overlay.set_shown(true)
	_feed()
	_overlay.refresh()
	_overlay._unhandled_input(_arrow(KEY_RIGHT))
	assert_eq(_overlay.selected_slot, PerfBotCostOverlay.ALL_SLOTS, "without Back the arrow does nothing")
	Input.action_press(&"camera_snap_home")
	_overlay._unhandled_input(_arrow(KEY_RIGHT))
	assert_eq(_overlay.selected_slot, 1)
	assert_true(_texts().has("400.0"), "slot 1's PROBE mean is shown")
	assert_false(_texts().has("600.0"), "the all-bots mean is gone")
	_overlay._unhandled_input(_arrow(KEY_RIGHT))
	assert_eq(_overlay.selected_slot, 2)
	_overlay._unhandled_input(_arrow(KEY_RIGHT))
	assert_eq(_overlay.selected_slot, PerfBotCostOverlay.ALL_SLOTS, "wraps back to all bots")
	_overlay._unhandled_input(_arrow(KEY_LEFT))
	assert_eq(_overlay.selected_slot, 2, "left steps back with wrap")
