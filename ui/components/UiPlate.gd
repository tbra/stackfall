class_name UiPlate
extends PanelContainer
## A flat tinted plate: a face colour, rounded corners, token padding and an optional edge (all four sides) or
## rule (bottom only). The lobby's lane fields and caps and the table's header rule are plates; screens call
## [method paint] with token colours instead of styling a panel by hand.


## Paints the plate. [param edge_px] > 0 draws an edge of [param edge] on all four sides; [param rule_px] > 0 a
## rule of [param edge] along the bottom only. Padding is in px (token values from the caller).
func paint(face: Color, radius_px: int, pad_x_px: int, pad_y_px: int, edge: Color = Color.TRANSPARENT, edge_px: int = 0, rule_px: int = 0) -> UiPlate:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = face
	box.set_corner_radius_all(radius_px)
	box.content_margin_left = float(pad_x_px)
	box.content_margin_right = float(pad_x_px)
	box.content_margin_top = float(pad_y_px)
	box.content_margin_bottom = float(pad_y_px)
	if edge_px > 0:
		box.set_border_width_all(edge_px)
		box.border_color = edge
	if rule_px > 0:
		box.border_width_bottom = rule_px
		box.border_color = edge
	add_theme_stylebox_override("panel", box)
	return self
