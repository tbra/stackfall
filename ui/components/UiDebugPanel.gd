class_name UiDebugPanel
extends PanelContainer
## The shell every debug readout sits in, look B "glass ledger": a translucent disc-950 plate, a small dust heading
## with the live key chip, hairline rules, and sections of aligned rows (names left, numbers right, a warn row is
## a flare band). Panels pass data only; setters skip work when nothing changed, so a caller polls only while visible.

class Part:
	var box: VBoxContainer = null
	var title: UiText = null
	var grid: GridContainer = null
	var signature: String = ""

const CHORD_JOINER: String = " + "

@export var heading: String = "":
	set(value):
		heading = value
		if _heading_label != null:
			_heading_label.text = value
## The Input Map action whose live binding the chip names for the active device.
var toggle_action: StringName = &"":
	set(value):
		toggle_action = value
		_refresh_chip()
## The chord half (camera_snap_home for F1-F3/F9, pause_menu for F4); shown "Back + Y" on a pad.
var modifier_action: StringName = &"":
	set(value):
		modifier_action = value
		_refresh_chip()

var _heading_label: UiText = null
var _chip: PanelContainer = null
var _chip_label: UiText = null
var _body: VBoxContainer = null
var _parts: Dictionary[StringName, Part] = {}
var _notes: Dictionary[StringName, UiText] = {}


func _init() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var metrics: ComponentMetrics = UiRowItem.metrics()
	var plate: StyleBoxFlat = StyleBoxFlat.new()
	plate.bg_color = Color(arcade.disc_950_color, metrics.debug_panel_alpha)
	plate.set_corner_radius_all(arcade.radius_block_px)
	plate.content_margin_left = float(arcade.space_3_px)
	plate.content_margin_right = float(arcade.space_3_px)
	plate.content_margin_top = float(arcade.space_2_px)
	plate.content_margin_bottom = float(arcade.space_2_px)
	add_theme_stylebox_override("panel", plate)
	custom_minimum_size = Vector2(float(metrics.debug_panel_min_width_px), 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", arcade.space_1_px)
	add_child(column)
	column.add_child(_build_header())
	column.add_child(_hairline())
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", arcade.space_2_px)
	column.add_child(_body)


func _ready() -> void:
	Events.input_device_changed.connect(_on_device_changed)
	_refresh_chip()


## Created at first call (order = first-call order); updated in place; empty rows hide the section.
func set_section(id: StringName, title: String, rows: Array[DebugRow]) -> void:
	_fill(id, title, PackedStringArray(), rows)


## Like set_section with right-aligned numeric columns and a dust header row.
func set_table(id: StringName, title: String, headers: PackedStringArray, rows: Array[DebugRow]) -> void:
	_fill(id, title, headers, rows)


## One free line (status, footer).
func set_note(id: StringName, text: String) -> void:
	var note: UiText = _notes.get(id)
	if note == null:
		note = UiText.make(UiText.Role.CAPTION)
		note.add_theme_font_size_override("font_size", UiRowItem.metrics().debug_font_px)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_notes[id] = note
		_body.add_child(note)
	if note.text != text:
		note.text = text
	note.visible = not text.is_empty()


## Escape hatch for controls the kit has no part for; sections and notes live in the same box, in call order.
func content() -> VBoxContainer:
	return _body


func _build_header() -> HBoxContainer:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var metrics: ComponentMetrics = UiRowItem.metrics()
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", arcade.space_3_px)
	_heading_label = UiText.make(UiText.Role.CAPTION, heading)
	_heading_label.add_theme_font_size_override("font_size", metrics.debug_font_px)
	_heading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_heading_label)
	_chip = PanelContainer.new()
	var outline: StyleBoxFlat = StyleBoxFlat.new()
	outline.bg_color = Color.TRANSPARENT
	outline.set_border_width_all(metrics.debug_hairline_px)
	outline.border_color = arcade.disc_400_color
	outline.set_corner_radius_all(arcade.radius_chip_px)
	outline.content_margin_left = float(arcade.space_2_px)
	outline.content_margin_right = float(arcade.space_2_px)
	_chip.add_theme_stylebox_override("panel", outline)
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_label = UiText.make(UiText.Role.CAPTION)
	_chip_label.add_theme_font_size_override("font_size", metrics.debug_font_px)
	_chip.add_child(_chip_label)
	_chip.visible = false
	row.add_child(_chip)
	return row


