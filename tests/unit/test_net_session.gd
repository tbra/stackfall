extends GutTest
## autoload/Net.gd: session lifecycle, handshake, roster, disconnect and
## command-line parsing (spec 3.4, docs/M3a_PLAN.md P1).
##
## Net.gd has no class_name (it must not collide with the `Net` autoload
## singleton), so a second, independent instance of the same script cannot be
## declared with a named static type. Each side below is created from the
## preloaded script and held through a `Variant`-typed reference — an
## explicit type annotation (CLAUDE.md's "static typing everywhere" targets
## *untyped* declarations; `Variant` is a type), just one that defers member
## checks to runtime the way calling a singleton autoload by name always does.
##
## Two full, independent instances (not the shared `Net` autoload) so a test
## can play host and client in the same process without polluting the real
## singleton other suites rely on. Each gets its own MultiplayerAPI scoped to
## its own node path — the documented way to run more than one multiplayer
## session in a single SceneTree (used for local split-screen, and here for
## tests). The path is computed *before* adding the node, and the custom API
## registered before that, so the node's own `_ready()` (which runs the
## instant it enters the tree) binds its signal connections to the right API.

const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")

var _host: Variant
var _client: Variant

## Ports increment per test so a socket the OS hasn't fully released yet from
## the previous test can never collide with the next one.
static var _next_port: int = 47800


func _make_side(node_name: String) -> Variant:
	var node: Node = _NET_SCRIPT.new()
	node.name = node_name
	var path: NodePath = NodePath(String(get_path()) + "/" + node_name)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), path)
	add_child_autofree(node)
	return node


func before_each() -> void:
	_host = _make_side("HostNet")
	_client = _make_side("ClientNet")


func after_each() -> void:
	if _client != null:
		_client.leave()
	if _host != null:
		_host.leave()
	# A rejected peer's own Net._reject_peer() waits a couple of frames
	# before actually closing the connection (docs/M3a_PLAN.md: the refusal
	# RPC must reach the wire first). Give it that time before add_child_
	# autofree() frees the node out from under the still-awaiting coroutine.
	await get_tree().process_frame
	await get_tree().process_frame


func _take_port() -> int:
	var port: int = _next_port
	_next_port += 1
	return port


## Polls until `condition` (a Callable returning bool) is true or `frames`
## process frames have passed. Returns whether it succeeded.
func _wait_until(condition: Callable, frames: int = 200) -> bool:
	for _i: int in range(frames):
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _connect_host_and_client(port: int, max_peers: int = -1) -> void:
	if max_peers > 0:
		var host_config: NetConfig = load("res://config/net_config.tres").duplicate() as NetConfig
		host_config.max_peers = max_peers
		_host.config = host_config
	assert_eq(_host.host_game(port, "Hostie"), OK)
	assert_eq(_client.join_game("127.0.0.1", port, "Clienty"), OK)


# --- Connect, handshake, roster ---------------------------------------------

func test_host_and_client_appear_in_each_others_roster() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)

	var ok: bool = await _wait_until(func() -> bool:
		return _host.peer_ids().size() == 2 and _client.peer_ids().size() == 2
	)
	assert_true(ok, "host and client must both settle on a 2-peer roster")

	var client_id: int = _client.local_peer_id()
	assert_eq(_host.slot_of_peer(client_id), 1, "the first joiner takes slot 1 (host holds slot 0)")
	assert_eq(_client.local_slot(), 1)
	assert_eq(_host.peer_info(client_id).get("name"), "Clienty")
	assert_eq(_client.peer_info(Net.HOST_PEER_ID).get("name"), "Hostie")
	assert_true(_host.is_host())
	assert_true(_client.is_client())


func test_ping_exchange_reports_low_round_trip() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)
	await _wait_until(func() -> bool: return _host.peer_ids().size() == 2)

	# Ping is periodic at config.ping_hz; give it a couple of seconds of
	# frames so at least one round trip completes on a loopback connection.
	var ok: bool = await _wait_until(func() -> bool: return _client.ping_ms() > 0.0, 400)
	assert_true(ok, "client must receive at least one ping report from the host")
	assert_lt(_client.ping_ms(), 50.0, "loopback RTT must be well under 50 ms")


# --- Version handshake -------------------------------------------------------

