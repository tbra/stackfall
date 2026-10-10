extends GutTest
## Bontago-1pi.37 (owner playtest 2026-10-03: "Some buttons have white icons,
## others have black icons. When navigating with the controller the black
## icons turn white when the button is 'hovered' and the white icons do
## nothing. The ones that turn white are basically invisible if the button is
## also white.").
##
## Root cause: only icon_normal_color/icon_hover_color were overridden per
## node, so the focus and pressed states fell back to the theme's default
## white icon on the (cream/mint/blue) pill. MenuStyleFactory.apply_ink() now
## sets one ink for every draw state, and ui/theme/stackfall_theme.tres gives
## every plain Button the matching defaults.
##
## This file walks the shipped menu scenes (MainMenu, PauseMenu, OptionsMenu)
## and, for every icon Button and every draw state, asserts the icon colour
## contrasts with the stylebox that state is drawn on by at least
## MenuVisualTuning.icon_min_contrast_ratio, that an icon never changes colour
## between states, that it follows its caption ink, and that every icon source
## is white SVG art (so the theme colour is the only thing colouring it).

const MAIN_MENU_SCENE: PackedScene = preload("res://ui/MainMenu.tscn")
const PAUSE_MENU_SCENE: PackedScene = preload("res://ui/PauseMenu.tscn")
const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/OptionsMenu.tscn")
const THEME: Theme = preload("res://ui/theme/stackfall_theme.tres")
const TUNING: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")

## Icon-bearing Buttons counted in the shipped scenes; a lower count means the
## walk silently missed some, so the contrast assertions would be vacuous.
const MAIN_MENU_ICON_BUTTONS: int = 15
const PAUSE_MENU_ICON_BUTTONS: int = 4
const OPTIONS_MENU_MUTE_BUTTONS: int = 4

## [state label, stylebox the state is drawn on, icon colour theme item]. A
## focused (not hovered) Button draws its "normal" stylebox plus the
## transparent focus ring, so focus is measured against "normal".
const STATES: Array = [
	["normal", "normal", "icon_normal_color"],
	["focus", "normal", "icon_focus_color"],
	["hover", "hover", "icon_hover_color"],
	["pressed", "pressed", "icon_pressed_color"],
	["disabled", "disabled", "icon_disabled_color"],
]
const TOGGLE_STATE: Array = ["hover_pressed", "hover_pressed", "icon_hover_pressed_color"]

## SVG paint values a white-source glyph may use.
const WHITE_SVG_PAINTS: PackedStringArray = ["none", "#fff", "#ffffff", "white"]


func _make_main_menu() -> MainMenu:
	var menu: MainMenu = autofree(MAIN_MENU_SCENE.instantiate())
	add_child_autofree(menu)
	menu.net_provider = FakeNet.new()
	return menu


func _make_pause_menu() -> PauseMenu:
	var menu: PauseMenu = autofree(PAUSE_MENU_SCENE.instantiate())
	add_child_autofree(menu)
	return menu


func _make_options_menu() -> OptionsMenu:
	var menu: OptionsMenu = autofree(OPTIONS_MENU_SCENE.instantiate())
	add_child_autofree(menu)
	return menu


## True for a Button drawn in the scene's own window: not inside a popup or
## dialog (OptionsMenu's FileDialog builds engine toolbar Buttons with
## built-in, pathless icons that are not menu art).
func _in_main_window(button: Button) -> bool:
	return button.get_window() == get_tree().root


func _icon_buttons(root: Node) -> Array[Button]:
	var found: Array[Button] = []
	for node: Node in root.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button.icon != null and _in_main_window(button):
			found.append(button)
	return found


## The mute buttons draw their speaker on a child TextureRect (see
## ui/OptionsMenu.gd's _style_mute_button_icon() DECISION), so they are walked
## separately from Button.icon buttons.
func _texture_icon_buttons(root: Node) -> Array[Button]:
	var found: Array[Button] = []
	for node: Node in root.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button.icon == null and button.get_node_or_null("Icon") is TextureRect and _in_main_window(button):
			found.append(button)
	return found


