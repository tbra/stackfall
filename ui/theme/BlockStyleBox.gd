class_name BlockStyleBox
extends StyleBox
## The Stackfall Arcade "block" (docs/ui_reskin/components.md BlockButton; docs/UI_RESKIN_PLAN.md P0):
## a face with a lit top edge, a dark lower lip and a solid ledge in disc-950 under it. A single
## StyleBoxFlat cannot draw it (one border colour for every side), so _draw() stacks four rounded
## rectangles. Pressed = no ledge, the face moves down by the drop and the lip is shallow;
## disabled = flat, translucent and ledge-less. Every size and mix comes from ArcadeVisualTuning
## (config/arcade_visual_tuning.tres); build instances with BlockStyleBox.make().

## Block face colour (the "normal" colour; pressed/hover variants are derived by make()).
@export var face_color: Color = Color.WHITE
## Lit top edge colour (the face mixed toward white).
@export var top_color: Color = Color.WHITE
## Dark lower lip colour (the face mixed toward black).
@export var lip_color: Color = Color.BLACK
## Ledge colour under the block (disc-950).
@export var ledge_color: Color = Color.BLACK
@export var radius_px: int = 0
@export var top_px: int = 0
@export var lip_px: int = 0
@export var drop_px: int = 0
@export var pressed: bool = false
@export var disabled: bool = false
## Alpha multiplier applied to every layer when [member disabled].
@export var disabled_alpha: float = 1.0

var _layer: StyleBoxFlat = StyleBoxFlat.new()


## Builds a block in [param face]. [param small] selects the compact recipe (lip-sm/drop-sm, tighter
## padding). [param lip] overrides the derived lip colour (flare-lip, rim-lip, mint-lip) and, when
## pressed, the pressed face. [param top] overrides the derived lit-top colour (flare-top).
static func make(face: Color, tuning: ArcadeVisualTuning, small: bool = false, state: int = 0, lip: Color = Color.TRANSPARENT, top: Color = Color.TRANSPARENT) -> BlockStyleBox:
	var box: BlockStyleBox = BlockStyleBox.new()
	box.pressed = state == STATE_PRESSED
	box.disabled = state == STATE_DISABLED
	var shown_face: Color = face
	if state == STATE_HOVER:
		shown_face = face.lerp(Color.WHITE, tuning.block_hover_light_mix)
	box.lip_color = lip if lip.a > 0.0 else shown_face.lerp(Color.BLACK, tuning.block_lip_dark_mix)
	box.top_color = top if top.a > 0.0 else shown_face.lerp(Color.WHITE, tuning.block_top_light_mix)
	box.face_color = shown_face
	box.ledge_color = tuning.disc_950_color
	box.radius_px = tuning.radius_block_px
	box.top_px = tuning.top_px
	box.lip_px = tuning.lip_sm_px if small else tuning.lip_px
	box.drop_px = tuning.drop_sm_px if small else tuning.drop_px
	box.disabled_alpha = tuning.disabled_alpha
	if box.pressed:
		# The pressed face is the lip colour (flare -> flare-lip); the rim shrinks to the shallow lip.
		box.face_color = box.lip_color
		box.top_color = box.lip_color.lerp(Color.BLACK, tuning.pressed_top_dark_mix)
		box.lip_color = box.lip_color.lerp(Color.BLACK, tuning.block_lip_dark_mix)
		box.top_px = tuning.pressed_lip_px
		box.lip_px = tuning.pressed_lip_px
	var pad_y: int = tuning.button_sm_pad_y_px if small else tuning.button_pad_y_px
	var pad_x: int = tuning.space_3_px if small else tuning.space_4_px
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	# The label sits on the face: above it the lit top, below it the lip and the ledge. A pressed
	# block trades the ledge for the same distance of travel, so its minimum size is unchanged.
	var top_margin: int = pad_y + tuning.top_px
	var bottom_margin: int = pad_y + (tuning.lip_sm_px if small else tuning.lip_px)
	var full_drop: int = tuning.drop_sm_px if small else tuning.drop_px
	if box.pressed:
		box.content_margin_top = top_margin + full_drop
		box.content_margin_bottom = bottom_margin
	else:
		box.content_margin_top = top_margin
		box.content_margin_bottom = bottom_margin + full_drop
	return box


const STATE_NORMAL: int = 0
const STATE_HOVER: int = 1
const STATE_PRESSED: int = 2
const STATE_DISABLED: int = 3


## The four layers [method _draw] paints, bottom to top, for a control rect [param rect] as
## [{name, rect, color}]. Pure so tests can assert the geometry without a renderer.
func layers_for(rect: Rect2) -> Array[Dictionary]:
	var layers: Array[Dictionary] = []
	var width: float = rect.size.x
	var drop: float = float(drop_px)
	if disabled:
		# Flat and translucent: the lip is a bottom strip, no overlap that would double-blend.
		var flat_h: float = rect.size.y - drop
		var body: Rect2 = Rect2(rect.position, Vector2(width, maxf(flat_h - float(lip_px), 0.0)))
		layers.append({"name": "face", "rect": body, "color": _faded(face_color)})
		layers.append({"name": "lip", "rect": Rect2(rect.position + Vector2(0.0, body.size.y), Vector2(width, minf(float(lip_px), flat_h))), "color": _faded(lip_color)})
		return layers
	var area: Rect2 = Rect2(rect.position, Vector2(width, maxf(rect.size.y - drop, 0.0)))
	if pressed:
		area.position.y += drop
	else:
		layers.append({"name": "ledge", "rect": Rect2(rect.position + Vector2(0.0, drop), Vector2(width, maxf(rect.size.y - drop, 0.0))), "color": ledge_color})
	var lip_h: float = minf(float(lip_px), area.size.y)
	layers.append({"name": "lip", "rect": area, "color": lip_color})
	layers.append({"name": "top", "rect": Rect2(area.position, Vector2(width, maxf(area.size.y - lip_h, 0.0))), "color": top_color})
	var face_top: float = minf(float(top_px), area.size.y)
	layers.append({"name": "face", "rect": Rect2(area.position + Vector2(0.0, face_top), Vector2(width, maxf(area.size.y - lip_h - face_top, 0.0))), "color": face_color})
	return layers


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	_layer.set_corner_radius_all(radius_px)
	for layer: Dictionary in layers_for(rect):
		_layer.bg_color = layer["color"] as Color
		_layer.draw(to_canvas_item, layer["rect"] as Rect2)


func _faded(color: Color) -> Color:
	return Color(color.r, color.g, color.b, color.a * disabled_alpha)
