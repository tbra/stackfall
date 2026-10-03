extends GutTest
## Bontago-1pi.34/36/38/39 (owner playtest 2026-10-03): the debug-only menu
## entry, the reworked Play local page, the controller-reachable "invisible"
## control, and left/right navigation on Play local. Navigation is driven with
## real InputEventJoypadButton events through Input.parse_input_event (the
## route a physical pad takes), the same technique test_main_menu.gd uses.
##
## Bontago-1pi.44 (flaky in the sharded gate): two things made the "no dead
## focus" checks depend on what else the machine was doing.
## 1. MainMenu._ready() starts the REAL Net autoload's LAN browser (UDP 47777)
##    before a test swaps in FakeNet, and nothing ever stopped it. In a sharded
##    run another shard's real host advertises on that shared port, the listener
##    re-emits it as Events.net_games_discovered, and the menu's game list
##    filled with a game nobody asked for. A non-empty list is focusable, so it
##    was checked, and
## 2. a page switch is not laid out until the frame ends (Container sorting is
##    deferred), so a freshly shown list still has no size when asserted
##    synchronously. Alone the list stayed empty (focus-skipped) and hid this.
## Fix: _make_menu() closes the real listener (hermetic), and every page switch
## is followed by _settle_layout() before sizes are asserted.

## Upper bound on frames _settle_layout() waits; a real layout bug still fails
## the size assertion that follows instead of hanging the test.
const LAYOUT_SETTLE_FRAME_CAP: int = 8


func _make_menu(debug_enabled: bool = false, steam_available: bool = false) -> MainMenu:
	DebugMode.set_override_for_test(debug_enabled)
	var scene: PackedScene = load("res://ui/MainMenu.tscn")
	var menu: MainMenu = autofree(scene.instantiate())
	add_child_autofree(menu)
	# _ready() opened the real Net's LAN listener; close it so only this test's
	# own Events emissions can reach the menu (see the header, point 1).
	Net.stop_discovery()
	var fake: FakeNet = FakeNet.new()
	fake.steam_available_value = steam_available
	menu.net_provider = fake
	menu._apply_steam_availability()
	return menu


func after_each() -> void:
	DebugMode.clear_override_for_test()
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


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


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _node(menu: MainMenu, unique_name: String) -> Control:
	return menu.get_node("%" + unique_name) as Control


## Presses [param button] up to [param limit] times and returns the names of
## the controls focus visited (starting with the current one).
func _walk(button: JoyButton, limit: int) -> Array[String]:
	var visited: Array[String] = [String(_focus().name)]
	for _i: int in range(limit):
		await _pad(button)
		visited.append(String(_focus().name))
	return visited


## Every visible control the pad can focus, in no particular order.
func _visible_focusable(menu: MainMenu) -> Array[Control]:
	var found: Array[Control] = []
	var stack: Array[Node] = [menu]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		var control: Control = node as Control
		if control == null or not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE:
			continue
		found.append(control)
	return found


## Waits for the layout a page switch / list rebuild queued. Container sorts are
## deferred to the end of the frame (and cascade within that flush), so one
## frame always settles it; the loop only keeps going while some focusable
## control is still unsized, bounded by LAYOUT_SETTLE_FRAME_CAP.
func _settle_layout(menu: MainMenu) -> void:
	for _i: int in range(LAYOUT_SETTLE_FRAME_CAP):
		await get_tree().process_frame
		var unsized: int = 0
		for control: Control in _visible_focusable(menu):
			if control.size.x * control.size.y <= 0.0:
				unsized += 1
		if unsized == 0:
			return


## Every focus-capable control that is visible in the tree must be one the pad
## can actually use: non-zero size, opaque, enabled, and not an empty list.
## Callers `await _settle_layout(menu)` after changing the page first.
func _assert_no_dead_focus(menu: MainMenu, label: String) -> void:
	for control: Control in _visible_focusable(menu):
		var where: String = "%s: %s" % [label, menu.get_path_to(control)]
		assert_gt(control.size.x * control.size.y, 0.0, "%s has no size" % where)
		assert_gt(control.modulate.a * control.self_modulate.a, 0.0, "%s is transparent" % where)
		if control is BaseButton:
			assert_false((control as BaseButton).disabled, "%s is disabled but focusable" % where)
		if control is ItemList:
			assert_gt((control as ItemList).item_count, 0, "%s is an empty list but focusable" % where)


## Every neighbour a visible, focusable control points at must itself be a
## visible, focusable control (Godot hops through anything else to nowhere).
func _assert_neighbours_usable(menu: MainMenu, label: String) -> void:
	var sides: Array[Side] = [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]
	var stack: Array[Node] = [menu]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		var control: Control = node as Control
		if control == null or not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE:
			continue
		for side: Side in sides:
			var path: NodePath = control.get_focus_neighbor(side)
			if path.is_empty():
				continue
			var target: Control = control.get_node(path) as Control
			var where: String = "%s: %s -> %s" % [label, menu.get_path_to(control), path]
			assert_true(target.is_visible_in_tree(), "%s hidden neighbour" % where)
			assert_ne(target.focus_mode, Control.FOCUS_NONE, "%s unfocusable neighbour" % where)


# --- 1pi.34: debug entry ----------------------------------------------------------

func test_debug_entry_is_visible_only_in_debug_mode() -> void:
	var player_menu: MainMenu = _make_menu(false)
	assert_false(_node(player_menu, "DebugButton").is_visible_in_tree())
	var debug_menu: MainMenu = _make_menu(true)
	assert_true(_node(debug_menu, "DebugButton").is_visible_in_tree())


func test_debug_entry_does_not_move_any_other_control() -> void:
	DebugMode.set_override_for_test(false)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)
	var scene: PackedScene = load("res://ui/MainMenu.tscn")
	var menu: MainMenu = scene.instantiate()
	menu.net_provider = FakeNet.new()
	viewport.add_child(menu)
	Net.stop_discovery() # _ready() reopened the real LAN listener (header, point 1)
	for _i: int in range(3):
		await get_tree().process_frame
	var names: Array[String] = ["NameEdit", "HostButton", "JoinButton", "PlayLocalButton", "OptionsButton", "QuitButton", "Panel", "Title", "Tagline"]
	var before: Dictionary = {}
	for node_name: String in names:
		before[node_name] = _node(menu, node_name).get_global_rect() if node_name != "Tagline" else (menu.get_node("Center/Panel/Layout/Tagline") as Control).get_global_rect()
	assert_false(_node(menu, "DebugButton").visible)
	menu.set_debug_entry_enabled(true)
	for _i: int in range(3):
		await get_tree().process_frame
	assert_true(_node(menu, "DebugButton").visible)
	for node_name: String in names:
		var after: Rect2 = _node(menu, node_name).get_global_rect() if node_name != "Tagline" else (menu.get_node("Center/Panel/Layout/Tagline") as Control).get_global_rect()
		assert_true((before[node_name] as Rect2).is_equal_approx(after), "%s moved when the debug entry appeared" % node_name)
	menu.set_debug_entry_enabled(false)
	for _i: int in range(3):
		await get_tree().process_frame
	for node_name: String in names:
		var restored: Rect2 = _node(menu, node_name).get_global_rect() if node_name != "Tagline" else (menu.get_node("Center/Panel/Layout/Tagline") as Control).get_global_rect()
		assert_true((before[node_name] as Rect2).is_equal_approx(restored), "%s moved when the debug entry went away" % node_name)


func test_debug_page_offers_both_demos_and_back_returns_to_the_entry() -> void:
	var menu: MainMenu = _make_menu(true)
	watch_signals(menu)
	menu._on_debug_pressed()
	assert_true(_node(menu, "VisualDemoButton").is_visible_in_tree())
	assert_true(_node(menu, "GiftDemoButton").is_visible_in_tree())
	assert_false(_node(menu, "HostButton").is_visible_in_tree())
	assert_false(_node(menu, "NameEdit").is_visible_in_tree())
	assert_eq(_focus(), _node(menu, "VisualDemoButton"))
	_node(menu, "VisualDemoButton").pressed.emit()
	_node(menu, "GiftDemoButton").pressed.emit()
	assert_signal_emitted_with_parameters(menu, "debug_scene_requested", [MainMenu.VISUAL_DEMO_SCENE], 0)
	assert_signal_emitted_with_parameters(menu, "debug_scene_requested", [MainMenu.GIFT_DEMO_SCENE], 1)
	var cancel: InputEventAction = InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	menu._unhandled_input(cancel)
	assert_true(_node(menu, "HostButton").is_visible_in_tree())
	assert_eq(_focus(), _node(menu, "DebugButton"), "Back lands on the entry that opened the page")


func test_demo_buttons_do_nothing_when_debug_mode_is_off() -> void:
	var menu: MainMenu = _make_menu(false)
	watch_signals(menu)
	menu._on_debug_pressed()
	menu._on_visual_demo_pressed()
	menu._on_gift_demo_pressed()
	assert_signal_not_emitted(menu, "debug_scene_requested")
	assert_false(_node(menu, "VisualDemoButton").is_visible_in_tree())


func test_pad_reaches_the_debug_entry_and_it_is_not_a_dead_end() -> void:
	var menu: MainMenu = _make_menu(true)
	await get_tree().process_frame
	_node(menu, "PlayLocalButton").grab_focus()
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_eq(_focus(), _node(menu, "DebugButton"))
	await _pad(JOY_BUTTON_A)
	assert_eq(_focus(), _node(menu, "VisualDemoButton"), "A on Debug opens the Debug page")
	await _pad(JOY_BUTTON_B)
	assert_eq(_focus(), _node(menu, "DebugButton"), "B goes back to the entry")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_eq(_focus(), _node(menu, "NameEdit"), "the wrap continues to the name field")


func test_debug_entry_off_leaves_home_navigation_as_before() -> void:
	var menu: MainMenu = _make_menu(false)
	var quit: Button = _node(menu, "QuitButton") as Button
	assert_eq(quit.get_node(quit.focus_neighbor_bottom), _node(menu, "NameEdit"))
	var name_edit: LineEdit = _node(menu, "NameEdit") as LineEdit
	assert_eq(name_edit.get_node(name_edit.focus_neighbor_top), _node(menu, "PlayLocalButton"))


func test_demo_launch_reports_a_missing_scene_without_changing_scene() -> void:
	var root_children: int = get_tree().root.get_child_count()
	assert_eq(DemoReturn.launch(get_tree(), "res://visual_demo/does_not_exist.tscn"), ERR_FILE_NOT_FOUND)
	assert_eq(get_tree().root.get_child_count(), root_children, "no return glue is left behind")


func test_demo_return_glue_rules() -> void:
	assert_true(DemoReturn.needs_glue(MainMenu.VISUAL_DEMO_SCENE))
	assert_false(DemoReturn.needs_glue(MainMenu.GIFT_DEMO_SCENE), "the gift demo returns through its own pause menu")
	assert_false(DemoReturn.consume_returning())


func test_demo_return_glue_answers_cancel() -> void:
	var glue: DemoReturn = DemoReturn.new()
	glue.auto_return = false
	add_child_autofree(glue)
	watch_signals(glue)
	var other: InputEventAction = InputEventAction.new()
	other.action = "ui_accept"
	other.pressed = true
	glue._unhandled_input(other)
	assert_signal_not_emitted(glue, "return_requested")
	var cancel: InputEventAction = InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	glue._unhandled_input(cancel)
	assert_signal_emitted(glue, "return_requested")


# --- 1pi.36: Play local ---------------------------------------------------------------

func test_play_local_has_no_name_input_and_vs_bots_first() -> void:
	var menu: MainMenu = _make_menu()
	menu._on_play_local_pressed()
	assert_false(_node(menu, "NameEdit").is_visible_in_tree())
	assert_false((menu.get_node("Center/Panel/Layout/NameRow") as Control).is_visible_in_tree())
	var visible_row: Array[Button] = []
	for child: Node in (menu.get_node("Center/Panel/Layout/BottomRow") as Control).get_children():
		var button: Button = child as Button
		if button != null and button.visible:
			visible_row.append(button)
	assert_eq(visible_row.size(), 4)
	assert_eq(visible_row[0], _node(menu, "BotsButton"), "vs Bots is the first option")
	assert_eq(_focus(), _node(menu, "BotsButton"), "and it takes focus first")


