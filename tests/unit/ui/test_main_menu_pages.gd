extends GutTest
## /36/38/39: the debug-only menu
## entry, the reworked Play local page, the controller-reachable "invisible"
## control, and left/right navigation on Play local. Navigation is driven with
## real InputEventJoypadButton events through Input.parse_input_event (the
## route a physical pad takes), the same technique test_main_menu.gd uses.
##
## flaky in the sharded gate: two things made the "no dead
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
	var scene: PackedScene = load("res://ui/menus/MainMenu.tscn")
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
	Settings._input(InputEventKey.new())


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


# --- debug entry ----------------------------------------------------------

func test_debug_entry_is_visible_only_in_debug_mode() -> void:
	var player_menu: MainMenu = _make_menu(false)
	assert_false(_node(player_menu, "DebugButton").is_visible_in_tree())
	var debug_menu: MainMenu = _make_menu(true)
	assert_true(_node(debug_menu, "DebugButton").is_visible_in_tree())


func test_demo_buttons_do_nothing_when_debug_mode_is_off() -> void:
	var menu: MainMenu = _make_menu(false)
	watch_signals(menu)
	menu._on_debug_pressed()
	menu._on_gift_demo_pressed()
	menu._on_tower_topple_pressed()
	assert_signal_not_emitted(menu, "gift_demo_requested")
	assert_signal_not_emitted(menu, "tower_topple_requested")
	assert_false(_node(menu, "GiftDemoButton").is_visible_in_tree())


func test_play_local_has_no_name_input_and_vs_bots_first() -> void:
	var menu: MainMenu = _make_menu()
	menu._on_play_local_pressed()
	assert_false(_node(menu, "NameEdit").is_visible_in_tree())
	assert_false((menu.get_node("Center/Panel/Layout/NameField") as Control).is_visible_in_tree())
	var visible_row: Array[Button] = []
	for child: Node in (menu.get_node("Center/Panel/Layout/BottomRow") as Control).get_children():
		var button: Button = child as Button
		if button != null and button.visible:
			visible_row.append(button)
	assert_eq(visible_row.size(), 4)
	assert_eq(visible_row[0], _node(menu, "BotsButton"), "vs Bots is the first option")
	assert_eq(_focus(), _node(menu, "BotsButton"), "and it takes focus first")


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


## the case the sharded gate hit by accident -- a LAN game in the
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
