class_name LobbyOpenSeatRow
extends PanelContainer
## The Players column's open seat (Stackfall Arcade, docs/ui_reskin/components.md "PlayerSlot"): a dashed
## outline holding a dimmed diamond in the next free colour, the words "Open seat" and the host's
## "+ Add bot" button. Look only: the button is the panel's own %AddBotButton, reparented here.

const OPEN_SEAT_TEXT: String = "Open seat"

var _layout_tuning: LobbyLayoutTuning = null
var diamond: SlotDiamond = null
var label: Label = null


## Builds the row around [param add_button] (reparented into it).
func build(layout_tuning: LobbyLayoutTuning, add_button: Button) -> void:
	_layout_tuning = layout_tuning
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	name = "OpenSeatRow"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inset: StyleBoxEmpty = StyleBoxEmpty.new()
	inset.content_margin_left = float(arcade.space_3_px)
	inset.content_margin_right = float(arcade.space_3_px)
	inset.content_margin_top = float(arcade.space_2_px)
	inset.content_margin_bottom = float(arcade.space_2_px)
	add_theme_stylebox_override("panel", inset)
	var layout: HBoxContainer = HBoxContainer.new()
	layout.add_theme_constant_override("separation", layout_tuning.seat_row_separation_px)
	add_child(layout)
	var box: CenterContainer = CenterContainer.new()
	box.custom_minimum_size = _layout_tuning.color_box_size_px
	layout.add_child(box)
	diamond = SlotDiamond.create(arcade.disc_500_color)
	diamond.name = "SlotDiamond"
	box.add_child(diamond)
	label = Label.new()
	label.text = OPEN_SEAT_TEXT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", arcade.dust_color)
	label.add_theme_font_size_override("font_size", layout_tuning.seat_name_font_size)
	layout.add_child(label)
	if add_button.get_parent() != null:
		add_button.get_parent().remove_child(add_button)
	layout.add_child(add_button)
	# Bontago-1pi.146: the same control height as the filled rows' pills.
	add_button.custom_minimum_size.y = float(layout_tuning.seat_control_height_px)
	add_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	MenuStyleFactory.apply_block(add_button, arcade.disc_600_color, arcade.cream_color, true)


## Paints the diamond in [param color], dimmed to the tuning's open-seat alpha.
func set_next_color(color: Color) -> void:
	if diamond == null:
		return
	diamond.set_color(color)
	diamond.modulate.a = _layout_tuning.open_seat_diamond_alpha


func _draw() -> void:
	if _layout_tuning == null:
		return
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var width: float = float(_layout_tuning.open_seat_border_px)
	var rect: Rect2 = Rect2(Vector2.ONE * width * 0.5, size - Vector2.ONE * width)
	var corners: Array[Vector2] = [
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
	]
	for i: int in range(corners.size()):
		_dashed_line(corners[i], corners[(i + 1) % corners.size()], arcade.disc_400_color, width)


func _dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var length: float = from.distance_to(to)
	var direction: Vector2 = (to - from).normalized()
	var dash: float = float(maxi(_layout_tuning.open_seat_dash_px, 1))
	var step: float = dash + float(_layout_tuning.open_seat_gap_px)
	var at: float = 0.0
	while at < length:
		draw_line(from + direction * at, from + direction * minf(at + dash, length), color, width)
		at += step


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
