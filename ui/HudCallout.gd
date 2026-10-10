class_name HudCallout
extends Control
## Stackfall Arcade Callout icon tile (Bontago-hfa.6, docs/ui_reskin/components.md "Callout"): a
## small ink square holding a cream cross, check, star or "!" glyph, drawn as lines/polygons so the
## message carries its meaning without relying on colour or on a font having the symbol. It sits at
## the left edge of the toast Label that styles itself as the Callout face (ui/HUD.gd).

enum Glyph { CROSS, CHECK, STAR, ALERT }

const STAR_POINTS: int = 5
const STAR_INNER_RATIO: float = 0.45
const STAR_RADIUS_SHARE: float = 0.62
## Glyph extent as a fraction of the tile edge.
const GLYPH_SHARE: float = 0.56
const CHECK_START: Vector2 = Vector2(0.0, 0.55)
const CHECK_KNEE: Vector2 = Vector2(0.38, 1.0)
const CHECK_END: Vector2 = Vector2(1.0, 0.05)
const ALERT_BAR_END: float = 0.62
const ALERT_DOT_Y: float = 0.9
const ALERT_DOT_RADIUS_SHARE: float = 0.55

var glyph: Glyph = Glyph.CROSS:
	set(value):
		glyph = value
		queue_redraw()
var tile_color: Color = Color.BLACK
var glyph_color: Color = Color.WHITE
var stroke_px: float = 1.0
var corner_px: int = 2


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Sizes and colours the tile from the HUD tuning and the Arcade tokens.
func configure(tuning: HUDVisualTuning, arcade: ArcadeVisualTuning) -> void:
	custom_minimum_size = Vector2.ONE * tuning.callout_icon_px
	size = custom_minimum_size
	stroke_px = tuning.callout_glyph_stroke_px
	tile_color = tuning.toast_fill_color
	glyph_color = arcade.cream_color
	corner_px = arcade.radius_chip_px
	queue_redraw()


func _draw() -> void:
	var tile: StyleBoxFlat = StyleBoxFlat.new()
	tile.bg_color = tile_color
	tile.set_corner_radius_all(corner_px)
	draw_style_box(tile, Rect2(Vector2.ZERO, size))
	var edge: float = minf(size.x, size.y)
	var extent: float = edge * GLYPH_SHARE
	var origin: Vector2 = (size - Vector2.ONE * extent) * 0.5
	match glyph:
		Glyph.CROSS:
			draw_line(origin, origin + Vector2.ONE * extent, glyph_color, stroke_px, true)
			draw_line(origin + Vector2(extent, 0.0), origin + Vector2(0.0, extent), glyph_color, stroke_px, true)
		Glyph.CHECK:
			var pts: PackedVector2Array = PackedVector2Array([
				origin + CHECK_START * extent,
				origin + CHECK_KNEE * extent,
				origin + CHECK_END * extent,
			])
			draw_polyline(pts, glyph_color, stroke_px, true)
		Glyph.STAR:
			draw_colored_polygon(star_points(size * 0.5, extent * STAR_RADIUS_SHARE), glyph_color)
		Glyph.ALERT:
			var x: float = size.x * 0.5
			draw_line(Vector2(x, origin.y), Vector2(x, origin.y + extent * ALERT_BAR_END), glyph_color, stroke_px, true)
			draw_circle(Vector2(x, origin.y + extent * ALERT_DOT_Y), stroke_px * ALERT_DOT_RADIUS_SHARE, glyph_color)


## Outline of a five-point star of outer `radius` around `center`, point up.
static func star_points(center: Vector2, radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var steps: int = STAR_POINTS * 2
	for i: int in range(steps):
		var r: float = radius if i % 2 == 0 else radius * STAR_INNER_RATIO
		var a: float = -PI * 0.5 + TAU * float(i) / float(steps)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts
