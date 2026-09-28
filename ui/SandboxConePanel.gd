class_name SandboxConePanel
extends CanvasLayer
## Sandbox-only, read-only comparison of the existing territory projection and
## an angle-based cone experiment. Does not modify Match or Field's raster.
signal measure_requested(angle_degrees: float)
signal open_changed(open: bool)

var opened: bool = false
var _panel: PanelContainer
var _angle: SpinBox
var _measure_button: Button
var _status: Label
var _baseline_map: TextureRect
var _cone_map: TextureRect
var _live: Label


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
	var list: VBoxContainer = VBoxContainer.new()
	_panel.add_child(list)
	var title: Label = Label.new()
	title.text = "SANDBOX TERRITORY — CONE EXPERIMENT"
	list.add_child(title)
	var explanation: Label = Label.new()
	explanation.text = "Static snapshot only. Match capture, holes, placement and physics remain unchanged."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(explanation)
	var angle_row: HBoxContainer = HBoxContainer.new()
	list.add_child(angle_row)
	var angle_label: Label = Label.new()
	angle_label.text = "Cone half-angle"
	angle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angle_row.add_child(angle_label)
	_angle = SpinBox.new()
	_angle.min_value = 5.0
	_angle.max_value = 75.0
	_angle.step = 1.0
	_angle.value = 30.0
	angle_row.add_child(_angle)
	var controls: HBoxContainer = HBoxContainer.new()
	list.add_child(controls)
	var measure: Button = Button.new()
	_measure_button = measure
	measure.text = "Measure current blocks"
	measure.pressed.connect(func() -> void: measure_requested.emit(_angle.value))
	controls.add_child(measure)
	var close: Button = Button.new()
	close.text = "Close / return to sandbox"
	close.pressed.connect(func() -> void: set_open(false))
	controls.add_child(close)
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
	list.add_child(_live)
	set_process(true)


func _map_column(parent: HBoxContainer, heading: String) -> TextureRect:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var label: Label = Label.new()
	label.text = heading
	column.add_child(label)
	var map: TextureRect = TextureRect.new()
	map.custom_minimum_size = Vector2(270.0, 270.0)
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	column.add_child(map)
	return map


func set_open(open: bool) -> void:
	opened = open
	_panel.visible = open
	open_changed.emit(open)
	if open:
		_measure_button.grab_focus()
		measure_requested.emit(_angle.value)


func show_snapshot(result: Dictionary, old_raster: TerritoryRaster, cone_raster: TerritoryRaster, colors: PackedColorArray) -> void:
	if result.has("error"):
		_status.text = String(result["error"])
		return
	_baseline_map.texture = _map_texture(old_raster, colors)
	_cone_map.texture = _map_texture(cone_raster, colors)
	_status.text = ("Blocks: %d   Culled: %d   Kept: %d   Different cells: %.1f%%\n"
		+ "Current: collect %.2f + solve %.2f + raster %.2f = %.2f ms\n"
		+ "Cone: same collect + filter %.2f + solve %.2f + raster %.2f = %.2f ms\n"
		+ "One-shot debug-build times; sampling itself adds work. Click again after placing blocks.") % [
		int(result["candidate_count"]), int(result["culled_count"]), int(result["kept_count"]),
		float(result["different_percent"]), float(result["collect_ms"]),
		float(result["old_solve_ms"]), float(result["old_raster_ms"]), float(result["old_total_ms"]),
		float(result["cone_filter_ms"]), float(result["cone_solve_ms"]),
		float(result["cone_raster_ms"]), float(result["cone_total_ms"]),
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


func _process(_delta: float) -> void:
	if not opened:
		return
	_live.text = "Live: %.0f FPS   Physics %.2f ms/frame" % [
		Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	]
