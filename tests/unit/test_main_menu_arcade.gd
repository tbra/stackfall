extends GutTest
## Bontago-hfa.3 (UI reskin P1, docs/UI_RESKIN_PLAN.md): the Stackfall Arcade main menu - a left
## column of blocks over a scrim, with a slow orbit over a live (non-physics) arena behind it.

const LAYOUT_SETTLE_FRAMES: int = 3
const MIN_FONT_PX: int = 13
const WALK_LIMIT: int = 12


func _make_menu() -> MainMenu:
	DebugMode.set_override_for_test(false)
	var menu: MainMenu = autofree((load("res://ui/MainMenu.tscn") as PackedScene).instantiate())
	add_child_autofree(menu)
	Net.stop_discovery()
	menu.net_provider = FakeNet.new()
	return menu


func after_each() -> void:
	DebugMode.clear_override_for_test()


func _node(menu: MainMenu, unique_name: String) -> Control:
	return menu.get_node("%" + unique_name) as Control


func _pad(button: JoyButton) -> void:
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.device = -1
	press.button_index = button
	press.pressed = true
	Input.parse_input_event(press)
	var release: InputEventJoypadButton = InputEventJoypadButton.new()
	release.device = -1
	release.button_index = button
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame


func _focus_name() -> String:
	return String(get_viewport().gui_get_focus_owner().name)


func _visible_buttons(menu: MainMenu) -> Array[Button]:
	var found: Array[Button] = []
	for node: Node in menu.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button.is_visible_in_tree() and button.get_window() == get_tree().root:
			found.append(button)
	return found


## The face colour of a block-styled button, or transparent when it is not a BlockStyleBox.
func _face(button: Button) -> Color:
	var block: BlockStyleBox = button.get_theme_stylebox("normal") as BlockStyleBox
	return block.face_color if block != null else Color.TRANSPARENT


func _flare_buttons(menu: MainMenu) -> Array[String]:
	var flare: Color = MenuStyleFactory.arcade_tuning().flare_color
	var names: Array[String] = []
	for button: Button in _visible_buttons(menu):
		if _face(button).is_equal_approx(flare):
			names.append(String(button.name))
	return names


## Runs [param check] on the home, Play offline and Join pages in turn.
func _on_each_page(menu: MainMenu, check: Callable) -> void:
	check.call()
	menu._on_play_local_pressed()
	check.call()
	menu._on_back_pressed()
	menu._on_join_pressed()
	check.call()


# --- the live arena backdrop -------------------------------------------------------------

func test_arena_reuses_the_real_arena_surface_and_beacons() -> void:
	var menu: MainMenu = _make_menu()
	var arena: MenuArena = menu.get_node("Arena") as MenuArena
	assert_not_null(arena.overlay(), "the real TerritoryOverlay draws the disc")
	assert_gt(arena.overlay().arena().materials().size(), 0, "with the real rim/band/bottom side surfaces")
	var homes: int = 0
	for flag: Node in arena.viewport().find_children("*", "HomeFlag", true, false):
		if not flag is GoalFlag:
			homes += 1
	assert_eq(homes, arena.tuning.arena_slot_count, "one real HomeFlag beacon per shown slot")
	assert_eq(arena.viewport().find_children("*", "GoalFlag", true, false).size(), 1)


func test_arena_runs_no_physics_and_no_match_state() -> void:
	var menu: MainMenu = _make_menu()
	var arena: MenuArena = menu.get_node("Arena") as MenuArena
	assert_eq(arena.viewport().find_children("*", "CollisionObject3D", true, false).size(), 0, "no bodies, areas or collision")
	assert_eq(arena.viewport().find_children("*", "CollisionShape3D", true, false).size(), 0)
	assert_true(arena.viewport().own_world_3d, "its own World3D, never the match world")


func test_arena_orbits_and_stops_when_hidden() -> void:
	var menu: MainMenu = _make_menu()
	var arena: MenuArena = menu.get_node("Arena") as MenuArena
	var before: Vector3 = arena.camera().position
	arena._process(1.0)
	assert_ne(arena.camera().position, before, "the camera moves")
	assert_almost_eq(arena.camera().position.y, arena.tuning.camera_height_m, 0.001, "on a level orbit")
	menu.hide()
	assert_eq(arena.viewport().render_target_update_mode, SubViewport.UPDATE_DISABLED)
	menu.show()
	assert_eq(arena.viewport().render_target_update_mode, SubViewport.UPDATE_ALWAYS)


