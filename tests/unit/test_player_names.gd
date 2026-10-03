extends GutTest
## Bontago-1pi.49 (owner playtest 2026-10-03: "names reset between menus and
## they don't show up in loading screen or in-game"): the typed name persists in
## Settings and prefills the menu, reaches the host, is validated there and is
## replicated to every roster, and the loading screen / HUD show each slot's
## name (bots keep their label).
##
## Real ENet between two independent Net nodes (test_net_session.gd's pattern)
## for the wire half; FakeNet / name_provider for the UI half.

const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")
const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")

var _cfg_path: String
var _nodes: Array[Node] = []
var _tiny_map: MapDef


func before_each() -> void:
	_cfg_path = OS.get_user_data_dir().path_join("test_player_names_tmp.cfg")
	_delete_if_exists(_cfg_path)
	# The menu talks to the real Settings autoload: start every test unnamed.
	Settings.set_player_name("")
	# The HUD/loading-screen tests read the real Match singleton by default.
	Match.abort_match()


func after_each() -> void:
	Settings.set_player_name("")
	# The slot-name tests below start real matches on the Match autoload.
	Net.leave()
	Match.set_net_provider(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	_delete_if_exists(_cfg_path)
	for node: Node in _nodes:
		if node != null and is_instance_valid(node):
			node.leave()
	_nodes.clear()
	# Net._reject_peer() closes a refused connection two frames later.
	await get_tree().process_frame
	await get_tree().process_frame


func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _max_len() -> int:
	return (load("res://config/net_config.tres") as NetConfig).max_player_name_length


# --- PlayerNames (pure rules) ----------------------------------------------------

func test_clean_trims_and_strips_control_characters() -> void:
	assert_eq(PlayerNames.clean("  Zed  ", 16), "Zed")
	assert_eq(PlayerNames.clean("Zed\tthe\nGreat\u0007", 32), "ZedtheGreat", "tab/newline/bell removed")
	assert_eq(PlayerNames.clean("\u202eevil\u200b", 16), "evil", "bidi override and zero-width removed")
	assert_eq(PlayerNames.clean("\u007F\u0085", 16), "", "DEL and C1 controls removed")
	assert_eq(PlayerNames.clean("Ana María", 16), "Ana María", "ordinary text and inner spaces are kept")


func test_clean_truncates_to_the_max_length_and_trims_the_cut() -> void:
	assert_eq(PlayerNames.clean("ABCDEFGHIJ", 4), "ABCD")
	assert_eq(PlayerNames.clean("AB   CDEF", 3), "AB", "a cut that ends on a space is trimmed")
	assert_eq(PlayerNames.clean("ABC", 0), "A", "a non-positive limit is one character, never unlimited")


func test_sanitize_falls_back_to_player_n_and_spectator() -> void:
	assert_eq(PlayerNames.sanitize("", 16, 0), "Player 1")
	assert_eq(PlayerNames.sanitize("  \t ", 16, 2), "Player 3")
	assert_eq(PlayerNames.sanitize("", 16, -1), PlayerNames.SPECTATOR_FALLBACK)
	assert_eq(PlayerNames.sanitize("Ann", 16, 2), "Ann")


func test_label_for_slot_prefers_the_peer_name_but_never_renames_a_bot() -> void:
	assert_eq(PlayerNames.label_for_slot(1, "Player 2", false, "Mira"), "Mira")
	assert_eq(PlayerNames.label_for_slot(1, "Player 2", false, ""), "Player 2", "no peer: the slot's own label")
	assert_eq(PlayerNames.label_for_slot(3, "Player 4", true, "Mira"), "Player 4", "a bot keeps its label")
	assert_eq(PlayerNames.label_for_slot(2, "", false, ""), "Player 3", "nothing at all: Player N")


# --- Settings ---------------------------------------------------------------------

func _fresh_settings() -> Node:
	var settings: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(settings)
	settings.set_config_path_for_test(_cfg_path)
	return settings


func test_settings_name_defaults_empty_and_survives_a_restart() -> void:
	var settings: Node = _fresh_settings()
	assert_eq(settings.player_name(), "", "never set: empty, so the host seats the player as Player N")
	settings.set_player_name("  Mira\t ")
	assert_eq(settings.player_name(), "Mira", "cleaned on the way in")
	var restarted: Node = _fresh_settings()
	assert_eq(restarted.player_name(), "Mira", "a fresh Settings reading the same file sees it")


func test_settings_name_is_capped_by_the_net_config_limit() -> void:
	var settings: Node = _fresh_settings()
	settings.set_player_name("X".repeat(_max_len() + 20))
	assert_eq(settings.player_name().length(), _max_len())
	assert_eq(_fresh_settings().player_name().length(), _max_len())


func test_settings_name_emits_only_on_a_real_change() -> void:
	var settings: Node = _fresh_settings()
	watch_signals(settings)
	settings.set_player_name("Mira")
	settings.set_player_name("  Mira ")
	assert_signal_emit_count(settings, "player_name_changed", 1)
	assert_signal_emitted_with_parameters(settings, "player_name_changed", ["Mira"])


# --- Main menu --------------------------------------------------------------------

func _make_menu() -> MainMenu:
	var menu: MainMenu = autofree(load("res://ui/MainMenu.tscn").instantiate())
	add_child_autofree(menu)
	Net.stop_discovery()
	menu.net_provider = FakeNet.new()
	return menu


func _name_edit(menu: MainMenu) -> LineEdit:
	return menu.get_node("%NameEdit") as LineEdit


func _type(menu: MainMenu, text: String) -> void:
	var edit: LineEdit = _name_edit(menu)
	edit.text = text
	edit.text_changed.emit(text)


func test_menu_starts_empty_for_a_new_player() -> void:
	var menu: MainMenu = _make_menu()
	assert_eq(_name_edit(menu).text, "", "no pre-typed name: the placeholder shows")
	assert_eq(menu._player_name(), "", "and nothing is sent, so the host assigns Player N")


func test_typed_name_persists_across_menu_pages_and_a_rebuilt_menu() -> void:
	var menu: MainMenu = _make_menu()
	_type(menu, "Mira")
	assert_eq(Settings.player_name(), "Mira", "every edit is saved")

	menu._on_join_pressed()
	assert_eq(_name_edit(menu).text, "Mira", "the Join page shows the same name")
	menu._on_back_pressed()
	menu._on_play_local_pressed()
	menu._on_back_pressed()
	assert_eq(_name_edit(menu).text, "Mira", "back on Home it is still there")

	var rebuilt: MainMenu = _make_menu()
	assert_eq(_name_edit(rebuilt).text, "Mira", "a menu built later (after a match or the lobby) is prefilled")
	assert_eq(rebuilt._player_name(), "Mira")


func test_editing_the_name_updates_settings() -> void:
	var menu: MainMenu = _make_menu()
	_type(menu, "Mira")
	_type(menu, "Mirabel")
	assert_eq(Settings.player_name(), "Mirabel")
	_type(menu, "")
	assert_eq(Settings.player_name(), "", "clearing the field clears the saved name")


func test_trailing_space_while_typing_is_not_rewritten() -> void:
	var menu: MainMenu = _make_menu()
	_type(menu, "Ana ")
	assert_eq(_name_edit(menu).text, "Ana ", "the field keeps the space the player just typed")
	assert_eq(Settings.player_name(), "Ana")


func test_menu_follows_a_name_changed_elsewhere() -> void:
	var menu: MainMenu = _make_menu()
	Settings.set_player_name("Pip")
	assert_eq(_name_edit(menu).text, "Pip")


func test_name_field_is_capped_by_the_config_limit() -> void:
	var menu: MainMenu = _make_menu()
	assert_eq(_name_edit(menu).max_length, _max_len())


func test_host_and_join_send_the_saved_name() -> void:
	var menu: MainMenu = _make_menu()
	_type(menu, "  Mira ")
	var fake: FakeNet = menu.net_provider as FakeNet
	menu._on_host_local_confirmed()
	assert_eq(fake.host_game_calls.size(), 1)
	assert_eq(fake.host_game_calls[0]["player_name"], "Mira")
	menu._direct_ip_edit.text = "127.0.0.1"
	menu._on_direct_join_pressed()
	assert_eq(fake.join_game_calls.size(), 1)
	assert_eq(fake.join_game_calls[0]["player_name"], "Mira")


func test_bots_request_carries_the_saved_name() -> void:
	var menu: MainMenu = _make_menu()
	_type(menu, "Mira")
	watch_signals(menu)
	menu._on_bots_pressed()
	assert_signal_emitted_with_parameters(menu, "bots_requested", ["Mira"])


# --- Net: host validation and replication (real ENet) ------------------------------

func _make_side(node_name: String) -> Variant:
	var node: Node = _NET_SCRIPT.new()
	node.name = node_name
	var path: NodePath = NodePath(String(get_path()) + "/" + node_name)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), path)
	add_child_autofree(node)
	_nodes.append(node)
	return node


