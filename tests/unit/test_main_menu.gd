extends GutTest
## docs/archive/M3a_PLAN.md P4: ui/MainMenu.gd offers only Host / Join / Quit (owner
## decision: hot-seat is unlisted), a LAN game list fed by Events, and a
## direct-IP fallback (spec 3.4).


func _make_menu() -> MainMenu:
	var scene: PackedScene = load("res://ui/MainMenu.tscn")
	var menu: MainMenu = autofree(scene.instantiate())
	add_child_autofree(menu)
	# MainMenu._ready() opens the real LAN listener; close it so another shard's
	# live host cannot fill this test's game list (Bontago-1pi.44).
	Net.stop_discovery()
	var fake: FakeNet = FakeNet.new()
	menu.net_provider = fake
	return menu


func _fake_of(menu: MainMenu) -> FakeNet:
	return menu.net_provider as FakeNet


## Bontago-1pi.15.1: this file's own gamepad-A test below routes a real
## InputEventJoypadButton through Input.parse_input_event(), which flips the
## Settings autoload's own active_input_device() to DEVICE_GAMEPAD as a side
## effect -- reset it so a later test file in the same run doesn't inherit
## gamepad mode from this one (tests/unit/test_options_menu.gd's own
## after_each() already does this for its own gamepad tests).
func after_each() -> void:
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)
	Net.stop_discovery()


# --- parse_address (static, no scene tree needed) ---------------------------

func test_parse_address_accepts_bare_ip() -> void:
	var result: Dictionary = MainMenu.parse_address("1.2.3.4")
	assert_true(result.get("valid"))
	assert_eq(result.get("address"), "1.2.3.4")
	assert_eq(result.get("port"), 0)


func test_parse_address_accepts_ip_with_port() -> void:
	var result: Dictionary = MainMenu.parse_address("1.2.3.4:47999")
	assert_true(result.get("valid"))
	assert_eq(result.get("address"), "1.2.3.4")
	assert_eq(result.get("port"), 47999)


func test_parse_address_rejects_junk() -> void:
	var junk_values: PackedStringArray = [
		"", "not an ip", "1.2.3", "1.2.3.4.5", "1.2.3.999", "1.2.3.4:notaport", "1.2.3.4:0", "1.2.3.4:99999",
	]
	for junk: String in junk_values:
		var result: Dictionary = MainMenu.parse_address(junk)
		assert_false(result.get("valid"), "%s should be rejected" % junk)


# --- Host / Join / Quit -------------------------------------------------------

func test_host_button_opens_transport_dialog_before_hosting() -> void:
	var menu: MainMenu = _make_menu()
	menu._on_host_pressed()
	assert_true(menu._host_dialog.visible)
	assert_eq(_fake_of(menu).host_game_calls.size(), 0)
	menu._on_host_local_confirmed()
	assert_eq(_fake_of(menu).host_game_calls.size(), 1)


func test_play_offline_label() -> void:
	var menu: MainMenu = _make_menu()
	assert_eq((menu.get_node("%PlayLocalButton") as Button).text, "Play Offline")


func test_join_and_play_local_keep_discovery_off_the_front_page() -> void:
	var menu: MainMenu = _make_menu()
	assert_false((menu.get_node("%LanGamesWell") as Control).visible)
	menu._on_join_pressed()
	assert_true((menu.get_node("%LanGamesWell") as Control).visible)
	assert_true((menu.get_node("%JoinLanTabButton") as Button).has_focus())
	menu._on_back_pressed()
	menu._on_play_local_pressed()
	assert_false((menu.get_node("%LanGamesWell") as Control).visible)
	assert_true((menu.get_node("%BotsButton") as Button).visible)
	assert_true((menu.get_node("%SandboxButton") as Button).visible)
	assert_true((menu.get_node("%TutorialButton") as Button).visible)


func test_shoulders_switch_join_transport_tabs() -> void:
	var menu: MainMenu = _make_menu()
	_fake_of(menu).steam_available_value = true
	menu._apply_steam_availability()
	menu._on_join_pressed()
	var next_tab: InputEventAction = InputEventAction.new()
	next_tab.action = "menu_tab_next"
	next_tab.pressed = true
	menu._unhandled_input(next_tab)
	assert_true((menu.get_node("%SteamSection") as VBoxContainer).visible)
	var previous_tab: InputEventAction = InputEventAction.new()
	previous_tab.action = "menu_tab_previous"
	previous_tab.pressed = true
	menu._unhandled_input(previous_tab)
	assert_true((menu.get_node("%LanGamesWell") as Control).visible)


