class_name ShareBar
extends Control
## Bontago-1pi.80: one HUD territory/score bar as a single control. Stackfall Arcade (Bontago-hfa.6):
## a disc-700 well track with the player's colour as the fill and a cut every 10 % (disc-900), so
## 5 % and 12 % compare at a glance without the bar looking empty. The track, fill, sheen and cuts
## are all drawn by this control, the fill inset inside the track border. Sizes and colours come
## from the HUDVisualTuning the HUD passes in plus the ArcadeVisualTuning tokens.

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
var _tick_color: Color = Color.TRANSPARENT
var _tick_count: int = 0
var _tick_width_px: float = 0.0


func configure(tuning: HUDVisualTuning) -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	custom_minimum_size = Vector2(tuning.share_bar_width_px, tuning.share_bar_height_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight_ratio = tuning.share_bar_highlight_ratio
	_track_style.bg_color = tuning.hud_share_bar_track_color
	_track_style.border_color = tuning.hud_share_bar_border_color
	_track_style.set_border_width_all(int(_border_px))
	_track_style.set_corner_radius_all(arcade.radius_cell_px)
	_fill_style.set_corner_radius_all(maxi(arcade.radius_cell_px - int(_border_px), 0))
	_highlight_color = tuning.hud_share_bar_highlight_color
	_tick_color = tuning.hud_share_bar_border_color
	_tick_count = tuning.share_tick_count
	_tick_width_px = tuning.share_tick_width_px
	queue_redraw()


## The fill's rectangle, inside the track's border.
func fill_rect() -> Rect2:
	var inner: Rect2 = Rect2(Vector2.ONE * _border_px, size - Vector2.ONE * _border_px * 2.0)
	inner.size.x *= fraction
	return inner


## X positions of the cuts across the track (every 1/tick_count of its width, none at the ends).
func tick_positions() -> PackedFloat32Array:
	var xs: PackedFloat32Array = PackedFloat32Array()
	if _tick_count <= 1:
		return xs
	for i: int in range(1, _tick_count):
		xs.append(size.x * float(i) / float(_tick_count))
	return xs


func _draw() -> void:
	draw_style_box(_track_style, Rect2(Vector2.ZERO, size))
	var rect: Rect2 = fill_rect()
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		_fill_style.bg_color = fill_color
		draw_style_box(_fill_style, rect)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * _highlight_ratio)), _highlight_color)
	for x: float in tick_positions():
		draw_rect(Rect2(x - _tick_width_px * 0.5, 0.0, _tick_width_px, size.y), _tick_color)
