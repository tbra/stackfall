class_name PerfBotCostOverlay
extends CanvasLayer
## Live Hard-bot think cost panel, in every build. `bot_cost_overlay_toggle` (F9, gamepad
## Back + left-stick click) shows or hides it. While visible it keeps
## core/ai/BotThinkCostCollector enabled (the bots then take their clock reads); hidden = disabled = zero
## cost, and the match context is not read. Reads the collector only: local, never networked, never writes
## game state. Bots run on the host, so a client shows one line instead of a table. Built on UiDebugPanel.
## The parent hands in `config` and `match_context` before add_child.
## Selector: while Back (camera_snap_home) is held, ui_left / ui_right (arrow keys, D-pad) step
## all bots -> slot A -> slot B ... (a chord, so the arrows keep their gameplay meaning otherwise).

const CANVAS_LAYER: int = 100
const ALL_SLOTS: int = -1
const HEADERS: PackedStringArray = ["phase", "mean us", "p95 us", "max us", "units", "us/unit", "share %"]
const ROW_SNAPSHOT: String = "SNAPSHOT"
const ROW_OTHER: String = "OTHER"
const HEADING: String = "BOT COST"
const NOTE_HEADER: StringName = &"header"
const NOTE_STATUS: StringName = &"status"
const NOTE_FOOTER: StringName = &"footer"
const TABLE_ID: StringName = &"phases"
const NO_VALUE: String = "-"
const CLIENT_LINE: String = "Bot think costs are measured on the host."
const EMPTY_LINE: String = "No bot thinks yet."

var config: DebugConfig = null
var match_context: MatchContext = null
var selected_slot: int = ALL_SLOTS

var _panel: UiDebugPanel = null
var _since_refresh_s: float = 0.0


func _ready() -> void:
	layer = CANVAS_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	if config == null:
		config = DebugConfig.new()
	_build()
	_apply_visibility(false)


func _exit_tree() -> void:
	if _panel != null and _panel.visible:
		BotThinkCostCollector.disable()


func is_shown() -> bool:
	return _panel != null and _panel.visible


func toggle() -> void:
	set_shown(not is_shown())


func set_shown(shown: bool) -> void:
	if _panel == null or shown == _panel.visible:
		return
	_apply_visibility(shown)


func _apply_visibility(shown: bool) -> void:
	_panel.visible = shown
	if shown:
		BotThinkCostCollector.enable("overlay", -1, true)
		_since_refresh_s = 0.0
		refresh()
	else:
		BotThinkCostCollector.disable()


## Top band, left of the HUD's timer ring, or under the stats cluster on a narrow canvas
## (ui/debug/DebugOverlayLayout.gd); follows the HUD scale.
func _place() -> void:
	DebugOverlayLayout.place_bot_cost(_panel, config)


