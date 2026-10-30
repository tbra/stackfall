extends GutTest
## The colour diamond is ONE shared component used by the HUD
## share rows, the lobby seat rows and the round score table; plus the lobby's bot names,
## session badge, Advanced disclosure and one-row prompt.

const DIAMOND_SCENE: String = "res://ui/hud/SlotDiamond.tscn"


func _make_lobby(is_host: bool = true) -> Lobby:
	var lobby: Lobby = autofree((load("res://ui/lobby/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = is_host
	fake.is_offline_value = is_host
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func test_a_seeded_vs_bots_bot_gets_a_themed_name_not_bot_n() -> void:
	var lobby: Lobby = _make_lobby()
	var config: MatchConfig = MatchConfig.new()
	config.player_count = 2
	config.ai_count = 1
	var data: Dictionary = config.to_dict()
	data["roster"] = [{"peer_id": 1, "slot_id": 0, "name": "Host", "ready": true}]
	Events.net_lobby_data_changed.emit(data)
	lobby._republish_roster_if_host()
	var names: PackedStringArray = (lobby.get_node("%PlayersPanel") as LobbyPlayersPanel)._config.bot_names
	assert_eq(names.size(), 1)
	assert_false(names[0].begins_with("Bot "), names[0])
	assert_true(BotNames.all_names().has(names[0]))


func test_status_badge_names_the_session_kind() -> void:
	assert_eq(Lobby.status_badge_text(true, false, true), "Vs bots")
	assert_eq(Lobby.status_badge_text(true, false, false), "Hosting %s LAN" % char(0xB7))
	assert_eq(Lobby.status_badge_text(false, true, false), "Joined %s Steam" % char(0xB7))
	var lobby: Lobby = _make_lobby()
	var badge: Label = lobby.get_node("%StatusBadgeLabel") as Label
	lobby._update_status_badge()
	var hosted_text: String = badge.text
	(lobby.net_provider as FakeNet).is_private_session_value = true
	lobby._update_status_badge()
	assert_ne(badge.text, hosted_text, "a bot-only lobby shows a different badge from a hosted one")
	assert_ne(badge.text, "")
