class_name UiWell
extends PanelContainer
## The design system's sunken well (a disc-900 face with a 2px
## disc-400 edge, shadow-well and radius-block) as a container: the LAN / Steam game lists, a
## roster or any inset area. Screens add their content as children and never style the panel.
## The shadow-well is the darker band along the inside of the top edge, drawn over the face.

func _init() -> void:
	add_theme_stylebox_override("panel", make_style())


## The face and edge (the shadow band is drawn by the node).
static func make_style() -> StyleBoxFlat:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = arcade.disc_900_color
	box.border_color = arcade.disc_400_color
	box.set_border_width_all(arcade.well_border_px)
	box.set_corner_radius_all(arcade.radius_block_px)
	box.set_content_margin_all(float(arcade.space_3_px))
	return box


## The top shadow's colour: the well face mixed toward black.
static func shadow_color() -> Color:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	return arcade.disc_900_color.lerp(Color.BLACK, arcade.well_shadow_mix)


## The shadow band's rect under the top edge, clear of the rounded corners, [param size] being the well's size.
static func shadow_rect(size: Vector2) -> Rect2:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var edge: float = float(arcade.well_border_px)
	var inset: float = float(arcade.radius_block_px)
	return Rect2(inset, edge, maxf(size.x - 2.0 * inset, 0.0), float(arcade.well_shadow_px))


func _draw() -> void:
	draw_rect(shadow_rect(size), shadow_color())
