class_name PerfOverlay
extends CanvasLayer
## F1 performance panel, available in every build. `perf_overlay_toggle` (F1, gamepad Back + right-stick
## click) cycles HIDDEN -> BASIC -> DETAILED -> HIDDEN. Reads game/debug/PerfSampler.gd only; local, never
## networked, and never writes game state. Hidden, it asks the sampler for nothing (PerfSampler.set_wanted),
## so a demand-driven sampler does no work.
##
## BASIC: fps, frame and physics ms, physics steps, effects nodes, block counter (live, awake, sleeping).
## DETAILED: adds the six per-tick probes, draw calls, objects/primitives, memory, node/object counts, the
## match state with the network role, and a rolling frame/physics/blocks graph. Network numbers are F3's.
## Until the first stats window closes after opening, every value reads "-".

enum Mode { HIDDEN, BASIC, DETAILED }

## Loaded by path and called by name: Main builds this overlay, and naming the layout class here would pull
## it into Main's compile closure (tools/lint_layers.py).
const LAYOUT_SCRIPT_PATH: String = "res://ui/debug/DebugOverlayLayout.gd"

## Names for the sampler's `net_mode` (Net.Mode order).
const ROLE_NAMES: PackedStringArray = ["offline", "host", "client"]
const PROBE_KEYS: PackedStringArray = ["territory", "weather", "gifts", "registry", "block_effects", "snapshot"]

var sampler: PerfSampler = null
var config: DebugConfig = null

var _mode: Mode = Mode.HIDDEN
var _panel: UiDebugPanel = null
var _graph: UiDebugGraph = null
var _layout: GDScript = null


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	if config == null:
		config = DebugConfig.new()
	_layout = load(LAYOUT_SCRIPT_PATH) as GDScript
	_build()
	_apply_mode()
	if sampler != null:
		sampler.sampled.connect(_on_sampled)


## HIDDEN -> BASIC -> DETAILED -> HIDDEN.
static func next_mode(current: Mode) -> Mode:
	return ((int(current) + 1) % Mode.size()) as Mode


func cycle_mode() -> void:
	_mode = next_mode(_mode)
	_apply_mode()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"perf_overlay_toggle"):
		return
	# tools/bootstrap_project.gd's DECISION: the pad half is right-stick click,
	# accepted only while Back (camera_snap_home) is held, like F3's chord.
	if event is InputEventJoypadButton and not Input.is_action_pressed(&"camera_snap_home"):
		return
	cycle_mode()
	get_viewport().set_input_as_handled()


func _build() -> void:
	_panel = UiDebugPanel.new()
	_panel.heading = "Performance"
	_panel.toggle_action = &"perf_overlay_toggle"
	_panel.modifier_action = &"camera_snap_home"
	add_child(_panel)
	_graph = UiDebugGraph.new()
	_panel.content().add_child(_graph)
	_place()


## Top band, right of the HUD's timer ring (ui/debug/DebugOverlayLayout.gd); follows the HUD scale.
func _place() -> void:
	_layout.call(&"place_beside_centre", _panel, false, config)


func _process(_delta: float) -> void:
	if _mode != Mode.HIDDEN:
		_place()


func _apply_mode() -> void:
	if sampler != null:
		sampler.set_wanted(_mode != Mode.HIDDEN)
	if _panel == null:
		return
	_panel.visible = _mode != Mode.HIDDEN
	_graph.visible = _mode == Mode.DETAILED
	if _mode != Mode.HIDDEN:
		_show(sampler.latest if sampler != null else {})


func _on_sampled(m: Dictionary) -> void:
	if _mode != Mode.HIDDEN:
		_show(m)


func _show(m: Dictionary) -> void:
	_panel.set_note(&"window", "avg and worst over a %.0f s window" % config.stats_window_s)
	_panel.set_section(&"frame", "", rows(m, _mode, config.warn_frame_ms))
	_panel.set_table(&"probes", "our ticks", PackedStringArray(["", "mean", "worst", "load"]), probe_rows(m, _mode))
	if _mode == Mode.DETAILED and sampler != null:
		_graph.set_series(2, sampler.history_blocks, config.graph_blocks_max, config.graph_blocks_color())
		_graph.set_series(1, sampler.history_physics_ms, config.graph_physics_ms_max, config.graph_physics_color())
		_graph.set_series(0, sampler.history_frame_ms, config.graph_frame_ms_max, config.graph_frame_color())


