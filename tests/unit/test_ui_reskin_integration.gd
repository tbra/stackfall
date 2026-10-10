extends GutTest
## Bontago-hfa.10 (UI reskin P8, docs/UI_RESKIN_PLAN.md): cross-screen integration checks.
## (a) a synthetic D-pad traversal per screen visits a chain of focus stops with no trap and every
## focusable control carries a drawn focus style, (b) no Label/Button/RichTextLabel under 13 px at
## the project's 1280x720 base viewport, (c) the ArcadeVisualTuning text-on-surface pairs meet
## WCAG 4.5:1 (3:1 for display text of 24 px and up). Per-screen look checks stay in their own
## files (test_main_menu_arcade, test_options_pause_arcade, test_lobby_gamepad_focus).

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/OptionsMenu.tscn")
const PAUSE_MENU_SCENE: PackedScene = preload("res://ui/PauseMenu.tscn")
const LOBBY_SCENE: PackedScene = preload("res://ui/Lobby.tscn")
const RESULTS_SCENE: PackedScene = preload("res://ui/ResultsScreen.tscn")
const LOADING_SCENE: PackedScene = preload("res://ui/LoadingScreen.tscn")
const MAIN_MENU_SCENE: PackedScene = preload("res://ui/MainMenu.tscn")
const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")
const SETTLE_FRAMES: int = 3
const WALK_LIMIT: int = 60
const MIN_FONT_PX: int = 13
const DISPLAY_FONT_PX: int = 24
const MIN_TEXT_RATIO: float = 4.5
const MIN_DISPLAY_RATIO: float = 3.0
const LOADING_SLOTS: int = 2
## Dev overlays are exempt from the size floor (docs/UI_RESKIN_PLAN.md P8).
const DEV_OVERLAY_NAMES: PackedStringArray = ["PerfOverlay", "NetDebugOverlay", "TuningPanel", "SandboxPanel"]

var _cfg_counter: int = 0


func after_each() -> void:
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)
	DebugMode.clear_override_for_test()


# --- harness ----------------------------------------------------------------

func _settle() -> void:
	for _i: int in SETTLE_FRAMES:
		await get_tree().process_frame


func _pad_down() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = 0
		event.button_index = JOY_BUTTON_DPAD_DOWN
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await get_tree().process_frame


func _add(scene: PackedScene) -> Node:
	var node: Node = autofree(scene.instantiate())
	add_child_autofree(node)
	return node


func _options() -> OptionsMenu:
	var menu: OptionsMenu = _add(OPTIONS_MENU_SCENE) as OptionsMenu
	_cfg_counter += 1
	var fresh: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(fresh)
	fresh.set_config_path_for_test(OS.get_user_data_dir().path_join("test_ui_p8_tmp_%d.cfg" % _cfg_counter))
	menu.settings_provider = fresh
	return menu


func _main_menu() -> MainMenu:
	DebugMode.set_override_for_test(false)
	var menu: MainMenu = _add(MAIN_MENU_SCENE) as MainMenu
	Net.stop_discovery()
	menu.net_provider = FakeNet.new()
	return menu


func _lobby() -> Lobby:
	var lobby: Lobby = _add(LOBBY_SCENE) as Lobby
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = true
	fake.is_offline_value = true
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func _results() -> ResultsScreen:
	var screen: ResultsScreen = _add(RESULTS_SCENE) as ResultsScreen
	screen.net_provider = FakeNet.host()
	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.config = MatchConfig.new()
	screen.match_provider = fake_match
	screen.show_results({
		"winner_kind": MatchStats.WINNER_KIND_SLOT, "winner_id": 0, "winner_name": "Alice", "match_duration": 120.0,
		"rows": [
			{"slot_id": 0, "name": "Alice", "team_id": 0, "is_bot": false, "blocks_placed": 10, "blocks_lost": 1,
				"gifts_claimed": 2, "specials_used": 1, "territory_share": 0.6, "eliminated_at": MatchStats.NOT_ELIMINATED},
			{"slot_id": 1, "name": "Bob", "team_id": 1, "is_bot": false, "blocks_placed": 8, "blocks_lost": 3,
				"gifts_claimed": 0, "specials_used": 0, "territory_share": 0.4, "eliminated_at": MatchStats.NOT_ELIMINATED},
		],
	})
	return screen


func _loading() -> LoadingScreen:
	var screen: LoadingScreen = _add(LOADING_SCENE) as LoadingScreen
	var slots: Array[PlayerSlot] = []
	for i: int in LOADING_SLOTS:
		slots.append(PlayerSlot.new(i, i, "Player %d" % (i + 1), Color.WHITE))
	screen.show_for_match(MatchConfig.new(), slots)
	return screen


func _is_dev(node: Node, root: Node) -> bool:
	var cursor: Node = node
	while cursor != null and cursor != root.get_parent():
		if DEV_OVERLAY_NAMES.has(String(cursor.name)):
			return true
		cursor = cursor.get_parent()
	return false


