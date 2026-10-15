class_name MenuStyleFactory
## M7 P7 (docs/M7_PLAN.md "P7 -- Main menu / lobby reskin"):
## builds the varied pastel pill buttons, sunken "well" panels and offset
## shadow cards mockups 10/11 (docs/art_mockups/10-main-menu-layered-pastel.png,
## 11-lobby-layered-pastel.png) show, entirely from StyleBoxFlat -- no image
## assets (hard constraint in the brief). Every color/size it draws from comes
## from config/ui/MenuVisualTuning.gd (CLAUDE.md "No magic numbers"); this file
## only assembles StyleBoxFlat objects, it owns no tunables of its own.
##
## ui/theme/stackfall_theme.tres already gives every Button/LineEdit/OptionButton
## a shared coral/cream base style and a dark-outline focus ring; this factory
## adds *per-instance* theme_override_styles on top of that shared Theme so
## individual buttons can be coral, cream, mint, powder-blue or dark-slate
## (a Theme resource cannot vary style per node of the same control type).
extends RefCounted

## the Button theme items apply_ink() paints, one per
## non-disabled draw state (the engine names the plain font state "font_color"
## but the plain icon state "icon_normal_color").
const BUTTON_FONT_COLOR_ITEMS: PackedStringArray = [
	"font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color",
]
const BUTTON_ICON_COLOR_ITEMS: PackedStringArray = [
	"icon_normal_color", "icon_focus_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color",
]


## Paints [param button] as a Stackfall Arcade block (docs/UI_RESKIN_PLAN.md P0):
## face [param face], a lit top, a dark lip and a solid ledge, drawn by ui/theme/BlockStyleBox.gd,
## with [param ink] as the label and icon colour in every draw state. The lip and top of the
## design's named faces (flare, rim, mint) come from the token table instead of a derived mix.
## [param small] selects the compact recipe (lip-sm/drop-sm, button-sm padding). Hover lightens
## the face, pressed drops it onto the ledge, disabled is translucent without a ledge. The shared
## Theme's 3 px cream focus outline is left untouched.
static func apply_block(button: Button, face: Color, ink: Color, small: bool = false) -> void:
	apply_block_states(button, face, _hover_face(face), ink, small)


## apply_block() with an explicit hover face.
static func apply_block_states(button: Button, face: Color, hover_face: Color, ink: Color, small: bool = false) -> void:
	var arcade: ArcadeVisualTuning = arcade_tuning()
	var lip: Color = lip_for(face)
	var top: Color = top_for(face)
	button.add_theme_stylebox_override("normal", BlockStyleBox.make(face, arcade, small, BlockStyleBox.STATE_NORMAL, lip, top))
	button.add_theme_stylebox_override("hover", BlockStyleBox.make(hover_face, arcade, small, BlockStyleBox.STATE_NORMAL, lip, top))
	button.add_theme_stylebox_override("pressed", BlockStyleBox.make(face, arcade, small, BlockStyleBox.STATE_PRESSED, lip, top))
	button.add_theme_stylebox_override("hover_pressed", BlockStyleBox.make(face, arcade, small, BlockStyleBox.STATE_PRESSED, lip, top))
	button.add_theme_stylebox_override("disabled", BlockStyleBox.make(face, arcade, small, BlockStyleBox.STATE_DISABLED, lip, top))
	apply_ink(button, ink)