func test_mismatched_build_version_is_refused_and_disconnected() -> void:
	# DECISION (autoload/Net.gd): host_game() snapshots build_version() once,
	# into _host_build_version, instead of re-reading ProjectSettings live in
	# _rpc_handshake — a host's advertised version cannot legitimately change
	# mid-session anyway, and it is what makes the version bump below
	# race-free to test in one process: it reproduces spec 3.4's "Compare the
	# version ... during the ENet handshake" with no timing dependency on
	# when either side's RPC actually runs.
	#
	# watch_signals()/get_signal_parameters() rather than a connected lambda
	# flipping a captured local: GDScript lambdas capture locals *by value*
	# at creation time, so `func(e): last_error = e` never actually updates
	# the outer `last_error` the test reads afterward.
	var port: int = _take_port()
	var real_version: Variant = ProjectSettings.get_setting("application/config/version", "")
	ProjectSettings.set_setting("application/config/version", "1.0.0-host")
	assert_eq(_host.host_game(port, "Hostie"), OK)
	ProjectSettings.set_setting("application/config/version", "9.9.9-client")

	watch_signals(Events)
	assert_eq(_client.join_game("127.0.0.1", port, "Clienty"), OK)

	var refused: bool = await _wait_until(func() -> bool:
		return get_signal_emit_count(Events, "net_join_failed") > 0
	)
	ProjectSettings.set_setting("application/config/version", real_version)

	assert_true(refused, "a mismatched build must be refused")
	assert_eq(get_signal_parameters(Events, "net_join_failed")[0], Net.JoinError.VERSION_MISMATCH)
	assert_eq(_host.peer_ids().size(), 1, "the refused peer must never receive a slot")
	assert_eq(_client.mode(), Net.Mode.OFFLINE, "a refused client returns to OFFLINE")


func test_server_full_refuses_the_next_peer() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port, 2)
	var joined: bool = await _wait_until(func() -> bool: return _host.peer_ids().size() == 2)
	assert_true(joined)

	var third: Variant = _make_side("ThirdNet")
	watch_signals(Events)
	assert_eq(third.join_game("127.0.0.1", port, "Thirdy"), OK)

	var refused: bool = await _wait_until(func() -> bool:
		return get_signal_emit_count(Events, "net_join_failed") > 0
	)
	assert_true(refused, "a peer beyond max_peers must be refused")
	assert_eq(get_signal_parameters(Events, "net_join_failed")[0], Net.JoinError.SERVER_FULL)
	assert_eq(_host.peer_ids().size(), 2, "the refused peer must never receive a slot")
	third.leave()


# --- Lobby-only joining (Bontago-mv0.1.8) ---------------------------------------
#
# Spec 3.4: joining is lobby-only in M3a. Net does not know Match's state
# machine (docs/M3a_PLAN.md P1: Net must not name a gameplay concept), so the
# match flow flips set_accepting_joins(); these tests flip it directly. The
# "not accepting" window stands in for COUNTDOWN, PLAYING, SUDDEN_DEATH and
# END alike — Net treats every non-lobby state the same way.

func test_a_fresh_host_accepts_joins_until_told_otherwise() -> void:
	assert_true(_host.accepting_joins(), "offline, the flag is at its default")
	var port: int = _take_port()
	assert_eq(_host.host_game(port, "Hostie"), OK)
	assert_true(_host.accepting_joins(), "a new lobby accepts joins")
	_host.set_accepting_joins(false)
	assert_false(_host.accepting_joins())
	_host.leave()
	assert_true(_host.accepting_joins(), "leave() resets it so the next session starts clean")
	assert_eq(_host.host_game(_take_port(), "Hostie"), OK)
	assert_true(_host.accepting_joins(), "and so does hosting again")