func _focusables(root: Node) -> Array[Control]:
	var found: Array[Control] = []
	for node: Node in root.find_children("*", "Control", true, false):
		var control: Control = node as Control
		# FOCUS_CLICK controls (e.g. the lobby backdrop SubViewportContainer) are not pad-reachable.
		if control is ScrollBar or control.focus_mode == Control.FOCUS_NONE or control.focus_mode == Control.FOCUS_CLICK:
			continue
		if not control.is_visible_in_tree() or control.get_window() != get_tree().root or _is_dev(control, root):
			continue
		if control is BaseButton and (control as BaseButton).disabled:
			continue
		found.append(control)
	return found


## A focus style counts only when it is drawn and visibly differs from the normal style.
func _has_drawn_focus(control: Control) -> bool:
	var box: StyleBox = control.get_theme_stylebox(&"focus")
	if box == null or box is StyleBoxEmpty:
		return false
	var normal: StyleBox = control.get_theme_stylebox(&"normal")
	if normal == null or normal == box:
		return normal == null
	if box is StyleBoxFlat and normal is StyleBoxFlat:
		var f: StyleBoxFlat = box as StyleBoxFlat
		var n: StyleBoxFlat = normal as StyleBoxFlat
		return f.border_color != n.border_color or f.border_width_left != n.border_width_left 			or f.bg_color != n.bg_color or f.draw_center != n.draw_center
	return true


## Walks D-pad down from the first stop; the walk must never lose focus, and it must either loop
## back onto a visited stop or run out of new stops (no trap), visiting at least two stops.
func _traverse(root: Node, screen_name: String, start: Control = null) -> void:
	var stops: Array[Control] = _focusables(root)
	assert_gt(stops.size(), 0, "%s has focusable controls" % screen_name)
	if stops.is_empty():
		return
	for stop: Control in stops:
		assert_true(_has_drawn_focus(stop), "%s: %s has a drawn focus style" % [screen_name, stop.name])
	var first: Control = start if start != null else stops[0]
	first.grab_focus()
	var visited: Dictionary[Control, bool] = {first: true}
	var looped: bool = false
	for _step: int in WALK_LIMIT:
		await _pad_down()
		var owner: Control = get_viewport().gui_get_focus_owner()
		assert_not_null(owner, "%s: focus is never lost during the walk" % screen_name)
		if owner == null:
			return
		if visited.has(owner):
			looped = true
			break
		visited[owner] = true
		assert_true(_has_drawn_focus(owner), "%s: walked stop %s has a drawn focus style" % [screen_name, owner.name])
	if stops.size() > 1:
		assert_gt(visited.size(), 1, "%s: D-pad down moves focus off the first stop" % screen_name)
	assert_true(looped or visited.size() >= stops.size(), "%s: no focus trap" % screen_name)


func _font_px(node: Control) -> int:
	if node is RichTextLabel:
		return node.get_theme_font_size(&"normal_font_size")
	return node.get_theme_font_size(&"font_size")


func _audit_text(root: Node, screen_name: String) -> void:
	var checked: int = 0
	for type_name: String in ["Label", "Button", "RichTextLabel"]:
		for node: Node in root.find_children("*", type_name, true, false):
			var control: Control = node as Control
			if not control.is_visible_in_tree() or control.get_window() != get_tree().root or _is_dev(control, root):
				continue
			var text: String = String(control.get("text"))
			if text == "":
				continue
			checked += 1
			assert_gte(_font_px(control), MIN_FONT_PX, "%s: %s font size" % [screen_name, control.name])
	assert_gt(checked, 0, "%s: fixture read some text nodes" % screen_name)


# --- (a) + (b) per screen ------------------------------------------------------

func test_main_menu_pages_focus_and_text() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	var menu: MainMenu = _main_menu()
	await _settle()
	await _traverse(menu, "main menu")
	_audit_text(menu, "main menu")
	menu._on_play_local_pressed()
	await _settle()
	await _traverse(menu, "main menu play page")
	_audit_text(menu, "main menu play page")


func test_options_settings_and_controls_tabs_focus_and_text() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	var menu: OptionsMenu = _options()
	await _settle()
	await _traverse(menu, "options settings tab")
	_audit_text(menu, "options settings tab")
	(menu.get_node("%ControlsTabButton") as Button).button_pressed = true
	await _settle()
	await _traverse(menu, "options controls tab (rebind rows)")
	_audit_text(menu, "options controls tab")


func test_pause_menu_focus_and_text() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	var menu: PauseMenu = _add(PAUSE_MENU_SCENE) as PauseMenu
	menu._open()
	await _settle()
	await _traverse(menu, "pause")
	_audit_text(menu, "pause")
	menu.force_close()