func test_name_typed_on_home_still_reaches_vs_bots() -> void:
	var menu: MainMenu = _make_menu()
	(_node(menu, "NameEdit") as LineEdit).text = "Zed"
	menu._on_play_local_pressed()
	watch_signals(menu)
	menu._on_bots_pressed()
	assert_signal_emitted_with_parameters(menu, "bots_requested", ["Zed"])


func test_name_field_returns_on_home_and_join() -> void:
	var menu: MainMenu = _make_menu()
	menu._on_play_local_pressed()
	menu._on_back_pressed()
	assert_true(_node(menu, "NameEdit").is_visible_in_tree())
	menu._on_join_pressed()
	assert_true(_node(menu, "NameEdit").is_visible_in_tree())


# --- 1pi.39: Play local navigation -------------------------------------------------------

func test_every_pad_direction_reaches_every_play_local_option() -> void:
	var menu: MainMenu = _make_menu()
	await get_tree().process_frame
	menu._on_play_local_pressed()
	var wanted: Array[String] = ["BotsButton", "SandboxButton", "TutorialButton", "BackButton"]
	for direction: JoyButton in [JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP]:
		menu._on_play_local_pressed()
		var visited: Array[String] = await _walk(direction, 4)
		for option: String in wanted:
			assert_true(visited.has(option), "direction %d never reached %s (%s)" % [direction, option, visited])


func test_right_from_tutorial_moves_on_instead_of_stalling() -> void:
	var menu: MainMenu = _make_menu()
	await get_tree().process_frame
	menu._on_play_local_pressed()
	_node(menu, "TutorialButton").grab_focus()
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(_focus(), _node(menu, "BackButton"), "Tutorial -> right was a dead end before 1pi.39")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(_focus(), _node(menu, "BotsButton"), "wraps round to the first option")
	await _pad(JOY_BUTTON_DPAD_LEFT)
	await _pad(JOY_BUTTON_DPAD_LEFT)
	assert_eq(_focus(), _node(menu, "TutorialButton"))


func test_play_local_pad_actions_still_work() -> void:
	var menu: MainMenu = _make_menu()
	await get_tree().process_frame
	menu._on_play_local_pressed()
	watch_signals(menu)
	await _pad(JOY_BUTTON_A)
	assert_signal_emitted(menu, "bots_requested")
	await _pad(JOY_BUTTON_B)
	assert_eq(_focus(), _node(menu, "PlayLocalButton"), "B returns to Play local's entry on the home page")


# --- 1pi.38: no focusable control that does nothing ---------------------------------------------

func test_no_dead_focus_on_any_page_without_steam() -> void:
	var menu: MainMenu = _make_menu(true, false)
	await _settle_layout(menu)
	_assert_no_dead_focus(menu, "home")
	_assert_neighbours_usable(menu, "home")
	menu._on_play_local_pressed()
	await _settle_layout(menu)
	_assert_no_dead_focus(menu, "local")
	_assert_neighbours_usable(menu, "local")
	menu._on_back_pressed()
	menu._on_debug_pressed()
	await _settle_layout(menu)
	_assert_no_dead_focus(menu, "debug")
	_assert_neighbours_usable(menu, "debug")
	menu._on_back_pressed()
	menu._on_join_pressed()
	await _settle_layout(menu)
	_assert_no_dead_focus(menu, "join (LAN, no Steam)")
	_assert_neighbours_usable(menu, "join (LAN, no Steam)")


## Bontago-1pi.44: the case the sharded gate hit by accident -- a LAN game in the
## list makes it focusable, so it must have a real size once the page is laid
## out. Driven deterministically through the Events bus instead of a stray
## real advert.
func test_no_dead_focus_on_the_join_page_with_a_lan_game_listed() -> void:
	var menu: MainMenu = _make_menu(false, false)
	await _settle_layout(menu)
	menu._on_join_pressed()
	var games: Array[Dictionary] = [{"name": "Alice's game", "address": "192.168.1.10", "port": 47778, "players": 2, "max": 8}]
	Events.net_games_discovered.emit(games)
	await _settle_layout(menu)
	var list: ItemList = _node(menu, "GameList") as ItemList
	assert_eq(list.item_count, 1)
	assert_ne(list.focus_mode, Control.FOCUS_NONE, "a list with a game is focusable")
	assert_gt(list.size.x * list.size.y, 0.0, "and laid out once the frame has passed")
	_assert_no_dead_focus(menu, "join (LAN, one game)")
	_assert_neighbours_usable(menu, "join (LAN, one game)")


