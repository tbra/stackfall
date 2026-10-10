class_name UiBlockButton
extends Button
## The design system's BlockButton (docs/ui_reskin/components.md): a coloured face, a lit top, a
## dark lip and a solid ledge, drawn by ui/theme/BlockStyleBox.gd from ArcadeVisualTuning. Screens
## pick a semantic [enum Look] and `small`; they never pass colours. A small button is a
## UiRowItem (BUTTON_SM): its face, lip and ledge fit inside ComponentMetrics.row_height_px so it
## is exactly as tall as every other item of its row. A full-size button keeps the standard
## padding and is not a row item.

enum Look { PRIMARY, SECONDARY, MINT, RIM }

const STATES: PackedStringArray = ["normal", "hover", "pressed", "hover_pressed", "disabled"]

@export var variant: Look = Look.SECONDARY:
	set(value):
		variant = value
		_restyle()
@export var small: bool = true:
	set(value):
		small = value
		_restyle()
## The Input Map action whose key / pad glyph trails the label. TODO(C1b+): draw the trailing
## hint through InputGlyph; today it is only stored so consumers compile against the final API.
var hint_action: StringName = &""


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
## row-item contract's vertical fit (see [method fit_row_height]).
static func style(button: Button, variant_value: Look, small_block: bool = true) -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var face: Color = face_for(variant_value, arcade)
	MenuStyleFactory.apply_block(button, face, MenuStyleFactory.ink_for_face(face), small_block)
	var font_px: int = arcade.font_size_button_sm_px if small_block else arcade.font_size_button_px
	button.add_theme_font_size_override("font_size", font_px)
	if small_block:
		fit_row_height(button, arcade)


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
	if small:
		UiRowItem.apply(self, UiRowItem.Kind.BUTTON_SM)
	else:
		remove_from_group(UiRowItem.GROUP)
		custom_minimum_size = Vector2.ZERO
		size_flags_vertical = Control.SIZE_FILL
		size_flags_horizontal = Control.SIZE_FILL
