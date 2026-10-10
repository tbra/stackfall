class_name PerfOverlay
extends CanvasLayer
## Bontago-470.8: debug-only performance overlay. `perf_overlay_toggle` (F1,
## gamepad Back + right-stick click) cycles HIDDEN -> BASIC -> DETAILED ->
## HIDDEN. Reads game/PerfSampler.gd only; local, never networked, and never
## writes game state.
##
## BASIC: fps, frame/physics ms, block counter (live, awake, sleeping).
## DETAILED: adds process ms, physics-step split (our probes), draw calls,
## objects/primitives, memory, node/object counts, active bodies, network, and a
## rolling frame/physics/blocks graph.

enum Mode { HIDDEN, BASIC, DETAILED }

var sampler: PerfSampler = null
var config: DebugConfig = null

var _mode: Mode = Mode.HIDDEN
var _panel: PanelContainer = null
var _label: Label = null
var _graph: _PerfGraph = null


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	if config == null:
		config = DebugConfig.new()
	_build()
	_apply_mode()
	if sampler != null:
		sampler.sampled.connect(_on_sampled)


func mode() -> Mode:
	return _mode


## HIDDEN -> BASIC -> DETAILED -> HIDDEN.
static func next_mode(current: Mode) -> Mode:
	return ((int(current) + 1) % Mode.size()) as Mode


func cycle_mode() -> void:
	_mode = next_mode(_mode)
	_apply_mode()
	if sampler != null and not sampler.latest.is_empty():
		_on_sampled(sampler.latest)


func _unhandled_input(event: InputEvent) -> void:
	if not DebugMode.is_enabled():
		return
	if not event.is_action_pressed(&"perf_overlay_toggle"):
		return
	# tools/bootstrap_project.gd's DECISION: the pad half is right-stick click,
	# accepted only while Back (camera_snap_home) is held, like F3's chord.
	if event is InputEventJoypadButton and not Input.is_action_pressed(&"camera_snap_home"):
		return
	cycle_mode()
	get_viewport().set_input_as_handled()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = config.overlay_background_color()
	# DECISION (Bontago-hfa.9): padding and corner come from the arcade tokens; the background
	# colour stays DebugConfig.overlay_background_color() (owner-tunable debug resource).
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	style.set_content_margin_all(float(arcade.space_2_px))
	style.set_corner_radius_all(arcade.radius_chip_px)
	_panel.add_theme_stylebox_override(&"panel", style)
	# Top-right corner; grows left/down from the anchor.
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -config.overlay_margin.x
	_panel.offset_top = config.overlay_margin.y
	add_child(_panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override(&"font_size", config.overlay_font_size)
	_label.add_theme_color_override(&"font_color", config.overlay_text_color())
	box.add_child(_label)
	_graph = _PerfGraph.new()
	_graph.config = config
	_graph.sampler = sampler
	_graph.custom_minimum_size = config.graph_size
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_graph)


func _apply_mode() -> void:
	if _panel == null:
		return
	_panel.visible = _mode != Mode.HIDDEN
	_graph.visible = _mode == Mode.DETAILED


func _on_sampled(m: Dictionary) -> void:
	if _mode == Mode.HIDDEN:
		return
	_label.text = format_metrics(m, _mode)
	var warn: bool = float(m.get("frame_ms_max", 0.0)) >= config.warn_frame_ms
	_label.add_theme_color_override(&"font_color", config.overlay_warn_color() if warn else config.overlay_text_color())
	if _mode == Mode.DETAILED:
		_graph.queue_redraw()