func _wait_until(condition: Callable, frames: int = 200) -> bool:
	for _i: int in range(frames):
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


## A loopback host plus one client that sends `client_name`; waits for the
## client's seat. Returns [host, client, port].
func _lobby_with_client(host_name: String, client_name: String) -> Array[Variant]:
	var host: Variant = _make_side("HostNet")
	var client: Variant = _make_side("ClientNet")
	var port: int = AgentProbe.free_udp_port()
	assert_eq(host.host_game(port, host_name, false), OK)
	host.set_accepting_joins(true)
	assert_eq(client.join_game("127.0.0.1", port, client_name), OK)
	var seated: bool = await _wait_until(func() -> bool:
		return client.local_slot() == 1 and client.peer_ids().size() == 2
	)
	assert_true(seated, "the client is seated and has the roster")
	return [host, client, port]


func test_client_name_reaches_the_host_and_both_rosters_and_slot_lookups() -> void:
	var sides: Array[Variant] = await _lobby_with_client("Hostie", "Clienty")
	var host: Variant = sides[0]
	var client: Variant = sides[1]
	assert_eq(host.peer_info(client.local_peer_id())["name"], "Clienty", "the host has the joiner's name")
	assert_eq(client.peer_info(client.local_peer_id())["name"], "Clienty", "and so does the joiner's own roster")
	assert_eq(client.peer_info(Net.HOST_PEER_ID)["name"], "Hostie", "the joiner sees the host's name")
	assert_eq(host.name_for_slot(0), "Hostie")
	assert_eq(host.name_for_slot(1), "Clienty")
	assert_eq(client.name_for_slot(0), "Hostie", "loading screen/HUD read the same names on the client")
	assert_eq(client.name_for_slot(1), "Clienty")
	assert_eq(host.name_for_slot(5), "", "no peer: no name")
	assert_eq(host.name_for_slot(-1), "")