func _hairline() -> Panel:
	var metrics: ComponentMetrics = UiRowItem.metrics()
	var rule: Panel = Panel.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(MenuStyleFactory.arcade_tuning().disc_500_color, metrics.debug_hairline_alpha)
	rule.add_theme_stylebox_override("panel", box)
	rule.custom_minimum_size = Vector2(0.0, float(metrics.debug_hairline_px))
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _on_device_changed(_device: StringName) -> void:
	_refresh_chip()


## "F3" for the keyboard binding, "Back + Y" (modifier then toggle) for the pad; hidden when nothing is bound.
func _refresh_chip() -> void:
	if _chip == null:
		return
	var text: String = _binding_text(toggle_action)
	if text != "" and Settings.active_input_device() == Settings.DEVICE_GAMEPAD and modifier_action != &"":
		var modifier: String = _binding_text(modifier_action)
		if modifier != "":
			text = modifier + CHORD_JOINER + text
	_chip_label.text = text
	_chip.visible = text != ""


static func _binding_text(action: StringName) -> String:
	var events: Array[InputEvent] = InputGlyph.events_for_action(action)
	if events.is_empty():
		return ""
	var glyph: InputGlyph = InputGlyph.new()
	glyph.set_event(events[0])
	var text: String = glyph.label_text()
	glyph.free()
	return text


func _fill(id: StringName, title: String, headers: PackedStringArray, rows: Array[DebugRow]) -> void:
	var part: Part = _parts.get(id)
	if part == null:
		part = _make_part(id)
	part.title.text = title
	part.box.visible = not rows.is_empty()
	if rows.is_empty():
		return
	var signature: String = _signature(headers, rows)
	if signature == part.signature:
		return
	part.signature = signature
	var columns: int = headers.size()
	for row: DebugRow in rows:
		columns = maxi(columns, row.cells.size())
	part.grid.columns = maxi(columns, 1)
	var filled: int = 0
	if not headers.is_empty():
		filled = _fill_row(part, filled, headers, false, true)
	for row: DebugRow in rows:
		filled = _fill_row(part, filled, row.cells, row.warn, false)
	while part.grid.get_child_count() > filled:
		var extra: Node = part.grid.get_child(part.grid.get_child_count() - 1)
		part.grid.remove_child(extra)
		extra.queue_free()


func _make_part(id: StringName) -> Part:
	var part: Part = Part.new()
	part.box = VBoxContainer.new()
	part.box.add_theme_constant_override("separation", MenuStyleFactory.arcade_tuning().space_1_px)
	part.title = UiText.make(UiText.Role.CAPTION)
	part.title.add_theme_font_size_override("font_size", UiRowItem.metrics().debug_font_px)
	part.box.add_child(part.title)
	part.grid = GridContainer.new()
	part.grid.add_theme_constant_override("h_separation", 0)
	part.grid.add_theme_constant_override("v_separation", 0)
	part.box.add_child(part.grid)
	_body.add_child(part.box)
	_parts[id] = part
	return part


## Writes one grid row from cell index `start`, reusing the labels already there; returns the next free index.
func _fill_row(part: Part, start: int, texts: PackedStringArray, warn: bool, header: bool) -> int:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var ink: Color = arcade.dust_color if header else (arcade.rim_color if warn else arcade.cream_color)
	var columns: int = part.grid.columns
	for i: int in columns:
		var index: int = start + i
		var label: Label = part.grid.get_child(index) as Label if index < part.grid.get_child_count() else null
		if label == null:
			label = UiText.make(UiText.Role.BODY)
			label.add_theme_font_size_override("font_size", UiRowItem.metrics().debug_font_px)
			part.grid.add_child(label)
		label.text = texts[i] if i < texts.size() else ""
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if i == 0 else Control.SIZE_FILL
		label.add_theme_color_override("font_color", ink)
		label.add_theme_stylebox_override("normal", _cell_box(i, columns, warn and not header))
	return start + columns


func _cell_box(column: int, columns: int, warn: bool) -> StyleBoxFlat:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var metrics: ComponentMetrics = UiRowItem.metrics()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(arcade.flare_color, metrics.debug_warn_alpha) if warn else Color.TRANSPARENT
	box.content_margin_left = float(arcade.space_1_px)
	box.content_margin_right = float(arcade.space_1_px) + (0.0 if column == columns - 1 else float(metrics.debug_column_gap_px))
	box.content_margin_top = float(metrics.debug_hairline_px)
	box.content_margin_bottom = float(metrics.debug_hairline_px)
	return box


static func _signature(headers: PackedStringArray, rows: Array[DebugRow]) -> String:
	var parts: PackedStringArray = PackedStringArray(["|".join(headers)])
	for row: DebugRow in rows:
		parts.append(("!" if row.warn else "") + "|".join(row.cells))
	return "\n".join(parts)
