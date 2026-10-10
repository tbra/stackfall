class_name UiDropdown
extends Button
## The design system's Dropdown (docs/ui_reskin/components.md "Dropdown"): a raised disc-700 block
## with a disc-400 edge, the value in cream and a sand chevron. It replaces every OptionButton and
## absorbs the click-to-cycle selector (owner decision Bontago-1pi.94). A UiRowItem (DROPDOWN).
##
## [enum Mode.CYCLE]: a click or ui_accept advances to the next enabled item, a right click steps
## back, both wrap; the control never opens a list. [enum Mode.POPUP]: a click or ui_accept opens a
## disc-800 list of rows, the current row disc-600 with a check; ui_up / ui_down move, ui_accept
## picks, ui_cancel (B) or a click outside closes it and hands focus back. [enum Mode.AUTO] (the
## default) cycles lists of up to [constant CYCLE_MAX_ITEMS] items and opens a list for longer ones.
## Focus navigation (ui_left / ui_right / ui_up / ui_down, held, echoed or from a pad) is never
## consumed while closed and never changes the value: only an activation does.
##
## It mirrors the slice of OptionButton's API the screens use (add_item, set_item_icon,
## set_item_disabled, set_item_tooltip, select, `selected`, `item_count`, `item_selected`), so every
## caller keeps the same stored int: [signal item_selected] carries the index, and setting
## [member selected] from code (a replicated config) does NOT emit, like OptionButton.
## With [member auto_advance] off a cycle activation only emits [signal cycled] and the owner
## redraws the control (a seat row's team pill, whose value lives in the panel's seat table).

## The user picked `index` (activation, right click or list row); not emitted by select().
signal item_selected(index: int)
## A cycle activation happened; `backwards` is true for a right click.
signal cycled(backwards: bool)
## The popup list opened or closed.
signal popup_toggled(open: bool)

enum Mode { AUTO, CYCLE, POPUP }

## Owner decision 1pi.94: short option lists cycle, longer ones open a list.
const CYCLE_MAX_ITEMS: int = 6
const LIST_NAME: StringName = &"DropdownList"
const STATES: PackedStringArray = ["normal", "hover", "pressed", "hover_pressed", "disabled"]

@export var mode: Mode = Mode.AUTO
## When false, a cycle activation only emits [signal cycled] and leaves the value to the owner.
@export var auto_advance: bool = true
## Draws the sand chevron right of the value (the legacy CycleSelector layer turns it off).
var show_chevron: bool = true:
	set(show):
		show_chevron = show
		_sync_chevron()
## Tooltip describing the whole list; the shown item's own tooltip is appended under it.
var list_tooltip: String = "":
	set(text_value):
		list_tooltip = text_value
		_refresh()
## Paints the chevron over the button face (a child draws after the Button's own styles).
var _chevron: Control = null

var _labels: Array[String] = []
var _icons: Array[Texture2D] = []
var _disabled_items: Array[bool] = []
var _tooltips: Array[String] = []
var _selected: int = -1
var _list: DropdownList = null

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
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mode = _initial_mode()
	show_chevron = _initial_chevron()
	_apply_row_contract()
	_restyle()
	gui_input.connect(_on_gui_input)
	pressed.connect(_on_pressed)
	_sync_chevron()
	visibility_changed.connect(_on_visibility_changed)


## The mode a new dropdown starts in (the legacy CycleSelector layer forces CYCLE).
func _initial_mode() -> Mode:
	return Mode.AUTO


## Whether a new dropdown draws the chevron (the legacy layer does not).
func _initial_chevron() -> bool:
	return true


## The row-item contract (one row height, DROPDOWN minimum width). Overridden to a no-op by the
## legacy CycleSelector, whose callers size it themselves.
func _apply_row_contract() -> void:
	UiRowItem.apply(self, UiRowItem.Kind.DROPDOWN)


## The look of the five block states from tokens. Overridden to a no-op by the legacy CycleSelector
## (the theme and the callers' pill styling stay in charge there).
func _restyle() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var faces: Dictionary = {
		"normal": arcade.disc_700_color, "pressed": arcade.disc_900_color, "disabled": arcade.disc_700_color,
		"hover": arcade.disc_600_color, "hover_pressed": arcade.disc_600_color,
	}
	for state: String in STATES:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = faces[state]
		box.border_color = arcade.disc_400_color
		box.set_border_width_all(arcade.well_border_px)
		box.set_corner_radius_all(arcade.radius_block_px)
		box.content_margin_left = float(arcade.space_3_px)
		box.content_margin_right = float(arcade.space_3_px + arcade.space_3_px + arcade.space_2_px)
		box.content_margin_top = 0.0
		box.content_margin_bottom = 0.0
		add_theme_stylebox_override(state, box)
	for item: String in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		add_theme_color_override(item, arcade.cream_color)
	add_theme_color_override("font_disabled_color", arcade.dust_color)
	add_theme_font_size_override("font_size", arcade.font_size_body_px)


