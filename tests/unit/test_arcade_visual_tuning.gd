extends GutTest
## Bontago-hfa.2 (UI reskin P0a): config/arcade_visual_tuning.tres mirrors every token of
## docs/ui_reskin/tokens.json, the documented text/face contrast ratios hold, and the font and
## marker assets the design system ships are present.

const TOKENS_PATH: String = "res://docs/ui_reskin/tokens.json"
const TUNING_PATH: String = "res://config/arcade_visual_tuning.tres"
## Documented ratios have one decimal; allow that much rounding.
const RATIO_SLACK: float = 0.1
const PLAYER_SLOTS: int = 8
## The tokens are 8-bit hex; MatchConfig stores the unrounded floats.
const CHANNEL_SLACK: float = 0.005

var _tuning: ArcadeVisualTuning = null
var _tokens: Dictionary = {}


func before_each() -> void:
	_tuning = load(TUNING_PATH) as ArcadeVisualTuning
	_tokens = JSON.parse_string(FileAccess.get_file_as_string(TOKENS_PATH)) as Dictionary


func _token_color(token_name: String) -> Color:
	var by_name: Dictionary = {}
	for entry: Dictionary in (_tokens["color"] as Dictionary)["tokens"]:
		by_name[String(entry["name"])] = String(entry["value"])
	var value: String = String(by_name[token_name])
	while value.begins_with("{"):
		value = String(by_name[value.trim_prefix("{").trim_suffix("}")])
	return Color(value)


func _ratio(text: Color, face: Color) -> float:
	return MenuStyleFactory.contrast_ratio(text, face)


func test_resource_loads_with_script() -> void:
	assert_not_null(_tuning, "arcade_visual_tuning.tres loads as ArcadeVisualTuning")


func test_every_colour_token_is_exported_with_the_documented_value() -> void:
	var checked: int = 0
	for entry: Dictionary in (_tokens["color"] as Dictionary)["tokens"]:
		var token_name: String = String(entry["name"])
		var property: String = token_name.replace("-", "_") + "_color"
		assert_true(property in _tuning, "%s is exported as %s" % [token_name, property])
		assert_true((_tuning.get(property) as Color).is_equal_approx(_token_color(token_name)), "%s value" % token_name)
		checked += 1
	assert_gt(checked, PLAYER_SLOTS, "fixture: colour tokens were read")


func test_every_px_token_is_exported_with_the_documented_value() -> void:
	var checked: int = 0
	var groups: Array[Dictionary] = [
		{"section": "spacing", "suffix": "_px"}, {"section": "radius", "suffix": "_px"}, {"section": "depth", "suffix": "_px"},
	]
	for group: Dictionary in groups:
		for entry: Dictionary in (_tokens[String(group["section"])] as Dictionary)["tokens"]:
			var property: String = String(entry["name"]).replace("-", "_") + String(group["suffix"])
			assert_true(property in _tuning, "%s exported" % property)
			assert_eq(int(_tuning.get(property)), int(String(entry["value"]).trim_suffix("px")), property)
			checked += 1
	assert_gt(checked, 10, "fixture: px tokens were read")


func test_opacity_and_font_size_tokens() -> void:
	assert_almost_eq(_tuning.scrim_alpha, 0.88, 0.0001)
	assert_almost_eq(_tuning.hud_plate_alpha, 0.86, 0.0001)
	assert_almost_eq(_tuning.disabled_alpha, 0.45, 0.0001)
	var expected: Dictionary = {
		"countdown": 128, "logo": 44, "score": 40, "timer": 34, "heading": 24,
		"button": 20, "button_sm": 15, "body": 16, "label": 13, "caption": 13,
	}
	for style: String in expected:
		assert_eq(int(_tuning.get("font_size_%s_px" % style)), int(expected[style]), "font size %s" % style)


