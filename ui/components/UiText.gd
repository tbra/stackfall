class_name UiText
extends Label
## The design system's text roles: a Label whose font, size, colour and outline come from the tokens, so a screen sets a [member role] instead of calling
## add_theme_*_override. TITLE is the Bungee display line, HEADING the 24px heavy uppercase panel
## heading, BODY the 16px sentence-case description, CAPTION the 13px dust hint, VALUE a Bungee
## readout. [member tint] overrides the role colour (any token colour). Sizes: ArcadeVisualTuning font_size_* and
## ComponentMetrics.text_*; colours: ArcadeVisualTuning; fonts: the shared Theme's variations.

enum Role { TITLE, HEADING, BODY, CAPTION, VALUE, LABEL }

## Theme type variation (the font) per role; BODY uses the plain Label font.
const FONT_VARIATIONS: Dictionary = {
	Role.TITLE: &"DisplayLabel", Role.HEADING: &"TitleLabel", Role.BODY: &"",
	Role.CAPTION: &"CaptionLabel", Role.VALUE: &"DisplayLabel", Role.LABEL: &"FieldLabel",
}

@export var role: Role = Role.BODY:
	set(value):
		role = value
		_apply()
## Colour override (a token colour); TRANSPARENT (alpha 0) keeps the role's own colour.
@export var tint: Color = Color.TRANSPARENT:
	set(value):
		tint = value
		_apply()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply()


## Builds a label in [param text_role] showing [param content], optionally tinted.
static func make(text_role: Role, content: String = "", ink: Color = Color.TRANSPARENT) -> UiText:
	var label: UiText = UiText.new()
	label.role = text_role
	label.text = content.to_upper() if text_role == Role.LABEL else content
	label.tint = ink
	return label


## Tints the text with whichever of ink / cream reads better on [param face] (text on a block).
func set_face(face: Color) -> void:
	tint = MenuStyleFactory.ink_for_face(face)


## The role's font size in px.
static func size_for(text_role: Role) -> int:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	match text_role:
		Role.TITLE:
			return arcade.font_size_score_px
		Role.HEADING:
			return arcade.font_size_heading_px
		Role.CAPTION, Role.LABEL:
			return arcade.font_size_caption_px
		Role.VALUE:
			return UiRowItem.metrics().text_value_font_px
	return arcade.font_size_body_px


## The role's own colour (before [member tint]).
static func color_for(text_role: Role) -> Color:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	match text_role:
		Role.BODY, Role.LABEL:
			return arcade.sand_color
		Role.CAPTION:
			return arcade.dust_color
	return arcade.cream_color


## The role's font (the shared Theme's font of its variation).
static func font_for(text_role: Role) -> Font:
	var theme: Theme = load("res://ui/theme/stackfall_theme.tres") as Theme
	var variation: StringName = FONT_VARIATIONS[text_role] as StringName
	return theme.get_font(&"font", variation if variation != &"" else &"Label")


func _apply() -> void:
	add_theme_font_override("font", font_for(role))
	add_theme_font_size_override("font_size", size_for(role))
	add_theme_color_override("font_color", tint if tint.a > 0.0 else color_for(role))
	add_theme_constant_override("outline_size", UiRowItem.metrics().text_outline_px)
