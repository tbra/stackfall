extends GutTest
## Bontago-hfa.2 (UI reskin P0b): ui/theme/stackfall_theme.tres is the Stackfall Arcade theme.

const THEME_PATH: String = "res://ui/theme/stackfall_theme.tres"

var _theme: Theme = null
var _arcade: ArcadeVisualTuning = null


func before_each() -> void:
	_theme = load(THEME_PATH) as Theme
	_arcade = load("res://config/arcade_visual_tuning.tres") as ArcadeVisualTuning


func test_theme_loads_with_rubik_body_and_no_manrope() -> void:
	assert_not_null(_theme)
	var font: FontVariation = _theme.default_font as FontVariation
	assert_not_null(font, "default font is a FontVariation")
	assert_true(font.base_font.resource_path.ends_with("Rubik-Variable.ttf"))
	assert_eq(_theme.default_font_size, _arcade.font_size_body_px)
	assert_false(FileAccess.get_file_as_string(THEME_PATH).contains("Manrope"), "Manrope is retired from the theme")


func test_display_label_uses_bungee() -> void:
	var font: FontVariation = _theme.get_font("font", "DisplayLabel") as FontVariation
	assert_true(font.base_font.resource_path.ends_with("Bungee-Regular.ttf"))


func test_button_states_are_blocks() -> void:
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		assert_true(_theme.get_stylebox(state, "Button") is BlockStyleBox, "Button/%s is a BlockStyleBox" % state)
	assert_true((_theme.get_stylebox("pressed", "Button") as BlockStyleBox).pressed)
	assert_true((_theme.get_stylebox("disabled", "Button") as BlockStyleBox).disabled)


func test_focus_is_a_three_px_cream_outline_three_px_outside() -> void:
	var focus: StyleBoxFlat = _theme.get_stylebox("focus", "Button") as StyleBoxFlat
	assert_eq(focus.border_width_left, _arcade.focus_px)
	assert_eq(focus.border_color, _arcade.cream_color)
	assert_eq(focus.expand_margin_left, float(_arcade.focus_offset_px))
	assert_false(focus.draw_center)


func test_text_reads_on_the_disc_surfaces() -> void:
	var pairs: Array = [
		[_theme.get_color("font_color", "Label"), _arcade.disc_800_color],
		[_theme.get_color("font_color", "Button"), (_theme.get_stylebox("normal", "Button") as BlockStyleBox).face_color],
		[_theme.get_color("font_color", "LineEdit"), _arcade.disc_900_color],
		[_theme.get_color("font_color", "OptionButton"), _arcade.disc_700_color],
		[_theme.get_color("font_color", "CaptionLabel"), _arcade.disc_800_color],
	]
	for pair: Array in pairs:
		assert_gte(MenuStyleFactory.contrast_ratio(pair[0] as Color, pair[1] as Color), 4.5, "%s on %s" % [pair[0], pair[1]])


func test_panel_and_field_use_the_arcade_radii() -> void:
	assert_eq((_theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).corner_radius_top_left, _arcade.radius_panel_px)
	assert_eq((_theme.get_stylebox("normal", "LineEdit") as StyleBoxFlat).corner_radius_top_left, _arcade.radius_block_px)


func test_factory_apply_block_make_plate_and_old_names_still_work() -> void:
	var button: Button = Button.new()
	add_child_autofree(button)
	var tuning: MenuVisualTuning = load("res://config/menu_visual_tuning.tres") as MenuVisualTuning
	MenuStyleFactory.apply_pill(button, tuning.pill_coral_color, tuning.pill_coral_hover_color, tuning.ink_color, tuning)
	assert_true(button.get_theme_stylebox("normal") is BlockStyleBox)
	assert_eq(button.get_theme_color("font_color"), _arcade.ink_color, "ink on the flare face, whatever the caller passed")
	var plate: StyleBoxFlat = MenuStyleFactory.make_plate()
	assert_eq(plate.bg_color, _arcade.disc_800_color)
	assert_eq(plate.corner_radius_top_left, _arcade.radius_panel_px)
	assert_not_null(MenuStyleFactory.make_card(tuning.card_cream_color, tuning))
	assert_not_null(MenuStyleFactory.make_badge(tuning.pill_mint_color, tuning))
	assert_not_null(MenuStyleFactory.make_well(tuning))