func test_cancel_returns_from_join_to_home() -> void:
	var menu: MainMenu = _make_menu()
	menu._on_join_pressed()
	var cancel: InputEventAction = InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	menu._unhandled_input(cancel)
	assert_true((menu.get_node("%HostButton") as Button).visible)
	assert_false((menu.get_node("%LanGamesWell") as Control).visible)


func test_bots_button_emits_player_name() -> void:
	var menu: MainMenu = _make_menu()
	watch_signals(menu)
	menu._on_bots_pressed()
	assert_signal_emitted(menu, "bots_requested")


# --- Sandbox (docs/archive/M6_PLAN.md package B1) ------------------------------------

## game/Main.gd owns the seam this button reaches (start_sandbox_from_menu()),
## the same "does not know about ... game/Main.gd" split ui/Lobby.gd's own
## start_requested signal uses (test_lobby.gd's
## test_start_pressed_emits_start_requested_only_when_ready): MainMenu only
## has to prove pressing %SandboxButton reaches its own signal, not that Main
## reacts to it (a separate, game/Main.gd-owned seam).
func test_sandbox_button_emits_sandbox_requested() -> void:
	var menu: MainMenu = _make_menu()
	watch_signals(menu)
	(menu.get_node("%SandboxButton") as Button).pressed.emit()
	assert_signal_emitted(menu, "sandbox_requested")


func test_direct_join_calls_join_game_with_parsed_address() -> void:
	var menu: MainMenu = _make_menu()
	(menu.get_node("%DirectIpEdit") as LineEdit).text = "10.0.0.5:47778"
	menu._on_direct_join_pressed()
	var calls: Array[Dictionary] = _fake_of(menu).join_game_calls
	assert_eq(calls.size(), 1)
	assert_eq(calls[0].get("address"), "10.0.0.5")
	assert_eq(calls[0].get("port"), 47778)


func test_direct_join_rejects_junk_without_calling_net() -> void:
	var menu: MainMenu = _make_menu()
	(menu.get_node("%DirectIpEdit") as LineEdit).text = "junk"
	menu._on_direct_join_pressed()
	assert_eq(_fake_of(menu).join_game_calls.size(), 0)


func test_join_failed_event_shows_a_message() -> void:
	var menu: MainMenu = _make_menu()
	Events.net_join_failed.emit(Net.JoinError.VERSION_MISMATCH, "Build version mismatch")
	assert_eq((menu.get_node("%StatusLabel") as Label).text, "Build version mismatch")


# --- LAN list ------------------------------------------------------------------

func test_games_discovered_populates_the_list() -> void:
	var menu: MainMenu = _make_menu()
	var games: Array[Dictionary] = [
		{"name": "Alice's game", "address": "192.168.1.10", "port": 47778, "players": 2, "max": 8},
	]
	Events.net_games_discovered.emit(games)
	var list: ItemList = menu.get_node("%GameList")
	assert_eq(list.item_count, 1)
	assert_true(list.get_item_text(0).contains("Alice's game"))


func test_games_discovered_can_shrink_the_list_back_to_empty() -> void:
	var menu: MainMenu = _make_menu()
	var one_game: Array[Dictionary] = [{"name": "A", "address": "1.2.3.4", "port": 1, "players": 1, "max": 8}]
	var no_games: Array[Dictionary] = []
	Events.net_games_discovered.emit(one_game)
	Events.net_games_discovered.emit(no_games)
	var list: ItemList = menu.get_node("%GameList")
	assert_eq(list.item_count, 0, "an expired advert should drop out of the list")


func test_activating_a_list_entry_joins_that_game() -> void:
	var menu: MainMenu = _make_menu()
	var games: Array[Dictionary] = [
		{"name": "Bob's game", "address": "192.168.1.20", "port": 47778, "players": 1, "max": 8},
	]
	Events.net_games_discovered.emit(games)
	menu._on_game_activated(0)
	var calls: Array[Dictionary] = _fake_of(menu).join_game_calls
	assert_eq(calls.size(), 1)
	assert_eq(calls[0].get("address"), "192.168.1.20")


# --- Steam section (docs/archive/M3b_PLAN.md P3) --------------------------------------

