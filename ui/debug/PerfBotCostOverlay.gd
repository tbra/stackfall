class_name PerfBotCostOverlay
extends CanvasLayer
## Bontago-1t5.63: debug-only live Hard-bot think cost overlay. `bot_cost_overlay_toggle` (F2, gamepad
## Back + left-stick click) shows or hides it, gated by game/debug/DebugMode.gd like F1. While visible it keeps
## core/ai/BotThinkCostCollector enabled (the bots then take their clock reads); hidden = disabled = zero
## cost. Reads the collector only: local, never networked, never writes game state. Bots run on the host,
## so a client shows one line instead of a table.
## Selector: while Back (camera_snap_home) is held, ui_left / ui_right (arrow keys, D-pad) step
## all bots -> slot A -> slot B ... (a chord, so the arrows keep their gameplay meaning otherwise).

const CANVAS_LAYER: int = 100
const ALL_SLOTS: int = -1
const COLUMN_COUNT: int = 7
const HEADERS: PackedStringArray = ["phase", "mean us", "p95 us", "max us", "units", "us/unit", "share %"]
const ROW_SNAPSHOT: String = "SNAPSHOT"
const ROW_OTHER: String = "OTHER"
const NO_VALUE: String = "-"
const CLIENT_LINE: String = "Bot think costs are measured on the host."
const EMPTY_LINE: String = "No bot thinks yet."

var config: DebugConfig = null
## Test seam: -1 = ask Net, 0 = host/offline, 1 = client.
var client_override: int = -1
var selected_slot: int = ALL_SLOTS

var _panel: PanelContainer = null
var _header: Label = null
var _status: Label = null
var _grid: GridContainer = null
var _footer: Label = null
var _since_refresh_s: float = 0.0
var _text_color: Color = Color.WHITE
var _hot_color: Color = Color.WHITE


func _ready() -> void:
	layer = CANVAS_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	if config == null:
		config = DebugConfig.new()
	_text_color = config.overlay_text_color()
	_hot_color = config.overlay_warn_color()
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


func _process(delta: float) -> void:
	if not is_shown():
		return
	if not DebugMode.is_enabled():
		set_shown(false)
		return
	_since_refresh_s += delta
	if _since_refresh_s >= config.bot_cost_refresh_s:
		_since_refresh_s = 0.0
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not DebugMode.is_enabled():
		return
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
	if client_override >= 0:
		return client_override == 1
	return Net.is_client()


## Rebuilds the text from the collector (called on the refresh timer, on show and by tests).
func refresh() -> void:
	if _panel == null:
		return
	var collector: BotThinkCostCollector = BotThinkCostCollector.current()
	var report: BotThinkCostReport = null
	if collector != null and collector.has_data():
		report = collector.aggregate() if selected_slot == ALL_SLOTS else collector.for_slot(selected_slot)
	if report == null or not report.has_data():
		_show_status(CLIENT_LINE if _is_client() else EMPTY_LINE)
		return
	_status.visible = false
	_grid.visible = true
	_footer.visible = true
	_header.text = header_text(report, collector.slot_ids().size(), selected_slot)
	_fill_grid(table_rows(report))
	_footer.text = "\n".join(footer_lines(report))


func _show_status(line: String) -> void:
	_status.text = line
	_status.visible = true
	_grid.visible = false
	_footer.visible = false
	_header.text = "Bot think cost"


## Pure: header line (window size and bot count).
static func header_text(report: BotThinkCostReport, bot_count: int, slot: int) -> String:
	var who: String = "all bots" if slot == ALL_SLOTS else "slot %d" % slot
	return "Bot think cost [%s]   %d bots   window %d thinks / %d frames   (Back + left/right: select)" % [
		who, bot_count, report.think_count(), report.frame_count()]


## Pure: table rows {cells: PackedStringArray, hot: bool}: one per phase, then snapshot build and other
## frame work. `hot` marks the top-ranked (most expensive) phase.
static func table_rows(report: BotThinkCostReport) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var top: int = report.ranking()[0]
	for i: int in range(BotThinkCostReport.PHASE_COUNT):
		var s: Dictionary = report.phase_stats(i)
		rows.append({"hot": i == top, "cells": PackedStringArray([
			s["name"], "%.1f" % s["mean_us"], "%.1f" % s["p95_us"], "%.0f" % s["max_us"],
			"%.2f" % s["units"], "%.2f" % s["us_per_unit"], "%.1f" % s["share_pct"]])})
	var o: Dictionary = report.outside_stats()
	rows.append({"hot": false, "cells": PackedStringArray([
		ROW_SNAPSHOT, "%.1f" % o["build_mean_us"], "%.1f" % o["build_p95_us"],
		NO_VALUE, NO_VALUE, NO_VALUE, NO_VALUE])})
	rows.append({"hot": false, "cells": PackedStringArray([
		ROW_OTHER, "%.1f" % (float(o["apply_mean_us"]) + float(o["other_tick_mean_us"])),
		NO_VALUE, NO_VALUE, NO_VALUE, NO_VALUE, NO_VALUE])})
	return rows


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


## Pure (Bontago-1t5.67): how often the zero-targeted FILL fallback ran in the window.
static func fill_fallback_line(report: BotThinkCostReport) -> String:
	var ff: Dictionary = report.fill_fallback_stats()
	return "FILL fallback: %d of %d thinks (%.1f%%, %d sites)" % [ff["count"], ff["thinks"], ff["share_pct"], ff["sites"]]


## The grid's cell labels in row order (header row first). For tests and the highlight.
func grid_cells() -> Array[Label]:
	var out: Array[Label] = []
	if _grid != null:
		for child: Node in _grid.get_children():
			out.append(child as Label)
	return out


func hot_color() -> Color:
	return _hot_color


func _fill_grid(rows: Array[Dictionary]) -> void:
	var needed: int = (rows.size() + 1) * COLUMN_COUNT
	var cells: Array[Label] = grid_cells()
	while cells.size() < needed:
		var cell: Label = _make_label()
		_grid.add_child(cell)
		cells.append(cell)
	for col: int in range(COLUMN_COUNT):
		_style_cell(cells[col], HEADERS[col], false, col)
	for r: int in range(rows.size()):
		var row: Dictionary = rows[r]
		var values: PackedStringArray = row["cells"] as PackedStringArray
		for col: int in range(COLUMN_COUNT):
			_style_cell(cells[(r + 1) * COLUMN_COUNT + col], values[col], bool(row["hot"]), col)


func _style_cell(cell: Label, text: String, hot: bool, col: int) -> void:
	cell.text = text
	cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if col == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	cell.add_theme_color_override(&"font_color", _hot_color if hot else _text_color)


func _make_label() -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", config.overlay_font_size)
	label.add_theme_color_override(&"font_color", _text_color)
	return label


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = config.overlay_background_color()
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	style.set_content_margin_all(float(arcade.space_2_px))
	style.set_corner_radius_all(arcade.radius_chip_px)
	_panel.add_theme_stylebox_override(&"panel", style)
	# Top-left corner (F1 owns the top-right); grows right/down from the anchor.
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = config.overlay_margin.x
	_panel.offset_top = config.overlay_margin.y
	add_child(_panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)
	_header = _make_label()
	box.add_child(_header)
	_status = _make_label()
	box.add_child(_status)
	_grid = GridContainer.new()
	_grid.columns = COLUMN_COUNT
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_theme_constant_override(&"h_separation", config.bot_cost_column_gap_px)
	box.add_child(_grid)
	_footer = _make_label()
	box.add_child(_footer)
