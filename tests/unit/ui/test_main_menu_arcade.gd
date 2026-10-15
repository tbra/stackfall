extends GutTest
## UI reskin P1, docs/UI_RESKIN_PLAN.md: the Stackfall Arcade main menu - a left
## column of blocks over a scrim, with a slow orbit over a live (non-physics) arena behind it.

const LAYOUT_SETTLE_FRAMES: int = 3
const MIN_FONT_PX: int = 13
const WALK_LIMIT: int = 12


func _make_menu() -> MainMenu:
	DebugMode.set_override_for_test(false)
	var menu: MainMenu = autofree((load("res://ui/menus/MainMenu.tscn") as PackedScene).instantiate())
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


## Runs [param check] on the home, Play offline and Join pages in turn.
func _on_each_page(menu: MainMenu, check: Callable) -> void:
	check.call()
	menu._on_play_local_pressed()
	check.call()
	menu._on_back_pressed()
	menu._on_join_pressed()
	check.call()


# --- the static image backdrop -----------------------------------------------------------

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