## Background colour of one stylebox as the icon sees it.
func _box_color(box: StyleBox, label: String) -> Color:
	var block: BlockStyleBox = box as BlockStyleBox
	if block != null:
		# Bontago-hfa.2: the Arcade block's face is what the icon sits on (disabled composites on the panel).
		if block.disabled:
			return MenuStyleFactory.arcade_tuning().disc_800_color.lerp(block.face_color, block.disabled_alpha)
		return Color(block.face_color.r, block.face_color.g, block.face_color.b, 1.0)
	assert_true(box is StyleBoxFlat, "%s must be a StyleBoxFlat or BlockStyleBox to measure icon contrast" % label)
	var flat: StyleBoxFlat = box as StyleBoxFlat
	return flat.bg_color if flat != null else Color.MAGENTA


## Icon colour as drawn over [param bg] (alpha composited onto it).
func _drawn(icon_color: Color, bg: Color) -> Color:
	return bg.lerp(Color(icon_color.r, icon_color.g, icon_color.b, 1.0), icon_color.a)


func _states_for(button: Button) -> Array:
	var states: Array = []
	states.append_array(STATES)
	if button.toggle_mode:
		states.append(TOGGLE_STATE)
	return states


func _assert_button_contrast(button: Button, scene_label: String) -> void:
	var minimum: float = TUNING.icon_min_contrast_ratio
	for state: Array in _states_for(button):
		var state_name: String = state[0]
		var box_name: String = state[1]
		var icon_item: String = state[2]
		var label: String = "%s/%s [%s]" % [scene_label, button.name, state_name]
		var bg: Color = _box_color(button.get_theme_stylebox(box_name), label)
		var icon_color: Color = button.get_theme_color(icon_item)
		var ratio: float = MenuStyleFactory.contrast_ratio(_drawn(icon_color, bg), bg)
		assert_gte(ratio, minimum, "%s icon contrast %.2f is below icon_min_contrast_ratio %.2f (icon %s on %s)" % [
			label, ratio, minimum, icon_color, bg,
		])


# --- contrast helper ----------------------------------------------------------

func test_contrast_ratio_matches_wcag_reference_values() -> void:
	assert_almost_eq(MenuStyleFactory.contrast_ratio(Color.BLACK, Color.WHITE), 21.0, 0.01)
	assert_almost_eq(MenuStyleFactory.contrast_ratio(Color.WHITE, Color.BLACK), 21.0, 0.01, "symmetric")
	assert_almost_eq(MenuStyleFactory.contrast_ratio(TUNING.pill_cream_color, TUNING.pill_cream_color), 1.0, 0.0001)


func test_white_icon_on_cream_pill_is_rejected_by_the_threshold() -> void:
	# The reported bug: a white glyph on a light face (Arcade: the rim-gold block).
	var ratio: float = MenuStyleFactory.contrast_ratio(Color.WHITE, MenuStyleFactory.arcade_tuning().rim_color)
	assert_lt(ratio, TUNING.icon_min_contrast_ratio, "white-on-rim measured %.2f must fail" % ratio)


# --- shipped scenes -----------------------------------------------------------

func test_main_menu_icons_contrast_in_every_state() -> void:
	var buttons: Array[Button] = _icon_buttons(_make_main_menu())
	assert_eq(buttons.size(), MAIN_MENU_ICON_BUTTONS, "icon buttons found in MainMenu.tscn")
	for button: Button in buttons:
		_assert_button_contrast(button, "MainMenu")


func test_pause_menu_icons_contrast_in_every_state() -> void:
	var buttons: Array[Button] = _icon_buttons(_make_pause_menu())
	assert_eq(buttons.size(), PAUSE_MENU_ICON_BUTTONS, "icon buttons found in PauseMenu.tscn")
	for button: Button in buttons:
		_assert_button_contrast(button, "PauseMenu")


