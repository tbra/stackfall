class_name ShareBar
extends Control
## Bontago-1pi.80: one HUD territory/score bar as a single control. The rounded
## track and its fill (plus the sheen) are all drawn by this control, the fill
## inset inside the track border, so no second control ever sits on top of the
## track. Sizes and colours come from the HUDVisualTuning the HUD passes in.

var fraction: float = 0.0:
	set(value):
		fraction = clampf(value, 0.0, 1.0)
		queue_redraw()
var fill_color: Color = Color.WHITE:
	set(value):
		fill_color = value
		queue_redraw()

var _track_style: StyleBoxFlat = StyleBoxFlat.new()
var _fill_style: StyleBoxFlat = StyleBoxFlat.new()
var _border_px: float = 1.0
var _highlight_color: Color = Color.TRANSPARENT
var _highlight_ratio: float = 0.0


func configure(tuning: HUDVisualTuning) -> void:
	custom_minimum_size = Vector2(tuning.share_bar_width_px, tuning.share_bar_height_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight_ratio = tuning.share_bar_highlight_ratio
	_track_style.bg_color = tuning.hud_share_bar_track_color
	_track_style.border_color = tuning.hud_share_bar_border_color
	_track_style.set_border_width_all(int(_border_px))
	_track_style.set_corner_radius_all(int(tuning.share_bar_height_px * 0.5))
	_fill_style.set_corner_radius_all(maxi(int(tuning.share_bar_height_px * 0.5 - _border_px), 0))
	_highlight_color = tuning.hud_share_bar_highlight_color
	queue_redraw()


## The fill's rectangle, inside the track's border.
func fill_rect() -> Rect2:
	var inner: Rect2 = Rect2(Vector2.ONE * _border_px, size - Vector2.ONE * _border_px * 2.0)
	inner.size.x *= fraction
	return inner


func _draw() -> void:
	draw_style_box(_track_style, Rect2(Vector2.ZERO, size))
	var rect: Rect2 = fill_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_fill_style.bg_color = fill_color
	draw_style_box(_fill_style, rect)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * _highlight_ratio)), _highlight_color)
