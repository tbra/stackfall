class_name UiSegmentMeter
extends Control
## The design system's SegmentMeter (docs/ui_reskin/components.md "SegmentMeter"): a slider drawn
## as voxel cells in a sunken well with the value always shown to the right in Bungee. A UiRowItem
## (METER): one row height tall, expands to its column. [member value] counts filled cells
## (0..[member step_count], never fewer than MIN_STEP_COUNT cells); consumers map it to their own
## range and give [member formatter] to turn it into the readout ("100%", "5.0 s", "Medium").
## Mouse: click or drag sets the cell under the pointer. Keyboard / pad: ui_left / ui_right step one
## cell (held: repeats after SliderNavTuning.repeat_delay_sec, a stick only auto-repeats near full
## deflection, like SliderNav). A muted or non-editable meter shows dust cells.
## DECISION (1pi.159.7): the hold timer is a compact copy of UiStepper's rules against the same
## SliderNav.TUNING numbers (SliderNav.Repeater drives an HSlider and cannot attach to a Control).
## The old overlay ui/SegmentMeter.gd keeps its HSlider and paints through [method draw_cells].

signal value_changed(value: int)

## The design system never allows fewer than five cells.
const MIN_STEP_COUNT: int = 5
const DISPLAY_FONT_THEME_TYPE: StringName = &"DisplayLabel"

@export var step_count: int = 10:
	set(count):
		step_count = maxi(count, MIN_STEP_COUNT)
		value = value  # re-clamp
		queue_redraw()
@export var value: int = 0:
	set(new_value):
		var clamped: int = clampi(new_value, 0, step_count)
		var changed: bool = clamped != value
		value = clamped
		queue_redraw()
		if changed and not _silent:
			value_changed.emit(value)
## Display only: turns the value into the readout text; unset shows the bare cell count.
var formatter: Callable = Callable()
## Draws the readout right of the well.
@export var show_value: bool = true:
	set(show):
		show_value = show
		queue_redraw()
## A non-editable or muted meter shows dust cells and ignores input.
@export var editable: bool = true:
	set(can_edit):
		editable = can_edit
		if not editable:
			_release()
		queue_redraw()
## Gallery preview of the focus look (a captured control cannot hold real focus).
var preview_focus: bool = false:
	set(preview):
		preview_focus = preview
		queue_redraw()
## Reads a stick axis; tests replace it (headless Input has no real pad state).
var axis_reader: Callable = Input.get_joy_axis

var _silent: bool = false
var _dragging: bool = false
var _direction: int = 0
var _stick_axis: int = -1
var _stick_device: int = 0
var _held_for: float = 0.0
var _next_due: float = 0.0


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UiRowItem.apply(self, UiRowItem.Kind.METER, true)
	custom_minimum_size.x += float(UiRowItem.metrics().row_value_cell_width_px)
	set_process(false)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(_on_focus_exited)
	visibility_changed.connect(_release)


## Sets the value without emitting `value_changed` (remote sync, read-only clients).
func set_value_silent(new_value: int) -> void:
	_silent = true
	value = new_value
	_silent = false


## 0..1 position of the filled part.
func ratio() -> float:
	return float(value) / float(step_count)


## Sets the filled cells from a 0..1 [param position_ratio].
func set_ratio(position_ratio: float) -> void:
	value = roundi(clampf(position_ratio, 0.0, 1.0) * float(step_count))


## The readout text: [member formatter] when set, else the cell count.
func display_text() -> String:
	if formatter.is_valid():
		return str(formatter.call(value))
	return str(value)


## [param current] moved one cell in [param direction] (-1 / +1) within 0..[param count].
static func step_value(current: int, direction: int, count: int) -> int:
	return clampi(current + signi(direction), 0, maxi(count, 0))


## The filled-cell count for a pointer at [param x] in a well [param width] wide.
static func value_from_x(x: float, width: float, count: int) -> int:
	if width <= 0.0:
		return 0
	return clampi(roundi(x / width * float(count)), 0, count)


## Steps once in [param direction]; returns whether the value moved.
func nudge(direction: int) -> bool:
	if not editable:
		return false
	var before: int = value
	value = step_value(value, direction, step_count)
	return value != before


func is_holding() -> bool:
	return _direction != 0


## The width left for the well once the readout column is taken.
func well_width() -> float:
	return size.x - (float(UiRowItem.metrics().row_value_cell_width_px) if show_value else 0.0)