func test_options_menu_mute_icons_contrast_on_their_panel_in_every_state() -> void:
	var menu: OptionsMenu = _make_options_menu()
	var buttons: Array[Button] = _texture_icon_buttons(menu)
	assert_eq(buttons.size(), OPTIONS_MENU_MUTE_BUTTONS, "mute buttons found in OptionsMenu.tscn")
	var minimum: float = TUNING.icon_min_contrast_ratio
	for icon_button: Button in _icon_buttons(menu):
		_assert_button_contrast(icon_button, "OptionsMenu")
	for button: Button in buttons:
		var icon_color: Color = (button.get_node("Icon") as TextureRect).modulate
		# The mute button is flat: whichever of its own styleboxes the engine
		# draws (none while flat, otherwise normal/hover/pressed), the glyph
		# must read on it and on the panel behind it.
		var backdrops: Dictionary = {"panel": _panel_color_behind(button)}
		for state: Array in STATES:
			var box_name: String = state[1]
			backdrops[box_name] = _box_color(button.get_theme_stylebox(box_name), "OptionsMenu/%s [%s]" % [button.name, state[0]])
		for backdrop: String in backdrops:
			if backdrop == "disabled":
				continue
			var bg: Color = backdrops[backdrop]
			var ratio: float = MenuStyleFactory.contrast_ratio(_drawn(icon_color, bg), bg)
			assert_gte(ratio, minimum, "OptionsMenu/%s icon contrast %.2f on %s %s is below %.2f" % [
				button.name, ratio, backdrop, bg, minimum,
			])


func _panel_color_behind(node: Control) -> Color:
	var ancestor: Node = node.get_parent()
	while ancestor != null:
		var panel: PanelContainer = ancestor as PanelContainer
		if panel != null:
			return _box_color(panel.get_theme_stylebox("panel"), "panel behind %s" % node.name)
		ancestor = ancestor.get_parent()
	fail_test("%s has no PanelContainer ancestor" % node.name)
	return Color.MAGENTA


func test_plain_theme_buttons_contrast_in_every_state() -> void:
	# A Button with no per-node overrides (every pill the factory does not
	# paint) must still pass: the shared Theme's own defaults.
	var minimum: float = TUNING.icon_min_contrast_ratio
	# (hover_pressed is not themed: the engine's own default style applies.)
	for state: Array in STATES:
		var state_name: String = state[0]
		var box_name: String = state[1]
		var icon_item: String = state[2]
		var bg: Color = _box_color(THEME.get_stylebox(box_name, "Button"), "theme Button/%s" % box_name)
		assert_true(THEME.has_color(icon_item, "Button"), "theme defines Button/%s" % icon_item)
		var icon_color: Color = THEME.get_color(icon_item, "Button")
		var ratio: float = MenuStyleFactory.contrast_ratio(_drawn(icon_color, bg), bg)
		assert_gte(ratio, minimum, "theme Button [%s] icon contrast %.2f" % [state_name, ratio])


func test_the_old_per_node_override_pattern_fails_the_focus_contrast() -> void:
	# Demonstrates the reported bug path: a bright (rim-gold) block whose dark icon was set
	# only for normal/hover keeps the theme's light icon colour while focused -- invisible on it.
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var face: Color = arcade.rim_color
	var button: Button = autofree(Button.new())
	button.theme = THEME
	add_child_autofree(button)
	button.add_theme_color_override("icon_normal_color", arcade.ink_color)
	button.add_theme_color_override("icon_hover_color", arcade.ink_color)
	var normal_ratio: float = MenuStyleFactory.contrast_ratio(button.get_theme_color("icon_normal_color"), face)
	var focus_ratio: float = MenuStyleFactory.contrast_ratio(button.get_theme_color("icon_focus_color"), face)
	assert_gte(normal_ratio, TUNING.icon_min_contrast_ratio, "the dark normal icon reads on the bright face")
	assert_lt(focus_ratio, TUNING.icon_min_contrast_ratio, "the un-overridden focus icon (%.2f) is invisible on it" % focus_ratio)
	MenuStyleFactory.apply_ink(button, arcade.ink_color)
	focus_ratio = MenuStyleFactory.contrast_ratio(button.get_theme_color("icon_focus_color"), face)
	assert_gte(focus_ratio, TUNING.icon_min_contrast_ratio, "apply_ink() fixes the focus icon (%.2f)" % focus_ratio)


# --- consistency ---------------------------------------------------------------

