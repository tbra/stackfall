class_name UiStatusBadge
extends PanelContainer
## The design system's StatusBadge (docs/ui_reskin/components.md): a small flat label with an
## optional live mint dot, never focusable and never clickable. It is a UiRowItem (BADGE) and the
## single implementation of the lobby title badge, the Ready / Not ready tile (icon-only, the
## owner's 1pi.94 S3 decision; ui/ReadyPill.gd is a thin wrapper) and the all-ready rim form.
## Faces and sizes come from ArcadeVisualTuning and ComponentMetrics.

enum Look { NEUTRAL, READY, ALL_READY, NOT_READY, HOST }

const TICK: int = 0x2713
const HOURGLASS: int = 0x231A

## The label shown (and, icon-only, the accessible tooltip).
var text: String = "":
	set(value):
		text = value
		_refresh()
var variant: Look = Look.NEUTRAL:
	set(value):
		variant = value
		_refresh()
## Draws the live mint dot left of the label.
var live: bool = false:
	set(value):
		live = value
		_refresh()
## Shows only a glyph (tick / hourglass for READY / NOT_READY); the text becomes the tooltip.
var icon_only: bool = false:
	set(value):
		icon_only = value
		_apply_width()
		_refresh()
## >= 0 replaces the vertical content margin (compact rows, e.g. the loading screen).
var pad_y_override_px: float = -1.0:
	set(value):
		pad_y_override_px = value
		_refresh()

var label: Label = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	UiRowItem.apply(self, UiRowItem.Kind.BADGE)
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	_refresh()


## The face colour of [param variant_value] (tokens).
static func face_for(variant_value: Look, tuning: ArcadeVisualTuning = null) -> Color:
	var arcade: ArcadeVisualTuning = tuning if tuning != null else MenuStyleFactory.arcade_tuning()
	match variant_value:
		Look.READY:
			return arcade.mint_color
		Look.ALL_READY, Look.HOST:
			return arcade.rim_color
		Look.NOT_READY:
			return arcade.disc_600_color
	return arcade.disc_700_color


## The glyph an icon-only badge of [param variant_value] shows; other variants show [param fallback].
static func glyph_for(variant_value: Look, fallback: String) -> String:
	match variant_value:
		Look.READY:
			return char(TICK)
		Look.NOT_READY:
			return char(HOURGLASS)
	return fallback


## Whether the face carries a lit lip (the neutral badge is flat).
static func has_lip(variant_value: Look) -> bool:
	return variant_value != Look.NEUTRAL


func _refresh() -> void:
	if label == null:
		return
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var m: ComponentMetrics = UiRowItem.metrics()
	var face: Color = face_for(variant, arcade)
	var lipped: bool = has_lip(variant)
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = face
	box.set_corner_radius_all(arcade.radius_chip_px)
	if lipped:
		box.border_color = MenuStyleFactory.lip_for(face)
		box.border_width_bottom = arcade.lip_sm_px
	var pad_y: float = pad_y_override_px if pad_y_override_px >= 0.0 else float(arcade.space_1_px)
	box.content_margin_left = float(arcade.space_3_px)
	box.content_margin_right = float(arcade.space_3_px)
	if live and not icon_only:
		box.content_margin_left += float(m.badge_dot_px + arcade.space_2_px)
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y + (float(arcade.lip_sm_px) if lipped else 0.0)
	add_theme_stylebox_override("panel", box)
	label.text = glyph_for(variant, text) if icon_only else text
	label.add_theme_font_size_override("font_size", arcade.font_size_label_px)
	label.add_theme_color_override("font_color", MenuStyleFactory.ink_for_face(face))
	tooltip_text = text if icon_only else ""
	queue_redraw()


## The default minimum width of the current form; callers may override custom_minimum_size after.
func _apply_width() -> void:
	var m: ComponentMetrics = UiRowItem.metrics()
	custom_minimum_size.x = float(m.badge_icon_only_min_width_px if icon_only else m.badge_min_width_px)


func _draw() -> void:
	if not live or icon_only:
		return
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var radius: float = float(UiRowItem.metrics().badge_dot_px) / 2.0
	var ink: Color = MenuStyleFactory.ink_for_face(face_for(variant, arcade))
	var dot: Color = arcade.mint_color if ink == arcade.cream_color else ink
	var lip: float = float(arcade.lip_sm_px) if has_lip(variant) else 0.0
	draw_circle(Vector2(float(arcade.space_3_px) + radius, (size.y - lip) / 2.0), radius, dot)
