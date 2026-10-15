extends GutTest
## Bontago-1pi.100: the local player's name defaults to the Steam persona name
## while Steam is initialised; a custom (typed/saved) name overrides it; without
## Steam only the stored name applies. FakeSteam only, no live Steam.

const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")

var _net: Variant


func before_each() -> void:
	_net = _NET_SCRIPT.new()
	add_child_autofree(_net)


func after_each() -> void:
	Match.set_net_provider(null)
	if _net != null and is_instance_valid(_net):
		_net.leave()


func _steam_up(persona: String) -> FakeSteam:
	var fake: FakeSteam = FakeSteam.new()
	fake.local_persona_name_value = persona
	_net.steam_provider = fake
	_net.init_steam()
	return fake


func _host_lobby_name(typed: String, fake: FakeSteam) -> String:
	assert_eq(_net.host_online(typed), OK)
	fake.lobby_created.emit(FakeSteam.RESULT_OK, 77)
	return fake.get_lobby_data(77, String(SteamClient.KEY_HOST_NAME))


func test_persona_used_when_steam_up_and_no_custom_name() -> void:
	var fake: FakeSteam = _steam_up("PersonaPat")
	assert_eq(_net.resolve_local_name(""), "PersonaPat")
	assert_eq(_host_lobby_name("", fake), "PersonaPat")


func test_persona_beats_typed_name_when_steam_up() -> void:
	var fake: FakeSteam = _steam_up("PersonaPat")
	assert_eq(_net.resolve_local_name("Zed"), "PersonaPat")
	assert_eq(_host_lobby_name("Zed", fake), "PersonaPat")


func test_stored_name_used_without_steam_and_empty_stays_empty() -> void:
	var fake: FakeSteam = FakeSteam.new()
	fake.available_value = false
	fake.local_persona_name_value = "PersonaPat"
	_net.steam_provider = fake
	_net.init_steam()
	assert_eq(_net.resolve_local_name("Zed"), "Zed")
	assert_eq(_net.resolve_local_name(""), "", "no Steam: the host seats Player N")


func test_persona_is_sanitised_like_any_name() -> void:
	var fake: FakeSteam = _steam_up("  Evil\u202e\u0007Pat  ")
	assert_eq(_host_lobby_name("", fake), "EvilPat")
	var long_name: String = "x".repeat(500)
	fake.local_persona_name_value = long_name
	assert_eq(PlayerNames.sanitize(_net.resolve_local_name(""), _net.config.max_player_name_length, 0).length(),
		_net.config.max_player_name_length)


func test_lan_host_and_join_use_persona_when_steam_up() -> void:
	_steam_up("PersonaPat")
	assert_eq(_net.host_game(AgentProbe.free_udp_port(), "Zed", false), OK)
	assert_eq(_net.name_for_slot(0), "PersonaPat", "LAN host seat uses the persona")
	_net.leave()
	assert_eq(_net.join_game("127.0.0.1", AgentProbe.free_udp_port(), "Zed"), OK)
	assert_eq(_net._pending_join_name, "PersonaPat")