func test_a_join_after_the_match_starts_is_refused_and_disturbs_nobody() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)
	var joined: bool = await _wait_until(func() -> bool:
		return _host.peer_ids().size() == 2 and _client.local_slot() == 1
	)
	assert_true(joined, "the lobby fills normally first")
	var roster_before: PackedInt32Array = _host.peer_ids()
	var client_id: int = _client.local_peer_id()

	# The match starts: the flow flips the flag (see the DECISION in Net.gd).
	_host.set_accepting_joins(false)

	var late: Variant = _make_side("LateNet")
	watch_signals(Events)
	assert_eq(late.join_game("127.0.0.1", port, "Latey"), OK)
	var refused: bool = await _wait_until(func() -> bool:
		return get_signal_emit_count(Events, "net_join_failed") > 0
	)
	assert_true(refused, "a join while the match is running must be refused")
	assert_eq(
		get_signal_parameters(Events, "net_join_failed")[0],
		Net.JoinError.MATCH_IN_PROGRESS,
		"with the reason the lobby can explain"
	)
	assert_eq(late.mode(), Net.Mode.OFFLINE, "the late joiner returns to OFFLINE")
	assert_eq(late.local_slot(), 0, "and never held a slot")

	assert_eq(_host.peer_ids(), roster_before, "the host's roster is exactly what it was")
	assert_eq(_host.slot_of_peer(client_id), 1, "the seated client keeps its slot")
	assert_eq(_host.peer_of_slot(2), -1, "no new slot was allocated")
	assert_eq(get_signal_emit_count(Events, "net_peer_joined"), 0, "nobody was announced as joining")
	assert_eq(get_signal_emit_count(Events, "net_peer_left"), 0, "and nobody was announced as leaving")
	assert_eq(_client.mode(), Net.Mode.CLIENT, "the seated client is still connected")
	assert_eq(_client.local_slot(), 1, "in its own slot")
	late.leave()


func test_joins_resume_once_the_match_returns_to_the_lobby() -> void:
	var port: int = _take_port()
	assert_eq(_host.host_game(port, "Hostie"), OK)
	_host.set_accepting_joins(false)

	watch_signals(Events)
	assert_eq(_client.join_game("127.0.0.1", port, "Clienty"), OK)
	var refused: bool = await _wait_until(func() -> bool:
		return get_signal_emit_count(Events, "net_join_failed") > 0
	)
	assert_true(refused, "refused while the match runs")
	assert_eq(get_signal_parameters(Events, "net_join_failed")[0], Net.JoinError.MATCH_IN_PROGRESS)
	assert_eq(_host.peer_ids().size(), 1, "the host is still alone")
	assert_eq(_client.mode(), Net.Mode.OFFLINE)

	# The match ends and the flow returns to the lobby. The host stays up
	# across the refusal here (unlike the tests above, where after_each tears
	# it down inside _reject_peer's two-frame grace), so this also covers the
	# host's deferred disconnect_peer() finding the refused id already gone:
	# it must not log an engine error.
	_host.set_accepting_joins(true)
	assert_eq(_client.join_game("127.0.0.1", port, "Clienty"), OK)
	var joined: bool = await _wait_until(func() -> bool:
		return _host.peer_ids().size() == 2 and _client.mode() == Net.Mode.CLIENT and _client.local_slot() == 1
	)
	assert_true(joined, "the same player joins normally once the lobby is back")
	assert_eq(_host.slot_of_peer(_client.local_peer_id()), 1, "and takes the first free slot")
	assert_eq(get_signal_emit_count(Events, "net_join_failed"), 1, "no second refusal")


# --- Disconnect ---------------------------------------------------------

func test_peer_disconnect_fires_net_peer_left_with_the_right_slot() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)
	await _wait_until(func() -> bool: return _host.peer_ids().size() == 2)
	var client_slot: int = _host.slot_of_peer(_client.local_peer_id())
	var client_id: int = _client.local_peer_id()

	watch_signals(Events)
	_client.leave()

	var seen: bool = await _wait_until(func() -> bool:
		return get_signal_emit_count(Events, "net_peer_left") > 0
	)
	assert_true(seen, "the host must observe the client leaving")
	var params: Array = get_signal_parameters(Events, "net_peer_left")
	assert_eq(params[0], client_id)
	assert_eq(params[1], client_slot)
	var still_two: bool = await _wait_until(func() -> bool: return _host.peer_ids().size() == 1, 30)
	assert_true(still_two, "the host's roster must drop the departed peer")


func test_host_leaving_returns_client_to_offline() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)
	await _wait_until(func() -> bool: return _client.mode() == Net.Mode.CLIENT and _host.peer_ids().size() == 2)

	_host.leave()
	var offline: bool = await _wait_until(func() -> bool: return _client.mode() == Net.Mode.OFFLINE, 300)
	assert_true(offline, "a client must return to OFFLINE when the host shuts down")


