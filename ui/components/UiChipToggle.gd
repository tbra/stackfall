class_name UiChipToggle
extends Button
## The design system's ChipToggle (docs/ui_reskin/components.md "ChipToggle"): a compact block for
## the gift / special pool and the lobby's experiment flags. On = a `mint` block with an ink
## check box holding a tick; off = a `disc-700` block with an empty box, so the state never relies
## on colour alone. A UiRowItem (BUTTON_SM height). Pad / keyboard: ui_accept toggles. A chip that
## is switched off for the match (set_available(false), e.g. the Cat gift) is shown disabled with
## its tooltip. The label is the Button's text, the optional pictogram its icon.

@export var label: String = "":
	set(value):
		label = value
		text = value
@export var chip_icon: Texture2D = null:
	set(value):
		chip_icon = value
		icon = value

var _available: bool = true
var _tooltip_when_unavailable: String = ""


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggled.connect(_on_toggled)
	_restyle()
	UiRowItem.apply(self, UiRowItem.Kind.BUTTON_SM)


func set_on(on: bool) -> void:
	button_pressed = on


## Sets the state without emitting `toggled` (remote sync).
func set_on_silent(on: bool) -> void:
	set_pressed_no_signal(on)
	_restyle()


func is_on() -> bool:
	return button_pressed


## Shows the chip disabled (e.g. a gift that is switched off) with [param why] as its tooltip.
func set_available(available: bool, why: String = "") -> void:
	_available = available
	_tooltip_when_unavailable = why
	disabled = not available
	if not available and not why.is_empty():
		tooltip_text = why
	_restyle()


func is_available() -> bool:
	return _available


## The face of a chip: mint when on, disc-700 when off (tokens).
static func face_for(on: bool, arcade: ArcadeVisualTuning = null) -> Color:
	var tokens: ArcadeVisualTuning = arcade if arcade != null else MenuStyleFactory.arcade_tuning()
	return tokens.mint_color if on else tokens.disc_700_color


func _on_toggled(_on: bool) -> void:
	_restyle()


func _restyle() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var m: ComponentMetrics = UiRowItem.metrics()
	var off_face: Color = face_for(false, arcade)
	var on_face: Color = face_for(true, arcade)
	var off_hover: Color = off_face.lerp(Color.WHITE, arcade.block_hover_light_mix)
	var on_hover: Color = on_face.lerp(Color.WHITE, arcade.block_hover_light_mix)
	var lip_off: Color = MenuStyleFactory.lip_for(off_face)
	var lip_on: Color = MenuStyleFactory.lip_for(on_face)
	var top_off: Color = MenuStyleFactory.top_for(off_face)
	var top_on: Color = MenuStyleFactory.top_for(on_face)
	var shown_face: Color = on_face if button_pressed else off_face
	var normal: int = BlockStyleBox.STATE_NORMAL
	# Godot's "pressed" is the toggled-on look; the block itself stays unpressed (lit, ledged).
	var boxes: Dictionary = {
		"normal": BlockStyleBox.make(off_face, arcade, true, normal, lip_off, top_off),
		"hover": BlockStyleBox.make(off_hover, arcade, true, normal, lip_off, top_off),
		"pressed": BlockStyleBox.make(on_face, arcade, true, normal, lip_on, top_on),
		"hover_pressed": BlockStyleBox.make(on_hover, arcade, true, normal, lip_on, top_on),
		"disabled": BlockStyleBox.make(shown_face, arcade, true, BlockStyleBox.STATE_DISABLED, MenuStyleFactory.lip_for(shown_face), MenuStyleFactory.top_for(shown_face)),
	}
	var lead: float = float(arcade.space_3_px + m.chip_box_px + arcade.space_2_px)
	for state: String in boxes:
		var box: BlockStyleBox = boxes[state] as BlockStyleBox
		box.content_margin_left = lead
		add_theme_stylebox_override(state, box)
	UiBlockButton.fit_row_height(self, arcade)
	var off_ink: Color = MenuStyleFactory.ink_for_face(off_face)
	var on_ink: Color = MenuStyleFactory.ink_for_face(on_face)
	for item: String in ["font_color", "font_focus_color", "font_hover_color", "icon_normal_color", "icon_focus_color", "icon_hover_color"]:
		add_theme_color_override(item, off_ink)
	for item: String in ["font_pressed_color", "font_hover_pressed_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		add_theme_color_override(item, on_ink)
	add_theme_font_size_override("font_size", arcade.font_size_button_sm_px)
	add_theme_constant_override("icon_max_width", arcade.icon_max_width_px)
	queue_redraw()


func _draw() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var m: ComponentMetrics = UiRowItem.metrics()
	var box: StyleBox = get_theme_stylebox("normal")
	var centre_y: float = (box.content_margin_top + size.y - box.content_margin_bottom) / 2.0
	var edge: float = float(m.chip_box_px)
	var rect: Rect2 = Rect2(Vector2(float(arcade.space_3_px), centre_y - edge / 2.0), Vector2(edge, edge))
	var alpha: float = arcade.disabled_alpha if disabled else 1.0
	var frame: StyleBoxFlat = StyleBoxFlat.new()
	frame.set_corner_radius_all(arcade.radius_cell_px)
	if button_pressed:
		frame.bg_color = Color(arcade.ink_color, alpha)
	else:
		frame.bg_color = Color(arcade.disc_900_color, alpha)
		frame.set_border_width_all(arcade.well_border_px)
		frame.border_color = Color(arcade.disc_400_color, alpha)
	frame.draw(get_canvas_item(), rect)
	if button_pressed:
		var tick: Color = Color(arcade.mint_color, alpha)
		var points: PackedVector2Array = PackedVector2Array([
			rect.position + rect.size * Vector2(TICK_START.x, TICK_START.y),
			rect.position + rect.size * Vector2(TICK_MID.x, TICK_MID.y),
			rect.position + rect.size * Vector2(TICK_END.x, TICK_END.y),
		])
		draw_polyline(points, tick, float(m.chip_check_stroke_px), true)


## The tick's three points as fractions of the check box (a fixed glyph shape, not a tunable).
const TICK_START: Vector2 = Vector2(0.22, 0.52)
const TICK_MID: Vector2 = Vector2(0.42, 0.72)
const TICK_END: Vector2 = Vector2(0.78, 0.28)
