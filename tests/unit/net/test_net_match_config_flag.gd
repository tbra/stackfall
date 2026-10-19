extends GutTest
## autoload/Net.gd: `--match-config=<path>` command-line flag (
## deferred from). Host-only override for the MatchConfig a
## `--headless-host` match starts from; extends the existing
## `_apply_command_line_args` parser rather than a parallel path.
##
## Same "independent Net instance" pattern as test_net_session.gd: Net.gd has
## no class_name (it must not collide with the `Net` autoload singleton), so
## each side below is built from the preloaded script and held through a
## `Variant`-typed reference, with its own MultiplayerAPI scoped to its own
## node path.

const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")

const _TURN_BASED_FIXTURE: String = "res://tests/support/fixtures/match_configs/turn_based.tres"
## Ports increment per test so a socket the OS hasn't fully released yet from
## the previous test can never collide with the next one. Chosen clear of the
## ranges already claimed by other *_next_port statics (see test_net_session.gd
## 47800, test_match_lifecycle.gd 47900, test_main.gd 48000,
## test_headless_bot_match.gd 48300, test_field_map_def.gd /
## test_hover_cap_real_match.gd 48700).
static var _next_port: int = 48900

var _node: Variant


func _make_side(node_name: String) -> Variant:
	var node: Node = _NET_SCRIPT.new()
	node.name = node_name
	var path: NodePath = NodePath(String(get_path()) + "/" + node_name)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), path)
	add_child_autofree(node)
	return node


func before_each() -> void:
	_node = _make_side("CmdNet")


func after_each() -> void:
	if _node != null:
		_node.leave()
	await get_tree().process_frame
	await get_tree().process_frame


func _take_port() -> int:
	# Parallel gate shards (tools/full_gate.py) run several Godot processes at
	# once; a fixed port sequence collided, so ask the OS for a free port.
	return AgentProbe.free_udp_port()


func test_match_config_flag_parsed_and_fixture_loaded() -> void:
	var started: bool = _node._apply_command_line_args(PackedStringArray([
		"--headless-host",
		"--port=%d" % _take_port(),
		"--match-config=%s" % _TURN_BASED_FIXTURE,
	]))
	assert_true(started)
	assert_eq(_node.mode(), Net.Mode.HOST)
	var override: MatchConfig = _node.match_config_override()
	assert_not_null(override)
	assert_true(override.turn_based)


func test_match_config_flag_wrong_path_falls_back_to_null() -> void:
	_node._apply_command_line_args(PackedStringArray([
		"--headless-host",
		"--port=%d" % _take_port(),
		"--match-config=res://tests/support/fixtures/match_configs/does_not_exist.tres",
	]))
	assert_push_error("no resource at that path", "a bad path must be logged, not silent")
	assert_null(_node.match_config_override())


func test_match_config_flag_ignored_without_host_flag() -> void:
	# A listener to join against so the --join branch actually runs (and can
	# be observed to ignore --match-config) rather than failing to connect.
	var host: Variant = _make_side("CmdNet_ListenHost")
	var host_port: int = _take_port()
	host._apply_command_line_args(PackedStringArray(["--headless-host", "--port=%d" % host_port]))

	_node._apply_command_line_args(PackedStringArray([
		"--join=127.0.0.1",
		"--port=%d" % host_port,
		"--match-config=%s" % _TURN_BASED_FIXTURE,
	]))
	assert_null(_node.match_config_override())

	host.leave()
	await get_tree().process_frame
	await get_tree().process_frame


## the playtest Steam launcher's --steam-public-lobby makes the
## host's Steam lobby Public on a private copy of the config.
func test_steam_public_lobby_flag_sets_public_lobby_type_on_a_copy() -> void:
	var shared: NetConfig = _node.config
	var started: bool = _node._apply_command_line_args(PackedStringArray(["--steam-public-lobby"]))
	assert_false(started, "the flag alone starts no session")
	assert_eq(_node.config.steam_lobby_type, NetConfig.STEAM_LOBBY_TYPE_PUBLIC)
	assert_ne(_node.config, shared, "the shared net_config.tres must not be mutated")
	assert_eq(shared.steam_lobby_type, 1, "shared default stays FriendsOnly")


# --- Net applies what NetCommandLine parsed ---------------------------------

func test_sim_flags_configure_the_simulator_without_starting_a_session() -> void:
	var started: bool = _node._apply_command_line_args(PackedStringArray(["--sim-lag=90", "--sim-loss=0.1"]))
	assert_false(started)
	assert_false(_node._sim.is_idle())
	_node.set_simulation(0.0, 0.0, 0.0)
	assert_true(_node._sim.is_idle())


func test_no_flags_start_nothing() -> void:
	assert_false(_node._apply_command_line_args(PackedStringArray()))
	assert_false(_node._apply_command_line_args(PackedStringArray(["--no-such-flag", "--port=abc"])))
	assert_eq(_node.mode(), Net.Mode.OFFLINE)


func test_host_flag_hosts_on_the_port_with_the_default_name_and_advertises() -> void:
	var port: int = _take_port()
	assert_true(_node._apply_command_line_args(PackedStringArray(["--host", "--port=%d" % port])))
	assert_eq(_node.mode(), Net.Mode.HOST)
	assert_eq(_node.host_port(), port)
	assert_eq(_node.peer_info(Net.HOST_PEER_ID)["name"], "Host")
	assert_true(_node._lan.is_advertising() or AgentProbe.is_active())


func test_headless_host_stays_off_the_lan_unless_advertise_and_takes_the_name() -> void:
	assert_true(_node._apply_command_line_args(PackedStringArray([
		"--headless-host", "--port=%d" % _take_port(), "--player-name=Botty",
	])))
	assert_false(_node._lan.is_advertising())
	assert_eq(_node.peer_info(Net.HOST_PEER_ID)["name"], "Botty")


func test_join_flag_splits_the_port_and_joins_as_a_client() -> void:
	var host: Variant = _make_side("CmdNet_JoinHost")
	var host_port: int = _take_port()
	host._apply_command_line_args(PackedStringArray(["--headless-host", "--port=%d" % host_port]))
	assert_true(_node._apply_command_line_args(PackedStringArray(["--join=127.0.0.1:%d" % host_port])))
	assert_eq(_node.mode(), Net.Mode.CLIENT)
	assert_eq(_node._join_scope, "enet:127.0.0.1:%d" % host_port)
	host.leave()
	await get_tree().process_frame
	await get_tree().process_frame


func test_connect_lobby_without_steam_does_not_join_on_a_bad_id() -> void:
	assert_false(_node._apply_connect_lobby_args(PackedStringArray(["+connect_lobby", "abc"])))
	assert_false(_node._apply_connect_lobby_args(PackedStringArray(["+connect_lobby", "0"])))
	assert_false(_node._apply_connect_lobby_args(PackedStringArray(["+connect_lobby"])))


# --- LAN advertising ---------------------------------------------------