# --- leave() idempotence -----------------------------------------------

func test_leave_from_either_side_returns_both_to_offline_and_is_idempotent() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)
	await _wait_until(func() -> bool: return _host.peer_ids().size() == 2)

	_client.leave()
	await _wait_until(func() -> bool: return _client.mode() == Net.Mode.OFFLINE, 60)
	assert_eq(_client.mode(), Net.Mode.OFFLINE)
	# Idempotent: calling it again while already offline must not error.
	_client.leave()
	assert_eq(_client.mode(), Net.Mode.OFFLINE)

	_host.leave()
	assert_eq(_host.mode(), Net.Mode.OFFLINE)
	_host.leave()
	assert_eq(_host.mode(), Net.Mode.OFFLINE)


func test_leave_while_already_offline_is_a_safe_no_op() -> void:
	assert_eq(_host.mode(), Net.Mode.OFFLINE)
	_host.leave()
	assert_eq(_host.mode(), Net.Mode.OFFLINE)


# --- Command line -------------------------------------------------------

## apply_command_line() itself always reads the real OS.get_cmdline_user_args()
## (there is no OS.set_cmdline_user_args() to fake it with), so these drive
## the private _apply_command_line_args(args) it delegates to instead — the
## exact same parsing/dispatch code, with the argument list passed explicitly.

func test_apply_command_line_parses_host_flag() -> void:
	var node: Variant = _make_side("CmdHostNet")
	var cfg: NetConfig = load("res://config/net_config.tres").duplicate() as NetConfig
	cfg.game_port = _take_port()
	node.config = cfg
	var started: bool = node._apply_command_line_args(PackedStringArray(["--headless-host"]))
	assert_true(started)
	assert_eq(node.mode(), Net.Mode.HOST)
	node.leave()


func test_apply_command_line_parses_join_with_port() -> void:
	var port: int = _take_port()
	assert_eq(_host.host_game(port, "Hostie"), OK)
	var started: bool = _client._apply_command_line_args(
		PackedStringArray(["--join=127.0.0.1:%d" % port])
	)
	assert_true(started)
	assert_eq(_client.mode(), Net.Mode.CLIENT)


func test_apply_command_line_parses_sim_lag_and_loss() -> void:
	_host._apply_command_line_args(PackedStringArray(["--sim-lag=100", "--sim-loss=0.02"]))
	assert_true(_host.simulation_enabled())
	assert_false(_host.simulation().is_idle())


func test_apply_command_line_with_no_relevant_flags_returns_false() -> void:
	assert_false(_host._apply_command_line_args(PackedStringArray()))
	assert_eq(_host.mode(), Net.Mode.OFFLINE)


# --- Steam session (spec 3.4, docs/M3b_PLAN.md P1) --------------------------
#
# Every test below drives Net through a FakeSteam, never the real Steam
# singleton, so the suite is correct whether or not addons/godotsteam/ is
# installed in this checkout (docs/M3b_PLAN.md's acceptance criterion).
#
# steam_available() requires both steam_provider.is_available() *and* a
# successful init_result (see autoload/Net.gd's `_steam_ready`), matching
# real usage where game/Main.gd always calls Net.init_steam() before the menu
# can reach host_online()/join_lobby() — so every positive-path test below
# calls _ready_steam() first. Net.gd additionally refuses to ever construct a
# real SteamMultiplayerPeer unless steam_provider `is SteamClient` (never true
# for a FakeSteam), a hard safety rail this worker added after reproducing a
# real engine crash: calling SteamMultiplayerPeer.create_host()/create_client()
# without a prior successful steamInitEx() segfaults the process
# (netcode-F-probe_peer_no_init.log). That means the actual HOST/CLIENT mode
# transition after a successful lobby_created/lobby_joined is exactly the one
# step docs/M3b_PLAN.md's "Testing without Steam" says GUT genuinely cannot
# exercise — every test below asserts the (deterministic, safe) OFFLINE
# outcome for that step rather than skipping it.

## Wires `fake` in as `node`'s steam_provider and runs it through
## init_steam() so steam_available() reads true afterward (fake's
## init_status_value defaults to 0, Steamworks' own "ok").
func _ready_steam(node: Variant, fake: FakeSteam) -> void:
	node.steam_provider = fake
	node.init_steam()


