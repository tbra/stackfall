extends GutTest
## ui/menus/MainMenu.gd offers only Host / Join / Quit (hot-seat is unlisted), a LAN game list fed by Events, and a
## direct-IP fallback (spec 2.6).


func _make_menu() -> MainMenu:
	var scene: PackedScene = load("res://ui/menus/MainMenu.tscn")
	var menu: MainMenu = autofree(scene.instantiate())
	add_child_autofree(menu)
	# MainMenu._ready() opens the real LAN listener; close it so another shard's
	# live host cannot fill this test's game list.
	Net.stop_discovery()
	var fake: FakeNet = FakeNet.new()
	menu.net_provider = fake
	return menu


func _fake_of(menu: MainMenu) -> FakeNet:
	return menu.net_provider as FakeNet


## this file's own gamepad-A test below routes a real
## InputEventJoypadButton through Input.parse_input_event(), which flips the
## Settings autoload's own active_input_device() to DEVICE_GAMEPAD as a side
## effect -- reset it so a later test file in the same run doesn't inherit
## gamepad mode from this one (tests/unit/ui/test_options_menu.gd's own
## after_each() already does this for its own gamepad tests).
func after_each() -> void:
	Settings._input(InputEventKey.new())
	Net.stop_discovery()


# --- parse_address (static, no scene tree needed) ---------------------------

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


func test_bots_button_emits_player_name() -> void:
	var menu: MainMenu = _make_menu()
	watch_signals(menu)
	menu._on_bots_pressed()
	assert_signal_emitted(menu, "bots_requested")


# --- Sandbox ------------------------------------

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


# --- Steam section --------------------------------------

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
