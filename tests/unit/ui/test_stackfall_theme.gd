extends GutTest
## UI reskin P0b: ui/theme/stackfall_theme.tres is the Stackfall Arcade theme.

const THEME_PATH: String = "res://ui/theme/stackfall_theme.tres"

var _theme: Theme = null
var _arcade: ArcadeVisualTuning = null


func before_each() -> void:
	_theme = load(THEME_PATH) as Theme
	_arcade = load("res://config/ui/arcade_visual_tuning.tres") as ArcadeVisualTuning


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
