class_name UiBlockButton
extends Button
## The design system's BlockButton (docs/ui_reskin/components.md): a coloured face, a lit top, a
## dark lip and a solid ledge, drawn by ui/theme/BlockStyleBox.gd from ArcadeVisualTuning. Screens
## pick a semantic [enum Look] and `small`; they never pass colours. A small button is a
## UiRowItem (BUTTON_SM): its face, lip and ledge fit inside ComponentMetrics.row_height_px so it
## is exactly as tall as every other item of its row. A full-size button keeps the standard
## padding and is not a row item.

## DANGER is a SECONDARY block with an alert-coloured label (a destructive action that is always
## followed by a confirm, e.g. Leave match).
enum Look { PRIMARY, SECONDARY, MINT, RIM, DANGER }

const STATES: PackedStringArray = ["normal", "hover", "pressed", "hover_pressed", "disabled"]
const LOOK_KEY_STRIDE: int = 4
const LOOK_SMALL_BIT: int = 1
const LOOK_ICON_BIT: int = 2

static var _looks: Dictionary = {}
static var _looks_tuning: ArcadeVisualTuning = null

@export var variant: Look = Look.SECONDARY:
	set(value):
		variant = value
		_restyle()
@export var small: bool = true:
	set(value):
		small = value
		_restyle()
## The Input Map action whose key / pad glyph trails the label (UiButtonHint: sized to the block,
## centred on the label line, dimmed / darkened with the button state; follows device and rebinds).
@export var hint_action: StringName = &"":
	set(value):
		hint_action = value
		UiButtonHint.attach(self, hint_action)


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_restyle()


## The face colour of [param variant_value] (token colours; no scene needed).
static func face_for(variant_value: Look, tuning: ArcadeVisualTuning = null) -> Color:
	var arcade: ArcadeVisualTuning = tuning if tuning != null else MenuStyleFactory.arcade_tuning()
	match variant_value:
		Look.PRIMARY:
			return arcade.flare_color
		Look.MINT:
			return arcade.mint_color
		Look.RIM:
			return arcade.rim_color
	return arcade.disc_600_color


## Styles any [param button] as a block of [param variant_value]. Used by the node itself and,
## during the migration, by tscn buttons that cannot be swapped yet. Small blocks also get the
## row-item contract's vertical fit (see [method fit_row_height]). The five block styleboxes come
## from [method shared_look]: one set per (variant, size) is built per token set and shared by
## every button, never mutated afterwards (UiButtonHint copies a box before it reserves room).
static func style(button: Button, variant_value: Look, small_block: bool = true) -> void:
	apply_look(button, shared_look(variant_value, small_block))


## Puts a [method shared_look] on [param button]: the shared boxes plus per-button ink and font size.
static func apply_look(button: Button, look: Dictionary) -> void:
	var boxes: Dictionary = look["boxes"] as Dictionary
	for state: String in STATES:
		button.add_theme_stylebox_override(state, boxes[state] as StyleBox)
	MenuStyleFactory.apply_ink(button, look["ink"] as Color)
	button.add_theme_font_size_override("font_size", look["font_size"] as int)


## The shared look {boxes, ink, font_size} of a block of [param variant_value]; [param icon_only]
## zeroes the side margins (UiIconButton's square block). Rebuilt only when the token resource
## instance changes, its `changed` fires or [method invalidate_style_cache] ran.
static func shared_look(variant_value: Look, small_block: bool, icon_only: bool = false) -> Dictionary:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	if _looks_tuning != arcade:
		invalidate_style_cache()
		_looks_tuning = arcade
		if not arcade.changed.is_connected(invalidate_style_cache):
			arcade.changed.connect(invalidate_style_cache)
	var key: int = int(variant_value) * LOOK_KEY_STRIDE + (LOOK_SMALL_BIT if small_block else 0) + (LOOK_ICON_BIT if icon_only else 0)
	if _looks.has(key):
		return _looks[key] as Dictionary
	var look: Dictionary = _build_look(variant_value, small_block, icon_only, arcade)
	_looks[key] = look
	return look


## Drops the shared blocks so the next button (re)styles from the current tokens (tests, tooling).
static func invalidate_style_cache() -> void:
	_looks = {}
	_looks_tuning = null


static func _build_look(variant_value: Look, small_block: bool, icon_only: bool, arcade: ArcadeVisualTuning) -> Dictionary:
	var scratch: Button = Button.new()
	var face: Color = face_for(variant_value, arcade)
	MenuStyleFactory.apply_block(scratch, face, MenuStyleFactory.ink_for_face(face), small_block)
	if variant_value == Look.SECONDARY or variant_value == Look.DANGER:
		_show_pressed_face(scratch, face, small_block, arcade)
	if small_block:
		fit_row_height(scratch, arcade)
	var boxes: Dictionary = {}
	for state: String in STATES:
		var box: StyleBox = scratch.get_theme_stylebox(state)
		if icon_only:
			box.content_margin_left = 0.0
			box.content_margin_right = 0.0
		boxes[state] = box
	scratch.free()
	return {
		"boxes": boxes,
		"ink": arcade.alert_color if variant_value == Look.DANGER else MenuStyleFactory.ink_for_face(face),
		"font_size": arcade.font_size_button_sm_px if small_block else arcade.font_size_button_px,
	}


## A pressed block's face is its lip colour (BlockStyleBox), and a disc face's lip is nearly the
## panel colour, so a pressed SECONDARY / ICON block vanished into the plate (C1a gallery note).
## Neutral faces stay their own colour when pressed (the block still drops onto its ledge and the
## top / lip go shallow), so the pressed button is visibly there.
static func _show_pressed_face(button: Button, face: Color, small_block: bool, arcade: ArcadeVisualTuning) -> void:
	for state: String in ["pressed", "hover_pressed"]:
		var shown: Color = face if state == "pressed" else face.lerp(Color.WHITE, arcade.block_hover_light_mix)
		button.add_theme_stylebox_override(state, BlockStyleBox.make(shown, arcade, small_block, BlockStyleBox.STATE_PRESSED, shown, MenuStyleFactory.top_for(shown)))


## Removes the standard vertical padding of the five block states so top + lip + drop + label fit
## ComponentMetrics.row_height_px (the ledge counts as part of the row height).
static func fit_row_height(button: Button, arcade: ArcadeVisualTuning) -> void:
	for state: String in STATES:
		var box: StyleBox = button.get_theme_stylebox(state)
		if box != null:
			box.content_margin_top = maxf(box.content_margin_top - float(arcade.button_sm_pad_y_px), 0.0)
			box.content_margin_bottom = maxf(box.content_margin_bottom - float(arcade.button_sm_pad_y_px), 0.0)


func _restyle() -> void:
	style(self, variant, small)
	if hint_action != &"":
		UiButtonHint.attach(self, hint_action)  # the restyle replaced the boxes that held the glyph's room
	if small:
		UiRowItem.apply(self, UiRowItem.Kind.BUTTON_SM)
	else:
		remove_from_group(UiRowItem.GROUP)
		custom_minimum_size = Vector2.ZERO
		size_flags_vertical = Control.SIZE_FILL
		size_flags_horizontal = Control.SIZE_FILL
