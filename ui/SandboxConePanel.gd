class_name SandboxConePanel
extends CanvasLayer
## Sandbox comparisons and an explicit live-only sandbox A/B selector.
signal measure_requested(mode: int, angle_degrees: float, height_source: int, base_mode: int)
signal open_changed(open: bool)
signal live_territory_mode_changed(mode: int, angle_degrees: float, height_source: int, base_mode: int)
signal block_collision_freeze_changed(frozen: bool)
signal territory_cache_changed(enabled: bool)

var opened: bool = false
var _panel: PanelContainer
var _angle: SpinBox
var _angle_row: HBoxContainer
var _cone_options_row: HBoxContainer
var _mode: OptionButton
var _height_source: OptionButton
var _base_mode: OptionButton
var _measure_button: Button
var _live_mode: OptionButton
var _freeze_blocks: CheckBox
var _cache_territory: CheckBox
var _live_badge: Label
var _explanation: Label
var _status: Label
var _baseline_map: TextureRect
var _cone_map: TextureRect
var _experiment_heading: Label
var _live: Label
var _hud: PanelContainer
var _hud_live: Label
var _hud_elapsed: float = 0.0


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -310.0
	_panel.offset_right = 310.0
	_panel.offset_top = -305.0
	_panel.offset_bottom = 305.0
	_panel.visible = false
	add_child(_panel)
	_hud = PanelContainer.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hud.offset_left = -540.0
	_hud.offset_right = -8.0
	_hud.offset_top = 56.0
	_hud.offset_bottom = 180.0
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud_style: StyleBoxFlat = StyleBoxFlat.new()
	hud_style.bg_color = Color(0.04, 0.05, 0.08, 0.78)
	hud_style.content_margin_left = 8.0
	hud_style.content_margin_right = 8.0
	hud_style.content_margin_top = 6.0
	hud_style.content_margin_bottom = 6.0
	_hud.add_theme_stylebox_override("panel", hud_style)
	_hud_live = Label.new()
	_hud_live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud_live.add_theme_font_size_override("font_size", 14)
	_hud.add_child(_hud_live)
	add_child(_hud)
	_live_badge = Label.new()
	_live_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_live_badge.offset_left = -400.0
	_live_badge.offset_right = -12.0
	_live_badge.offset_top = 12.0
	_live_badge.offset_bottom = 48.0
	_live_badge.visible = false
	add_child(_live_badge)
	var list: VBoxContainer = VBoxContainer.new()
	_panel.add_child(list)
	var title: Label = Label.new()
	title.text = "SANDBOX TERRITORY — EXPERIMENTS"
	list.add_child(title)
	_explanation = Label.new()
	_explanation.text = "Static snapshot only. Match capture, holes, placement and physics remain unchanged."
	_explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(_explanation)
	var mode_row: HBoxContainer = HBoxContainer.new()
	list.add_child(mode_row)
	var mode_label: Label = Label.new()
	mode_label.text = "Method"
	mode_row.add_child(mode_label)
	_mode = OptionButton.new()
	_mode.add_item("Cone projection", SandboxConeComparison.MODE_CONE)
	_mode.add_item("Exact containment", SandboxConeComparison.MODE_CONTAINMENT)
	_mode.item_selected.connect(_on_mode_selected)
	mode_row.add_child(_mode)
	_angle_row = HBoxContainer.new()
	_angle_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(_angle_row)
	var angle_label: Label = Label.new()
	angle_label.text = "Cone half-angle"
	angle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_angle_row.add_child(angle_label)
	_angle = SpinBox.new()
	_angle.min_value = 5.0
	_angle.max_value = 75.0
	_angle.step = 0.1
	_angle.value = 45.0
	_angle.value_changed.connect(_on_angle_changed)
	_angle_row.add_child(_angle)
	_cone_options_row = HBoxContainer.new()
	list.add_child(_cone_options_row)
	var height_label: Label = Label.new()
	height_label.text = "Height"
	_cone_options_row.add_child(height_label)
	_height_source = OptionButton.new()
	_height_source.add_item("Block center", SandboxConeComparison.HEIGHT_CENTER)
	_height_source.add_item("Block top", SandboxConeComparison.HEIGHT_TOP)
	_height_source.select(SandboxConeComparison.HEIGHT_TOP)
	_height_source.item_selected.connect(_on_cone_option_changed)
	_cone_options_row.add_child(_height_source)
	var base_label: Label = Label.new()
	base_label.text = "Base"
	_cone_options_row.add_child(base_label)
	_base_mode = OptionButton.new()
	_base_mode.add_item("None (old)", SandboxConeExperiment.BASE_NONE)
	_base_mode.add_item("Min 1.5 m", SandboxConeExperiment.BASE_FLOOR)
	_base_mode.add_item("Add 1.5 m", SandboxConeExperiment.BASE_ADDITIVE)
	_base_mode.select(SandboxConeExperiment.BASE_ADDITIVE)
	_base_mode.tooltip_text = "Min uses max(1.5, height × tan(angle)); Add uses 1.5 + height × tan(angle). Both use the current radius cap."
	_base_mode.item_selected.connect(_on_cone_option_changed)
	_cone_options_row.add_child(_base_mode)
	var controls: HBoxContainer = HBoxContainer.new()
	list.add_child(controls)
	var measure: Button = Button.new()
	_measure_button = measure
	measure.text = "Measure current blocks"
	measure.pressed.connect(_request_measurement)
	controls.add_child(measure)
	var close: Button = Button.new()
	close.text = "Close / return to sandbox"
	close.pressed.connect(func() -> void: set_open(false))
	controls.add_child(close)
	_live_mode = OptionButton.new()
	_live_mode.add_item("Live: current", MatchAutoload.SANDBOX_TERRITORY_CURRENT)
	_live_mode.add_item("Live: cones", MatchAutoload.SANDBOX_TERRITORY_CONE)
	_live_mode.add_item("Live: paused", MatchAutoload.SANDBOX_TERRITORY_PAUSED)
	_live_mode.tooltip_text = "Current uses today's territory rule; Cones runs the selected cone settings live; Paused freezes territory CPU updates while physics continues. Sandbox only."
	_live_mode.item_selected.connect(_on_live_mode_selected)
	controls.add_child(_live_mode)
	_freeze_blocks = CheckBox.new()
	_freeze_blocks.text = "Freeze block simulation"
	_freeze_blocks.tooltip_text = "Diagnostic: holds blocks in place, disables their contacts and settlement updates, while territory and rendering keep running on the same settled-block snapshot. Uncheck or reset to restore physics."
	_freeze_blocks.toggled.connect(func(frozen: bool) -> void: block_collision_freeze_changed.emit(frozen))
	list.add_child(_freeze_blocks)
	_cache_territory = CheckBox.new()
	_cache_territory.text = "Cache unchanged territory"
	_cache_territory.button_pressed = true
	_cache_territory.tooltip_text = "Reuses circles and connectivity when every settled block, home flag, field transform and territory setting is unchanged. Capture and hole timers still advance. Uncheck here to compare against uncached solving."
	_cache_territory.toggled.connect(func(enabled: bool) -> void: territory_cache_changed.emit(enabled))
	list.add_child(_cache_territory)
	var maps: HBoxContainer = HBoxContainer.new()
	list.add_child(maps)
	_baseline_map = _map_column(maps, "CURRENT CIRCLES (ALL POINTS)")
	_cone_map = _map_column(maps, "EXPERIMENTAL CONES")
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 100.0
	_status.text = "Place blocks in sandbox, then measure a snapshot.\nGrey = contested; dark = unowned."
	list.add_child(_status)
	_live = Label.new()
	_live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(_live)
	set_process(true)
	_on_mode_selected(_mode.selected)