func test_arena_is_cheap_by_construction() -> void:
	var menu: MainMenu = _make_menu()
	var viewport: SubViewport = (menu.get_node("Arena") as MenuArena).viewport()
	assert_eq(viewport.msaa_3d, Viewport.MSAA_DISABLED)
	assert_gte(MenuBackdrop.budget_holders(), 1, "the menu render budget (fps cap) is still held")
	assert_eq(Engine.max_fps, (load("res://config/menu_visual_tuning.tres") as MenuVisualTuning).menu_max_fps)


# --- the left column ---------------------------------------------------------------------------

func test_lockup_and_scrim_are_in_place() -> void:
	var menu: MainMenu = _make_menu()
	var title: TextureRect = _node(menu, "Title") as TextureRect
	assert_eq(title.texture.resource_path, "res://assets/ui/stackfall-lockup.svg")
	assert_not_null((_node(menu, "Scrim") as TextureRect).texture, "the left scrim gradient is built")
	assert_eq(menu.get_node("Backdrop").get("draw_art"), false, "the paper-cut art is off, only the budget stays")


func test_exactly_one_primary_block_per_page() -> void:
	var menu: MainMenu = _make_menu()
	var expected: Array[Array] = [["HostButton"], ["BotsButton"], ["DirectJoinButton"]]
	assert_eq(_flare_buttons(menu), expected[0], "home: Host")
	menu._on_play_local_pressed()
	assert_eq(_flare_buttons(menu), expected[1], "local: Vs bots")
	menu._on_back_pressed()
	menu._on_join_pressed()
	assert_eq(_flare_buttons(menu), expected[2], "join: Join IP")


func _check_text(menu: MainMenu) -> void:
	for button: Button in _visible_buttons(menu):
		if button.text != "":
			assert_eq(button.text, button.text.to_upper(), "%s is uppercase" % button.name)
			assert_gte(button.get_theme_font_size("font_size"), MIN_FONT_PX, "%s font" % button.name)
	for node: Node in menu.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.is_visible_in_tree() and label.text != "":
			assert_gte(label.get_theme_font_size("font_size"), MIN_FONT_PX, "%s font" % label.name)


func test_buttons_read_uppercase_and_no_text_is_under_13px() -> void:
	var menu: MainMenu = _make_menu()
	_on_each_page(menu, func() -> void: _check_text(menu))


func _check_focus_outline(menu: MainMenu) -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	for node: Node in menu.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE or control.get_window() != get_tree().root:
			continue
		if control is ScrollBar:
			continue # the engine's own inner scroll bars of an ItemList are never pad-focused
		var focus: StyleBoxFlat = control.get_theme_stylebox("focus") as StyleBoxFlat
		assert_not_null(focus, "%s has a flat focus outline" % control.name)
		if focus != null:
			assert_eq(focus.border_width_left, arcade.focus_px, "%s outline width" % control.name)
			assert_eq(focus.border_color, arcade.cream_color, "%s outline is cream" % control.name)


func test_every_focusable_control_keeps_the_theme_focus_outline() -> void:
	var menu: MainMenu = _make_menu()
	_on_each_page(menu, func() -> void: _check_focus_outline(menu))


# --- gamepad traversal ---------------------------------------------------------------------------

func test_pad_walks_the_whole_home_column_and_wraps() -> void:
	var menu: MainMenu = _make_menu()
	await get_tree().process_frame
	var visited: Array[String] = [_focus_name()]
	for _i: int in range(WALK_LIMIT):
		await _pad(JOY_BUTTON_DPAD_DOWN)
		if _focus_name() == visited[0]:
			break
		visited.append(_focus_name())
	var expected: Array[String] = ["HostButton", "JoinButton", "PlayLocalButton", "OptionsButton", "NameEdit"]
	assert_eq(visited, expected, "down walks Host, Join, Play offline, Options, then the Name field and wraps")
	_node(menu, "OptionsButton").grab_focus()
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(_focus_name(), "QuitButton", "right moves inside the Options | Quit row")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(_focus_name(), "QuitButton", "and clamps at the end of the row")


func test_pad_reaches_every_join_page_control() -> void:
	var menu: MainMenu = _make_menu()
	await get_tree().process_frame
	menu._on_join_pressed()
	for _i: int in range(LAYOUT_SETTLE_FRAMES):
		await get_tree().process_frame
	var seen: Dictionary = {}
	for _i: int in range(WALK_LIMIT):
		seen[_focus_name()] = true
		await _pad(JOY_BUTTON_DPAD_DOWN)
	for wanted: String in ["JoinLanTabButton", "NameEdit", "RefreshButton", "DirectIpEdit", "BackButton"]:
		assert_true(seen.has(wanted), "the pad reaches %s on the Join page (%s)" % [wanted, seen.keys()])