func test_steam_unavailable_refuses_host_online_without_creating_a_lobby() -> void:
	var fake: FakeSteam = FakeSteam.new()
	fake.available_value = false
	_ready_steam(_host, fake)

	assert_false(_host.steam_available())
	assert_eq(_host.host_online("Hostie"), ERR_UNAVAILABLE)
	assert_eq(_host.mode(), Net.Mode.OFFLINE)
	assert_true(fake.create_lobby_calls.is_empty())


func test_steam_unavailable_refuses_join_lobby_without_joining() -> void:
	var fake: FakeSteam = FakeSteam.new()
	fake.available_value = false
	_ready_steam(_client, fake)

	assert_eq(_client.join_lobby(4242, "Clienty"), ERR_UNAVAILABLE)
	assert_eq(_client.mode(), Net.Mode.OFFLINE)
	assert_true(fake.join_lobby_calls.is_empty())


func test_steam_init_failure_leaves_steam_available_false() -> void:
	var fake: FakeSteam = FakeSteam.new()
	fake.init_status_value = 2 # k_EResultFail-shaped: "Steam client not running"
	_ready_steam(_host, fake)

	assert_false(_host.steam_available(), "addon present but init failed must still read as unavailable")
	assert_eq(_host.host_online("Hostie"), ERR_UNAVAILABLE)


func test_init_steam_with_unavailable_provider_emits_signal_and_leaves_steam_unavailable() -> void:
	var fake: FakeSteam = FakeSteam.new()
	fake.available_value = false
	_host.steam_provider = fake

	watch_signals(Events)
	_host.init_steam()

	assert_eq(get_signal_emit_count(Events, "net_steam_status_changed"), 1, "signal must emit even when provider is unavailable")
	assert_false(_host.steam_available(), "steam_available() must be false when provider reports unavailable")


func test_host_online_creates_a_lobby_with_the_configured_type_and_size() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_host, fake)

	assert_eq(_host.host_online("Hostie"), OK)
	assert_eq(fake.create_lobby_calls.size(), 1)
	assert_eq(fake.create_lobby_calls[0]["lobby_type"], _host.config.steam_lobby_type)
	assert_eq(fake.create_lobby_calls[0]["max_members"], _host.config.max_peers)
	# Async: nothing happens to _mode until the fake answers.
	assert_eq(_host.mode(), Net.Mode.OFFLINE)


func test_lobby_created_tags_the_lobby_with_the_json_encoded_match_config() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_host, fake)
	# Set before hosting, the same way ui/Lobby.gd could prime settings
	# before host_online() actually finishes creating the lobby: is_host()
	# is true offline too, so this is accepted and stored locally.
	_host.set_lobby_data({"map_variant": 2, "player_count": 4})

	assert_eq(_host.host_online("Hostie"), OK)
	var lobby_id: int = 4242
	fake.lobby_created.emit(FakeSteam.RESULT_OK, lobby_id)

	assert_eq(fake.get_lobby_data(lobby_id, String(SteamClient.KEY_GAME)), String(Net.DISCOVERY_MAGIC))
	assert_eq(fake.get_lobby_data(lobby_id, String(SteamClient.KEY_VERSION)), _host.build_version())
	assert_eq(fake.get_lobby_data(lobby_id, String(SteamClient.KEY_HOST_NAME)), "Hostie")

	var decoded: Dictionary = SteamClient.decode_match_config(
		fake.get_lobby_data(lobby_id, String(SteamClient.KEY_MATCH_CONFIG))
	)
	assert_eq(int(decoded.get("map_variant")), 2, "the JSON-encoded config must be written under one key")
	assert_eq(int(decoded.get("player_count")), 4)

	# The lobby is tagged unconditionally (see the block comment above), but
	# actually becoming HOST needs a real SteamMultiplayerPeer, which Net.gd
	# now refuses to construct for a FakeSteam-driven provider (crash safety;
	# see this file's own header comment above).
	assert_eq(_host.mode(), Net.Mode.OFFLINE, "no real SteamMultiplayerPeer is ever built for a FakeSteam provider")
	assert_false(_host.is_steam_session())