func _map_column(parent: HBoxContainer, heading: String) -> TextureRect:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var label: Label = Label.new()
	label.text = heading
	column.add_child(label)
	if heading == "EXPERIMENTAL CONES":
		_experiment_heading = label
	var map: TextureRect = TextureRect.new()
	map.custom_minimum_size = Vector2(220.0, 220.0)
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	column.add_child(map)
	return map


func set_open(open: bool) -> void:
	opened = open
	_panel.visible = open
	_hud.visible = not open
	open_changed.emit(open)
	if open:
		var live_raster: TerritoryRaster = Match.raster()
		if live_raster != null:
			var base_radius: float = live_raster.tuning().influence_base
			_base_mode.set_item_text(SandboxConeExperiment.BASE_FLOOR, "Min %.1f m" % base_radius)
			_base_mode.set_item_text(SandboxConeExperiment.BASE_ADDITIVE, "Add %.1f m" % base_radius)
			_base_mode.tooltip_text = ("Min uses max(%.1f, height × tan(angle)); Add uses %.1f + height × tan(angle). Both use the current radius cap." % [base_radius, base_radius])
		_measure_button.grab_focus()
		_request_measurement()


func _on_mode_selected(_index: int) -> void:
	var containment: bool = _mode.get_selected_id() == SandboxConeComparison.MODE_CONTAINMENT
	_angle_row.visible = not containment
	_cone_options_row.visible = not containment
	_experiment_heading.text = "EXACT CONTAINMENT" if containment else "EXPERIMENTAL CONES"
	_explanation.text = ("Exact containment is snapshot-only. The Live selector independently controls sandbox territory."
		if containment else "Maps are snapshots. Select Live: cones to run these settings in the sandbox.")
	if opened:
		_request_measurement()


func _on_cone_option_changed(_index: int) -> void:
	if opened:
		_request_measurement()
	if _live_mode.get_selected_id() == MatchAutoload.SANDBOX_TERRITORY_CONE:
		_emit_live_mode()


func _on_angle_changed(_value: float) -> void:
	if _live_mode != null and _live_mode.get_selected_id() == MatchAutoload.SANDBOX_TERRITORY_CONE:
		_emit_live_mode()


