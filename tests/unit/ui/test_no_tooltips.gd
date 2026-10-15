extends GutTest
## "tooltips should be fully removed": player-facing
## screens explain themselves inline (UiHelpLine, labels, dialog text), never through tooltip_text.
## The developer F4 TuningPanel and the debug / sandbox panels are out of scope and may keep theirs.

const LOBBY_SCENE: PackedScene = preload("res://ui/lobby/Lobby.tscn")
const MAIN_MENU_SCENE: PackedScene = preload("res://ui/menus/MainMenu.tscn")
const PAUSE_MENU_SCENE: PackedScene = preload("res://ui/menus/PauseMenu.tscn")
const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/menus/OptionsMenu.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/hud/HUD.tscn")
const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")


func after_each() -> void:
	DebugMode.clear_override_for_test()


## Every Control under [param root] (itself included) with a non-empty tooltip, as "path: text" lines.
func _tooltips_under(root: Node) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var control: Control = node as Control
		if control != null and not control.tooltip_text.is_empty():
			found.append("%s: %s" % [str(root.get_path_to(control)), control.tooltip_text])
		pending.append_array(node.get_children())
	return found


func _assert_no_tooltips(root: Node, screen: String) -> void:
	var found: PackedStringArray = _tooltips_under(root)
	assert_eq(found.size(), 0, "%s has no tooltips (inline help only): %s" % [screen, "; ".join(found)])


func _make_lobby(is_host: bool) -> Lobby:
	var lobby: Lobby = autofree(LOBBY_SCENE.instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = is_host
	fake.is_offline_value = is_host
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func test_lobby_host_has_no_tooltips() -> void:
	var lobby: Lobby = _make_lobby(true)
	await wait_frames(2)
	_assert_no_tooltips(lobby, "Lobby (host)")


func test_main_menu_has_no_tooltips() -> void:
	DebugMode.set_override_for_test(true)
	var menu: MainMenu = autofree(MAIN_MENU_SCENE.instantiate())
	add_child_autofree(menu)
	Net.stop_discovery()
	menu.net_provider = FakeNet.new()
	await wait_frames(2)
	_assert_no_tooltips(menu, "MainMenu")


func test_options_menu_has_no_tooltips() -> void:
	var menu: OptionsMenu = autofree(OPTIONS_MENU_SCENE.instantiate())
	add_child_autofree(menu)
	var settings: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(settings)
	menu.settings_provider = settings
	await wait_frames(2)
	_assert_no_tooltips(menu, "OptionsMenu")