func test_roster_changed_payload_carries_names_for_the_lobby() -> void:
	var host: Variant = _make_side("HostNet")
	var client: Variant = _make_side("ClientNet")
	var port: int = AgentProbe.free_udp_port()
	watch_signals(Events)
	assert_eq(host.host_game(port, "Hostie", false), OK)
	host.set_accepting_joins(true)
	assert_eq(client.join_game("127.0.0.1", port, "Clienty"), OK)
	var landed: bool = await _wait_until(func() -> bool:
		return client.peer_ids().size() == 2 and get_signal_emit_count(Events, "net_roster_changed") >= 2
	)
	assert_true(landed)
	var names: Array[String] = []
	for index: int in range(get_signal_emit_count(Events, "net_roster_changed")):
		var roster: Array = get_signal_parameters(Events, "net_roster_changed", index)[0]
		for entry: Variant in roster:
			names.append(String((entry as Dictionary)["name"]))
	assert_true(names.has("Hostie"), "the host's row")
	assert_true(names.has("Clienty"), "the joiner's row, on host and client alike")


func test_host_sanitises_a_hostile_handshake_name() -> void:
	var host: Variant = _make_side("HostNet")
	var client: Variant = _make_side("ClientNet")
	var port: int = AgentProbe.free_udp_port()
	assert_eq(host.host_game(port, "Hostie", false), OK)
	host.set_accepting_joins(true)
	assert_eq(client.join_game("127.0.0.1", port, "Clienty"), OK)
	# A tampered client skips its own cleaning: overwrite what the handshake sends.
	var hostile: String = "\u202e  Mal\tlory\n" + "Z".repeat(_max_len() * 3)
	client._pending_join_name = hostile
	var seated: bool = await _wait_until(func() -> bool:
		return client.local_slot() == 1 and client.peer_ids().size() == 2
	)
	assert_true(seated)
	var stored: String = host.peer_info(client.local_peer_id())["name"]
	assert_lte(stored.length(), _max_len(), "cut to the configured maximum")
	assert_true(stored.begins_with("Mallory"), "control and bidi characters stripped: %s" % stored)
	assert_eq(stored, PlayerNames.clean(hostile, _max_len()), "and exactly what the shared rule produces")
	assert_eq(client.peer_info(client.local_peer_id())["name"], stored, "replicated to the client unchanged")


