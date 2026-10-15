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

const MAIN_MENU_SCENE: PackedScene = preload("res://ui/menus/MainMenu.tscn")
const PAUSE_MENU_SCENE: PackedScene = preload("res://ui/menus/PauseMenu.tscn")
const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/menus/OptionsMenu.tscn")
const THEME: Theme = preload("res://ui/theme/stackfall_theme.tres")
const TUNING: MenuVisualTuning = preload("res://config/ui/menu_visual_tuning.tres")

## Icon-bearing Buttons counted in the shipped scenes; a lower count means the
## walk silently missed some, so the contrast assertions would be vacuous.
const MAIN_MENU_ICON_BUTTONS: int = 13
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