func test_lobby_focus_and_text() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	var lobby: Lobby = _lobby()
	await _settle()
	# The lobby wires an explicit focus loop (Lobby._main_chain); start where a pad user lands.
	await _traverse(lobby, "lobby", lobby._visible_chain(lobby._main_chain)[0])
	_audit_text(lobby, "lobby")


func test_results_screen_focus_and_text() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	var screen: ResultsScreen = _results()
	await _settle()
	await _traverse(screen, "results")
	_audit_text(screen, "results")


func test_loading_screen_text() -> void:
	# The loading screen has no required pad-focus chain (ready is a bare prompt); any focusable
	# control it does expose must still draw focus.
	var screen: LoadingScreen = _loading()
	await _settle()
	_audit_text(screen, "loading")
	for stop: Control in _focusables(screen):
		assert_true(_has_drawn_focus(stop), "loading: %s has a drawn focus style" % stop.name)


# --- (c) contrast ----------------------------------------------------------------

func _ratio(text: Color, surface: Color) -> float:
	return MenuStyleFactory.contrast_ratio(text, surface)


func test_text_on_surface_pairs_meet_wcag_aa() -> void:
	var a: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var discs: Array[Color] = [a.disc_950_color, a.disc_900_color, a.disc_800_color, a.disc_700_color]
	for text: Color in [a.cream_color, a.sand_color, a.dust_color, a.mint_color, a.rim_color]:
		for surface: Color in discs:
			assert_gte(_ratio(text, surface), MIN_TEXT_RATIO, "%s on %s" % [text.to_html(), surface.to_html()])
	assert_gte(_ratio(a.cream_color, a.disc_600_color), MIN_TEXT_RATIO, "cream on the secondary block face")
	var bright: Array[Color] = [a.flare_color, a.rim_color, a.mint_color, a.player_1_color, a.player_2_color,
		a.player_3_color, a.player_4_color, a.player_5_color, a.player_6_color, a.player_7_color, a.player_8_color]
	for face: Color in bright:
		assert_gte(_ratio(a.ink_color, face), MIN_TEXT_RATIO, "ink on %s" % face.to_html())
	# Display text (>= 24 px, Bungee headlines/timers) only needs the large-text ratio.
	assert_gte(a.font_size_heading_px, DISPLAY_FONT_PX, "fixture: the heading size is large text")
	for text: Color in [a.flare_color, a.alert_color]:
		for surface: Color in discs:
			assert_gte(_ratio(text, surface), MIN_DISPLAY_RATIO, "display %s on %s" % [text.to_html(), surface.to_html()])


func test_toggle_icons_use_the_mint_token() -> void:
	var a: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var theme: Theme = load("res://ui/theme/stackfall_theme.tres") as Theme
	var mint_hex: String = "#" + a.mint_color.to_html(false)
	for theme_type: String in ["CheckButton", "CheckBox"]:
		for icon_name: String in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
			assert_true(theme.has_icon(icon_name, theme_type), "%s has icon %s" % [theme_type, icon_name])
	# Every icon file is drawn from the tokens: the track/box well, its outline, and the knob/mark.
	var well_hex: String = "#" + a.disc_900_color.to_html(false)
	var edge_hex: String = "#" + a.disc_400_color.to_html(false)
	var dust_hex: String = "#" + a.dust_color.to_html(false)
	for family: String in ["toggle", "checkbox"]:
		for state: String in ["on", "off", "on_disabled", "off_disabled"]:
			var path: String = "res://assets/ui/icons/%s_%s.svg" % [family, state]
			var svg: String = FileAccess.get_file_as_string(path).to_lower()
			assert_true(svg.contains(edge_hex), "%s outline uses disc-400" % path)
			assert_true(svg.contains(well_hex), "%s well uses disc-900" % path)
			if state.begins_with("on"):
				assert_true(svg.contains(mint_hex), "%s is drawn in the mint token" % path)
			elif family == "toggle":
				assert_true(svg.contains(dust_hex), "%s knob uses dust" % path)
			if state.ends_with("disabled"):
				assert_true(svg.contains("opacity=\"0.45\""), "%s is dimmed" % path)
	var on_icon: Texture2D = theme.get_icon("checked", "CheckButton")
	assert_true(on_icon.resource_path.ends_with("toggle_on.svg"))


func test_debug_overlay_colours_follow_the_arcade_tokens() -> void:
	var a: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var cfg: DebugConfig = DebugConfig.new()
	assert_eq(Color(cfg.overlay_text_color(), 1.0), a.cream_color)
	assert_eq(Color(cfg.overlay_warn_color(), 1.0), a.rim_color)
	assert_eq(Color(cfg.graph_frame_color(), 1.0), a.mint_color)
	assert_eq(Color(cfg.overlay_background_color(), 1.0), a.disc_950_color)
	assert_almost_eq(cfg.overlay_background_color().a, cfg.overlay_background_alpha, 0.001)
	cfg.overlay_text_override = Color.HOT_PINK
	assert_eq(cfg.overlay_text_color(), Color.HOT_PINK, "an owner override wins over the token")
