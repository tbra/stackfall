class_name UiIconButton
extends Button
## A small secondary block holding one icon (the kick / remove X, docs/UI_COMPONENTS_PLAN.md
## section 3.2). A square UiRowItem (ICON): exactly row_height wide and tall, so it never reads
## smaller than the other items of its row. DANGER paints the glyph in `alert` (flare) on a
## disc-600 face; SECONDARY uses the ink the face asks for. The tooltip is the Button's own.

enum Tone { SECONDARY, DANGER }

## The glyph shown when no icon texture is set (the design's flare X).
const DEFAULT_GLYPH: int = 0x2715

@export var tone: Tone = Tone.SECONDARY:
	set(value):
		tone = value
		_restyle()


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	expand_icon = true
	text = char(DEFAULT_GLYPH)
	_restyle()


## Shows [param texture] instead of the default glyph.
func set_icon_texture(texture: Texture2D) -> void:
	icon = texture
	text = "" if texture != null else char(DEFAULT_GLYPH)


func _restyle() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	UiBlockButton.style(self, UiBlockButton.Look.SECONDARY, true)
	if tone == Tone.DANGER:
		MenuStyleFactory.apply_ink(self, arcade.alert_color)
	for state: String in UiBlockButton.STATES:
		var box: StyleBox = get_theme_stylebox(state)
		if box != null:
			box.content_margin_left = 0.0
			box.content_margin_right = 0.0
	add_theme_constant_override("icon_max_width", arcade.icon_max_width_px)
	add_theme_font_size_override("font_size", UiRowItem.metrics().icon_glyph_font_px)
	UiRowItem.apply(self, UiRowItem.Kind.ICON)