## Pure text builder (unit-tested).
static func format_metrics(m: Dictionary, mode_value: Mode) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var window: String = "%.0f s" % float(m.get("window_s", 0.0))
	lines.append("%.0f fps   frame %.1f ms avg / %.1f worst (%s)" % [
		float(m.get("fps", 0.0)), float(m.get("frame_ms", 0.0)), float(m.get("frame_ms_max", 0.0)), window])
	lines.append("physics tick %.2f ms avg / %.2f worst (%s)" % [
		float(m.get("physics_ms", 0.0)), float(m.get("physics_ms_max", 0.0)), window])
	lines.append("physics steps/frame %d now / %d peak, %.0f%% frames >1 (max %d)" % [
		int(m.get("steps_current", 0)), int(m.get("steps_peak", 0)),
		float(m.get("steps_multi_pct", 0.0)), int(m.get("steps_max_setting", 0))])
	lines.append("effects nodes %d now / %d peak" % [
		int(m.get("effects_current", 0)), int(m.get("effects_peak", 0))])
	lines.append("blocks %d  (awake %d / asleep %d)" % [
		int(m.get("blocks_total", 0)), int(m.get("blocks_awake", 0)), int(m.get("blocks_sleeping", 0))])
	if mode_value != Mode.DETAILED:
		return "\n".join(lines)
	lines.append("-- our ticks (mean / worst ms, load %)")
	for key: String in ["territory", "weather", "gifts", "registry", "block_effects", "snapshot"]:
		lines.append("  %-13s %.2f / %.2f  %.1f%%" % [
			key, float(m.get("%s_ms" % key, 0.0)), float(m.get("%s_peak_ms" % key, 0.0)),
			float(m.get("%s_load_pct" % key, 0.0))])
	lines.append("draw calls %d   objs %d   prims %d" % [
		int(m.get("draw_calls", 0)), int(m.get("objects_in_frame", 0)), int(m.get("primitives", 0))])
	lines.append("vram %.0f MB   static mem %.0f MB" % [
		float(m.get("vram_mb", 0.0)), float(m.get("static_mem_mb", 0.0))])
	lines.append("nodes %d   objects %d   orphans %d" % [
		int(m.get("node_count", 0)), int(m.get("object_count", 0)), int(m.get("orphan_nodes", 0))])
	var weather_id: String = str(m.get("weather_id", ""))
	lines.append("%s   players %d   weather %s %.2f" % [
		str(m.get("match_state", "?")), int(m.get("players", 0)),
		weather_id if weather_id != "" else "-", float(m.get("weather_intensity", 0.0))])
	if int(m.get("net_mode", 0)) != 0:
		lines.append("net peers %d  ping %.0f ms  snapshots %.0f B/s" % [
			int(m.get("net_peers", 0)), float(m.get("net_ping_ms", 0.0)),
			float(m.get("net_snapshot_bps", 0.0))])
	return "\n".join(lines)


## Lightweight rolling graph: frame ms (green), physics ms (orange) and block
## count (blue), each scaled to its own ceiling from DebugConfig.
class _PerfGraph:
	extends Control

	var config: DebugConfig = null
	var sampler: PerfSampler = null

	func _draw() -> void:
		if sampler == null or config == null:
			return
		# DECISION (Bontago-hfa.9): the graph well is the arcade disc-950 token at the soft-shadow alpha.
		var well: Color = MenuStyleFactory.arcade_tuning().disc_950_color
		draw_rect(Rect2(Vector2.ZERO, size), Color(well.r, well.g, well.b, MenuStyleFactory.arcade_tuning().panel_shadow_alpha))
		var budget_y: float = size.y * (1.0 - clampf(config.graph_budget_ms / config.graph_frame_ms_max, 0.0, 1.0))
		draw_line(Vector2(0.0, budget_y), Vector2(size.x, budget_y), config.graph_budget_color(), 1.0)
		_plot(sampler.history_blocks, config.graph_blocks_max, config.graph_blocks_color())
		_plot(sampler.history_physics_ms, config.graph_physics_ms_max, config.graph_physics_color())
		_plot(sampler.history_frame_ms, config.graph_frame_ms_max, config.graph_frame_color())

	func _plot(values: PackedFloat32Array, ceiling: float, color: Color) -> void:
		var count: int = values.size()
		if count < 2:
			return
		var capacity: int = maxi(int(ceilf(config.graph_window_s / config.graph_interval_s)), 2)
		var step: float = size.x / float(capacity - 1)
		var start_x: float = size.x - step * float(count - 1)
		var points: PackedVector2Array = PackedVector2Array()
		for i: int in range(count):
			var y: float = size.y * (1.0 - clampf(values[i] / ceiling, 0.0, 1.0))
			points.append(Vector2(start_x + step * float(i), y))
		draw_polyline(points, color, 1.5)
