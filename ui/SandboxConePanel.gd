class_name SandboxConePanel
extends CanvasLayer
## Sandbox live territory settings: cone angle, height source, base mode and a pause
## toggle. (The static old-vs-cone snapshot comparison and the earlier linear
## radius model were removed by owner decision 2026-10-08, Bontago-1pi.111.)
signal open_changed(open: bool)
signal live_territory_mode_changed(mode: int, angle_degrees: float, height_source: int, base_mode: int)
signal block_collision_freeze_changed(frozen: bool)
signal territory_cache_changed(enabled: bool)

var opened: bool = false
var _panel: PanelContainer
var _angle: SpinBox
var _height_source: OptionButton
var _base_mode: OptionButton
var _live_mode: OptionButton
var _freeze_blocks: CheckBox
var _cache_territory: CheckBox
var _live_badge: Label
var _live: Label
var _hud_elapsed: float = 0.0


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -310.0
	_panel.offset_right = 310.0
	_panel.offset_top = -170.0
	_panel.offset_bottom = 170.0
	_panel.visible = false
	add_child(_panel)
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
	title.text = "SANDBOX TERRITORY — CONE SETTINGS"
	list.add_child(title)
	var angle_row: HBoxContainer = HBoxContainer.new()
	list.add_child(angle_row)
	var angle_label: Label = Label.new()
	angle_label.text = "Cone half-angle"
	angle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angle_row.add_child(angle_label)
	_angle = SpinBox.new()
	_angle.min_value = 5.0
	_angle.max_value = 75.0
	_angle.step = 0.1
	_angle.value = MatchAutoload.DEFAULT_CONE_ANGLE_DEGREES
	_angle.value_changed.connect(_on_angle_changed)
	angle_row.add_child(_angle)
	var cone_options_row: HBoxContainer = HBoxContainer.new()
	list.add_child(cone_options_row)
	var height_label: Label = Label.new()
	height_label.text = "Height"
	cone_options_row.add_child(height_label)
	_height_source = OptionButton.new()
	_height_source.add_item("Block center", SandboxConeExperiment.HEIGHT_CENTER)
	_height_source.add_item("Block top", SandboxConeExperiment.HEIGHT_TOP)
	_height_source.select(SandboxConeExperiment.HEIGHT_TOP)
	_height_source.item_selected.connect(_on_cone_option_changed)
	cone_options_row.add_child(_height_source)
	var base_label: Label = Label.new()
	base_label.text = "Base"
	cone_options_row.add_child(base_label)
	_base_mode = OptionButton.new()
	_base_mode.add_item("None (old)", SandboxConeExperiment.BASE_NONE)
	_base_mode.add_item("Min 1.5 m", SandboxConeExperiment.BASE_FLOOR)
	_base_mode.add_item("Add 1.5 m", SandboxConeExperiment.BASE_ADDITIVE)
	_base_mode.select(SandboxConeExperiment.BASE_ADDITIVE)
	_base_mode.tooltip_text = "Min uses max(1.5, height × tan(angle)); Add uses 1.5 + height × tan(angle). Both use the current radius cap."
	_base_mode.item_selected.connect(_on_cone_option_changed)
	cone_options_row.add_child(_base_mode)
	var controls: HBoxContainer = HBoxContainer.new()
	list.add_child(controls)
	var close: Button = Button.new()
	close.text = "Close / return to sandbox"
	close.pressed.connect(func() -> void: set_open(false))
	controls.add_child(close)
	_live_mode = OptionButton.new()
	_live_mode.add_item("Live: cones", MatchAutoload.SANDBOX_TERRITORY_CONE)
	_live_mode.add_item("Live: paused", MatchAutoload.SANDBOX_TERRITORY_PAUSED)
	_live_mode.tooltip_text = "Cones is the normal-match default. Paused freezes territory CPU updates while physics continues. Sandbox only."
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
	_live = Label.new()
	_live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(_live)
	set_process(true)


func set_open(open: bool) -> void:
	opened = open
	_panel.visible = open
	open_changed.emit(open)
	if open:
		var live_raster: TerritoryRaster = Match.raster()
		if live_raster != null:
			var base_radius: float = live_raster.tuning().influence_base
			_base_mode.set_item_text(SandboxConeExperiment.BASE_FLOOR, "Min %.1f m" % base_radius)
			_base_mode.set_item_text(SandboxConeExperiment.BASE_ADDITIVE, "Add %.1f m" % base_radius)
			_base_mode.tooltip_text = ("Min uses max(%.1f, height × tan(angle)); Add uses %.1f + height × tan(angle). Both use the current radius cap." % [base_radius, base_radius])
		_live_mode.grab_focus()


func _on_cone_option_changed(_index: int) -> void:
	if _live_mode.get_selected_id() == MatchAutoload.SANDBOX_TERRITORY_CONE:
		_emit_live_mode()


func _on_angle_changed(_value: float) -> void:
	if _live_mode != null and _live_mode.get_selected_id() == MatchAutoload.SANDBOX_TERRITORY_CONE:
		_emit_live_mode()


func set_live_territory_mode(mode: int) -> void:
	_live_mode.select(_live_mode.get_item_index(mode))
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
	_live_badge.visible = mode != MatchAutoload.DEFAULT_TERRITORY_MODE
	_live_badge.text = "TERRITORY SOLVE PAUSED — F2 to resume"


func _process(delta: float) -> void:
	_hud_elapsed += delta
	if _hud_elapsed < 0.2:
		return
	_hud_elapsed = 0.0
	var mode: int = _live_mode.get_selected_id()
	var mode_name: String = "CONES" if mode == MatchAutoload.SANDBOX_TERRITORY_CONE else "PAUSED"
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
