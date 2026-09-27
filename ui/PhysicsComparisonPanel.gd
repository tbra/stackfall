class_name PhysicsComparisonPanel
extends CanvasLayer
## Focusable sandbox-only measurement controls, intentionally not a tuning resource.
signal run_requested(mode: String, height: float, interval: float, gap: float)
signal clear_requested
signal open_changed(open: bool)
var _panel: PanelContainer
var _status: Label
var _height: SpinBox
var _interval: SpinBox
var _gap: SpinBox
var _drop: Button
var _stack: Button
var _last_mode: String = "drop"
var opened: bool = false

func _ready() -> void:
	layer = 10
	var hint: Label = Label.new()
	hint.text = "F2 / Back+X: physics comparison   F4: tuning/presets"
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 16.0
	hint.offset_top = -30.0
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
	_gap = _spin(list, "Stack release gap (cube edges)", 0.05, 3.0, 0.3)
	var row: HBoxContainer = HBoxContainer.new()
	list.add_child(row)
	_drop = _button(row, "Drop cube", func() -> void: _run("drop"))
	_stack = _button(row, "Stack 3 cubes", func() -> void: _run("stack"))
	_button(row, "Repeat", func() -> void: _run(_last_mode))
	_button(row, "Clear / cancel", func() -> void: clear_requested.emit())
	var close_row: HBoxContainer = HBoxContainer.new()
	list.add_child(close_row)
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
	run_requested.emit(mode, _height.value, _interval.value, _gap.value)

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
	var snapshot: Dictionary = result["tuning"]
	text += "\nGravity x%.2f  Mass %.2f  Bounce %.2f\nFriction %.2f  Damp %.2f / %.2f  Rebound damping %.2f" % [float(snapshot["gravity_multiplier"]), float(snapshot["cube_mass"]), float(snapshot["block_bounce"]), float(snapshot["block_friction"]), float(snapshot["linear_damp"]), float(snapshot["angular_damp"]), float(snapshot["rebound_damping"])]
	show_status(text)