## Paints the well and [param count] cells ([param filled] of them lit) into [param rect] of
## [param canvas]. Live cells are flare, dust when not [param live]; the current cell gets the cream
## outline. Shared with the legacy HSlider overlay (ui/SegmentMeter.gd).
static func draw_cells(canvas: CanvasItem, rect: Rect2, filled: int, count: int, live: bool) -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var well: StyleBoxFlat = StyleBoxFlat.new()
	well.bg_color = arcade.disc_900_color
	well.border_color = arcade.disc_400_color
	well.set_border_width_all(arcade.well_border_px)
	well.set_corner_radius_all(arcade.radius_block_px)
	canvas.draw_style_box(well, rect)
	var cells: int = maxi(count, 1)
	var inset: float = float(arcade.well_border_px + arcade.space_1_px)
	var area: Rect2 = Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2(inset, inset) * 2.0)
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	var gap: float = float(arcade.space_1_px)
	var cell_w: float = (area.size.x - gap * float(cells - 1)) / float(cells)
	for i: int in range(cells):
		var cell: Rect2 = Rect2(area.position + Vector2(float(i) * (cell_w + gap), 0.0), Vector2(cell_w, area.size.y))
		var face: Color = arcade.disc_700_color
		var lip: Color = arcade.disc_600_color
		if i < filled:
			face = arcade.flare_color if live else arcade.dust_color
			lip = arcade.flare_lip_color if live else arcade.disc_400_color
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = face
		box.border_color = lip
		box.border_width_bottom = arcade.pressed_lip_px
		box.set_corner_radius_all(arcade.radius_cell_px)
		canvas.draw_style_box(box, cell)
	if filled > 0 and live:
		var current: int = clampi(filled - 1, 0, cells - 1)
		var outline: StyleBoxFlat = StyleBoxFlat.new()
		outline.draw_center = false
		outline.border_color = arcade.cream_color
		outline.set_border_width_all(arcade.well_border_px)
		outline.set_corner_radius_all(arcade.radius_cell_px)
		canvas.draw_style_box(outline, Rect2(area.position + Vector2(float(current) * (cell_w + gap), 0.0), Vector2(cell_w, area.size.y)))


func _draw() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var width: float = well_width()
	draw_cells(self, Rect2(Vector2.ZERO, Vector2(width, size.y)), value, step_count, editable)
	if show_value:
		var font: Font = get_theme_font(&"font", DISPLAY_FONT_THEME_TYPE)
		var font_px: int = UiRowItem.metrics().stepper_value_font_px
		var text: String = display_text()
		var text_height: float = font.get_height(font_px)
		var baseline: float = (size.y - text_height) * 0.5 + font.get_ascent(font_px)
		var color: Color = arcade.cream_color if editable else arcade.dust_color
		draw_string(font, Vector2(width + float(arcade.space_2_px), baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px, color)
	if has_focus() or preview_focus:
		draw_style_box(get_theme_stylebox("focus", "Button"), Rect2(Vector2.ZERO, Vector2(width, size.y)))


func _gui_input(event: InputEvent) -> void:
	if not editable:
		return
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT:
			_dragging = click.pressed
			if click.pressed:
				value = value_from_x(click.position.x, well_width(), step_count)
				accept_event()
		return
	if event is InputEventMouseMotion and _dragging:
		value = value_from_x((event as InputEventMouseMotion).position.x, well_width(), step_count)
		accept_event()
		return
	if event is InputEventJoypadMotion:
		_on_stick(event as InputEventJoypadMotion)
		return
	for action: StringName in [&"ui_left", &"ui_right"]:
		var direction: int = -1 if action == &"ui_left" else 1
		if event.is_action_pressed(action, true):
			accept_event()
			if not (event is InputEventKey and (event as InputEventKey).echo):
				_start(direction, -1)
			return
		if event.is_action_released(action) and _direction == direction and _stick_axis < 0:
			_release()


func _on_stick(motion: InputEventJoypadMotion) -> void:
	var tuning: SliderNavTuning = SliderNav.TUNING
	if _stick_axis == motion.axis and _direction != 0:
		if absf(motion.axis_value) < tuning.stick_release_threshold or signf(motion.axis_value) != float(_direction):
			_release()
		else:
			accept_event()
			return
	for action: StringName in [&"ui_left", &"ui_right"]:
		if motion.is_action(action, true) and motion.is_action_pressed(action, true):
			accept_event()
			if absf(motion.axis_value) >= tuning.stick_press_threshold and _direction == 0:
				_stick_device = motion.device
				_start(-1 if action == &"ui_left" else 1, motion.axis)
			return


func _start(direction: int, stick_axis: int) -> void:
	_direction = direction
	_stick_axis = stick_axis
	_held_for = 0.0
	var tuning: SliderNavTuning = SliderNav.TUNING
	_next_due = tuning.stick_repeat_delay_sec if stick_axis >= 0 else tuning.repeat_delay_sec
	nudge(direction)
	set_process(true)


func _release() -> void:
	_direction = 0
	_stick_axis = -1
	_dragging = false
	set_process(false)


func _process(delta: float) -> void:
	advance(delta)


## Advances the hold timer; at most one repeat step per call.
func advance(delta: float) -> void:
	if _direction == 0:
		return
	if not is_visible_in_tree() or not editable or not has_focus() or not _still_held():
		_release()
		return
	var tuning: SliderNavTuning = SliderNav.TUNING
	var interval: float = tuning.repeat_interval_sec
	if _stick_axis >= 0:
		interval = tuning.stick_repeat_interval_sec
		if absf(float(axis_reader.call(_stick_device, _stick_axis))) < tuning.stick_repeat_threshold:
			_held_for = 0.0
			_next_due = tuning.stick_repeat_delay_sec
			return
	_held_for += delta
	if _held_for >= _next_due:
		_next_due += interval
		nudge(_direction)


func _still_held() -> bool:
	if _stick_axis >= 0:
		var deflection: float = float(axis_reader.call(_stick_device, _stick_axis))
		return absf(deflection) >= SliderNav.TUNING.stick_release_threshold and signf(deflection) == float(_direction)
	return Input.is_action_pressed(&"ui_left" if _direction < 0 else &"ui_right")


func _on_focus_exited() -> void:
	_release()
	queue_redraw()
