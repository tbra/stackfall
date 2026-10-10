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
	# Stackfall Arcade (Bontago-hfa.6) beacon marker (docs/ui_reskin/markers/): an ink diamond frame,
	# the inner diamond split into a lit left and shaded right half, and the slot colour over its top facet.
	var center: Vector2 = size * 0.5
	var half: float = diamond_size_px() * 0.5
	var frame: PackedVector2Array = points(center, half)
	draw_colored_polygon(frame, tuning.hud_diamond_outline_color)
	var inner: PackedVector2Array = points(center, maxf(half - tuning.hud_diamond_outline_width_px, 0.0))
	draw_colored_polygon(PackedVector2Array([inner[CORNER_TOP], inner[CORNER_LEFT], inner[CORNER_BOTTOM]]), color.lightened(tuning.hud_diamond_lit_amount))
	draw_colored_polygon(PackedVector2Array([inner[CORNER_TOP], inner[CORNER_RIGHT], inner[CORNER_BOTTOM]]), color.darkened(tuning.hud_diamond_shade_amount))
	var facet: Color = Color(color.r, color.g, color.b, tuning.hud_diamond_top_facet_alpha)
	draw_colored_polygon(PackedVector2Array([inner[CORNER_TOP], inner[CORNER_RIGHT], inner[CORNER_LEFT]]), facet)