func test_empty_names_fall_back_to_player_n_per_seat() -> void:
	var sides: Array[Variant] = await _lobby_with_client("", "")
	var host: Variant = sides[0]
	var client: Variant = sides[1]
	assert_eq(host.peer_info(Net.HOST_PEER_ID)["name"], "Player 1", "an unnamed host is Player 1")
	assert_eq(host.peer_info(client.local_peer_id())["name"], "Player 2", "an unnamed joiner takes its seat number")
	assert_eq(client.name_for_slot(1), "Player 2")


func test_a_whitespace_only_name_is_treated_as_empty() -> void:
	var sides: Array[Variant] = await _lobby_with_client("Hostie", "   \t ")
	assert_eq(sides[0].peer_info(sides[1].local_peer_id())["name"], "Player 2")


func test_join_event_carries_the_checked_name_on_both_ends() -> void:
	var host: Variant = _make_side("HostNet")
	var client: Variant = _make_side("ClientNet")
	var port: int = AgentProbe.free_udp_port()
	assert_eq(host.host_game(port, "Hostie", false), OK)
	host.set_accepting_joins(true)
	watch_signals(Events)
	assert_eq(client.join_game("127.0.0.1", port, "  Clienty\t"), OK)
	var landed: bool = await _wait_until(func() -> bool:
		return client.local_slot() == 1 and get_signal_emit_count(Events, "net_peer_joined") >= 2
	)
	assert_true(landed)
	for index: int in range(get_signal_emit_count(Events, "net_peer_joined")):
		assert_eq(get_signal_parameters(Events, "net_peer_joined", index)[2], "Clienty")


func test_mid_match_joiner_and_rejoiner_get_their_names_through_the_roster() -> void:
	var host: Variant = _make_side("HostNet")
	var client: Variant = _make_side("ClientNet")
	var port: int = AgentProbe.free_udp_port()
	assert_eq(host.host_game(port, "Hostie", false), OK)
	host.set_accepting_joins(true)
	assert_eq(client.join_game("127.0.0.1", port, "Clienty"), OK)
	var seated: bool = await _wait_until(func() -> bool: return client.local_slot() == 1)
	assert_true(seated)
	var reclaim_ok: Array[bool] = [true]
	host.set_seat_policy(func() -> int: return 2, func(_slot: int) -> bool: return reclaim_ok[0])
	host.set_match_in_progress(true)
	host.set_accepting_joins(true)

	# A late joiner takes the open seat under its own name; the old client learns it.
	var late: Variant = _make_side("LateNet")
	assert_eq(late.join_game("127.0.0.1", port, "Latey"), OK)
	var late_in: bool = await _wait_until(func() -> bool:
		return late.local_slot() == 2 and client.name_for_slot(2) == "Latey" and late.name_for_slot(1) == "Clienty"
	)
	assert_true(late_in, "the late joiner gets every name, and the others get its name")
	assert_eq(late.name_for_slot(0), "Hostie")

	# The seated client drops and comes back under a new typed name: its seat is
	# reclaimed and the roster carries the new name to everyone.
	var token: String = client.rejoin_token()
	assert_ne(token, "")
	client.leave(false)
	var gone: bool = await _wait_until(func() -> bool: return host.name_for_slot(1) == "")
	assert_true(gone, "no peer holds seat 1 while the player is away")
	assert_eq(client.join_game("127.0.0.1", port, "Cli2"), OK)
	var back: bool = await _wait_until(func() -> bool:
		return client.local_slot() == 1 and late.name_for_slot(1) == "Cli2" and host.name_for_slot(1) == "Cli2"
	)
	assert_true(back, "the rejoiner's seat is back under its current name on every roster")
	assert_eq(client.name_for_slot(2), "Latey")


# --- Loading screen and HUD -------------------------------------------------------

func _slots(count: int, bot_from: int = -1) -> Array[PlayerSlot]:
	var slots: Array[PlayerSlot] = []
	for i: int in range(count):
		var slot_item: PlayerSlot = PlayerSlot.new(i, i, "Player %d" % (i + 1), Color.WHITE)
		slot_item.is_bot = bot_from >= 0 and i >= bot_from
		slots.append(slot_item)
	return slots


func _named_fake(names: Dictionary) -> FakeNet:
	var fake: FakeNet = FakeNet.new()
	for slot_id: Variant in names.keys():
		fake.slots_by_peer[int(slot_id) + 1] = int(slot_id)
		fake.names_by_peer[int(slot_id) + 1] = String(names[slot_id])
	return fake


