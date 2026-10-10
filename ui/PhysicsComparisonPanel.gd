class_name PhysicsComparisonPanel
extends CanvasLayer
## Focusable sandbox-only measurement controls, intentionally not a tuning resource.
signal run_requested(mode: String, height: float, interval: float, gap: float, offset: float)
signal clear_requested
signal open_changed(open: bool)
signal cone_requested
var _panel: PanelContainer
var _status: Label
var _height: SpinBox
var _interval: SpinBox
var _gap: SpinBox
var _offset: SpinBox
var _drop: Button
var _stack: Button
var _last_mode: String = "drop"
var opened: bool = false
## Bontago-1pi.23: hint label geometry (logical px under the project stretch rule).
const HINT_HALF_WIDTH_PX: float = 260.0
const HINT_HEIGHT_PX: float = 18.0
const HINT_BOTTOM_MARGIN_PX: float = 6.0
const HINT_ALPHA: float = 0.55
const HINT_OUTLINE_PX: int = 3

func _ready() -> void:
	layer = 10
	var hint: Label = Label.new()
	hint.text = "F2 / Back+X: physics or territory comparison   F4: tuning/presets"
	# Bontago-1pi.23: bottom-centre, dim and small, so it never overlaps the
	# bottom-left held/next cards or the bottom-right minimap.
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -HINT_HALF_WIDTH_PX
	hint.offset_right = HINT_HALF_WIDTH_PX
	hint.offset_top = -HINT_HEIGHT_PX - HINT_BOTTOM_MARGIN_PX
	hint.offset_bottom = -HINT_BOTTOM_MARGIN_PX
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# DECISION (Bontago-hfa.9): the hint is caption text (theme CaptionLabel: dust ink, 13 px),
	# outlined in the arcade disc-950 token; HINT_ALPHA keeps it dim.
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	hint.theme_type_variation = &"CaptionLabel"
	hint.modulate = Color(1.0, 1.0, 1.0, HINT_ALPHA)
	hint.add_theme_constant_override("outline_size", HINT_OUTLINE_PX)
	hint.add_theme_color_override("font_outline_color", arcade.disc_950_color)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -590.0
	_panel.offset_right = -16.0
	_panel.offset_top = 126.0
	_panel.custom_minimum_size = Vector2(574, 0)
	_panel.visible = false
	add_child(_panel)
	var list: VBoxContainer = VBoxContainer.new()
	_panel.add_child(list)
	var title: Label = Label.new()
	title.text = "Physics comparison (10 simulation seconds)"
	list.add_child(title)
	_height = _spin(list, "Drop height (cube edges)", 0.1, 10.0, 2.0)
	_interval = _spin(list, "Stack release interval (s)", 0.1, 4.5, 2.0)
	_gap = _spin(list, "Stack / impact gap (cube edges)", 0.05, 3.0, 0.3)
	_offset = _spin(list, "Impact sideways offset (cube edges)", 0.0, 0.9, 0.0)
	var row: HBoxContainer = HBoxContainer.new()
	list.add_child(row)
	_drop = _button(row, "Drop cube", func() -> void: _run("drop"))
	_stack = _button(row, "Stack 3 cubes", func() -> void: _run("stack"))
	_button(row, "Cube on cube", func() -> void: _run("impact"))
	_button(row, "Repeat", func() -> void: _run(_last_mode))
	var close_row: HBoxContainer = HBoxContainer.new()
	list.add_child(close_row)
	_button(close_row, "Clear / cancel", func() -> void: clear_requested.emit())
	_button(close_row, "Territory experiments", func() -> void: cone_requested.emit())
	_button(close_row, "Close controls", func() -> void: set_open(false))
	_status = Label.new()
	_status.custom_minimum_size.x = 390
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Uses live F4 physics at release. Clear nearby blocks (F5) first.\nEngine sleep is not visually settled time."
	list.add_child(_status)

func _spin(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, initial: float) -> SpinBox:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	var label: Label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin: SpinBox = SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 0.05
	spin.value = initial
	row.add_child(spin)
	return spin

func _button(parent: HBoxContainer, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func set_open(open: bool) -> void:
	opened = open
	_panel.visible = open
	open_changed.emit(open)
	if open:
		_drop.grab_focus()

func _run(mode: String) -> void:
	_last_mode = mode
	run_requested.emit(mode, _height.value, _interval.value, _gap.value, _offset.value)

func show_status(text: String) -> void:
	_status.text = text

func show_result(result: Dictionary) -> void:
	if result.has("error"):
		show_status(String(result["error"]))
		return
	var sleep: float = float(result["first_asleep_s"])
	var text: String = "%s complete — engine sleep: %s\nLateral drift: %.3f cube edges" % [String(result["mode"]), "not reached" if sleep < 0.0 else "%.2f simulation s" % sleep, float(result["max_lateral_drift_cubes"])]
	if result["mode"] == "drop":
		text += "\nContact: %.3fs  Rebound: %.3f edges (%.3f ratio)" % [float(result["first_contact_s"]), float(result["rebound_height_cubes"]), float(result["rebound_to_drop_ratio"])]
	if result["mode"] == "impact":
		text += "\nGap %.2f  Offset %.2f  Peak rotation %.1f°\nConfigured release tilt %.1f° (experimental)" % [float(result["placement_gap_cubes"]), float(result["offset_cubes"]), float(result["max_rotation_degrees"]), float(result["release_tilt_degrees"])]
	var snapshot: Dictionary = result["tuning"]
	text += "\nGravity x%.2f  Mass %.2f  Bounce %.2f\nFriction %.2f  Damp %.2f / %.2f  Rebound damping %.2f" % [float(snapshot["gravity_multiplier"]), float(snapshot["cube_mass"]), float(snapshot["block_bounce"]), float(snapshot["block_friction"]), float(snapshot["linear_damp"]), float(snapshot["angular_damp"]), float(snapshot["rebound_damping"])]
	show_status(text)
