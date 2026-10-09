class_name MenuStyleFactory
## M7 P7 (docs/M7_PLAN.md "P7 -- Main menu / lobby reskin", Bontago-xtq.32):
## builds the varied pastel pill buttons, sunken "well" panels and offset
## shadow cards mockups 10/11 (docs/art_mockups/10-main-menu-layered-pastel.png,
## 11-lobby-layered-pastel.png) show, entirely from StyleBoxFlat -- no image
## assets (hard constraint in the brief). Every color/size it draws from comes
## from config/MenuVisualTuning.gd (CLAUDE.md "No magic numbers"); this file
## only assembles StyleBoxFlat objects, it owns no tunables of its own.
##
## ui/theme/stackfall_theme.tres already gives every Button/LineEdit/OptionButton
## a shared coral/cream base style and a dark-outline focus ring; this factory
## adds *per-instance* theme_override_styles on top of that shared Theme so
## individual buttons can be coral, cream, mint, powder-blue or dark-slate
## (a Theme resource cannot vary style per node of the same control type).
extends RefCounted

## Bontago-1pi.37: the Button theme items apply_ink() paints, one per
## non-disabled draw state (the engine names the plain font state "font_color"
## but the plain icon state "icon_normal_color").
const BUTTON_FONT_COLOR_ITEMS: PackedStringArray = [
	"font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color",
]
const BUTTON_ICON_COLOR_ITEMS: PackedStringArray = [
	"icon_normal_color", "icon_focus_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color",
]


## Paints [param button] as a pastel pill in [param normal_color], with
## [param hover_color] on hover/pressed and [param font_color] as its label
## color. The shared Theme's dark-outline focus StyleBox is left untouched
## (gamepad focus must keep looking the same on every pill).
##
## Bontago-1pi.37: [param font_color] is the pill's one "ink" -- the label AND
## the button's icon take it in every draw state (see apply_ink()), so a white
## SVG glyph can no longer fall back to the theme's default white in the
## focus/pressed states while the label is dark (the owner's "black icons turn
## white on the focused button" report).
static func apply_pill(button: Button, normal_color: Color, hover_color: Color, font_color: Color, tuning: MenuVisualTuning) -> void:
	button.add_theme_stylebox_override("normal", _pill_box(normal_color, tuning))
	button.add_theme_stylebox_override("hover", _pill_box(hover_color, tuning))
	button.add_theme_stylebox_override("pressed", _pill_box(hover_color.darkened(tuning.pill_pressed_darken_amount), tuning))
	apply_ink(button, font_color)


## Bontago-1pi.37: the single place a Button's label and icon colours are set.
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


## Bontago-1pi.37: WCAG relative luminance of an sRGB [param color]
## (0.0 black .. 1.0 white); alpha is ignored.
static func relative_luminance(color: Color) -> float:
	return 0.2126 * _linear_channel(color.r) + 0.7152 * _linear_channel(color.g) + 0.0722 * _linear_channel(color.b)


## Bontago-1pi.37: WCAG contrast ratio of two colours, symmetric, 1.0 (same
## colour) .. 21.0 (black on white). tests/unit/test_menu_icons.gd asserts
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


## A sunken input/list "well": inset border, no drop shadow, used for the
## LAN games list, the Steam lobby list and the direct-IP field (gap item 5).
static func make_well(tuning: MenuVisualTuning) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = tuning.well_color
	box.border_color = tuning.well_border_color
	box.set_border_width_all(int(tuning.well_border_width_px))
	box.set_corner_radius_all(int(tuning.well_corner_radius_px))
	box.set_content_margin_all(tuning.well_content_margin_px)
	return box


## Bontago-mp0.3.5 (polish pass, problem 2): a sunken, fully rounded pill --
## same inset-border/no-shadow "well" language as make_well(), but with the
## pill corner radius instead of the well's own smaller one, for mockup 11's
## single "[label] (-) value (+)" stepper pill.
static func make_well_pill(tuning: MenuVisualTuning) -> StyleBoxFlat:
	var box: StyleBoxFlat = make_well(tuning)
	box.set_corner_radius_all(int(tuning.pill_corner_radius_px))
	return box


## Bontago-mp0.3.5 (polish pass, problem 2): a borderless "-"/"+" glyph
## button for inside a stepper pill -- no background of its own in any state
## (the pill it sits in already draws one), just the ink-colored glyph, so it
## doesn't read as a second nested button.
static func apply_flat_stepper_button(button: Button, tuning: MenuVisualTuning) -> void:
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	empty.content_margin_left = 4.0
	empty.content_margin_right = 4.0
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", empty)
	button.add_theme_stylebox_override("pressed", empty)
	button.add_theme_stylebox_override("disabled", empty)
	# Bontago-1pi.37: apply_ink() also covers the focus state, which the theme's
	# pale default font_focus_color left near-invisible on this cream pill.
	apply_ink(button, tuning.ink_color)
	button.add_theme_color_override("font_disabled_color", tuning.label_muted_color)