func test_icon_keeps_its_caption_ink_in_every_enabled_state() -> void:
	var buttons: Array[Button] = []
	buttons.append_array(_icon_buttons(_make_main_menu()))
	buttons.append_array(_icon_buttons(_make_pause_menu()))
	assert_gt(buttons.size(), 0)
	for button: Button in buttons:
		var ink: Color = button.get_theme_color("font_color")
		for item: String in MenuStyleFactory.BUTTON_ICON_COLOR_ITEMS:
			assert_eq(button.get_theme_color(item), ink, "%s %s must equal its label ink (no state flips the icon colour)" % [button.name, item])
		for item: String in MenuStyleFactory.BUTTON_FONT_COLOR_ITEMS:
			assert_eq(button.get_theme_color(item), ink, "%s %s must equal its label ink" % [button.name, item])


func test_focused_light_pill_icon_is_dark_and_focused_dark_pill_icon_is_light() -> void:
	var menu: MainMenu = _make_main_menu()
	var cream_pill: Button = menu.get_node("%OptionsButton") as Button
	var slate_pill: Button = menu.get_node("%BackButton") as Button
	assert_eq(cream_pill.get_theme_color("icon_focus_color"), TUNING.ink_color, "focused cream pill: dark icon")
	assert_eq(cream_pill.get_theme_color("icon_hover_color"), TUNING.ink_color, "hovered cream pill: dark icon")
	assert_eq(slate_pill.get_theme_color("icon_focus_color"), TUNING.label_ink_light_color, "focused dark pill: light icon")
	assert_eq(slate_pill.get_theme_color("icon_pressed_color"), TUNING.label_ink_light_color, "pressed dark pill: light icon")


func test_toggle_chip_and_stepper_cover_the_focus_state() -> void:
	# apply_toggle_chip() and apply_flat_stepper_button() go through the same
	# apply_ink(), so their focused label/icon cannot fall back to the pale
	# theme default on a cream chip.
	var chip: CheckButton = autofree(CheckButton.new())
	var stepper: Button = autofree(Button.new())
	add_child_autofree(chip)
	add_child_autofree(stepper)
	MenuStyleFactory.apply_toggle_chip(chip, TUNING.pill_cream_color, TUNING.pill_cream_hover_color, TUNING.pill_coral_color, TUNING.pill_coral_hover_color, TUNING.ink_color, TUNING)
	MenuStyleFactory.apply_flat_stepper_button(stepper, TUNING)
	for button: Button in [chip, stepper]:
		assert_eq(button.get_theme_color("font_focus_color"), TUNING.ink_color, "%s focused caption ink" % button.get_class())
		assert_eq(button.get_theme_color("icon_focus_color"), TUNING.ink_color, "%s focused icon ink" % button.get_class())


# --- source art -----------------------------------------------------------------

func test_every_menu_icon_source_is_white_svg_art() -> void:
	var textures: Dictionary = {}
	var roots: Array[Node] = [_make_main_menu(), _make_pause_menu(), _make_options_menu()]
	for root: Node in roots:
		for button: Button in _icon_buttons(root):
			textures[button.icon.resource_path] = "%s/%s" % [root.name, button.name]
		for button: Button in _texture_icon_buttons(root):
			textures[((button.get_node("Icon") as TextureRect).texture).resource_path] = "%s/%s" % [root.name, button.name]
	for icon: Texture2D in [OptionsMenu.SPEAKER_MUTED_ICON, OptionsMenu.SPEAKER_LOW_ICON, OptionsMenu.SPEAKER_MID_ICON, OptionsMenu.SPEAKER_HIGH_ICON]:
		textures[icon.resource_path] = "OptionsMenu speaker constant"
	assert_gt(textures.size(), 0)
	var paint_regex: RegEx = RegEx.create_from_string("(?:fill|stroke)=\"([^\"]*)\"")
	for path: String in textures:
		var owner_label: String = textures[path]
		assert_true(path.ends_with(".svg"), "'%s' (used by %s) is an SVG source" % [path, owner_label])
		var source: String = FileAccess.get_file_as_string(path)
		assert_false(source.is_empty(), "'%s' (used by %s) readable" % [path, owner_label])
		for hit: RegExMatch in paint_regex.search_all(source):
			var paint: String = hit.get_string(1).to_lower()
			assert_true(WHITE_SVG_PAINTS.has(paint), "%s bakes colour '%s'; icon art must be white so theme icon colours apply" % [path, paint])