func clear() -> void:
	close()
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


func set_item_tooltip(index: int, text_value: String) -> void:
	if index >= 0 and index < _tooltips.size():
		_tooltips[index] = text_value
		_refresh()


## Shows `index` without emitting. Out of range (other than -1) is ignored.
func select(index: int) -> void:
	if index < -1 or index >= _labels.size():
		return
	_selected = index
	_refresh()


## True when an activation opens the list rather than cycling.
func uses_popup() -> bool:
	match mode:
		Mode.POPUP:
			return true
		Mode.CYCLE:
			return false
	return _labels.size() > CYCLE_MAX_ITEMS


## Steps to the next (or previous) enabled item, wrapping; stays put when no other item is
## enabled. Returns the new index, or -1 when nothing changed.
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


## The user's cycle activation, forwards or backwards.
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


func is_open() -> bool:
	return _list != null


## Opens the list (a no-op for an empty or disabled dropdown). [param take_focus] false leaves
## focus where it is (the gallery shows the open state without a focus owner).
func open(take_focus: bool = true) -> void:
	if _list != null or disabled or _labels.is_empty():
		return
	_list = DropdownList.new(self)
	add_child(_list)
	_list.place()
	if take_focus:
		_list.focus_current()
	_redraw_chevron()
	popup_toggled.emit(true)


## Closes the list; focus returns to the dropdown when it was inside the list.
func close() -> void:
	if _list == null:
		return
	var had_focus: bool = _list.has_focus_inside()
	_list.queue_free()
	remove_child(_list)
	_list = null
	if had_focus and is_inside_tree():
		grab_focus()
	_redraw_chevron()
	popup_toggled.emit(false)


## A list row was activated.
func pick(index: int) -> void:
	if index < 0 or index >= _labels.size() or _disabled_items[index]:
		return
	var changed: bool = index != _selected
	close()
	if changed:
		_selected = index
		_refresh()
		item_selected.emit(index)


func _on_pressed() -> void:
	if uses_popup():
		if is_open():
			close()
		else:
			open()
	else:
		cycle(false)


## Right click = previous in cycle mode. Connected to `gui_input` (not _gui_input) so a test can
## drive it with a plain emit. A held ui_accept (echo) is swallowed so it cannot spin the value;
## every other event, navigation included, is left alone.
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_RIGHT and not uses_popup():
			accept_event()
			cycle(true)
	elif event.is_echo() and event.is_action(&"ui_accept"):
		accept_event()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		close()


func _refresh() -> void:
	if _selected < 0 or _selected >= _labels.size():
		return
	text = _labels[_selected]
	icon = _icons[_selected]
	if _tooltips[_selected] != "":
		tooltip_text = _tooltips[_selected] if list_tooltip == "" else "%s\n\n%s" % [list_tooltip, _tooltips[_selected]]
	elif list_tooltip != "":
		tooltip_text = list_tooltip


## Adds or removes the chevron child to match [member show_chevron].
func _sync_chevron() -> void:
	if show_chevron and _chevron == null:
		_chevron = Control.new()
		_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_chevron.set_anchors_preset(Control.PRESET_FULL_RECT)
		_chevron.draw.connect(_draw_chevron.bind(_chevron))
		add_child(_chevron)
	elif not show_chevron and _chevron != null:
		_chevron.queue_free()
		remove_child(_chevron)
		_chevron = null


func _redraw_chevron() -> void:
	if _chevron != null:
		_chevron.queue_redraw()


## The chevron child's paint: a sand triangle, pointing up while the list is open.
func _draw_chevron(canvas: Control) -> void:
	if not show_chevron:
		return
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var half_width: float = float(arcade.space_2_px) * 0.5 + float(arcade.space_1_px) * 0.5
	var half_height: float = float(arcade.space_1_px)
	var centre: Vector2 = Vector2(canvas.size.x - float(arcade.space_3_px) - half_width, canvas.size.y * 0.5)
	var rise: float = -half_height if is_open() else half_height
	var tint: Color = arcade.dust_color if disabled else arcade.sand_color
	canvas.draw_colored_polygon(PackedVector2Array([
		centre + Vector2(-half_width, -rise), centre + Vector2(half_width, -rise), centre + Vector2(0.0, rise),
	]), tint)