## Bontago-mp0.3.5 (review r1, item 5): a borderless white list panel for a
## server/lobby row list that already sits inside its own make_well() card
## (ui/MainMenu.tscn's %LanGamesWell) -- avoids stacking two sunken borders.
static func make_flat_list(tuning: MenuVisualTuning) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = tuning.pill_cream_hover_color
	box.set_corner_radius_all(int(tuning.well_corner_radius_px) - 4)
	box.set_content_margin_all(tuning.well_content_margin_px)
	return box


## One card in the offset triple-card stack (gap item 2): a flat pastel
## rectangle with a soft shadow, used for the two "peeking out" shadow cards
## and (in cream) the front panel itself.
static func make_card(color: Color, tuning: MenuVisualTuning) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(tuning.card_corner_radius_px))
	box.shadow_color = Color(0.0, 0.0, 0.0, tuning.card_shadow_base_alpha * tuning.card_shadow_alpha)
	box.shadow_size = int(tuning.card_shadow_size_px)
	box.shadow_offset = Vector2(tuning.card_offset_px * 0.5, tuning.card_offset_px)
	box.border_color = color.lightened(0.35)
	box.border_width_top = 2
	box.content_margin_left = tuning.card_content_margin_px
	box.content_margin_top = tuning.card_content_margin_px
	box.content_margin_right = tuning.card_content_margin_px
	box.content_margin_bottom = tuning.card_content_margin_px
	return box


## A static (no hover state) pill background for a badge-style Label/
## PanelContainer, e.g. the Lobby header's "Hosting * LAN" status badge
## (Bontago-xtq.32 redo, mockup 11's top-right badge). Same StyleBoxFlat as
## a button pill's "normal" state, just without apply_pill()'s hover/pressed
## variants -- a badge never receives input focus or a press.
static func make_badge(color: Color, tuning: MenuVisualTuning) -> StyleBoxFlat:
	return _pill_box(color, tuning)


## Paints a small toggle chip (Bontago-xtq.32 redo: compact specials/advanced-
## rules toggles replacing the round-1 full-width red bars). [param toggle]
## is any Button with toggle_mode = true (CheckBox and CheckButton both
## qualify). Off state uses [param off_color]/[param off_hover_color]; the
## checked/pressed draw states (BaseButton.DRAW_PRESSED,
## DRAW_HOVER_PRESSED) use [param on_color]/[param on_hover_color] so a
## checked chip reads as a distinct pastel pill rather than Button's default
## coral. Reuses _pill_box's sizing so chips match every other pill on this
## screen; introduces no new MenuVisualTuning tunables.
static func apply_toggle_chip(toggle: Button, off_color: Color, off_hover_color: Color, on_color: Color, on_hover_color: Color, font_color: Color, tuning: MenuVisualTuning) -> void:
	toggle.add_theme_stylebox_override("normal", _pill_box(off_color, tuning))
	toggle.add_theme_stylebox_override("hover", _pill_box(off_hover_color, tuning))
	toggle.add_theme_stylebox_override("pressed", _pill_box(on_color, tuning))
	toggle.add_theme_stylebox_override("hover_pressed", _pill_box(on_hover_color, tuning))
	apply_ink(toggle, font_color)


## Cached 1x1 fully-transparent texture shared by every hide_spinbox_arrows()
## call -- built once, not per SpinBox.
static var _blank_icon: ImageTexture = null


## Bontago-mp0.3.5 (review r3, problem 3): SpinBox's own "buttons_width" theme
## constant only changes the *reserved layout width* for its native up/down
## spinner, not whether the chevron icons themselves still draw (confirmed
## by a windowed capture: the chevrons still rendered, just squeezed against
## the LineEdit's right edge) -- the icons are theme items in their own
## right (ThemeDB.get_default_theme().get_icon_list("SpinBox") ==
## ["updown","up","up_hover","up_pressed","up_disabled","down","down_hover",
## "down_pressed","down_disabled"]), so this overrides every one of them with
## a blank 1x1 transparent texture. [param spin] keeps its normal min/max/
## step/value/value_changed and LineEdit -- only its own native buttons
## become invisible; mockup 11's round pill "-"/"+" buttons
## (_add_stepper_buttons()) are the only visible way to nudge it now.
static func hide_spinbox_arrows(spin: SpinBox) -> void:
	if _blank_icon == null:
		var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.0, 0.0, 0.0, 0.0))
		_blank_icon = ImageTexture.create_from_image(image)
	for icon_name: String in [
		"updown", "up", "up_hover", "up_pressed", "up_disabled",
		"down", "down_hover", "down_pressed", "down_disabled",
	]:
		spin.add_theme_icon_override(icon_name, _blank_icon)
	spin.add_theme_constant_override("buttons_width", 0)
	spin.add_theme_constant_override("field_and_buttons_separation", 0)


static func _pill_box(color: Color, tuning: MenuVisualTuning) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(tuning.pill_corner_radius_px))
	box.shadow_color = color.darkened(0.24)
	box.shadow_size = 2
	box.shadow_offset = Vector2(0.0, 4.0)
	box.border_color = color.lightened(0.35)
	box.border_width_top = 2
	box.content_margin_left = tuning.pill_margin_x_px
	box.content_margin_right = tuning.pill_margin_x_px
	box.content_margin_top = tuning.pill_margin_y_px
	box.content_margin_bottom = tuning.pill_margin_y_px
	return box
