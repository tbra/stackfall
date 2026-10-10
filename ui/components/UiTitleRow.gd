class_name UiTitleRow
extends HBoxContainer
## A screen / panel title row (docs/UI_COMPONENTS_PLAN.md section 4, "Title alignment"): the flare
## voxel bullet and the uppercase heading on the left edge, then optional trailing items (a status
## badge, a Back button) pushed right, all centred on one baseline. It owns the heading look so
## every screen title lines up with its panel's inner padding. [UiPanel] uses one as its header.

## The heading text; shown in capitals.
@export var title: String = "":
	set(value):
		title = value
		label.text = value.to_upper()
## The flare bullet before the heading.
@export var bullet: bool = true:
	set(value):
		bullet = value
		_bullet.visible = value

var label: Label = null
var _bullet: Control = null
var _spacer: Control = null


func _init() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	add_theme_constant_override("separation", arcade.space_2_px)
	_bullet = Control.new()
	_bullet.custom_minimum_size = Vector2.ONE * float(arcade.space_3_px)
	_bullet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bullet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bullet.draw.connect(_draw_bullet)
	add_child(_bullet)
	label = Label.new()
	label.theme_type_variation = &"TitleLabel"
	label.add_theme_font_size_override("font_size", arcade.font_size_heading_px)
	label.add_theme_color_override("font_color", arcade.cream_color)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	_spacer = Control.new()
	_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_spacer)


## Appends [param item] on the right (a badge, a Back button), vertically centred.
func add_trailing(item: Control) -> void:
	item.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(item)


## The panel-heading look for a bare [param heading_label] (a flare notch on its left and the
## text in capitals) for screens whose title Label is authored in a scene.
static func style_heading_label(heading_label: Label) -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var notch: StyleBoxFlat = StyleBoxFlat.new()
	notch.bg_color = Color.TRANSPARENT
	notch.border_color = arcade.flare_color
	notch.border_width_left = arcade.space_2_px
	notch.set_corner_radius_all(arcade.radius_cell_px)
	notch.content_margin_left = float(arcade.space_4_px)
	heading_label.text = heading_label.text.to_upper()
	heading_label.add_theme_stylebox_override("normal", notch)


func _draw_bullet() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = arcade.flare_color
	box.border_color = arcade.flare_lip_color
	box.border_width_bottom = arcade.pressed_lip_px
	box.set_corner_radius_all(arcade.radius_cell_px)
	_bullet.draw_style_box(box, Rect2(Vector2.ZERO, _bullet.size))
