extends GutTest
## Player names: saved name, handshake validation on the host, rosters and slot labels.

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
	Match._net_provider = null
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	_delete_if_exists(_cfg_path)
	for node: Node in _nodes:
		if node != null and is_instance_valid(node):
			node.leave()
	_nodes.clear()
	# The host closes a refused connection two frames after refusing it.
	await get_tree().process_frame
	await get_tree().process_frame


func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _max_len() -> int:
	return (load("res://config/net/net_config.tres") as NetConfig).max_player_name_length


# --- PlayerNames (pure rules) ----------------------------------------------------

func test_clean_trims_and_strips_control_characters() -> void:
	assert_eq(PlayerNames.clean("  Zed  ", 16), "Zed")
	assert_eq(PlayerNames.clean("Zed\tthe\nGreat\u0007", 32), "ZedtheGreat", "tab/newline/bell removed")
	assert_eq(PlayerNames.clean("\u202eevil\u200b", 16), "evil", "bidi override and zero-width removed")
	assert_eq(PlayerNames.clean("\u007F\u0085", 16), "", "DEL and C1 controls removed")
	assert_eq(PlayerNames.clean("Ana María", 16), "Ana María", "ordinary text and inner spaces are kept")


func test_sanitize_falls_back_to_player_n_and_spectator() -> void:
	assert_eq(PlayerNames.sanitize("", 16, 0), "Player 1")
	assert_eq(PlayerNames.sanitize("  \t ", 16, 2), "Player 3")
	assert_eq(PlayerNames.sanitize("", 16, -1), PlayerNames.SPECTATOR_FALLBACK)
	assert_eq(PlayerNames.sanitize("Ann", 16, 2), "Ann")


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


# --- Main menu --------------------------------------------------------------------

func _make_menu() -> MainMenu:
	var menu: MainMenu = autofree(load("res://ui/menus/MainMenu.tscn").instantiate())
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


func test_a_hostile_typed_name_is_stored_cut_and_cleaned_on_both_rosters() -> void:
	var hostile: String = "\u202e  Mal\tlory\n" + "Z".repeat(_max_len() * 3)
	var sides: Array[Variant] = await _lobby_with_client("Hostie", hostile)
	var host: Variant = sides[0]
	var client: Variant = sides[1]
	var stored: String = host.peer_info(client.local_peer_id())["name"]
	assert_lte(stored.length(), _max_len(), "cut to the configured maximum")
	assert_true(stored.begins_with("Mallory"), "control and bidi characters stripped: %s" % stored)
	assert_eq(stored, PlayerNames.clean(hostile, _max_len()), "and exactly what the shared rule produces")
	assert_eq(client.peer_info(client.local_peer_id())["name"], stored, "replicated to the client unchanged")


# --- Loading screen and HUD -------------------------------------------------------

func _named_fake(names: Dictionary) -> FakeNet:
	var fake: FakeNet = FakeNet.new()
	for slot_id: Variant in names.keys():
		fake.slots_by_peer[int(slot_id) + 1] = int(slot_id)
		fake.names_by_peer[int(slot_id) + 1] = String(names[slot_id])
	return fake


# --- Slot display names: what Results and every PlayerSlot reader show -----------
# Follow-up of MatchLifecycle._build_slots() used to seed every
# slot "Player N", so the host's results (MatchStats reads PlayerSlot.display_name)
# ignored the names the loading screen and HUD already showed.

func _register_world() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
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
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.ai_count = ai_count
	config.hot_seat = hot_seat
	config.rng_seed = 24680
	return config


const BOT_NAME: String = "<bot>"


func _slot_names() -> Array[String]:
	var names: Array[String] = []
	for slot_id: int in range(Match.slot_count()):
		var shown: String = Match.slot(slot_id).display_name
		# a bot carries a themed name from BotNames, never a human's.
		if Match.slot(slot_id).is_bot:
			assert_true(BotNames.all_names().has(shown), "bot slot %d name %s" % [slot_id, shown])
			shown = BOT_NAME
		names.append(shown)
	return names


func test_host_slots_are_seeded_from_the_roster_and_bots_keep_their_label() -> void:
	_register_world()
	var fake: FakeNet = _named_fake({0: "Mira", 1: "Zed", 3: "ShouldNotShow"})
	Match._net_provider = fake
	Match.start_match(_tiny_config(4, 1))
	assert_eq(Match.slot_count(), 4)
	assert_true(Match.slot(3).is_bot, "fixture: the trailing slot is the bot")
	assert_eq(_slot_names(), ["Mira", "Zed", "Player 3", BOT_NAME] as Array[String], "named humans, an unheld human seat and a bot")


## A session double that only knows is_host(): the shape several older tests give Match.
class BareHost:
	extends RefCounted

	func is_host() -> bool:
		return true


## -- single-player formats ------------------------------------
