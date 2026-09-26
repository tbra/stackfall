class_name MenuBackdrop
extends Control
## M7 P7 (docs/M7_PLAN.md "P7 -- Main menu / lobby reskin", Bontago-xtq.32):
## the flat "paper-cut" half of the split background (docs/art_mockups/
## 10-main-menu-layered-pastel.png, 11-lobby-layered-pastel.png) -- a banded
## sky, a layered concentric sun, pill-shaped cloud strata and apricot/mint
## ground bands, all drawn with _draw() so no image asset is needed (hard
## constraint in the brief). Sits full-rect behind everything else; the live
## 3D diorama (ui/MenuDiorama.gd) is reframed into the right third on top of
## it as its own small framed island.
##
## Every color, count and layout fraction it draws from is a
## config/MenuVisualTuning.gd export (CLAUDE.md "No magic numbers"); this
## script holds no tunables of its own, only the drawing routine, matching
## ui/MenuDiorama.gd's existing "build everything in _ready()/_draw(), no
## companion .tscn children" convention.

@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")

const SKY_BAND_COUNT: int = 24


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var size: Vector2 = get_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_sky(size)
	_draw_sun(size)
	_draw_clouds(size)
	_draw_ground_bands(size)


func _draw_sky(size: Vector2) -> void:
	var band_height: float = size.y / float(SKY_BAND_COUNT)
	for i: int in range(SKY_BAND_COUNT):
		var t: float = float(i) / float(SKY_BAND_COUNT - 1)
		var color: Color = tuning.backdrop_sky_top_color.lerp(tuning.backdrop_sky_horizon_color, t)
		var rect: Rect2 = Rect2(0.0, band_height * float(i), size.x, band_height + 1.0)
		draw_rect(rect, color, true)


## Draws the sun as [member MenuVisualTuning.backdrop_sun_ring_count] concentric
## filled circles, largest first, alternating the two sun colors so each
## smaller circle drawn on top leaves the previous one visible as a ring.
func _draw_sun(size: Vector2) -> void:
	var ring_count: int = tuning.backdrop_sun_ring_count
	if ring_count <= 0:
		return
	var center: Vector2 = Vector2(
		size.x * tuning.backdrop_sun_pos_x_fraction,
		size.y * tuning.backdrop_sun_pos_y_fraction
	)
	var outer_radius: float = minf(size.x, size.y) * tuning.backdrop_sun_radius_fraction
	for k: int in range(ring_count, 0, -1):
		var radius: float = outer_radius * (float(k) / float(ring_count))
		var color: Color = tuning.backdrop_sun_color if k % 2 == 1 else tuning.backdrop_sun_ring_color
		draw_circle(center, radius, color)


## Pill-shaped cloud strata, spaced evenly across the sky at a fixed height
## band with a small alternating vertical offset.
func _draw_clouds(size: Vector2) -> void:
	var count: int = tuning.backdrop_cloud_count
	if count <= 0:
		return
	var cloud_height: float = size.y * 0.05
	var cloud_width: float = size.x * 0.16
	var base_y: float = size.y * 0.34
	for i: int in range(count):
		var t: float = (float(i) + 0.5) / float(count)
		var offset_y: float = cloud_height * 0.8 if i % 2 == 0 else 0.0
		var rect: Rect2 = Rect2(
			size.x * t - cloud_width * 0.5,
			base_y + offset_y,
			cloud_width,
			cloud_height
		)
		var pill: StyleBoxFlat = StyleBoxFlat.new()
		pill.bg_color = tuning.backdrop_cloud_color
		pill.set_corner_radius_all(int(cloud_height * 0.5))
		draw_style_box(pill, rect)


func _draw_ground_bands(size: Vector2) -> void:
	var band_height: float = size.y * tuning.ground_band_height_fraction
	var mint_rect: Rect2 = Rect2(0.0, size.y - band_height, size.x, band_height)
	var apricot_rect: Rect2 = Rect2(0.0, size.y - band_height * 2.0, size.x, band_height)
	draw_rect(apricot_rect, tuning.ground_band_apricot_color, true)
	draw_rect(mint_rect, tuning.ground_band_mint_color, true)