func test_steam_choices_follow_availability_on_host_and_join_pages() -> void:
	var menu: MainMenu = _make_menu()
	var fake: FakeNet = _fake_of(menu)
	fake.steam_available_value = false
	menu._apply_steam_availability()
	assert_true(menu._host_steam_choice.disabled)
	menu._on_join_pressed()
	assert_false((menu.get_node("%SteamSection") as VBoxContainer).visible)
	assert_true((menu.get_node("%LanGamesWell") as Control).visible)
	fake.steam_available_value = true
	menu._apply_steam_availability()
	menu._on_join_steam_tab_pressed()
	assert_false(menu._host_steam_choice.disabled)
	assert_true((menu.get_node("%SteamSection") as VBoxContainer).visible)
	assert_false((menu.get_node("%LanGamesWell") as Control).visible)


func test_host_online_button_calls_host_online() -> void:
	var menu: MainMenu = _make_menu()
	menu._on_host_online_pressed()
	assert_eq(_fake_of(menu).host_online_calls.size(), 1)


func test_steam_lobbies_discovered_populates_the_list() -> void:
	var menu: MainMenu = _make_menu()
	var lobbies: Array[Dictionary] = [
		{"lobby_id": 555, "name": "Alice's lobby", "players": 2, "max": 8, "map": "Round"},
	]
	Events.net_steam_lobbies_discovered.emit(lobbies)
	var list: ItemList = menu.get_node("%SteamLobbyList")
	assert_eq(list.item_count, 1)
	assert_true(list.get_item_text(0).contains("Alice's lobby"))


func test_activating_a_steam_list_entry_joins_that_lobby() -> void:
	var menu: MainMenu = _make_menu()
	var lobbies: Array[Dictionary] = [
		{"lobby_id": 777, "name": "Bob's lobby", "players": 1, "max": 8, "map": "Oval"},
	]
	Events.net_steam_lobbies_discovered.emit(lobbies)
	menu._on_steam_lobby_activated(0)
	var calls: Array[Dictionary] = _fake_of(menu).join_lobby_calls
	assert_eq(calls.size(), 1)
	assert_eq(calls[0].get("lobby_id"), 777)


func test_refresh_steam_button_calls_refresh_lobby_list() -> void:
	var menu: MainMenu = _make_menu()
	menu._on_refresh_steam_pressed()
	assert_eq(_fake_of(menu).refresh_lobby_list_calls, 1)


# --- Gamepad parity (Bontago-1pi.15.1: "gamepad works in some menus but not
# all") ------------------------------------------------------------------------
#
# Drives real InputEventJoypadButton press+release through Input.
# parse_input_event() -- the actual InputMap route a real controller takes,
# not a synthetic InputEventAction -- so these prove tools/bootstrap_project.
# gd's ui_accept/ui_cancel gamepad bindings actually reach this menu, the same
# real-binding technique tests/unit/test_pause_menu.gd's own
# test_gamepad_start_toggles_visibility() already uses for pause_menu.

func _pad_press_and_release(button: JoyButton) -> void:
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


func test_dpad_up_from_first_action_reaches_player_name() -> void:
	var menu: MainMenu = _make_menu()
	var host: Button = menu.get_node("%HostButton") as Button
	assert_eq(host.get_node(host.focus_neighbor_top), menu.get_node("%NameEdit"))
	menu._on_join_pressed()
	var join_tab: Button = menu.get_node("%JoinLanTabButton") as Button
	assert_eq(join_tab.get_node(join_tab.focus_neighbor_top), menu.get_node("%NameEdit"))


func test_opening_grabs_focus_on_the_host_button() -> void:
	var menu: MainMenu = _make_menu()
	assert_not_null(get_viewport().gui_get_focus_owner(), "the menu must land focus somewhere as soon as it opens.")
	assert_true(menu._host_button.has_focus(), "Host is the menu's own first/primary action.")


func test_gamepad_a_activates_the_focused_host_button() -> void:
	var menu: MainMenu = _make_menu()
	await get_tree().process_frame
	menu._host_button.grab_focus()
	_pad_press_and_release(JOY_BUTTON_A)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(menu._host_dialog.visible, "gamepad A on Host must open its transport choices.")
	assert_eq(_fake_of(menu).host_game_calls.size(), 0, "hosting needs an explicit transport choice.")


## Bontago-mp0.18: the card's minimum width exceeds the anchored column at
## 16:9, which used to push it off the left edge.
func test_front_card_keeps_left_margin_at_1280x720() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)
	var scene: PackedScene = load("res://ui/MainMenu.tscn")
	var menu: MainMenu = scene.instantiate()
	menu.net_provider = FakeNet.new()
	viewport.add_child(menu)
	Net.stop_discovery() # _ready() reopened the real LAN listener (Bontago-1pi.44)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gte(menu._front_card.get_global_rect().position.x, menu.tuning.menu_card_left_margin_px - 0.5)
