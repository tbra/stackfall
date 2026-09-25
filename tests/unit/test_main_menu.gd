extends GutTest
## docs/M3a_PLAN.md P4: ui/MainMenu.gd offers only Host / Join / Quit (owner
## decision: hot-seat is unlisted), a LAN game list fed by Events, and a
## direct-IP fallback (spec 3.4).


func _make_menu() -> MainMenu:
	var scene: PackedScene = load("res://ui/MainMenu.tscn")
	var menu: MainMenu = autofree(scene.instantiate())
	add_child_autofree(menu)
	var fake: FakeNet = FakeNet.new()
	menu.net_provider = fake
	return menu


func _fake_of(menu: MainMenu) -> FakeNet:
	return menu.net_provider as FakeNet


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

func test_host_button_calls_host_game() -> void:
	var menu: MainMenu = _make_menu()
	menu._on_host_pressed()
	assert_eq(_fake_of(menu).host_game_calls.size(), 1)


# --- Sandbox (docs/M6_PLAN.md package B1) ------------------------------------

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


# --- Steam section (docs/M3b_PLAN.md P3) --------------------------------------

func test_steam_section_hidden_and_notice_shown_when_steam_unavailable() -> void:
	var menu: MainMenu = _make_menu()
	_fake_of(menu).steam_available_value = false
	menu._apply_steam_availability()
	assert_false((menu.get_node("%SteamSection") as VBoxContainer).visible)
	assert_true((menu.get_node("%SteamUnavailableLabel") as Label).visible)


func test_steam_section_shown_and_notice_hidden_when_steam_available() -> void:
	var menu: MainMenu = _make_menu()
	_fake_of(menu).steam_available_value = true
	menu._apply_steam_availability()
	assert_true((menu.get_node("%SteamSection") as VBoxContainer).visible)
	assert_false((menu.get_node("%SteamUnavailableLabel") as Label).visible)


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
