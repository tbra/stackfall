class_name UiCycler
extends HBoxContainer
## The design system's Cycler (Bontago-1pi.159.28): the Stepper's sibling for options that cycle
## through named choices. A "<" block, the value printed plainly (no well, no unit) and a ">" block,
## all one square-button row height tall; it hugs its content instead of filling the row. Unlike the
## stepper it has no limits: stepping past either end wraps around, and disabled items are skipped.
## A UiRowItem (row height, no minimum width). The cycler takes focus: ui_left / ui_right
## step it, holding repeats and a stick follows the shared friction rules (UiHoldRepeat); the
## buttons repeat while the mouse holds them. The value label is sized to the widest item so the
## buttons do not jump while cycling.

signal item_selected(index: int)

const PREV_GLYPH: String = "<"
const NEXT_GLYPH: String = ">"
const NONE: int = -1

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
var prev_button: UiIconButton = null
var next_button: UiIconButton = null
var value_label: Label = null
## Reads a stick axis; tests replace it (headless Input has no real pad state).
var axis_reader: Callable = Input.get_joy_axis:
	set(reader):
		axis_reader = reader
		_hold.axis_reader = reader

var _texts: PackedStringArray = PackedStringArray()
var _disabled_items: Array[bool] = []
var _selected: int = NONE
var _hold: UiHoldRepeat = UiHoldRepeat.new(nudge)
var _hold_button: UiIconButton = null


func _init() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var m: ComponentMetrics = UiRowItem.metrics()
	add_theme_constant_override("separation", arcade.space_1_px)
	focus_mode = Control.FOCUS_ALL
	UiRowItem.apply(self, UiRowItem.Kind.BADGE)  # row height, hugs content: no minimum width
	custom_minimum_size.x = 0.0
	set_process(false)
	prev_button = _make_button(PREV_GLYPH, -1)
	value_label = Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.add_theme_color_override("font_color", arcade.cream_color)
	value_label.add_theme_font_size_override("font_size", m.stepper_value_font_px)
	var display: Font = (load("res://ui/theme/stackfall_theme.tres") as Theme).get_font(&"font", &"DisplayLabel")
	if display != null:
		value_label.add_theme_font_override("font", display)
	add_child(value_label)
	next_button = _make_button(NEXT_GLYPH, 1)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(_on_focus_exited)
	visibility_changed.connect(release)
	_refresh()


## Appends an item and returns its index; the first item becomes the selection.
func add_item(text: String, item_disabled: bool = false) -> int:
	_texts.append(text)
	_disabled_items.append(item_disabled)
	if _selected == NONE:
		_selected = _texts.size() - 1
	_refresh()
	return _texts.size() - 1


func clear() -> void:
	release()
	_texts.clear()
	_disabled_items.clear()
	_selected = NONE
	_refresh()


func get_item_count() -> int:
	return _texts.size()


func get_item_text(index: int) -> String:
	return _texts[index] if index >= 0 and index < _texts.size() else ""


func set_item_disabled(index: int, item_disabled: bool) -> void:
	if index >= 0 and index < _disabled_items.size():
		_disabled_items[index] = item_disabled
		_refresh()


func is_item_disabled(index: int) -> bool:
	return index >= 0 and index < _disabled_items.size() and _disabled_items[index]


## Selects [param index] without emitting `item_selected` (remote sync, initial value).
func select(index: int) -> void:
	_selected = index if index >= 0 and index < _texts.size() else NONE
	_refresh()


## The selected index, or [constant NONE] when there are no items.
func selected() -> int:
	return _selected


func selected_text() -> String:
	return get_item_text(_selected)


## The index [param direction] (-1 / +1) away from [param from], wrapping and skipping disabled
## items; [param from] itself when no other item is enabled.
func next_index(from: int, direction: int) -> int:
	var count: int = _texts.size()
	if count == 0:
		return NONE
	var dir: int = signi(direction)
	if dir == 0:
		return from
	for offset: int in range(1, count):
		var candidate: int = posmod(from + dir * offset, count)
		if not _disabled_items[candidate]:
			return candidate
	return from


## Steps once in [param direction] (the keyboard / pad / click path); returns whether it moved.
func nudge(direction: int) -> bool:
	if disabled or _selected == NONE:
		return false
	var target: int = next_index(_selected, direction)
	if target == _selected:
		return false
	_selected = target
	_refresh()
	item_selected.emit(_selected)
	return true


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
	var alive: bool = is_visible_in_tree() and not disabled \
			and (_hold.source == UiHoldRepeat.SOURCE_MOUSE or has_focus())
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


func _enabled_count() -> int:
	var count: int = 0
	for item_disabled: bool in _disabled_items:
		if not item_disabled:
			count += 1
	return count


func _refresh() -> void:
	if value_label == null:
		return
	value_label.text = selected_text()
	var widest: float = 0.0
	var font: Font = value_label.get_theme_font(&"font")
	var font_size: int = value_label.get_theme_font_size(&"font_size")
	for text: String in _texts:
		widest = maxf(widest, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
	value_label.custom_minimum_size.x = ceilf(widest)
	var can_step: bool = not disabled and _enabled_count() > 1
	prev_button.disabled = not can_step
	next_button.disabled = not can_step
	queue_redraw()


func _draw() -> void:
	if has_focus() or preview_focus:
		draw_style_box(get_theme_stylebox("focus", "Button"), Rect2(Vector2.ZERO, size))