## A panel plate in the arena-disc look: [param face] (default disc-800), radius-panel, panel
## padding and the solid disc-950 drop. Cards, dialogs and menu columns use this.
static func make_plate(face: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var arcade: ArcadeVisualTuning = arcade_tuning()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = face if face.a > 0.0 else arcade.disc_800_color
	box.set_corner_radius_all(arcade.radius_panel_px)
	box.shadow_color = arcade.disc_950_color
	box.shadow_size = 1
	box.shadow_offset = Vector2(0.0, float(arcade.panel_drop_px))
	box.set_content_margin_all(float(arcade.space_5_px))
	return box


## The lazily loaded shared design tokens (config/ui/arcade_visual_tuning.tres).
static var _arcade_tuning: ArcadeVisualTuning = null


static func arcade_tuning() -> ArcadeVisualTuning:
	if _arcade_tuning == null:
		_arcade_tuning = load("res://config/ui/arcade_visual_tuning.tres") as ArcadeVisualTuning
	return _arcade_tuning


## The label ink for text/icons on [param face]: the better-contrasting of ink (disc-900) and
## cream, so bright faces (flare, rim, mint, players) get ink and disc faces get cream.
static func ink_for_face(face: Color) -> Color:
	var arcade: ArcadeVisualTuning = arcade_tuning()
	if contrast_ratio(arcade.ink_color, face) >= contrast_ratio(arcade.cream_color, face):
		return arcade.ink_color
	return arcade.cream_color


## The design's named lip colour for [param face] (flare-lip, rim-lip, mint-lip), or the derived
## darkened mix for any other face.
static func lip_for(face: Color) -> Color:
	var arcade: ArcadeVisualTuning = arcade_tuning()
	if face.is_equal_approx(arcade.flare_color):
		return arcade.flare_lip_color
	if face.is_equal_approx(arcade.rim_color):
		return arcade.rim_lip_color
	if face.is_equal_approx(arcade.mint_color):
		return arcade.mint_lip_color
	return face.lerp(Color.BLACK, arcade.block_lip_dark_mix)


## The design's named lit-top colour for [param face] (flare-top) or the derived lightened mix.
static func top_for(face: Color) -> Color:
	var arcade: ArcadeVisualTuning = arcade_tuning()
	if face.is_equal_approx(arcade.flare_color):
		return arcade.flare_top_color
	return face.lerp(Color.WHITE, arcade.block_top_light_mix)


static func _hover_face(face: Color) -> Color:
	return face.lerp(Color.WHITE, arcade_tuning().block_hover_light_mix)


## the single place a Button's label and icon colours are set.
## Every non-disabled draw state (normal, focus, hover, pressed, hover_pressed)
## gets [param ink] for both the font_*color and icon_*_color theme items:
## icons are white-source SVGs (assets/ui/icons/*.svg, tinted by
## BaseButton's icon_*_color, which multiplies the texture), so the icon takes
## exactly the caption colour and keeps it while focused or pressed. The
## disabled state keeps the shared Theme's own muted font/icon colours.
static func apply_ink(button: Button, ink: Color) -> void:
	for item: String in BUTTON_FONT_COLOR_ITEMS:
		button.add_theme_color_override(item, ink)
	for item: String in BUTTON_ICON_COLOR_ITEMS:
		button.add_theme_color_override(item, ink)


## WCAG relative luminance of an sRGB [param color]
## (0.0 black .. 1.0 white); alpha is ignored.
static func relative_luminance(color: Color) -> float:
	return 0.2126 * _linear_channel(color.r) + 0.7152 * _linear_channel(color.g) + 0.0722 * _linear_channel(color.b)


## WCAG contrast ratio of two colours, symmetric, 1.0 (same
## colour) .. 21.0 (black on white). tests/unit/ui/test_menu_icons.gd asserts
## every menu icon stays above MenuVisualTuning.icon_min_contrast_ratio.
static func contrast_ratio(a: Color, b: Color) -> float:
	var luminance_a: float = relative_luminance(a)
	var luminance_b: float = relative_luminance(b)
	return (maxf(luminance_a, luminance_b) + CONTRAST_FLARE) / (minf(luminance_a, luminance_b) + CONTRAST_FLARE)


## The sRGB piecewise transfer constants and the WCAG contrast flare term.
const SRGB_LINEAR_CUTOFF: float = 0.03928
const SRGB_LINEAR_DIVISOR: float = 12.92
const SRGB_GAMMA_OFFSET: float = 0.055
const SRGB_GAMMA_SCALE: float = 1.055
const SRGB_GAMMA_EXPONENT: float = 2.4
const CONTRAST_FLARE: float = 0.05


static func _linear_channel(channel: float) -> float:
	if channel <= SRGB_LINEAR_CUTOFF:
		return channel / SRGB_LINEAR_DIVISOR
	return pow((channel + SRGB_GAMMA_OFFSET) / SRGB_GAMMA_SCALE, SRGB_GAMMA_EXPONENT)


## review r1, item 5: a borderless white list panel for a
## server/lobby row list that already sits inside its own well card
## (ui/menus/MainMenu.tscn's %LanGamesWell) -- avoids stacking two sunken borders.
static func make_flat_list(tuning: MenuVisualTuning) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = arcade_tuning().disc_700_color
	box.set_corner_radius_all(arcade_tuning().radius_block_px)
	box.set_content_margin_all(tuning.well_content_margin_px)
	return box


## Paints a toggle chip (any Button with toggle_mode = true). Off uses [param off_color] (disc
## face, cream label), on uses [param on_color] (a bright face, ink label); the label/icon ink of
## each state is chosen per face by ink_for_face(), [param font_color] is kept for old callers.
static func apply_toggle_chip(toggle: Button, off_color: Color, off_hover_color: Color, on_color: Color, on_hover_color: Color, font_color: Color, tuning: MenuVisualTuning) -> void:
	var arcade: ArcadeVisualTuning = arcade_tuning()
	toggle.add_theme_stylebox_override("normal", BlockStyleBox.make(off_color, arcade, true, BlockStyleBox.STATE_NORMAL, lip_for(off_color), top_for(off_color)))
	toggle.add_theme_stylebox_override("hover", BlockStyleBox.make(off_hover_color, arcade, true, BlockStyleBox.STATE_NORMAL, lip_for(off_color), top_for(off_color)))
	toggle.add_theme_stylebox_override("pressed", BlockStyleBox.make(on_color, arcade, true, BlockStyleBox.STATE_NORMAL, lip_for(on_color), top_for(on_color)))
	toggle.add_theme_stylebox_override("hover_pressed", BlockStyleBox.make(on_hover_color, arcade, true, BlockStyleBox.STATE_NORMAL, lip_for(on_color), top_for(on_color)))
	var off_ink: Color = ink_for_face(off_color)
	var on_ink: Color = ink_for_face(on_color)
	for item: String in ["font_color", "font_focus_color", "font_hover_color"]:
		toggle.add_theme_color_override(item, off_ink)
	for item: String in ["font_pressed_color", "font_hover_pressed_color"]:
		toggle.add_theme_color_override(item, on_ink)
	for item: String in ["icon_normal_color", "icon_focus_color", "icon_hover_color"]:
		toggle.add_theme_color_override(item, off_ink)
	for item: String in ["icon_pressed_color", "icon_hover_pressed_color"]:
		toggle.add_theme_color_override(item, on_ink)