## Bontago-1pi.44: a menu under test must not be listening on the real LAN
## discovery port, or another process's host advert lands in its game list.
func test_menu_under_test_does_not_listen_on_the_real_lan_port() -> void:
	var _menu: MainMenu = _make_menu(false, false)
	assert_false(Net._lan.is_listening(), "the real Net LAN browser is closed after _make_menu")


func test_no_dead_focus_on_the_steam_pages() -> void:
	var menu: MainMenu = _make_menu(false, true)
	await _settle_layout(menu)
	menu._on_join_pressed()
	await _settle_layout(menu)
	_assert_no_dead_focus(menu, "join (LAN, Steam on)")
	_assert_neighbours_usable(menu, "join (LAN, Steam on)")
	menu._on_join_steam_tab_pressed()
	await _settle_layout(menu)
	_assert_no_dead_focus(menu, "join (Steam tab, no lobbies)")
	_assert_neighbours_usable(menu, "join (Steam tab, no lobbies)")
	var lobbies: Array[Dictionary] = [{"lobby_id": 1, "name": "A", "players": 1, "max": 8, "map": "Round"}]
	Events.net_steam_lobbies_discovered.emit(lobbies)
	await _settle_layout(menu)
	assert_ne(_node(menu, "SteamLobbyList").focus_mode, Control.FOCUS_NONE, "a list with a lobby is focusable")
	_assert_no_dead_focus(menu, "join (Steam tab, one lobby)")
	_assert_neighbours_usable(menu, "join (Steam tab, one lobby)")


func test_disabled_steam_tab_cannot_be_reached_with_the_pad() -> void:
	var menu: MainMenu = _make_menu(false, false)
	await get_tree().process_frame
	menu._on_join_pressed()
	var steam_tab: Control = _node(menu, "JoinSteamTabButton")
	assert_eq(steam_tab.focus_mode, Control.FOCUS_NONE)
	for direction: JoyButton in [JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_LEFT]:
		menu._on_join_pressed()
		var visited: Array[String] = await _walk(direction, 8)
		assert_false(visited.has("JoinSteamTabButton"), "direction %d reached the disabled Steam tab (%s)" % [direction, visited])


func test_empty_game_list_is_skipped_until_a_game_appears() -> void:
	var menu: MainMenu = _make_menu(false, false)
	await get_tree().process_frame
	menu._on_join_pressed()
	var list: ItemList = _node(menu, "GameList") as ItemList
	assert_eq(list.focus_mode, Control.FOCUS_NONE)
	var games: Array[Dictionary] = [{"name": "Alice's game", "address": "192.168.1.10", "port": 47778, "players": 2, "max": 8}]
	Events.net_games_discovered.emit(games)
	assert_ne(list.focus_mode, Control.FOCUS_NONE)
	var refresh: Control = _node(menu, "RefreshButton")
	assert_eq(refresh.get_node(refresh.focus_neighbor_bottom), list)
	list.grab_focus()
	var no_games: Array[Dictionary] = []
	Events.net_games_discovered.emit(no_games)
	assert_eq(list.focus_mode, Control.FOCUS_NONE)
	assert_eq(_focus(), refresh, "focus moves off a list that just emptied")


func test_host_dialog_steam_choice_is_not_focusable_while_unavailable() -> void:
	var offline: MainMenu = _make_menu(false, false)
	assert_true(offline._host_steam_choice.disabled)
	assert_eq(offline._host_steam_choice.focus_mode, Control.FOCUS_NONE)
	var online: MainMenu = _make_menu(false, true)
	assert_false(online._host_steam_choice.disabled)
	assert_ne(online._host_steam_choice.focus_mode, Control.FOCUS_NONE)


func test_decorative_title_and_diorama_cannot_take_focus() -> void:
	var menu: MainMenu = _make_menu()
	for node_name: String in ["Title", "TitleShadow"]:
		assert_eq(_node(menu, node_name).focus_mode, Control.FOCUS_NONE)
	assert_eq((menu.get_node("Diorama") as Control).focus_mode, Control.FOCUS_NONE)