func test_lobby_created_failure_is_reported_and_creates_no_session() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_host, fake)
	assert_eq(_host.host_online("Hostie"), OK)

	watch_signals(Events)
	fake.lobby_created.emit(2, 0) # k_EResultFail-shaped failure, not 1 (OK)

	assert_eq(get_signal_emit_count(Events, "net_join_failed"), 1)
	assert_eq(get_signal_parameters(Events, "net_join_failed")[0], Net.JoinError.TRANSPORT)
	assert_eq(_host.mode(), Net.Mode.OFFLINE)
	assert_false(_host.is_steam_session())


func test_set_lobby_data_tees_into_steam_lobby_data_after_the_lobby_is_tagged() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_host, fake)
	assert_eq(_host.host_online("Hostie"), OK)
	fake.lobby_created.emit(FakeSteam.RESULT_OK, 55)
	# _steam_lobby_id is only set once the (unreachable, for a FakeSteam
	# provider) peer construction succeeds; directly poke the id this fake
	# tagged so set_lobby_data()'s tee has somewhere to write, exactly as it
	# would once a real Steam session is actually live.
	_host._steam_lobby_id = 55
	_host._steam_session = true
	fake.set_lobby_data_calls.clear() # only interested in calls after this point

	_host.set_lobby_data({"map_variant": 7})

	var decoded: Dictionary = SteamClient.decode_match_config(
		fake.get_lobby_data(55, String(SteamClient.KEY_MATCH_CONFIG))
	)
	assert_eq(int(decoded.get("map_variant")), 7, "a later set_lobby_data() call must re-tag the lobby too")


func test_join_lobby_calls_fake_steam_join_lobby_with_the_right_id() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_client, fake)

	assert_eq(_client.join_lobby(9001, "Clienty"), OK)
	assert_eq(fake.join_lobby_calls, [9001])
	assert_eq(_client.mode(), Net.Mode.OFFLINE, "async: nothing happens until lobby_joined answers")


func test_lobby_joined_with_a_failure_response_refuses_and_returns_offline() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_client, fake)
	assert_eq(_client.join_lobby(9001, "Clienty"), OK)

	watch_signals(Events)
	fake.lobby_joined.emit(9001, 3) # k_EChatRoomEnterResponseFull-shaped failure, not 1

	assert_eq(get_signal_emit_count(Events, "net_join_failed"), 1)
	assert_eq(get_signal_parameters(Events, "net_join_failed")[0], Net.JoinError.REFUSED)
	assert_eq(_client.mode(), Net.Mode.OFFLINE)


func test_lobby_joined_success_never_constructs_a_real_peer_for_a_fake_provider() -> void:
	var fake: FakeSteam = FakeSteam.new()
	fake.lobby_owners[9001] = 555
	_ready_steam(_client, fake)
	assert_eq(_client.join_lobby(9001, "Clienty"), OK)

	fake.lobby_joined.emit(9001, FakeSteam.CHAT_ROOM_ENTER_SUCCESS)

	# See this file's header comment: constructing a real SteamMultiplayerPeer
	# for a FakeSteam-driven provider is refused by design (crash safety), so
	# a "successful" lobby_joined still leaves this instance OFFLINE.
	assert_eq(_client.mode(), Net.Mode.OFFLINE)
	assert_false(_client.is_steam_session())
	# REPRO (Bontago-mv0.2.6 finding A): _on_steam_lobby_created()'s matching
	# peer==null branch already abandons the lobby it could not host
	# (test_lobby_created_failure_is_reported_and_creates_no_session()
	# implicitly covers that through leave_lobby_calls being unset there, and
	# test_leave_leaves_the_steam_lobby_and_resets_session_state() spells it
	# out directly) -- the join-side branch below must do the same instead of
	# leaking the Steam lobby this instance is still a member of.
	assert_eq(
		fake.leave_lobby_calls, [9001] as Array[int],
		"a joined-but-peerless lobby must be abandoned via leave_lobby(), not leaked"
	)


func test_discovered_lobbies_filters_by_game_and_version_tag() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_client, fake)
	fake.seed_lobby(111, 555, 2, {
		"game": String(Net.DISCOVERY_MAGIC),
		"version": _client.build_version(),
		"map": "round",
		"host_name": "Alice",
	})
	fake.seed_lobby(222, 777, 5, {
		"game": "some_other_game",
		"version": _client.build_version(),
		"map": "square",
		"host_name": "Mallory",
	})

	_client.refresh_lobby_list()
	assert_eq(fake.request_lobby_list_calls.size(), 1)
	fake.lobby_match_list.emit([111, 222])

	var lobbies: Array[Dictionary] = _client.discovered_lobbies()
	assert_eq(lobbies.size(), 1, "only the matching-tagged lobby must be returned")
	assert_eq(int(lobbies[0]["lobby_id"]), 111)
	assert_eq(lobbies[0]["name"], "Alice")
	assert_eq(int(lobbies[0]["players"]), 2)