func _request_measurement() -> void:
	measure_requested.emit(
		_mode.get_selected_id(), _angle.value, _height_source.get_selected_id(), _base_mode.get_selected_id()
	)


func set_live_territory_mode(mode: int) -> void:
	_live_mode.select(mode)
	_update_live_badge()


func set_blocks_frozen(frozen: bool) -> void:
	_freeze_blocks.set_pressed_no_signal(frozen)


func set_cache_enabled(enabled: bool) -> void:
	_cache_territory.set_pressed_no_signal(enabled)


func _on_live_mode_selected(_index: int) -> void:
	_update_live_badge()
	_emit_live_mode()


func _emit_live_mode() -> void:
	live_territory_mode_changed.emit(
		_live_mode.get_selected_id(), _angle.value, _height_source.get_selected_id(), _base_mode.get_selected_id()
	)


func _update_live_badge() -> void:
	var mode: int = _live_mode.get_selected_id()
	_live_badge.visible = mode != MatchAutoload.SANDBOX_TERRITORY_CURRENT
	_live_badge.text = ("LIVE CONE TERRITORY — F2 to switch" if mode == MatchAutoload.SANDBOX_TERRITORY_CONE
		else "TERRITORY SOLVE PAUSED — F2 to resume")


func show_snapshot(result: Dictionary, old_raster: TerritoryRaster, cone_raster: TerritoryRaster, colors: PackedColorArray) -> void:
	if result.has("error"):
		_status.text = String(result["error"])
		return
	_baseline_map.texture = _map_texture(old_raster, colors)
	_cone_map.texture = _map_texture(cone_raster, colors)
	_status.text = ("Blocks: %d   Culled: %d   Kept: %d   Different cells: %d (%.2f%%)\n"
		+ "Current: collect %.2f + solve %.2f + raster %.2f = %.2f ms\n"
		+ "%s: same collect + filter %.2f + solve %.2f + raster %.2f = %.2f ms\n"
		+ "One-shot debug-build times; sampling itself adds work. Click again after placing blocks.") % [
		int(result["candidate_count"]), int(result["culled_count"]), int(result["kept_count"]),
		int(result["different_cells"]),
		float(result["different_percent"]), float(result["collect_ms"]),
		float(result["old_solve_ms"]), float(result["old_raster_ms"]), float(result["old_total_ms"]),
		String(result["method"]), float(result["experiment_filter_ms"]), float(result["experiment_solve_ms"]),
		float(result["experiment_raster_ms"]), float(result["experiment_total_ms"]),
	]


func _map_texture(raster: TerritoryRaster, colors: PackedColorArray) -> Texture2D:
	var side: int = raster.grid().res
	var owners: PackedByteArray = raster.owner_bytes()
	var states: PackedByteArray = raster.state_bytes()
	var pixels: PackedByteArray = PackedByteArray()
	pixels.resize(side * side * 4)
	for index: int in range(side * side):
		var color: Color = Color(0.11, 0.12, 0.17, 1.0)
		if (states[index] & TerritoryRaster.STATE_CONTESTED) != 0:
			color = Color(0.68, 0.67, 0.68, 1.0)
		elif owners[index] > 0 and owners[index] - 1 < colors.size():
			color = colors[owners[index] - 1]
		pixels[index * 4] = roundi(color.r * 255.0)
		pixels[index * 4 + 1] = roundi(color.g * 255.0)
		pixels[index * 4 + 2] = roundi(color.b * 255.0)
		pixels[index * 4 + 3] = 255
	return ImageTexture.create_from_image(Image.create_from_data(side, side, false, Image.FORMAT_RGBA8, pixels))


func _process(delta: float) -> void:
	_hud_elapsed += delta
	if _hud_elapsed < 0.2:
		return
	_hud_elapsed = 0.0
	var mode: int = _live_mode.get_selected_id()
	var mode_name: String = "CURRENT" if mode == MatchAutoload.SANDBOX_TERRITORY_CURRENT else ("CONES" if mode == MatchAutoload.SANDBOX_TERRITORY_CONE else "PAUSED")
	_live.text = "Live: %.0f FPS   Physics %.2f ms   Territory %s   Blocks %s   Cache %s" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		mode_name, "FROZEN" if _freeze_blocks.button_pressed else "SIMULATING",
		"ON" if _cache_territory.button_pressed else "OFF"
	]
	var profile: Dictionary = Match._territory.sandbox_profile()
	var sample: Dictionary = profile["step_ms"]
	if mode != MatchAutoload.SANDBOX_TERRITORY_PAUSED and not sample.is_empty():
		_live.text += "\nTerritory tick %.2f ms / %d steps; last step %.2f ms" % [
			profile["tick_ms"], profile["steps"], sample["total"]
		]
		_live.text += "   Cache hits %d" % profile["cache_hits"]
		_live.text += "\nCollect %.2f  Solve %.2f  Raster %.2f  Overlay %.2f  Other %.2f ms" % [
			sample["collect"], sample["solve"], sample["raster"], sample["overlay"], sample["other"]
		]
	_hud_live.text = _live.text