func test_player_colours_match_match_config() -> void:
	var config: MatchConfig = MatchConfig.new()
	for slot: int in PLAYER_SLOTS:
		var tuned: Color = _tuning.get("player_%d_color" % (slot + 1)) as Color
		assert_true(absf(tuned.r - config.player_colors[slot].r) <= CHANNEL_SLACK and absf(tuned.g - config.player_colors[slot].g) <= CHANNEL_SLACK and absf(tuned.b - config.player_colors[slot].b) <= CHANNEL_SLACK, "player-%d equals MatchConfig.player_colors[%d]" % [slot + 1, slot])


func test_text_on_disc_surfaces_meets_the_documented_ratios() -> void:
	# [text, face, documented ratio] from tokens.json usage notes.
	var cases: Array = [
		[_tuning.cream_color, _tuning.disc_800_color, 15.9], [_tuning.sand_color, _tuning.disc_800_color, 10.7],
		[_tuning.dust_color, _tuning.disc_800_color, 6.4], [_tuning.cream_color, _tuning.disc_700_color, 14.0],
		[_tuning.sand_color, _tuning.disc_700_color, 9.5], [_tuning.dust_color, _tuning.disc_700_color, 5.6],
		[_tuning.cream_color, _tuning.disc_600_color, 11.8], [_tuning.sand_color, _tuning.disc_600_color, 7.9],
		[_tuning.dust_color, _tuning.disc_600_color, 4.7], [_tuning.disc_400_color, _tuning.disc_800_color, 3.0],
	]
	for case: Array in cases:
		assert_gte(_ratio(case[0] as Color, case[1] as Color), float(case[2]) - RATIO_SLACK, "ratio %s on %s" % [case[0], case[1]])


func test_ink_on_every_bright_face_is_at_least_aa() -> void:
	var aa: float = 4.5
	var faces: Dictionary = {
		"flare": _tuning.flare_color, "rim": _tuning.rim_color, "mint": _tuning.mint_color,
	}
	for slot: int in PLAYER_SLOTS:
		faces["player-%d" % (slot + 1)] = _tuning.get("player_%d_color" % (slot + 1))
	for face_name: String in faces:
		assert_gte(_ratio(_tuning.ink_color, faces[face_name] as Color), aa, "ink on %s" % face_name)
	assert_lt(_ratio(_tuning.cream_color, _tuning.flare_color), aa, "cream on flare is the documented failure the ink rule avoids")


func test_ink_for_face_picks_ink_on_bright_and_cream_on_disc() -> void:
	assert_eq(MenuStyleFactory.ink_for_face(_tuning.flare_color), _tuning.ink_color)
	assert_eq(MenuStyleFactory.ink_for_face(_tuning.mint_color), _tuning.ink_color)
	assert_eq(MenuStyleFactory.ink_for_face(_tuning.disc_600_color), _tuning.cream_color)
	assert_eq(MenuStyleFactory.ink_for_face(_tuning.disc_700_color), _tuning.cream_color)


func test_design_assets_are_present() -> void:
	for path: String in [
		"res://assets/ui/fonts/Bungee-Regular.ttf", "res://assets/ui/fonts/Rubik-Variable.ttf",
		"res://assets/ui/fonts/OFL-Bungee.txt", "res://assets/ui/fonts/OFL-Rubik.txt",
		"res://assets/ui/stackfall_mark.svg", "res://assets/ui/stackfall-lockup.svg", "res://assets/ui/stackfall-lockup-on-light.svg",
	]:
		assert_true(ResourceLoader.exists(path) or FileAccess.file_exists(path), path)
	for slot: int in PLAYER_SLOTS:
		var found: int = 0
		for entry: String in DirAccess.get_files_at("res://assets/ui/markers"):
			if entry.begins_with("p%d-" % (slot + 1)) and entry.ends_with(".svg"):
				found += 1
		assert_eq(found, 2, "slot %d has a marker and an assist marker" % (slot + 1))