## The name/value rows for `mode`; an empty `m` (no stats window closed yet) reads "-". The frame row is a
## warn row when the worst frame of the window is at or above `warn_frame_ms`.
static func rows(m: Dictionary, mode: Mode, warn_frame_ms: float) -> Array[DebugRow]:
	var out: Array[DebugRow] = []
	if mode == Mode.HIDDEN:
		return out
	out.append(DebugRow.pair("fps", _num(m, "fps", "%.0f")))
	out.append(DebugRow.pair("frame ms avg / worst",
		"%s / %s" % [_num(m, "frame_ms", "%.1f"), _num(m, "frame_ms_max", "%.1f")],
		float(m.get("frame_ms_max", 0.0)) >= warn_frame_ms))
	out.append(DebugRow.pair("physics tick ms avg / worst",
		"%s / %s" % [_num(m, "physics_ms", "%.2f"), _num(m, "physics_ms_max", "%.2f")]))
	out.append(DebugRow.pair("physics steps/frame now / peak",
		"%s / %s" % [_num(m, "steps_current", "%d"), _num(m, "steps_peak", "%d")]))
	out.append(DebugRow.pair("frames with >1 step (max %s)" % _num(m, "steps_max_setting", "%d"),
		_num(m, "steps_multi_pct", "%.0f%%")))
	out.append(DebugRow.pair("effects nodes now / peak",
		"%s / %s" % [_num(m, "effects_current", "%d"), _num(m, "effects_peak", "%d")]))
	out.append(DebugRow.pair("blocks", _num(m, "blocks_total", "%d")))
	out.append(DebugRow.pair("blocks awake / asleep",
		"%s / %s" % [_num(m, "blocks_awake", "%d"), _num(m, "blocks_sleeping", "%d")]))
	if mode != Mode.DETAILED:
		return out
	out.append(DebugRow.pair("draw calls", _num(m, "draw_calls", "%d")))
	out.append(DebugRow.pair("objects / primitives in frame",
		"%s / %s" % [_num(m, "objects_in_frame", "%d"), _num(m, "primitives", "%d")]))
	out.append(DebugRow.pair("vram / static mem MB",
		"%s / %s" % [_num(m, "vram_mb", "%.0f"), _num(m, "static_mem_mb", "%.0f")]))
	out.append(DebugRow.pair("nodes / objects / orphans", "%s / %s / %s" % [
		_num(m, "node_count", "%d"), _num(m, "object_count", "%d"), _num(m, "orphan_nodes", "%d")]))
	out.append(DebugRow.pair("match state", str(m.get("match_state", "-"))))
	out.append(DebugRow.pair("players", _num(m, "players", "%d")))
	var weather_id: String = str(m.get("weather_id", ""))
	out.append(DebugRow.pair("weather", "-" if m.is_empty() or weather_id == "" else
		"%s %.2f" % [weather_id, float(m.get("weather_intensity", 0.0))]))
	out.append(DebugRow.pair("network role", ROLE_NAMES[clampi(int(m.get("net_mode", 0)), 0, ROLE_NAMES.size() - 1)]
		if m.has("net_mode") else "-"))
	return out


## The six per-tick probes (mean ms, worst ms, load %) in DETAILED; empty otherwise, which hides the table.
static func probe_rows(m: Dictionary, mode: Mode) -> Array[DebugRow]:
	var out: Array[DebugRow] = []
	if mode != Mode.DETAILED:
		return out
	for key: String in PROBE_KEYS:
		var row: DebugRow = DebugRow.new()
		row.cells = PackedStringArray([key, _num(m, "%s_ms" % key, "%.2f"),
			_num(m, "%s_peak_ms" % key, "%.2f"), _num(m, "%s_load_pct" % key, "%.1f%%")])
		out.append(row)
	return out


static func _num(m: Dictionary, key: String, format: String) -> String:
	return format % m[key] if m.has(key) else "-"
