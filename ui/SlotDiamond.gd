class_name SlotDiamond
extends Control
## Bontago-1pi.81: the ONE faceted colour diamond (lit left half, shaded right half,
## thin outline) that marks a player slot: the HUD share rows, the lobby seat rows and the
## round score table all instance ui/SlotDiamond.tscn. It draws whatever colour its owner
## hands to set_color(); it has no colour logic of its own (the slot -> colour lookup
## stays with the caller). Look and default size come from HUDVisualTuning.

const SCENE: PackedScene = preload("res://ui/SlotDiamond.tscn")

@export var tuning: HUDVisualTuning = preload("res://config/hud_visual_tuning.tres")

var color: Color = Color.WHITE
var _size_px: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_size()


## A fresh shared diamond painted `slot_color`; `size_px` <= 0 uses the tuning default.
static func create(slot_color: Color, size_px: float = -1.0) -> SlotDiamond:
	var diamond: SlotDiamond = SCENE.instantiate() as SlotDiamond
	diamond.color = slot_color
	diamond._size_px = size_px
	diamond.custom_minimum_size = Vector2.ONE * diamond.diamond_size_px()
	return diamond


func set_color(value: Color) -> void:
	color = value
	queue_redraw()


func set_size_px(value: float) -> void:
	_size_px = value
	_apply_size()


## The side length in effect.
func diamond_size_px() -> float:
	return _size_px if _size_px > 0.0 else tuning.hud_row_glyph_size_px


## The diamond's corners (top, right, bottom, left) around `center`, `half` from it; also
## the shape other canvases (the minimap beacons) can draw.
## Corner indices of points(): clockwise from the top.
const CORNER_TOP: int = 0
const CORNER_RIGHT: int = 1
const CORNER_BOTTOM: int = 2
const CORNER_LEFT: int = 3


static func points(center: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0.0, -half), center + Vector2(half, 0.0),
		center + Vector2(0.0, half), center + Vector2(-half, 0.0),
	])


func _apply_size() -> void:
	custom_minimum_size = Vector2.ONE * diamond_size_px()
	queue_redraw()


func _draw() -> void:
	var corners: PackedVector2Array = points(size * 0.5, diamond_size_px() * 0.5)
	draw_colored_polygon(PackedVector2Array([corners[CORNER_TOP], corners[CORNER_LEFT], corners[CORNER_BOTTOM]]), color.lightened(tuning.hud_diamond_lit_amount))
	draw_colored_polygon(PackedVector2Array([corners[CORNER_TOP], corners[CORNER_RIGHT], corners[CORNER_BOTTOM]]), color.darkened(tuning.hud_diamond_shade_amount))
	var outline: PackedVector2Array = corners.duplicate()
	outline.append(corners[CORNER_TOP])
	draw_polyline(outline, tuning.hud_diamond_outline_color, tuning.hud_diamond_outline_width_px, true)
