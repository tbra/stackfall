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


## Paints [param button] as a pastel pill in [param normal_color], with
## [param hover_color] on hover/pressed and [param font_color] as its label
## color. The shared Theme's dark-outline focus StyleBox is left untouched
## (gamepad focus must keep looking the same on every pill).
static func apply_pill(button: Button, normal_color: Color, hover_color: Color, font_color: Color, tuning: MenuVisualTuning) -> void:
	button.add_theme_stylebox_override("normal", _pill_box(normal_color, tuning))
	button.add_theme_stylebox_override("hover", _pill_box(hover_color, tuning))
	button.add_theme_stylebox_override("pressed", _pill_box(hover_color.darkened(0.12), tuning))
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color)
	button.add_theme_color_override("font_pressed_color", font_color)


## A sunken input/list "well": inset border, no drop shadow, used for the
## LAN games list, the Steam lobby list and the direct-IP field (gap item 5).
static func make_well(tuning: MenuVisualTuning) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = tuning.well_color
	box.border_color = tuning.well_border_color
	box.set_border_width_all(2)
	box.set_corner_radius_all(int(tuning.well_corner_radius_px))
	box.set_content_margin_all(8.0)
	return box


## One card in the offset triple-card stack (gap item 2): a flat pastel
## rectangle with a soft shadow, used for the two "peeking out" shadow cards
## and (in cream) the front panel itself.
static func make_card(color: Color, tuning: MenuVisualTuning) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(tuning.card_corner_radius_px))
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.12 * tuning.card_shadow_alpha)
	box.shadow_size = 6
	box.content_margin_left = 20.0
	box.content_margin_top = 20.0
	box.content_margin_right = 20.0
	box.content_margin_bottom = 20.0
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
	toggle.add_theme_color_override("font_color", font_color)
	toggle.add_theme_color_override("font_hover_color", font_color)
	toggle.add_theme_color_override("font_pressed_color", font_color)
	toggle.add_theme_color_override("font_hover_pressed_color", font_color)


static func _pill_box(color: Color, tuning: MenuVisualTuning) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(tuning.pill_corner_radius_px))
	box.content_margin_left = tuning.pill_margin_x_px
	box.content_margin_right = tuning.pill_margin_x_px
	box.content_margin_top = tuning.pill_margin_y_px
	box.content_margin_bottom = tuning.pill_margin_y_px
	return box