func test_loading_screen_lists_each_slots_name_and_keeps_bot_labels() -> void:
	var screen: LoadingScreen = autofree(load("res://ui/LoadingScreen.tscn").instantiate())
	add_child_autofree(screen)
	screen.name_provider = _named_fake({0: "Mira", 1: "Zed"})
	var slots: Array[PlayerSlot] = _slots(4, 2)
	screen.show_for_match(MatchConfig.new(), slots)
	var lines: PackedStringArray = screen._info_label.text.split("\n")
	assert_eq(lines.size(), 4)
	assert_eq(lines[0], "Mira")
	assert_eq(lines[1], "Zed")
	assert_eq(lines[2], "Player 3" + screen.tuning.bot_suffix, "bots keep their label")
	assert_eq(lines[3], "Player 4" + screen.tuning.bot_suffix)
	assert_eq(screen._slot_label_text(slots[0]), "Mira", "the ready-list rows use the same label")


func test_loading_screen_falls_back_to_the_slot_label_when_no_peer_holds_a_seat() -> void:
	var screen: LoadingScreen = autofree(load("res://ui/LoadingScreen.tscn").instantiate())
	add_child_autofree(screen)
	screen.name_provider = _named_fake({0: "Mira"})
	assert_eq(screen._slot_label_text(_slots(3)[2]), "Player 3", "an empty human seat stays Player N")


func test_hud_turn_label_shows_the_slots_name() -> void:
	var hud: HUD = autofree(load("res://ui/HUD.tscn").instantiate())
	add_child_autofree(hud)
	hud.name_provider = _named_fake({0: "Mira", 1: "Zed"})
	hud.set_local_slot(1)
	assert_eq(hud._turn_label.text, "Zed")
	hud.set_local_slot(0)
	assert_eq(hud._turn_label.text, "Mira")
	hud.set_local_slot(3)
	assert_eq(hud._turn_label.text, "Player 4", "no peer on the seat: Player N")


func test_hud_bot_slot_keeps_its_label() -> void:
	var hud: HUD = autofree(load("res://ui/HUD.tscn").instantiate())
	add_child_autofree(hud)
	var fake_match: FakeMatch = FakeMatch.new()
	var bot: PlayerSlot = PlayerSlot.new(1, 1, "Bot 1", Color.WHITE)
	bot.is_bot = true
	fake_match.slots_by_id[1] = bot
	hud.match_provider = fake_match
	hud.name_provider = _named_fake({1: "ShouldNotShow"})
	hud.set_local_slot(1)
	assert_eq(hud._turn_label.text, "Bot 1")


# --- Slot display names: what Results and every PlayerSlot reader show -----------
# Follow-up of Bontago-1pi.49: MatchLifecycle._build_slots() used to seed every
# slot "Player N", so the host's results (MatchStats reads PlayerSlot.display_name)
# ignored the names the loading screen and HUD already showed.

func _register_world() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	var field: Field = autofree(Field.new())
	field.map_def = _tiny_map
	add_child_autofree(field)
	var blocks_root: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks_root)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	Match.register_world(field, registry, blocks_root)


func _tiny_config(player_count: int, ai_count: int = 0, hot_seat: bool = false) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.ai_count = ai_count
	config.hot_seat = hot_seat
	config.rng_seed = 24680
	return config


func _slot_names() -> Array[String]:
	var names: Array[String] = []
	for slot_id: int in range(Match.slot_count()):
		names.append(Match.slot(slot_id).display_name)
	return names


func test_host_slots_are_seeded_from_the_roster_and_bots_keep_their_label() -> void:
	_register_world()
	var fake: FakeNet = _named_fake({0: "Mira", 1: "Zed", 3: "ShouldNotShow"})
	Match.set_net_provider(fake)
	Match.start_match(_tiny_config(4, 1))
	assert_eq(Match.slot_count(), 4)
	assert_true(Match.slot(3).is_bot, "fixture: the trailing slot is the bot")
	assert_eq(_slot_names(), ["Mira", "Zed", "Player 3", "Player 4"] as Array[String], "named humans, an unheld human seat and a bot")