## The popup list: a disc-800 panel of rows below (or, near the screen bottom, above) its dropdown.
## A top-level control, so it draws over its siblings and escapes any clipping container.
class DropdownList extends PanelContainer:
	var _owner_dropdown: UiDropdown = null
	var _rows: Array[Row] = []

	func _init(dropdown: UiDropdown) -> void:
		_owner_dropdown = dropdown
		name = UiDropdown.LIST_NAME
		top_level = true
		z_index = RenderingServer.CANVAS_ITEM_Z_MAX
		var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = arcade.disc_800_color
		box.border_color = arcade.disc_400_color
		box.set_border_width_all(arcade.well_border_px)
		box.set_corner_radius_all(arcade.radius_block_px)
		box.set_content_margin_all(float(arcade.space_1_px))
		add_theme_stylebox_override("panel", box)
		var column: VBoxContainer = VBoxContainer.new()
		column.add_theme_constant_override("separation", arcade.space_1_px)
		add_child(column)
		for index: int in range(dropdown.item_count):
			var row: Row = Row.new(index, dropdown)
			column.add_child(row)
			_rows.append(row)
		set_process(true)

	func _ready() -> void:
		# Rows keep focus inside the list: left / right stay put, the ends do not wrap out.
		for index: int in range(_rows.size()):
			var row: Row = _rows[index]
			row.focus_neighbor_left = row.get_path()
			row.focus_neighbor_right = row.get_path()
			if index == 0:
				row.focus_neighbor_top = row.get_path()
			if index == _rows.size() - 1:
				row.focus_neighbor_bottom = row.get_path()

	func _process(_delta: float) -> void:
		place()

	## Sits under the dropdown, as wide as it is; flips above when the screen bottom would clip it.
	func place() -> void:
		var wanted: Vector2 = get_combined_minimum_size()
		size = Vector2(maxf(_owner_dropdown.size.x, wanted.x), wanted.y)
		var below: Vector2 = _owner_dropdown.global_position + Vector2(0.0, _owner_dropdown.size.y)
		var screen: Rect2 = _owner_dropdown.get_viewport_rect()
		if below.y + size.y > screen.end.y and _owner_dropdown.global_position.y - size.y >= screen.position.y:
			below.y = _owner_dropdown.global_position.y - size.y
		global_position = below

	func focus_current() -> void:
		var target: int = clampi(_owner_dropdown.selected, 0, _rows.size() - 1)
		_rows[target].grab_focus()

	func has_focus_inside() -> bool:
		var owner_focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		return owner_focus != null and is_ancestor_of(owner_focus)

	func row_at(index: int) -> Row:
		return _rows[index] if index >= 0 and index < _rows.size() else null

	## A press outside the list and its dropdown closes it (the dropdown's own press toggles).
	func _input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
			return
		var point: Vector2 = (event as InputEventMouseButton).global_position
		if not get_global_rect().has_point(point) and not _owner_dropdown.get_global_rect().has_point(point):
			_owner_dropdown.close()


	## One row of the list: label left, the current row disc-600 with a check on the right.
	class Row extends Button:
		var index: int = 0
		var is_current: bool = false
		var _dropdown: UiDropdown = null

		func _init(row_index: int, dropdown: UiDropdown) -> void:
			index = row_index
			is_current = row_index == dropdown.selected
			var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
			text = dropdown.get_item_text(row_index)
			icon = dropdown.get_item_icon(row_index)
			alignment = HORIZONTAL_ALIGNMENT_LEFT
			focus_mode = Control.FOCUS_ALL
			disabled = dropdown.is_item_disabled(row_index)
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			custom_minimum_size.y = float(UiRowItem.metrics().row_height_px)
			var faces: Dictionary = {
				"normal": arcade.disc_600_color if is_current else Color.TRANSPARENT,
				"pressed": arcade.disc_700_color, "disabled": Color.TRANSPARENT,
				"hover": arcade.disc_700_color, "hover_pressed": arcade.disc_700_color,
			}
			for state: String in UiDropdown.STATES:
				var box: StyleBoxFlat = StyleBoxFlat.new()
				box.bg_color = faces[state]
				box.set_corner_radius_all(arcade.radius_cell_px)
				box.content_margin_left = float(arcade.space_3_px)
				box.content_margin_right = float(arcade.space_3_px + arcade.space_4_px)
				add_theme_stylebox_override(state, box)
			for item: String in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
				add_theme_color_override(item, arcade.cream_color)
			add_theme_color_override("font_disabled_color", arcade.dust_color)
			add_theme_font_size_override("font_size", arcade.font_size_body_px)
			_dropdown = dropdown
			pressed.connect(dropdown.pick.bind(row_index))

		## Key events reach only the focus owner, so each row handles B (ui_cancel) itself.
		func _gui_input(event: InputEvent) -> void:
			if event.is_action_pressed(&"ui_cancel"):
				accept_event()
				_dropdown.close()

		func _draw() -> void:
			if not is_current:
				return
			var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
			var stroke: float = float(arcade.well_border_px)
			var reach: float = float(arcade.space_1_px)
			var tip: Vector2 = Vector2(size.x - float(arcade.space_3_px) - reach * 2.0, size.y * 0.5 + reach)
			draw_polyline(PackedVector2Array([tip + Vector2(-reach, -reach), tip, tip + Vector2(reach * 2.0, -reach * 2.0)]), arcade.cream_color, stroke)
