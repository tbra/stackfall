class_name UiStepper
extends HBoxContainer
## The design system's Stepper (docs/ui_reskin/components.md "Stepper"): - and + blocks around a
## Bungee value in a sunken well, for goal flags, bots and match minutes. A UiRowItem (STEPPER):
## stepper_width_units row heights wide, one row height tall, never expands. At a limit the matching
## block is disabled (dimmed). The stepper itself takes focus: ui_left / ui_right step it, holding
## repeats after SliderNavTuning.repeat_delay_sec every repeat_interval_sec; a stick follows the
## same friction rules (UiHoldRepeat, Bontago-1pi.152): it presses past
## stick_press_threshold, releases below stick_release_threshold, and auto-repeats only near full
## deflection. The -/+ blocks repeat while the mouse holds them.
## The hold timer is the shared UiHoldRepeat (Bontago-1pi.159.10).

signal value_changed(value: int)

const MINUS_GLYPH: int = 0x2212
const PLUS_GLYPH: String = "+"

@export var min_value: int = 0:
	set(new_min):
		min_value = new_min
		_refresh()
@export var max_value: int = 100:
	set(new_max):
		max_value = new_max
		_refresh()
@export var step: int = 1
@export var value: int = 0:
	set(new_value):
		var clamped: int = clampi(new_value, min_value, max_value)
		var changed: bool = clamped != value
		value = clamped
		_refresh()
		if changed and not _silent:
			value_changed.emit(value)
## Display only (e.g. "%.1f s"); never changes the stored int.
var formatter: Callable = Callable()
var disabled: bool = false:
	set(new_disabled):
		disabled = new_disabled
		if disabled:
			release()
		_refresh()
## Gallery preview of the focus look (a captured control cannot hold real focus).
var preview_focus: bool = false:
	set(value):
		preview_focus = value
		queue_redraw()
var minus_button: UiIconButton = null
var plus_button: UiIconButton = null
var value_label: Label = null
## Reads a stick axis; tests replace it (headless Input has no real pad state).
var axis_reader: Callable = Input.get_joy_axis:
	set(reader):
		axis_reader = reader
		_hold.axis_reader = reader

var _well: PanelContainer = null
var _silent: bool = false
var _hold: UiHoldRepeat = UiHoldRepeat.new(nudge)
var _hold_button: UiIconButton = null


func _init() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var m: ComponentMetrics = UiRowItem.metrics()
	add_theme_constant_override("separation", arcade.space_1_px)
	focus_mode = Control.FOCUS_ALL
	UiRowItem.apply(self, UiRowItem.Kind.STEPPER)
	set_process(false)
	minus_button = _make_button(char(MINUS_GLYPH), -1)
	_well = PanelContainer.new()
	_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_well.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_well.custom_minimum_size.y = float(m.row_height_px - arcade.drop_sm_px)
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = arcade.disc_900_color
	box.set_corner_radius_all(arcade.radius_block_px)
	box.set_border_width_all(arcade.well_border_px)
	box.border_color = arcade.disc_400_color
	box.set_content_margin_all(0.0)
	_well.add_theme_stylebox_override("panel", box)
	value_label = Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.add_theme_color_override("font_color", arcade.cream_color)
	value_label.add_theme_font_size_override("font_size", m.stepper_value_font_px)
	var display: Font = (load("res://ui/theme/stackfall_theme.tres") as Theme).get_font(&"font", &"DisplayLabel")
	if display != null:
		value_label.add_theme_font_override("font", display)
	_well.add_child(value_label)
	add_child(_well)
	plus_button = _make_button(PLUS_GLYPH, 1)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(_on_focus_exited)
	visibility_changed.connect(release)
	_refresh()


## Sets the value without emitting `value_changed` (remote sync, read-only clients).
func set_value_silent(new_value: int) -> void:
	_silent = true
	value = new_value
	_silent = false


## [param current] moved one step in [param direction] (-1 / +1), clamped to [lo, hi].
static func clamp_step(current: int, direction: int, lo: int = 0, hi: int = 0, step_size: int = 1) -> int:
	return clampi(current + signi(direction) * maxi(step_size, 1), lo, maxi(lo, hi))


## The text the value well shows: [member formatter] when set, else the integer.
func display_text() -> String:
	if formatter.is_valid():
		return str(formatter.call(value))
	return str(value)


func is_at_min() -> bool:
	return value <= min_value


func is_at_max() -> bool:
	return value >= max_value


## Steps once in [param direction] (the keyboard / pad / click path); returns whether it moved.
func nudge(direction: int) -> bool:
	if disabled:
		return false
	var before: int = value
	value = clamp_step(value, direction, min_value, max_value, step)
	return value != before


func is_holding() -> bool:
	return _hold.is_holding()


func release() -> void:
	_hold.release()
	_hold_button = null
	set_process(false)


## Advances the hold timer; at most one repeat step per call.
func advance(delta: float) -> void:
	if not _hold.is_holding():
		return
	var alive: bool = is_visible_in_tree() and not disabled 			and (_hold.source == UiHoldRepeat.SOURCE_MOUSE or has_focus())
	var mouse_down: bool = _hold_button != null and _hold_button.is_pressed()
	if not _hold.advance(delta, alive, mouse_down):
		release()


func _process(delta: float) -> void:
	advance(delta)


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	var consumed: bool = false
	if event is InputEventJoypadMotion:
		consumed = _hold.handle_stick(event as InputEventJoypadMotion)
	else:
		consumed = _hold.handle_action_event(event)
	if consumed:
		accept_event()
	set_process(_hold.is_holding())
	if not _hold.is_holding():
		_hold_button = null


func _make_button(glyph: String, direction: int) -> UiIconButton:
	var button: UiIconButton = UiIconButton.new()
	button.text = glyph
	button.focus_mode = Control.FOCUS_NONE
	button.button_down.connect(_on_block_down.bind(button, direction))
	button.button_up.connect(_on_block_up.bind(button))
	add_child(button)
	return button


func _on_block_down(button: UiIconButton, direction: int) -> void:
	if disabled:
		return
	grab_focus()
	_hold_button = button
	_hold.start(direction, UiHoldRepeat.SOURCE_MOUSE)
	set_process(true)


func _on_block_up(button: UiIconButton) -> void:
	if _hold_button == button:
		release()


func _on_focus_exited() -> void:
	release()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release()


func _refresh() -> void:
	if value_label == null:
		return
	value_label.text = display_text()
	minus_button.disabled = disabled or is_at_min()
	plus_button.disabled = disabled or is_at_max()
	queue_redraw()


func _draw() -> void:
	if has_focus() or preview_focus:
		draw_style_box(get_theme_stylebox("focus", "Button"), Rect2(Vector2.ZERO, size))