func _process(delta: float) -> void:
	if not is_shown():
		return
	_place()
	_since_refresh_s += delta
	if _since_refresh_s >= config.bot_cost_refresh_s:
		_since_refresh_s = 0.0
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"bot_cost_overlay_toggle"):
		# tools/bootstrap_project.gd's DECISION: the pad half only counts while Back is held.
		if event is InputEventJoypadButton and not Input.is_action_pressed(&"camera_snap_home"):
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not is_shown() or not Input.is_action_pressed(&"camera_snap_home"):
		return
	if event.is_action_pressed(&"ui_right"):
		step_selection(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_left"):
		step_selection(-1)
		get_viewport().set_input_as_handled()


## Steps the selector over [all, slots...] with wrap-around.
func step_selection(direction: int) -> void:
	var collector: BotThinkCostCollector = BotThinkCostCollector.current()
	var choices: Array[int] = [ALL_SLOTS]
	if collector != null:
		for id: int in collector.slot_ids():
			choices.append(id)
	var index: int = maxi(choices.find(selected_slot), 0)
	selected_slot = choices[posmod(index + direction, choices.size())]
	refresh()


func _is_client() -> bool:
	return match_context != null and match_context.net_is_client()


## Rebuilds the text from the collector (called on the refresh timer, on show and on a selector step).
## Does nothing while hidden, so a hidden panel reads neither the collector nor the match context.
func refresh() -> void:
	if not is_shown():
		return
	var collector: BotThinkCostCollector = BotThinkCostCollector.current()
	var report: BotThinkCostReport = null
	if collector != null and collector.has_data():
		report = collector.aggregate() if selected_slot == ALL_SLOTS else collector.for_slot(selected_slot)
	if report == null or not report.has_data():
		_show_status(CLIENT_LINE if _is_client() else EMPTY_LINE)
		return
	_panel.set_note(NOTE_STATUS, "")
	_panel.set_note(NOTE_HEADER, header_text(report, collector.slot_ids().size(), selected_slot))
	_panel.set_table(TABLE_ID, "", HEADERS, table_rows(report))
	_panel.set_note(NOTE_FOOTER, "\n".join(footer_lines(report)))


func _show_status(line: String) -> void:
	_panel.set_note(NOTE_HEADER, "")
	_panel.set_note(NOTE_STATUS, line)
	_panel.set_table(TABLE_ID, "", HEADERS, [] as Array[DebugRow])
	_panel.set_note(NOTE_FOOTER, "")


## Pure: header line (window size and bot count).
static func header_text(report: BotThinkCostReport, bot_count: int, slot: int) -> String:
	var who: String = "all bots" if slot == ALL_SLOTS else "slot %d" % slot
	return "[%s]   %d bots   window %d thinks / %d frames" % [
		who, bot_count, report.think_count(), report.frame_count()]


## Pure: table rows, one per phase, then snapshot build and other frame work. `warn` marks the
## top-ranked (most expensive) phase.
static func table_rows(report: BotThinkCostReport) -> Array[DebugRow]:
	var rows: Array[DebugRow] = []
	var top: int = report.ranking()[0]
	for i: int in range(BotThinkCostReport.PHASE_COUNT):
		var s: Dictionary = report.phase_stats(i)
		rows.append(_row(PackedStringArray([
			s["name"], "%.1f" % s["mean_us"], "%.1f" % s["p95_us"], "%.0f" % s["max_us"],
			"%.2f" % s["units"], "%.2f" % s["us_per_unit"], "%.1f" % s["share_pct"]]), i == top))
	var o: Dictionary = report.outside_stats()
	rows.append(_row(PackedStringArray([
		ROW_SNAPSHOT, "%.1f" % o["build_mean_us"], "%.1f" % o["build_p95_us"],
		NO_VALUE, NO_VALUE, NO_VALUE, NO_VALUE]), false))
	rows.append(_row(PackedStringArray([
		ROW_OTHER, "%.1f" % (float(o["apply_mean_us"]) + float(o["other_tick_mean_us"])),
		NO_VALUE, NO_VALUE, NO_VALUE, NO_VALUE, NO_VALUE]), false))
	return rows


static func _row(cells: PackedStringArray, warn: bool) -> DebugRow:
	var row: DebugRow = DebugRow.new()
	row.cells = cells
	row.warn = warn
	return row


## Pure: PROBE split, latency and per-frame lines.
static func footer_lines(report: BotThinkCostReport) -> PackedStringArray:
	var p: Dictionary = report.probe_split()
	var l: Dictionary = report.latency_stats()
	var f: Dictionary = report.frame_stats()
	return PackedStringArray([
		"PROBE physics %.1f us (p95 %.1f, %.1f calls) vs maths %.1f us   physics %.0f%% of PROBE" % [
			p["call_mean_us"], p["call_p95_us"], p["calls_per_think"], p["rest_mean_us"], p["call_share_of_probe_pct"]],
		"latency %.1f ticks (p95 %.0f, max %.0f)   %.2f ms (p95 %.2f, max %.2f)" % [
			l["ticks_mean"], l["ticks_p95"], l["ticks_max"], l["wall_ms_mean"], l["wall_ms_p95"], l["wall_ms_max"]],
		"bot frame %.3f ms mean / %.3f ms p99" % [f["mean_ms"], f["p99_ms"]],
		fill_fallback_line(report),
	])


## Pure: how often the zero-targeted FILL fallback ran in the window.
static func fill_fallback_line(report: BotThinkCostReport) -> String:
	var ff: Dictionary = report.fill_fallback_stats()
	return "FILL fallback: %d of %d thinks (%.1f%%, %d sites)" % [ff["count"], ff["thinks"], ff["share_pct"], ff["sites"]]


func _build() -> void:
	_panel = UiDebugPanel.new()
	_panel.heading = HEADING
	_panel.toggle_action = &"bot_cost_overlay_toggle"
	_panel.modifier_action = &"camera_snap_home"
	_panel.custom_minimum_size.x = config.bot_cost_panel_width_px
	_panel.visible = false
	add_child(_panel)
	_place()