func test_refresh_lobby_list_filters_by_this_builds_game_and_version() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_client, fake)
	_client.refresh_lobby_list()
	assert_eq(fake.request_lobby_list_calls.size(), 1)
	var filters: Array = fake.request_lobby_list_calls[0]
	var keys: Array = []
	for entry: Dictionary in filters:
		keys.append(entry.get("key"))
	assert_true(keys.has(String(SteamClient.KEY_GAME)))
	assert_true(keys.has(String(SteamClient.KEY_VERSION)))


func test_invite_friends_is_a_no_op_off_steam_or_before_a_lobby_exists() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_host.steam_provider = fake
	_host.invite_friends() # no session yet
	assert_true(fake.activate_invite_overlay_calls.is_empty())


func test_apply_connect_lobby_from_the_full_command_line_calls_join_lobby() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_client, fake)

	var started: bool = _client._apply_connect_lobby_args(
		PackedStringArray(["stackfall.exe", "+connect_lobby", "12345"])
	)
	assert_true(started)
	assert_eq(fake.join_lobby_calls, [12345])


func test_apply_connect_lobby_ignores_a_command_line_without_the_token() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_client.steam_provider = fake
	assert_false(_client._apply_connect_lobby_args(PackedStringArray(["stackfall.exe", "--host"])))
	assert_true(fake.join_lobby_calls.is_empty())


func test_apply_connect_lobby_rejects_a_non_numeric_id_without_erroring() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_client.steam_provider = fake
	assert_false(
		_client._apply_connect_lobby_args(PackedStringArray(["stackfall.exe", "+connect_lobby", "not-a-number"]))
	)
	assert_true(fake.join_lobby_calls.is_empty())


func test_leave_leaves_the_steam_lobby_and_resets_session_state() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_host, fake)
	assert_eq(_host.host_online("Hostie"), OK)
	fake.lobby_created.emit(FakeSteam.RESULT_OK, 77)
	# The peer-construction failure branch above (crash safety: no real
	# SteamMultiplayerPeer is ever built for a FakeSteam provider) already
	# calls steam_provider.leave_lobby(77) once, abandoning the lobby this
	# attempt could not actually host — clear that expected call so this
	# test's own assertion is only about leave()'s teardown below.
	fake.leave_lobby_calls.clear()
	# _steam_session/_steam_lobby_id only ever flip once a real
	# SteamMultiplayerPeer succeeds, which Net.gd refuses to attempt for a
	# FakeSteam-driven provider (crash safety; see this file's header
	# comment) — poke the state directly to exercise leave()'s own teardown,
	# exactly what it would do once a real Steam session were actually live.
	_host._steam_session = true
	_host._steam_lobby_id = 77
	_host._mode = Net.Mode.HOST

	_host.leave()

	assert_eq(fake.leave_lobby_calls, [77])
	assert_false(_host.is_steam_session())
	assert_eq(_host.mode(), Net.Mode.OFFLINE)


# --- In-flight guard (Bontago-mv0.2.6 finding B) ----------------------------
# host_online()/join_lobby() only kick off Steam's own async request; _mode
# stays OFFLINE the whole time that answer is pending (every test above
# already proves this). A second call in the meantime must not issue a
# second Steam request -- there would be no way to tell the two requests'
# eventual answers apart -- so it is refused with ERR_BUSY instead.

func test_host_online_refuses_a_second_call_while_the_first_is_still_pending() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_host, fake)

	assert_eq(_host.host_online("Hostie"), OK)
	assert_eq(_host.host_online("Hostie2"), ERR_BUSY, "a second concurrent host_online() must be refused")
	assert_eq(
		fake.create_lobby_calls.size(), 1,
		"a second concurrent host_online() must not issue a second Steam request"
	)

	fake.lobby_created.emit(FakeSteam.RESULT_OK, 111)
	assert_eq(
		fake.get_lobby_data(111, String(SteamClient.KEY_HOST_NAME)), "Hostie",
		"the only request in flight must be the first one's"
	)


