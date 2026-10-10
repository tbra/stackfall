class_name UiTab
extends Button
## One tab of a UiTabs bar (docs/ui_reskin/components.md "Tabs"): an uppercase label on a flat
## face. Idle = transparent with a sand label, hover = disc-700, active = disc-600 with a `rim`
## notch (top edge in a HORIZONTAL bar, left edge in a VERTICAL one). The theme's cream focus
## outline stays. Selected by UiTabs through a ButtonGroup, so exactly one tab is active.

## Emitted when ui_left / ui_right (HORIZONTAL) or ui_up / ui_down (VERTICAL) is pressed on the
## focused tab; direction is -1 / +1.
signal step_requested(direction: int)

var id: StringName = &""
var vertical: bool = false:
	set(value):
		vertical = value
		restyle()


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	alignment = HORIZONTAL_ALIGNMENT_LEFT if vertical else HORIZONTAL_ALIGNMENT_CENTER
	restyle()


func setup(tab_id: StringName, label: String, is_vertical: bool) -> UiTab:
	id = tab_id
	text = label.to_upper()
	vertical = is_vertical
	return self


## The face of a tab in [param active] / [param hovered] state (tokens).
static func face_for(active: bool, hovered: bool, arcade: ArcadeVisualTuning = null) -> Color:
	var tokens: ArcadeVisualTuning = arcade if arcade != null else MenuStyleFactory.arcade_tuning()
	if active:
		return tokens.disc_600_color
	if hovered:
		return tokens.disc_700_color
	return Color.TRANSPARENT


func restyle() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var m: ComponentMetrics = UiRowItem.metrics()
	alignment = HORIZONTAL_ALIGNMENT_LEFT if vertical else HORIZONTAL_ALIGNMENT_CENTER
	add_theme_stylebox_override("normal", _box(face_for(false, false, arcade), false, arcade, m))
	add_theme_stylebox_override("hover", _box(face_for(false, true, arcade), false, arcade, m))
	add_theme_stylebox_override("pressed", _box(face_for(true, false, arcade), true, arcade, m))
	add_theme_stylebox_override("hover_pressed", _box(face_for(true, true, arcade), true, arcade, m))
	add_theme_stylebox_override("disabled", _box(Color.TRANSPARENT, false, arcade, m))
	for item: String in ["font_color", "font_focus_color", "font_hover_color"]:
		add_theme_color_override(item, arcade.sand_color)
	add_theme_color_override("font_hover_color", arcade.cream_color)
	for item: String in ["font_pressed_color", "font_hover_pressed_color"]:
		add_theme_color_override(item, arcade.cream_color)
	var dim: Color = arcade.dust_color
	dim.a *= arcade.disabled_alpha
	add_theme_color_override("font_disabled_color", dim)
	add_theme_font_size_override("font_size", arcade.font_size_button_sm_px)
	custom_minimum_size.y = float(m.tab_height_px)


func _box(face: Color, notch: bool, arcade: ArcadeVisualTuning, m: ComponentMetrics) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = face
	box.set_corner_radius_all(arcade.radius_chip_px)
	if notch:
		box.border_color = arcade.rim_color
		if vertical:
			box.border_width_left = m.tab_notch_px
		else:
			box.border_width_top = m.tab_notch_px
	box.content_margin_left = float(arcade.space_4_px)
	box.content_margin_right = float(arcade.space_4_px)
	box.content_margin_top = float(arcade.space_1_px)
	box.content_margin_bottom = float(arcade.space_1_px)
	return box


func _gui_input(event: InputEvent) -> void:
	var back: StringName = &"ui_up" if vertical else &"ui_left"
	var forward: StringName = &"ui_down" if vertical else &"ui_right"
	if event.is_action_pressed(back):
		accept_event()
		step_requested.emit(-1)
	elif event.is_action_pressed(forward):
		accept_event()
		step_requested.emit(1)