func test_client_builds_the_same_slot_names_from_its_replicated_roster() -> void:
	_register_world()
	var names: Dictionary = {0: "Mira", 1: "Zed"}
	var client_net: FakeNet = _named_fake(names)
	client_net.is_host_value = false
	client_net.is_client_value = true
	client_net.is_offline_value = false
	client_net.mode_value = 2
	client_net.local_slot_value = 1
	Match.set_net_provider(client_net)
	Match.start_match(_tiny_config(3))
	var client_names: Array[String] = _slot_names()
	Match.abort_match()
	Match.set_net_provider(_named_fake(names))
	Match.start_match(_tiny_config(3))
	assert_eq(client_names, _slot_names(), "host and client agree slot by slot")
	assert_eq(client_names, ["Mira", "Zed", "Player 3"] as Array[String])


func test_hot_seat_offline_keeps_player_n() -> void:
	_register_world()
	Match.set_net_provider(null)
	assert_true(Net.is_offline(), "fixture: the real Net is offline")
	Match.start_match(_tiny_config(3, 0, true))
	assert_eq(_slot_names(), ["Player 1", "Player 2", "Player 3"] as Array[String])


func test_real_host_session_names_its_own_slot_and_checks_the_name() -> void:
	_register_world()
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "  Hostie	", false), OK)
	Match.set_net_provider(null)
	Match.start_match(_tiny_config(3, 2))
	assert_eq(_slot_names(), ["Hostie", "Player 2", "Player 3"] as Array[String], "the host's sanitised name on slot 0, bots keep Player N")


func test_unnamed_real_host_is_player_one() -> void:
	_register_world()
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "", false), OK)
	Match.start_match(_tiny_config(2, 1))
	assert_eq(_slot_names(), ["Player 1", "Player 2"] as Array[String])


func test_session_double_without_a_name_roster_leaves_the_default_labels() -> void:
	_register_world()
	var bare: BareHost = BareHost.new()
	Match.set_net_provider(bare)
	assert_eq(Match._lifecycle._peer_name_for_slot(0), "", "a double with no name_for_slot is not an error")


## A session double that only knows is_host(): the shape several older tests give Match.
class BareHost:
	extends RefCounted

	func is_host() -> bool:
		return true


func test_roster_change_mid_match_names_a_new_seat_holder_and_keeps_a_departed_name() -> void:
	_register_world()
	var fake: FakeNet = _named_fake({0: "Mira", 1: "Zed"})
	Match.set_net_provider(fake)
	Match.start_match(_tiny_config(4, 1))
	assert_eq(_slot_names(), ["Mira", "Zed", "Player 3", "Player 4"] as Array[String])
	# A late joiner takes seat 2; Zed leaves; a roster entry for the bot's seat is ignored.
	fake.slots_by_peer[9] = 2
	fake.names_by_peer[9] = "Latey"
	fake.slots_by_peer.erase(2)
	fake.names_by_peer.erase(2)
	fake.slots_by_peer[10] = 3
	fake.names_by_peer[10] = "ShouldNotShow"
	var roster: Array[Dictionary] = []
	Events.net_roster_changed.emit(roster)
	assert_eq(_slot_names(), ["Mira", "Zed", "Latey", "Player 4"] as Array[String], "new holder named, departed player keeps the name, bot untouched")


func test_results_payload_and_screen_show_the_real_names() -> void:
	_register_world()
	Match.set_net_provider(_named_fake({0: "Mira", 1: "Zed"}))
	Match.start_match(_tiny_config(2))
	var payload: Dictionary = Match.stats().build_results_payload(1)
	assert_eq(String(payload["winner_name"]), "Zed", "FFA winner is named, not Player 2")
	var rows: Array = payload["rows"]
	assert_eq(String((rows[0] as Dictionary)["name"]), "Mira")
	assert_eq(String((rows[1] as Dictionary)["name"]), "Zed")
	var screen: ResultsScreen = autofree(load("res://ui/ResultsScreen.tscn").instantiate())
	screen.net_provider = FakeNet.host()
	screen.match_net_provider = null
	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.config = MatchConfig.new()
	screen.match_provider = fake_match
	add_child_autofree(screen)
	screen.show_results(payload)
	assert_eq(screen._headline.text, "Zed wins!")
	var names_in_table: Array[String] = []
	for row_node: Node in screen._rows_list.get_children():
		for cell: Node in row_node.find_children("*", "Label", true, false):
			names_in_table.append((cell as Label).text)
	assert_true(names_in_table.has("Mira") and names_in_table.has("Zed"), "the stats table rows carry the real names: %s" % [names_in_table])
