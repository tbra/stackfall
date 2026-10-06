class_name CycleSelector
extends Button
## The one click-to-cycle control behind every short option list on a menu screen
## (Bontago-1pi.94): a click or ui_accept advances to the next enabled item, a right click
## steps back, both wrap. Focus navigation (ui_left / ui_right / ui_up / ui_down, held,
## echoed or from a pad) is never consumed here and never changes the value: only an
## activation does.
##
## It mirrors the slice of OptionButton's API the lobby used (add_item, set_item_icon,
## set_item_disabled, set_item_tooltip, select, `selected`, `item_count`, `item_selected`),
## so every caller keeps the same stored int and wire format: [signal item_selected] carries
## the same index the old dropdown emitted, and setting [member selected] from code (e.g.
## applying a replicated config) does NOT emit, like OptionButton.
##
## With [member auto_advance] off the control does not move itself: it only emits [signal
## cycled] and the owner redraws it (a seat row's team pill, whose value lives in the
## panel's seat table; the row is rebuilt after each request).

## The user picked `index` (activation or right click); not emitted by select() / `selected =`.
signal item_selected(index: int)
## An activation happened; `backwards` is true for a right click.
signal cycled(backwards: bool)

## When false, an activation only emits [signal cycled] and leaves the value to the owner.
@export var auto_advance: bool = true

## Tooltip describing the whole list; the shown item's own tooltip is appended under it.
var list_tooltip: String = "":
	set(value):
		list_tooltip = value
		_refresh()

var _labels: Array[String] = []
var _icons: Array[Texture2D] = []
var _disabled_items: Array[bool] = []
var _tooltips: Array[String] = []
var _selected: int = -1

## Index of the shown item, -1 when empty. Assigning an out-of-range index is ignored
## (OptionButton parity); assigning never emits [signal item_selected].
var selected: int:
	get:
		return _selected
	set(value):
		select(value)

var item_count: int:
	get:
		return _labels.size()


func _init() -> void:
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	expand_icon = true
	clip_text = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_gui_input)
	pressed.connect(_on_pressed)


func clear() -> void:
	_labels.clear()
	_icons.clear()
	_disabled_items.clear()
	_tooltips.clear()
	_selected = -1
	_refresh()


func add_item(label: String, _id: int = -1) -> void:
	_labels.append(label)
	_icons.append(null)
	_disabled_items.append(false)
	_tooltips.append("")
	if _selected < 0:
		_selected = 0
	_refresh()


func get_item_count() -> int:
	return _labels.size()


func get_item_text(index: int) -> String:
	return _labels[index] if index >= 0 and index < _labels.size() else ""


func get_item_icon(index: int) -> Texture2D:
	return _icons[index] if index >= 0 and index < _icons.size() else null


func get_item_tooltip(index: int) -> String:
	return _tooltips[index] if index >= 0 and index < _tooltips.size() else ""


func is_item_disabled(index: int) -> bool:
	return index >= 0 and index < _disabled_items.size() and _disabled_items[index]


func set_item_icon(index: int, texture: Texture2D) -> void:
	if index >= 0 and index < _icons.size():
		_icons[index] = texture
		_refresh()


func set_item_disabled(index: int, value: bool) -> void:
	if index >= 0 and index < _disabled_items.size():
		_disabled_items[index] = value


func set_item_tooltip(index: int, text: String) -> void:
	if index >= 0 and index < _tooltips.size():
		_tooltips[index] = text
		_refresh()


## Shows `index` without emitting. Out of range (other than -1) is ignored.
func select(index: int) -> void:
	if index < -1 or index >= _labels.size():
		return
	_selected = index
	_refresh()


## Steps to the next (or previous) enabled item, wrapping; stays put when no other item
## is enabled. Returns the new index, or -1 when nothing changed.
func next_index(backwards: bool) -> int:
	var count: int = _labels.size()
	if count == 0:
		return -1
	var step: int = -1 if backwards else 1
	var candidate: int = _selected
	for _i: int in range(count):
		candidate = posmod(candidate + step, count)
		if not _disabled_items[candidate]:
			return candidate if candidate != _selected else -1
	return -1


## The user's activation, forwards or backwards.
func cycle(backwards: bool) -> void:
	if disabled:
		return
	if auto_advance:
		var target: int = next_index(backwards)
		if target >= 0:
			_selected = target
			_refresh()
			item_selected.emit(target)
	cycled.emit(backwards)


func _on_pressed() -> void:
	cycle(false)


## Right click = previous. Connected to `gui_input` (not _gui_input) so a test can drive
## it with a plain emit. A held ui_accept (echo) is swallowed so it cannot spin the value;
## every other event, navigation included, is left alone.
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			cycle(true)
	elif event.is_echo() and event.is_action(&"ui_accept"):
		accept_event()


func _refresh() -> void:
	if _selected < 0 or _selected >= _labels.size():
		return
	text = _labels[_selected]
	icon = _icons[_selected]
	if _tooltips[_selected] != "":
		tooltip_text = _tooltips[_selected] if list_tooltip == "" else "%s

%s" % [list_tooltip, _tooltips[_selected]]
	elif list_tooltip != "":
		tooltip_text = list_tooltip