func test_join_lobby_refuses_a_second_call_while_the_first_is_still_pending() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_client, fake)

	assert_eq(_client.join_lobby(9001, "Clienty"), OK)
	assert_eq(_client.join_lobby(9002, "Clienty2"), ERR_BUSY, "a second concurrent join_lobby() must be refused")
	assert_eq(
		fake.join_lobby_calls, [9001],
		"a second concurrent join_lobby() must not issue a second Steam request"
	)


## Regression for the exact race finding B describes: a caller cancels an
## in-flight attempt (leave(), e.g. backing out of the menu before Steam
## answered) and the attempt's own late answer arrives afterward. It must not
## resurrect a session nobody is waiting for, and it must not leak the lobby
## Steam actually created for it either -- leave()'s own cancellation must
## also free this instance to start a genuinely new attempt afterward.
func test_leave_between_two_host_online_attempts_clears_the_pending_state() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_host, fake)

	assert_eq(_host.host_online("Hostie"), OK)
	_host.leave() # cancels the in-flight attempt before Steam has answered

	# The cancelled attempt's own late answer must be abandoned, not revived.
	# Cleared here so the assertion below distinguishes the *stale-answer*
	# short-circuit (this fix: bails out before tagging anything) from the
	# pre-existing, unrelated "no real SteamMultiplayerPeer is ever built for
	# a FakeSteam provider" safety net (docs/M3b_PLAN.md's crash-safety rail),
	# which every P1 test's peer construction already falls through to and
	# would otherwise call leave_lobby() too, masking whether this fix's own
	# early return actually ran.
	fake.set_lobby_data_calls.clear()
	fake.leave_lobby_calls.clear()
	fake.lobby_created.emit(FakeSteam.RESULT_OK, 111)
	assert_eq(fake.leave_lobby_calls, [111], "a late answer to a cancelled attempt must abandon its lobby")
	assert_true(
		fake.set_lobby_data_calls.is_empty(),
		"a stale answer must be abandoned before ever tagging the lobby, not fall through to the normal tag-then-fail path"
	)
	assert_eq(_host.mode(), Net.Mode.OFFLINE)
	assert_false(_host.is_steam_session())

	# leave()'s cancellation must not leave this instance stuck refusing every
	# future attempt -- a genuinely new one right after must be accepted.
	assert_eq(_host.host_online("Hostie2"), OK, "leave() must clear the pending state for a fresh attempt")
	assert_eq(fake.create_lobby_calls.size(), 2)


func test_init_steam_forwards_steamclient_status_onto_events_and_is_idempotent() -> void:
	var fake: FakeSteam = FakeSteam.new()
	fake.init_status_value = 0
	fake.init_verbal_value = ""
	_host.steam_provider = fake

	watch_signals(Events)
	_host.init_steam()
	assert_eq(fake.init_calls, 1)
	assert_eq(get_signal_emit_count(Events, "net_steam_status_changed"), 1)
	assert_eq(get_signal_parameters(Events, "net_steam_status_changed")[0], true)

	_host.init_steam() # second call must be a no-op
	assert_eq(fake.init_calls, 1, "init_steam() must be idempotent")


## Regression: Steamworks is a manual-dispatch API (net/SteamClient.gd's
## run_callbacks() doc comment) — without a periodic pump, host_online()'s own
## async lobby_created (and every other Steam signal) never fires against a
## real Steam client no matter how long a caller waits. Found by this
## worker's own windowed smoke test (docs/M3b_PLAN.md P1 acceptance), not by
## a plan bullet, so it gets a test of its own.
func test_process_pumps_steam_callbacks_once_steam_is_ready() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_host, fake)
	assert_true(_host.steam_available())

	var ok: bool = await _wait_until(func() -> bool: return fake.run_callbacks_calls > 0, 10)
	assert_true(ok, "Net._process() must pump Steam callbacks every frame once steam_available() is true")


func test_process_never_pumps_steam_callbacks_before_steam_is_ready() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_host.steam_provider = fake # init_steam() never called: steam_available() stays false

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(fake.run_callbacks_calls, 0, "must not pump a provider that never answered init_result")
