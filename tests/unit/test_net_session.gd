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


func _make_side(node_name: String, tuned: NetConfig = null) -> Variant:
	var node: Node = _NET_SCRIPT.new()
	node.name = node_name
	if tuned != null:
		node.config = tuned # set before add_child so _ready() sees it
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
	# Parallel gate shards (tools/full_gate.py) run several Godot processes at
	# once; a fixed port sequence collided, so ask the OS for a free port.
	return AgentProbe.free_udp_port()


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


## Bontago-mv0.6: Events.net_roster_changed must fire on both sides of a
## ready-flag flip, not just update the internal _peers table, or
## ui/Lobby.gd's rows never move (docs of that bug: the label only ever
## rebuilds from Events.net_lobby_data_changed / net_roster_changed, and
## nothing used to publish the latter).
func test_ready_flag_change_emits_roster_changed_on_host_and_client() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)
	var joined: bool = await _wait_until(func() -> bool:
		return _host.peer_ids().size() == 2 and _client.peer_ids().size() == 2
	)
	assert_true(joined, "host and client must both settle on a 2-peer roster first")

	watch_signals(Events)
	_host.set_local_ready(true)

	assert_eq(
		get_signal_emit_count(Events, "net_roster_changed"), 1,
		"the host must emit as soon as it marks its own peer ready"
	)
	var host_roster: Array = get_signal_parameters(Events, "net_roster_changed", 0)[0]
	assert_true(_ready_in_roster(host_roster, Net.HOST_PEER_ID), "the host's own entry must read ready")

	var client_id: int = _client.local_peer_id()
	# Wait on the emit count itself (not peer_info().ready alone, which could pass
	# on stale pre-flip data), and confirm the roster's content after.
	var landed: bool = await _wait_until(func() -> bool:
		return get_signal_emit_count(Events, "net_roster_changed") >= 2
	)
	assert_true(landed, "the roster RPC must reach the client and it must emit in turn")
	assert_true(bool(_client.peer_info(Net.HOST_PEER_ID).get("ready", false)), "the client's own state must agree")
	var client_roster: Array = get_signal_parameters(Events, "net_roster_changed", 1)[0]
	assert_true(_ready_in_roster(client_roster, Net.HOST_PEER_ID), "the client's copy must show the host as ready")
	# Untouched by this flip: sanity-checks the payload is the whole roster,
	# not just the entry that changed.
	assert_false(_ready_in_roster(client_roster, client_id), "the client's own entry was never marked ready")


func _ready_in_roster(roster: Array, peer_id: int) -> bool:
	for entry_variant: Variant in roster:
		var entry: Dictionary = entry_variant as Dictionary
		if int(entry.get("peer_id", -1)) == peer_id:
			return bool(entry.get("ready", false))
	return false


## Bontago-1pi.67: the host is seeded not ready (mirrors its Ready toggle like a
## client); the Start gate ignores the host's own flag and waits for the others.
func test_host_seeded_not_ready_and_start_gate_ignores_the_host_flag() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)
	await _wait_until(func() -> bool: return _host.peer_ids().size() == 2)
	assert_false(bool(_host.peer_info(Net.HOST_PEER_ID).get("ready", true)), "host starts not ready")
	assert_false(_host.all_peers_ready(), "the client is not ready")
	_host.set_peer_ready(_client.local_peer_id(), true)
	assert_true(_host.all_peers_ready(), "host pressing Start is its own consent")


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


## Bontago-mv0.1.10: reproduces the teardown-ordering race in isolation.
## Before the _can_send() guard, _broadcast_roster() called
## _rpc_roster_update.rpc(roster) unconditionally, and this exact sequence
## (peer_disconnected signal for a still-registered peer arriving after the
## transport itself has already been closed and nulled — as can happen while
## a multi-peer session is tearing down) raised an engine error:
##   "ERROR: Trying to call an RPC while no multiplayer peer is active."
##   at res://autoload/Net.gd:1173 (_broadcast_roster), called from
##   _on_peer_disconnected (Net.gd:1072).
## GUT surfaces engine-level errors raised during a test as an "Unexpected
## Errors" failure, so this fails outright pre-fix rather than merely
## printing — no extra assertion needed to catch it.
func test_broadcast_roster_after_transport_closed_does_not_rpc() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)
	await _wait_until(func() -> bool: return _host.peer_ids().size() == 2)
	var client_id: int = _client.local_peer_id()

	# Simulate the transport already closing while _mode is still HOST — the
	# exact ordering _on_peer_disconnected can race.
	_host.multiplayer.multiplayer_peer.close()
	_host.multiplayer.multiplayer_peer = null

	assert_false(_host._can_send(), "no live multiplayer_peer to send through")
	_host._on_peer_disconnected(client_id)
	await get_tree().process_frame
	# Reaching here without GUT recording an "Unexpected Errors" failure is
	# the assertion: the RPC attempt above must have been skipped.


func test_tick_ping_after_transport_closed_does_not_rpc() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)
	await _wait_until(func() -> bool: return _host.peer_ids().size() == 2)

	# Simulate the transport already closing while _mode is still HOST.
	_host.multiplayer.multiplayer_peer.close()
	_host.multiplayer.multiplayer_peer = null

	assert_false(_host._can_send(), "no live multiplayer_peer to send through")
	_host._tick_ping(1.0)  # Force a ping attempt
	await get_tree().process_frame
	# Reaching here without GUT recording an "Unexpected Errors" failure is
	# the assertion: the RPC attempt above must have been skipped.


## Bontago-mv0.1.10, second half of the guard: the transport can still be
## open and CONNECTED while the host has zero remaining connected peers (the
## last client just left) — _can_send() must refuse this too, not just a
## null/closed peer.
func test_can_send_is_false_once_the_last_peer_leaves() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)
	await _wait_until(func() -> bool: return _host.peer_ids().size() == 2)
	assert_true(_host._can_send(), "still one connected client to broadcast to")

	_client.leave()
	var alone: bool = await _wait_until(func() -> bool: return _host.peer_ids().size() == 1)
	assert_true(alone, "the host must observe the client leaving")
	assert_false(_host._can_send(), "no connected peers left to broadcast to")


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


## REPRO (Bontago-mv0.4): the case the test above does not cover -- a SECOND
## host_online() is issued (after leave() cancels the first) *before* the
## first attempt's own Steam answer has landed, so two requests are
## genuinely outstanding at once. A single shared pending bool cannot tell
## the two eventual answers apart: the first (stale) answer arriving would
## get consumed as if it were the second (current) attempt's own, and the
## second attempt's real, later answer would then be dropped as stale in its
## place -- silently hosting the wrong (cancelled) lobby and abandoning the
## live one. The generation queue fix (_steam_request_generation /
## _steam_pending_generations) must resolve the two answers the other way
## around: whichever answer arrives *first* resolves the oldest still-
## outstanding (here, the cancelled) request, and whichever arrives *after*
## resolves the live one.
func test_leave_then_host_online_before_either_answers_the_first_delivered_answer_is_abandoned() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_host, fake)

	assert_eq(_host.host_online("Hostie"), OK) # attempt 1: create_lobby #1 in flight
	_host.leave() # cancels attempt 1 before Steam has answered it
	assert_eq(_host.host_online("Hostie2"), OK) # attempt 2: create_lobby #2 in flight too
	assert_eq(fake.create_lobby_calls.size(), 2, "leave() must not have refused the second attempt")

	# Attempt 1's own late answer arrives first (the reported race).
	fake.lobby_created.emit(FakeSteam.RESULT_OK, 111)
	assert_eq(fake.leave_lobby_calls, [111], "the first-delivered answer must be abandoned, not hosted")
	assert_true(
		fake.set_lobby_data_calls.is_empty(),
		"an abandoned answer must never be tagged as if it were the live attempt's own lobby"
	)
	assert_eq(_host.mode(), Net.Mode.OFFLINE, "attempt 2 must still be unresolved")
	assert_false(_host.is_steam_session())

	# Attempt 2's real answer, delivered afterward, must still be accepted --
	# not dropped as stale in its place (the exact bug this fix targets).
	fake.lobby_created.emit(FakeSteam.RESULT_OK, 222)
	assert_eq(
		fake.get_lobby_data(222, String(SteamClient.KEY_HOST_NAME)), "Hostie2",
		"the attempt delivered second must be accepted as the live one, tagged with its own player name"
	)
	# 222 is still handed to leave_lobby() here too, but for an unrelated,
	# pre-existing reason every other P1 test already hits: _make_steam_host_
	# peer() refuses to build a real SteamMultiplayerPeer for a FakeSteam-
	# driven provider (crash safety), so even the *accepted* lobby's peer
	# construction fails and the lobby is released. That is not this fix's
	# stale-answer path (which never reaches set_lobby_data() at all, proven
	# above for 111) -- get_lobby_data() above already proves 222 was tagged
	# as the live attempt first.
	assert_eq(fake.leave_lobby_calls, [111, 222])


## Same race, ids delivered in the opposite order. DECISION: GodotSteam's
## lobby_created signal carries no call-correlation id (see
## _steam_request_generation's doc comment in autoload/Net.gd), so this fix
## resolves answers by *delivery* order, not by which physical lobby_id a
## test happens to use -- whichever answer arrives first always resolves the
## oldest still-outstanding (cancelled) request, and whichever arrives after
## resolves the live one. This proves that guarantee holds with the ids
## swapped: exactly one attempt is ever accepted as live, and no lobby is
## ever left permanently orphaned, regardless of which id arrives first.
func test_leave_then_host_online_before_either_answers_also_resolves_with_the_ids_swapped() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_host, fake)

	assert_eq(_host.host_online("Hostie"), OK)
	_host.leave()
	assert_eq(_host.host_online("Hostie2"), OK)

	# This time id 222 (which a reader might expect to be "attempt 2's own")
	# is delivered *first* -- it must still be the one abandoned, because it
	# is the first answer this instance sees since the second call was made.
	fake.lobby_created.emit(FakeSteam.RESULT_OK, 222)
	assert_eq(fake.leave_lobby_calls, [222], "whichever answer is delivered first must be abandoned")
	assert_true(fake.set_lobby_data_calls.is_empty(), "the first-delivered answer must never be tagged")
	assert_eq(_host.mode(), Net.Mode.OFFLINE)

	fake.lobby_created.emit(FakeSteam.RESULT_OK, 111)
	assert_eq(
		fake.get_lobby_data(111, String(SteamClient.KEY_HOST_NAME)), "Hostie2",
		"whichever answer arrives after must be accepted as the live attempt"
	)
	assert_eq(fake.leave_lobby_calls, [222, 111], "111 is released only by the peer-construction crash-safety path")


## Same fix, exercised through join_lobby()/_on_steam_lobby_joined() instead
## of host_online()/_on_steam_lobby_created() -- both callbacks share
## _consume_steam_answer_is_stale(), but only a regression on each call site
## proves the wiring (both push a generation, both pop it) actually matches.
func test_leave_then_join_lobby_before_either_answers_resolves_the_second_attempt() -> void:
	var fake: FakeSteam = FakeSteam.new()
	fake.lobby_owners[9001] = 555
	fake.lobby_owners[9002] = 555
	_ready_steam(_client, fake)
	watch_signals(Events)

	assert_eq(_client.join_lobby(9001, "Clienty"), OK)
	_client.leave()
	assert_eq(_client.join_lobby(9002, "Clienty2"), OK)
	assert_eq(fake.join_lobby_calls, [9001, 9002], "leave() must not have refused the second attempt")

	# The cancelled attempt's own late answer arrives first. A stale answer
	# returns before ever reaching _fail_join()/lobby_owner(), so no
	# net_join_failed is emitted for it either.
	fake.lobby_joined.emit(9001, FakeSteam.CHAT_ROOM_ENTER_SUCCESS)
	assert_eq(fake.leave_lobby_calls, [9001], "the first-delivered (cancelled) attempt's lobby must be abandoned")
	assert_eq(_client.mode(), Net.Mode.OFFLINE, "the second attempt must still be unresolved")
	assert_eq(get_signal_emit_count(Events, "net_join_failed"), 0, "a stale answer must not report a join failure")

	# The live attempt's real answer, delivered afterward, must be accepted
	# as the current generation (proceeds into the real success path) instead
	# of being dropped as stale in its place. _make_steam_client_peer() then
	# still refuses to build a real SteamMultiplayerPeer for a FakeSteam
	# provider (the same crash-safety rail test_lobby_joined_success_never_
	# constructs_a_real_peer_for_a_fake_provider() covers), so this ends in
	# _fail_join() -- but only *because* it was accepted as live, unlike 9001
	# above which never got that far at all.
	fake.lobby_joined.emit(9002, FakeSteam.CHAT_ROOM_ENTER_SUCCESS)
	assert_eq(fake.leave_lobby_calls, [9001, 9002], "9002 is released by the peer-construction crash-safety path")
	assert_eq(
		get_signal_emit_count(Events, "net_join_failed"), 1,
		"the live attempt's answer must reach _fail_join(), proving it was not treated as stale"
	)


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


# --- Lobby seat preferences (Bontago-1pi.53) ------------------------------------
#
# Net.request_seat_pref -> any_peer RPC -> host checks -> Events.net_seat_pref_requested.
# Most cases drive the host-side handler directly (the transport-given sender id is
# its first argument, exactly what _rpc_request_seat_pref passes it), seeding the
# host's roster instead of connecting ENet peers; the ENet cases below prove the
# RPC itself.

## Hosts on a free port and seats fake peers: {peer_id: slot_id} (-1 = spectator).
func _host_with_peers(slots: Dictionary) -> void:
	assert_eq(_host.host_game(_take_port(), "Hostie"), OK)
	for peer_id: int in slots.keys():
		_host._peers[peer_id] = {
			"peer_id": peer_id, "slot_id": int(slots[peer_id]), "name": "P%d" % peer_id,
			"ready": false, "ping_ms": 0.0, "build": "",
		}


func _seat_pref_count() -> int:
	return get_signal_emit_count(Events, "net_seat_pref_requested")


func test_seat_pref_valid_request_emits_with_the_senders_peer_id() -> void:
	_host_with_peers({2: 1})
	watch_signals(Events)
	assert_true(_host._handle_seat_pref(2, 3, 2), "a seated peer's in-range request goes through")
	assert_eq(_seat_pref_count(), 1)
	assert_eq(get_signal_parameters(Events, "net_seat_pref_requested", 0), [2, 3, 2])


func test_seat_pref_one_field_unchanged_and_the_range_edges_are_accepted() -> void:
	_host_with_peers({2: 1})
	watch_signals(Events)
	assert_true(_host._handle_seat_pref(2, -1, 4), "team only, the highest lobby team number")
	assert_true(_host._handle_seat_pref(2, 7, -1), "colour only, the last palette index")
	assert_true(_host._handle_seat_pref(2, 0, 0), "colour 0 and team 0 (Random) are real values, not 'unchanged'")
	assert_eq(_seat_pref_count(), 3)
	assert_eq(get_signal_parameters(Events, "net_seat_pref_requested", 0), [2, -1, 4])
	assert_eq(get_signal_parameters(Events, "net_seat_pref_requested", 1), [2, 7, -1])
	assert_eq(get_signal_parameters(Events, "net_seat_pref_requested", 2), [2, 0, 0])


## Spoofed seat: a sender that does not hold a lobby seat never reaches the lobby,
## whatever it claims. The id is the transport's; the payload names nobody.
func test_seat_pref_from_a_peer_without_a_seat_is_refused() -> void:
	_host_with_peers({2: 1, 3: -1})
	watch_signals(Events)
	assert_false(_host._handle_seat_pref(99, 1, 1), "an id that is not connected at all")
	assert_false(_host._handle_seat_pref(3, 1, 1), "a spectator (slot -1)")
	_host._peers.erase(2)
	assert_false(_host._handle_seat_pref(2, 1, 1), "a late packet from a peer that already left")
	assert_eq(_seat_pref_count(), 0)


func test_seat_pref_from_a_client_instance_is_ignored() -> void:
	# A hostile peer can aim the RPC at another client: only the host acts on it.
	var port: int = _take_port()
	_connect_host_and_client(port)
	watch_signals(Events)
	assert_false(_client._handle_seat_pref(Net.HOST_PEER_ID, 1, 1, true))
	assert_false(_client._handle_seat_pref(Net.HOST_PEER_ID, 1, 1, false))
	assert_eq(_seat_pref_count(), 0)


func test_seat_pref_out_of_range_values_are_refused_not_clamped() -> void:
	_host_with_peers({2: 1})
	watch_signals(Events)
	# A fresh minute per call: a full bucket every time, so only the range check can refuse.
	var tick: float = 0.0
	var bad_colors: Array[int] = [-2, LobbySeats.palette_size(), 9, 1000000, 2147483647, -2147483648]
	for bad: int in bad_colors:
		tick += 60.0
		assert_false(_host._handle_seat_pref(2, bad, -1, true, tick), "colour %d" % bad)
	var bad_teams: Array[int] = [-2, MatchConfig.TEAM_PICK_MAX + 1, 99, 2147483647, -2147483648]
	for bad: int in bad_teams:
		tick += 60.0
		assert_false(_host._handle_seat_pref(2, -1, bad, true, tick), "team %d" % bad)
	tick += 60.0
	assert_false(_host._handle_seat_pref(2, 1, 99, true, tick), "one bad field refuses the whole request")
	tick += 60.0
	assert_false(_host._handle_seat_pref(2, 99, 1, true, tick), "in either order")
	tick += 60.0
	assert_false(_host._handle_seat_pref(2, -1, -1, true, tick), "asking for nothing is refused")
	assert_eq(_seat_pref_count(), 0)


func test_seat_pref_malformed_payload_types_are_refused() -> void:
	_host_with_peers({2: 1})
	watch_signals(Events)
	var junk: Array = [1.0, 1.5, NAN, INF, "1", true, null, [1], {"color": 1}, Vector2i(1, 1), StringName("1")]
	var tick: float = 0.0
	for value: Variant in junk:
		tick += 100.0
		assert_false(_host._handle_seat_pref(2, value, 1, true, tick), "colour %s" % str(value))
		tick += 100.0
		assert_false(_host._handle_seat_pref(2, 1, value, true, tick), "team %s" % str(value))
	assert_eq(_seat_pref_count(), 0)


func test_seat_pref_is_refused_while_a_match_runs_and_resumes_in_the_lobby() -> void:
	_host_with_peers({2: 1})
	watch_signals(Events)
	_host.set_match_in_progress(true)
	assert_false(_host._handle_seat_pref(2, 1, 1, true, 10.0), "remote request mid-match")
	_host.request_seat_pref(1, 1)
	assert_eq(_seat_pref_count(), 0, "the host's own request mid-match too")
	_host.set_match_in_progress(false)
	assert_true(_host._handle_seat_pref(2, 1, 1, true, 20.0), "back in the lobby it is accepted again")
	assert_eq(_seat_pref_count(), 1)


func test_seat_pref_flood_is_rate_limited_per_peer() -> void:
	_host_with_peers({2: 1, 3: 2})
	watch_signals(Events)
	var burst: int = _host.config.seat_pref_burst
	for i: int in range(burst):
		assert_true(_host._handle_seat_pref(2, i % 8, -1, true, 50.0), "request %d is inside the burst" % i)
	for i: int in range(20):
		assert_false(_host._handle_seat_pref(2, 1, 1, true, 50.0), "request %d beyond the burst is dropped" % i)
	assert_eq(_seat_pref_count(), burst)
	assert_true(_host._handle_seat_pref(3, 1, 1, true, 50.0), "another peer has its own bucket")
	assert_false(_host._handle_seat_pref(2, 1, 1, true, 50.1), "a fraction of a second refills less than one request")
	# One second later the bucket has refilled by seat_pref_refill_per_s requests.
	var refilled: int = int(_host.config.seat_pref_refill_per_s)
	for i: int in range(refilled):
		assert_true(_host._handle_seat_pref(2, 1, 1, true, 51.1), "refilled request %d" % i)
	assert_false(_host._handle_seat_pref(2, 1, 1, true, 51.1), "and no more than that")
	assert_true(_host._handle_seat_pref(2, 1, 1, true, 1000.0), "a long pause refills to the burst, no further")
	assert_true(_host._seat_pref_buckets.has(2))
	_host._on_peer_disconnected(2)
	assert_false(_host._seat_pref_buckets.has(2), "a departed peer's bucket is dropped")


func test_seat_pref_malformed_flood_drains_the_bucket_too() -> void:
	_host_with_peers({2: 1})
	watch_signals(Events)
	for i: int in range(_host.config.seat_pref_burst):
		assert_false(_host._handle_seat_pref(2, "x", 99, true, 10.0))
	assert_false(_host._handle_seat_pref(2, 1, 1, true, 10.0), "garbage cannot be used to keep a free bucket")
	assert_eq(_seat_pref_count(), 0)


func test_seat_pref_flood_limit_follows_the_net_config_values() -> void:
	var tuned: NetConfig = load("res://config/net_config.tres").duplicate() as NetConfig
	assert_eq(tuned.seat_pref_burst, 6, "the shipped burst")
	assert_eq(tuned.seat_pref_refill_per_s, 3.0, "the shipped refill")
	tuned.seat_pref_burst = 2
	tuned.seat_pref_refill_per_s = 1.0
	_host.config = tuned
	_host_with_peers({2: 1})
	assert_true(_host._handle_seat_pref(2, 1, -1, true, 10.0))
	assert_true(_host._handle_seat_pref(2, 2, -1, true, 10.0))
	assert_false(_host._handle_seat_pref(2, 3, -1, true, 10.0), "a burst of 2 allows two requests")
	assert_false(_host._handle_seat_pref(2, 3, -1, true, 10.5), "half a second at 1/s is not a whole token")
	assert_true(_host._handle_seat_pref(2, 3, -1, true, 11.0), "one second at 1/s refills one request")
	assert_false(_host._handle_seat_pref(2, 4, -1, true, 11.0))


func test_net_config_sanitize_keeps_the_seat_pref_limiter_usable() -> void:
	var tuned: NetConfig = NetConfig.new()
	tuned.seat_pref_burst = 0
	tuned.seat_pref_refill_per_s = -4.0
	tuned.sanitize()
	assert_eq(tuned.seat_pref_burst, 1, "a zero burst would lock every client out")
	assert_gt(tuned.seat_pref_refill_per_s, 0.0, "a bucket that never refills would lock them out for good")
	tuned.seat_pref_burst = 6
	tuned.seat_pref_refill_per_s = 3.0
	tuned.sanitize()
	assert_eq(tuned.seat_pref_burst, 6)
	assert_eq(tuned.seat_pref_refill_per_s, 3.0)


func test_seat_pref_host_local_request_emits_under_the_local_peer_id_without_the_flood_limit() -> void:
	_host_with_peers({})
	watch_signals(Events)
	_host.request_seat_pref(2, 1)
	assert_eq(get_signal_parameters(Events, "net_seat_pref_requested", 0), [Net.HOST_PEER_ID, 2, 1])
	for i: int in range(_host.config.seat_pref_burst * 3):
		_host.request_seat_pref(i % 8, -1)
	assert_eq(_seat_pref_count(), 1 + _host.config.seat_pref_burst * 3, "the host's own UI is not throttled")
	_host.request_seat_pref(99, -1)
	_host.request_seat_pref(-1, 99)
	_host.request_seat_pref()
	assert_eq(_seat_pref_count(), 1 + _host.config.seat_pref_burst * 3, "out-of-range and empty requests are refused locally too")


func test_seat_pref_offline_request_emits_under_the_local_peer_id() -> void:
	assert_true(_host.is_offline())
	watch_signals(Events)
	_host.request_seat_pref(-1, 3)
	assert_eq(get_signal_parameters(Events, "net_seat_pref_requested", 0), [Net.HOST_PEER_ID, -1, 3])
	_host.request_seat_pref(8, 1)
	assert_eq(_seat_pref_count(), 1, "offline is validated like everywhere else")


func test_seat_pref_before_the_client_is_connected_sends_nothing() -> void:
	assert_eq(_client.join_game("127.0.0.1", _take_port(), "Clienty"), OK)
	watch_signals(Events)
	_client.request_seat_pref(1, 1)
	assert_eq(_seat_pref_count(), 0)
	assert_eq(_client.mode(), Net.Mode.CLIENT, "and nothing broke")


func test_seat_pref_over_enet_reaches_the_host_under_the_senders_transport_id() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)
	var joined: bool = await _wait_until(func() -> bool:
		return _host.peer_ids().size() == 2 and _client.local_slot() == 1
	)
	assert_true(joined, "the client is seated first")
	var client_id: int = _client.local_peer_id()
	watch_signals(Events)

	_client.request_seat_pref(3, 2)
	var landed: bool = await _wait_until(func() -> bool: return _seat_pref_count() >= 1)
	assert_true(landed, "the RPC must reach the host")
	assert_eq(get_signal_parameters(Events, "net_seat_pref_requested", 0), [client_id, 3, 2])

	# Raw packets a modified client could send (the RPC has no peer-id field to
	# forge; wrong types and ranges are the only thing left). The reliable channel
	# is ordered, so the marker request landing proves the ones before it were seen.
	_client._rpc_request_seat_pref.rpc_id(Net.HOST_PEER_ID, 1.0, "x")
	_client._rpc_request_seat_pref.rpc_id(Net.HOST_PEER_ID, 99, 1)
	_client._rpc_request_seat_pref.rpc_id(Net.HOST_PEER_ID, -1, -1)
	_client.request_seat_pref(99, 1) # refused on the client before it is sent
	_client._rpc_request_seat_pref.rpc_id(Net.HOST_PEER_ID, 5, -1)
	var marker: bool = await _wait_until(func() -> bool: return _seat_pref_count() >= 2)
	assert_true(marker, "the final valid request lands")
	assert_eq(_seat_pref_count(), 2, "only the two valid requests got through")
	assert_eq(get_signal_parameters(Events, "net_seat_pref_requested", 1), [client_id, 5, -1])

	# The seat is the client's own and the host did not change anything itself.
	assert_eq(_host.slot_of_peer(client_id), 1)
	assert_eq(_host.peer_ids().size(), 2)


func test_seat_pref_from_a_client_still_in_the_handshake_is_refused() -> void:
	# The connection exists (peer_connected fired) but no roster entry yet: the host
	# must not act on it. Model it by dropping the client's roster entry.
	var port: int = _take_port()
	_connect_host_and_client(port)
	var joined: bool = await _wait_until(func() -> bool:
		return _host.peer_ids().size() == 2 and _client.local_slot() == 1
	)
	assert_true(joined)
	_host._peers.erase(_client.local_peer_id())
	watch_signals(Events)
	_client.request_seat_pref(1, 1)
	# A request the host honours would arrive within a few frames; none must.
	for _i: int in range(20):
		await get_tree().process_frame
	assert_eq(_seat_pref_count(), 0)


# --- Lowest free lobby slot (plan R4) --------------------------------------------

func test_take_next_lobby_slot_reuses_the_lowest_free_slot_in_the_lobby() -> void:
	_host_with_peers({5: 1, 6: 2, 7: 3, 8: -1})
	assert_eq(_host._take_next_lobby_slot(), 4, "no hole: the next slot up; a spectator holds nothing")
	_host._peers.erase(6)
	assert_eq(_host._take_next_lobby_slot(), 2, "a hole below the top is filled first")
	_host._peers.erase(5)
	assert_eq(_host._take_next_lobby_slot(), 1, "the lowest hole wins")
	_host._reservations["token"] = 1
	assert_eq(_host._take_next_lobby_slot(), 2, "a slot a rejoin reservation names is not free")
	_host._peers.erase(Net.HOST_PEER_ID)
	assert_eq(_host._take_next_lobby_slot(), 0, "slot 0 comes back too once nobody holds it (the host never leaves in practice)")


func test_take_next_lobby_slot_stays_monotonic_mid_match() -> void:
	_host_with_peers({5: 1, 6: 2})
	_host._next_slot_id = 3
	_host.set_match_in_progress(true)
	_host._peers.erase(5)
	assert_eq(_host._take_next_lobby_slot(), 3, "a vacated seat is not handed to someone new mid-match")
	assert_eq(_host._take_next_lobby_slot(), 4)


func test_spectators_returning_to_the_lobby_take_the_lowest_free_slots() -> void:
	_host_with_peers({5: 1, 7: 3, 8: -1, 9: -1})
	_host.set_match_in_progress(true)
	_host.set_match_in_progress(false)
	var reseated: Array[int] = [_host.slot_of_peer(8), _host.slot_of_peer(9)]
	reseated.sort() # which spectator comes first is not specified
	assert_eq(reseated, [2, 4] as Array[int], "one fills the hole, the next goes above the top")
	assert_eq(_host.slot_of_peer(5), 1)
	assert_eq(_host.slot_of_peer(7), 3)


## A lobby leaver's seat is closed up (compaction), so the next joiner lands on top
## of the table, not in a hole; the end-to-end version over real ENet is below.
func test_a_joiner_takes_the_next_slot_after_a_departed_lobby_peer_was_compacted() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)
	var second: Variant = _make_side("SecondNet")
	assert_eq(second.join_game("127.0.0.1", port, "Seconds"), OK)
	var seated: bool = await _wait_until(func() -> bool:
		return _host.peer_ids().size() == 3 and second.local_slot() == 2 and _client.local_slot() == 1
	)
	assert_true(seated, "first joiner holds slot 1, the second slot 2")

	_client.leave()
	var gone: bool = await _wait_until(func() -> bool:
		return _host.peer_ids().size() == 2 and second.local_slot() == 1
	)
	assert_true(gone, "the host drops the first joiner and the second moves down to slot 1")

	var third: Variant = _make_side("ThirdNet")
	assert_eq(third.join_game("127.0.0.1", port, "Thirds"), OK)
	var refilled: bool = await _wait_until(func() -> bool:
		return _host.peer_ids().size() == 3 and third.local_slot() >= 0 and third.mode() == Net.Mode.CLIENT
	)
	assert_true(refilled, "the third client joins")
	assert_eq(_host.slot_of_peer(third.local_peer_id()), 2, "it takes the slot above the compacted table")
	assert_eq(_host.slot_of_peer(second.local_peer_id()), 1, "the second client kept the slot it was compacted into")
	third.leave()
	second.leave()


# --- Lobby slot compaction (P2 review finding 1) -----------------------------------

## What the lobby would decide about Start for the roster's seated peers: the seats
## it reconciles and the peer -> slot map it derives from the roster.
func _lobby_start_blocker(host: Variant, ai_count: int = 0) -> String:
	var seated: PackedInt32Array = PackedInt32Array()
	var slot_of_peer: Dictionary = {}
	for peer_id: int in host.peer_ids():
		if host.slot_of_peer(peer_id) >= 0:
			seated.append(peer_id)
			slot_of_peer[peer_id] = host.slot_of_peer(peer_id)
	var seats: Dictionary = LobbySeats.reconcile(LobbySeats.empty(), seated, ai_count, MatchConfig.AiDifficulty.NORMAL, 0)
	return LobbySeats.start_blocker(seats, slot_of_peer, 0)


func _slots_of(host: Variant, peers: Array[int]) -> Array[int]:
	var slots: Array[int] = []
	for peer_id: int in peers:
		slots.append(host.slot_of_peer(peer_id))
	return slots


func test_a_lobby_leave_compacts_the_slots_and_start_is_not_blocked() -> void:
	_host_with_peers({5: 1, 6: 2, 7: 3})
	assert_eq(_lobby_start_blocker(_host), "", "a full table starts")
	# What the old allocation left behind: the hole below the top human slot blocks
	# Start even with no bots (LobbySeats.BLOCKER_SLOT_CONFLICT), until someone rejoined.
	var seats: Dictionary = LobbySeats.reconcile(
		LobbySeats.empty(), PackedInt32Array([1, 5, 7]), 0, MatchConfig.AiDifficulty.NORMAL, 0
	)
	assert_ne(LobbySeats.start_blocker(seats, {1: 0, 5: 1, 7: 3}, 0), "", "the uncompacted table is blocked")

	_host._on_peer_disconnected(6)
	assert_eq(_slots_of(_host, [Net.HOST_PEER_ID, 5, 7] as Array[int]), [0, 1, 2] as Array[int], "7 moved down into the hole")
	assert_eq(_lobby_start_blocker(_host), "", "Start is no longer blocked after the leave")
	assert_eq(_host.peer_of_slot(2), 7)
	assert_eq(_host.peer_of_slot(3), -1, "nothing is left above the table")


func test_a_lobby_leave_with_bots_does_not_collide_with_the_trailing_bot_slots() -> void:
	_host_with_peers({5: 1, 6: 2})
	_host._on_peer_disconnected(5)
	assert_eq(_host.slot_of_peer(6), 1)
	assert_eq(_lobby_start_blocker(_host, 2), "", "2 humans + 2 bots: humans 0 and 1, bots 2 and 3")


func test_compaction_keeps_the_seat_order_and_is_deterministic() -> void:
	# Peer ids deliberately not in slot order; holes at 2, 4 and 5.
	_host_with_peers({9: 1, 8: 2, 4: 3, 7: 6, 3: 7})
	_host._on_peer_disconnected(8)
	assert_eq(_slots_of(_host, [Net.HOST_PEER_ID, 9, 4, 7, 3] as Array[int]), [0, 1, 2, 3, 4] as Array[int])
	# A second leave compacts again from the already-compacted table.
	_host._on_peer_disconnected(9)
	assert_eq(_slots_of(_host, [Net.HOST_PEER_ID, 4, 7, 3] as Array[int]), [0, 1, 2, 3] as Array[int])
	# Nothing to close up: nothing moves.
	assert_eq(_host._compact_lobby_slots(), 0)


func test_compaction_never_moves_the_host_or_a_spectator() -> void:
	_host_with_peers({5: 1, 6: 2, 8: -1})
	_host._on_peer_disconnected(5)
	assert_eq(_host.slot_of_peer(Net.HOST_PEER_ID), 0)
	assert_eq(_host.slot_of_peer(6), 1)
	assert_eq(_host.slot_of_peer(8), -1, "a spectator holds no seat and keeps holding none")


func test_a_lobby_leave_publishes_the_compacted_roster_and_reports_the_old_slot() -> void:
	_host_with_peers({5: 1, 6: 2, 7: 3})
	watch_signals(Events)
	_host._on_peer_disconnected(6)
	assert_eq(get_signal_emit_count(Events, "net_roster_changed"), 1, "one broadcast carries the whole change")
	var roster: Array = get_signal_parameters(Events, "net_roster_changed", 0)[0]
	var published: Dictionary = {}
	for entry: Dictionary in roster:
		published[int(entry["peer_id"])] = int(entry["slot_id"])
	assert_eq(published, {Net.HOST_PEER_ID: 0, 5: 1, 7: 2}, "the roster already shows the compacted slots")
	assert_eq(get_signal_parameters(Events, "net_peer_left", 0), [6, 2, Net.LeaveReason.TIMEOUT], "the leaver is reported at the slot it held")


func test_a_mid_match_leave_does_not_compact_and_keeps_the_rejoin_reservation() -> void:
	_host_with_peers({5: 1, 6: 2, 7: 3})
	_host._tokens[6] = "tok6"
	_host.set_match_in_progress(true)
	watch_signals(Events)
	_host._on_peer_disconnected(6)
	assert_eq(_slots_of(_host, [5, 7] as Array[int]), [1, 3] as Array[int], "slot ids are PlayerSlot indices mid-match: nothing moves")
	assert_eq(_host._reservations.get("tok6"), 2, "the leaver's seat is still reserved for its rejoin")
	assert_eq(_host._compact_lobby_slots(), 0, "and a direct call mid-match is refused too")
	assert_eq(get_signal_parameters(Events, "net_peer_left", 0), [6, 2, Net.LeaveReason.TIMEOUT])


func test_the_hole_a_mid_match_leave_left_closes_when_the_lobby_returns() -> void:
	_host_with_peers({5: 1, 6: 2, 7: 3})
	_host.set_match_in_progress(true)
	_host._on_peer_disconnected(6)
	assert_eq(_host.slot_of_peer(7), 3, "the hole stays for the whole match")
	watch_signals(Events)
	_host.set_match_in_progress(false)
	assert_eq(_slots_of(_host, [5, 7] as Array[int]), [1, 2] as Array[int], "back in the lobby the table closes up")
	assert_eq(get_signal_emit_count(Events, "net_roster_changed"), 1, "and is published once")
	assert_eq(_lobby_start_blocker(_host), "")
	# Returning with nothing to change publishes nothing.
	_host.set_match_in_progress(true)
	_host.set_match_in_progress(false)
	assert_eq(get_signal_emit_count(Events, "net_roster_changed"), 1)


func test_a_lobby_kick_compacts_too() -> void:
	_host_with_peers({5: 1, 6: 2, 7: 3})
	# No transport behind the fake peers: kick_peer would otherwise ask ENet to
	# disconnect (and broadcast to) ids it does not hold.
	_host.multiplayer.multiplayer_peer.close()
	_host.multiplayer.multiplayer_peer = null
	watch_signals(Events)
	_host.kick_peer(5)
	assert_eq(_slots_of(_host, [6, 7] as Array[int]), [1, 2] as Array[int])
	assert_eq(_lobby_start_blocker(_host), "")
	assert_eq(get_signal_parameters(Events, "net_peer_left", 0), [5, 1, Net.LeaveReason.KICKED], "reported at the slot it held")
	var roster: Array = get_signal_parameters(Events, "net_roster_changed", 0)[0]
	var published: Dictionary = {}
	for entry: Dictionary in roster:
		published[int(entry["peer_id"])] = int(entry["slot_id"])
	assert_eq(published, {Net.HOST_PEER_ID: 0, 6: 1, 7: 2}, "and the roster it publishes is already compacted")


func test_a_lobby_leave_over_enet_moves_the_remaining_client_down_on_every_peer() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)
	var second: Variant = _make_side("SecondNet")
	assert_eq(second.join_game("127.0.0.1", port, "Seconds"), OK)
	var seated: bool = await _wait_until(func() -> bool:
		return _host.peer_ids().size() == 3 and second.local_slot() == 2 and second.peer_ids().size() == 3
	)
	assert_true(seated, "slots 1 and 2 are taken")
	var second_id: int = second.local_peer_id()

	_client.leave()
	var agreed: bool = await _wait_until(func() -> bool:
		return second.local_slot() == 1 and second.slot_of_peer(second_id) == 1 and _host.slot_of_peer(second_id) == 1
	)
	assert_true(agreed, "the host and the client agree on the compacted slot")
	assert_eq(_host.peer_of_slot(1), second_id)
	assert_eq(second.peer_of_slot(1), second_id, "the client's own roster mirror agrees")
	assert_eq(second.peer_of_slot(2), -1)
	assert_eq(_lobby_start_blocker(_host), "", "Start is not blocked on the host")
	second.leave()


# --- Auto-assigned names follow a slot move (N1 review F1) ------------------------

## Hosts and seats fake peers as the host would have stored them:
## {peer_id: [slot_id, typed_name]}. An empty typed name is "auto": the entry holds
## the "Player N" of its slot and carries name_auto, exactly as _accept_peer writes it.
func _host_with_named_peers(seats: Dictionary) -> void:
	assert_eq(_host.host_game(_take_port(), "Hostie"), OK)
	for peer_id: int in seats.keys():
		var slot_id: int = int((seats[peer_id] as Array)[0])
		var typed: String = String((seats[peer_id] as Array)[1])
		_host._peers[peer_id] = {
			"peer_id": peer_id, "slot_id": slot_id,
			"name": typed if typed != "" else PlayerNames.fallback_for_slot(slot_id),
			"name_auto": typed == "", "ready": false, "ping_ms": 0.0, "build": "",
		}


func _names_of(host: Variant, peers: Array[int]) -> Array[String]:
	var names: Array[String] = []
	for peer_id: int in peers:
		names.append(String(host.peer_info(peer_id).get("name", "")))
	return names


func test_a_lobby_leave_re_derives_the_auto_names_of_the_peers_that_move() -> void:
	_host_with_named_peers({5: [1, ""], 6: [2, ""], 7: [3, ""]})
	assert_eq(_names_of(_host, [5, 6, 7] as Array[int]), ["Player 2", "Player 3", "Player 4"] as Array[String])
	_host._on_peer_disconnected(5)
	assert_eq(_slots_of(_host, [6, 7] as Array[int]), [1, 2] as Array[int])
	assert_eq(_names_of(_host, [6, 7] as Array[int]), ["Player 2", "Player 3"] as Array[String], "the moved peers read the seat they now hold")
	# What the next arrival, or a bot, would be called for the slot above the table.
	var next_label: String = PlayerNames.fallback_for_slot(_host._take_next_lobby_slot())
	var taken: Array[String] = _names_of(_host, [Net.HOST_PEER_ID, 6, 7] as Array[int])
	assert_eq(next_label, "Player 4")
	assert_false(taken.has(next_label), "no seated human already carries the label the next seat gets")


func test_a_name_the_player_typed_never_changes_when_the_seat_moves() -> void:
	# 7 typed "Player 3" while sitting in slot 3; compaction moves it to slot 2.
	_host_with_named_peers({5: [1, ""], 6: [2, "Zed"], 7: [3, "Player 3"]})
	_host._on_peer_disconnected(5)
	assert_eq(_slots_of(_host, [6, 7] as Array[int]), [1, 2] as Array[int])
	assert_eq(_names_of(_host, [6, 7] as Array[int]), ["Zed", "Player 3"] as Array[String], "typed names are the player's own, whatever the slot")
	assert_false(bool(_host.peer_info(7).get("name_auto", true)))


func test_the_roster_published_after_a_move_carries_the_re_derived_names() -> void:
	_host_with_named_peers({5: [1, ""], 6: [2, ""]})
	watch_signals(Events)
	_host._on_peer_disconnected(5)
	var roster: Array = get_signal_parameters(Events, "net_roster_changed", 0)[0]
	var published: Dictionary = {}
	for entry: Dictionary in roster:
		published[int(entry["peer_id"])] = String(entry["name"])
	assert_eq(published[6], "Player 2", "every peer is told the new name in the same roster as the new slot")
	assert_eq(_host.name_for_slot(1), "Player 2")


func test_a_spectator_reseated_in_the_lobby_takes_the_fallback_of_its_seat() -> void:
	_host_with_named_peers({5: [1, ""], 8: [-1, ""], 9: [-1, "Watcher"]})
	assert_eq(_host.peer_info(8).get("name"), "Spectator")
	_host.set_match_in_progress(true)
	_host.set_match_in_progress(false)
	for peer_id: int in [8, 9]:
		assert_gte(_host.slot_of_peer(peer_id), 2, "both spectators are seated again")
	assert_eq(_host.peer_info(8).get("name"), PlayerNames.fallback_for_slot(_host.slot_of_peer(8)), "an auto name follows the new seat")
	assert_eq(_host.peer_info(9).get("name"), "Watcher", "a typed name stays")


## The reviewer's scenario end to end over ENet: three default (empty-name) joiners,
## the first leaves, the others move down and are renamed on every peer, and the next
## joiner and a bot's seat do not reuse a label.
func test_default_named_joiners_keep_unique_player_names_through_a_leave_over_enet() -> void:
	var port: int = _take_port()
	assert_eq(_host.host_game(port, "Hostie"), OK)
	var second: Variant = _make_side("SecondNet")
	var third: Variant = _make_side("ThirdNet")
	var fourth: Variant = _make_side("FourthNet")
	var sides: Array = [_client, second, third]
	for index: int in range(sides.size()):
		assert_eq(sides[index].join_game("127.0.0.1", port, ""), OK, "an empty name is what the menu sends by default")
		var seated: bool = await _wait_until(func() -> bool:
			return sides[index].local_slot() == index + 1 and _host.peer_ids().size() == index + 2
		)
		assert_true(seated, "joiner %d takes slot %d" % [index, index + 1])
	var second_id: int = second.local_peer_id()
	var third_id: int = third.local_peer_id()
	assert_eq(_names_of(_host, [_client.local_peer_id(), second_id, third_id] as Array[int]),
		["Player 2", "Player 3", "Player 4"] as Array[String])

	_client.leave()
	var moved: bool = await _wait_until(func() -> bool:
		return second.local_slot() == 1 and third.local_slot() == 2 and String(third.peer_info(third_id).get("name", "")) == "Player 3"
	)
	assert_true(moved, "the remaining joiners move down and hear their new names")
	assert_eq(_names_of(_host, [second_id, third_id] as Array[int]), ["Player 2", "Player 3"] as Array[String], "host")
	assert_eq(_names_of(second, [second_id, third_id] as Array[int]), ["Player 2", "Player 3"] as Array[String], "joiner mirror")
	assert_eq(_host.name_for_slot(2), "Player 3")

	assert_eq(fourth.join_game("127.0.0.1", port, ""), OK)
	var joined: bool = await _wait_until(func() -> bool:
		return fourth.local_slot() == 3 and _host.peer_ids().size() == 4
	)
	assert_true(joined, "the next joiner takes the slot above the table")
	var names: Array[String] = _names_of(_host, [Net.HOST_PEER_ID, second_id, third_id, fourth.local_peer_id()] as Array[int])
	assert_eq(names, ["Hostie", "Player 2", "Player 3", "Player 4"] as Array[String], "no duplicate label")
	assert_false(names.has(PlayerNames.fallback_for_slot(4)), "and a bot at the first slot after the humans is not shadowed")
	fourth.leave()
	third.leave()
	second.leave()


# --- kick_peer announces the compacted table (N1 review F2) ----------------------

func test_a_lobby_kick_compacts_before_net_peer_left_is_emitted() -> void:
	_host_with_named_peers({5: [1, ""], 6: [2, ""], 7: [3, ""]})
	_host.multiplayer.multiplayer_peer.close()
	_host.multiplayer.multiplayer_peer = null
	var seen: Dictionary = {}
	var on_left: Callable = func(_peer_id: int, _slot_id: int, _reason: int) -> void:
		seen["slots"] = _slots_of(_host, [6, 7] as Array[int])
		seen["peer_at_2"] = _host.peer_of_slot(2)
		seen["peer_at_3"] = _host.peer_of_slot(3)
	Events.net_peer_left.connect(on_left)
	_host.kick_peer(5)
	Events.net_peer_left.disconnect(on_left)
	assert_eq(seen.get("slots"), [1, 2] as Array[int], "a net_peer_left listener already reads the closed-up slots")
	assert_eq(seen.get("peer_at_2"), 7)
	assert_eq(seen.get("peer_at_3"), -1)


## Bontago-1pi.57: kick_peer announced the new roster with a plain broadcast while
## the kicked peer was still in get_peers() (ENet only drops it once its disconnect
## completes), which the engine reports as an error ("Unable to send packet on
## channel 0, max channels: 0"). Over a real ENet connection; GUT fails a test on an
## unexpected engine error.
func test_kicking_a_connected_peer_over_enet_raises_no_engine_error() -> void:
	var port: int = _take_port()
	_connect_host_and_client(port)
	var joined: bool = await _wait_until(func() -> bool:
		return _host.peer_ids().size() == 2 and _client.peer_ids().size() == 2
	)
	assert_true(joined, "host and client settle on a 2-peer roster first")
	var client_id: int = _client.local_peer_id()
	assert_true(_host.multiplayer.get_peers().has(client_id), "the client is a live ENet peer")
	watch_signals(Events)
	_host.kick_peer(client_id)
	assert_false(_host.peer_ids().has(client_id), "the kicked peer is out of the host's roster")
	assert_eq(get_signal_parameters(Events, "net_peer_left", 0), [client_id, 1, Net.LeaveReason.KICKED])
	var published: Array = get_signal_parameters(Events, "net_roster_changed", 0)[0]
	assert_eq(published.size(), 1, "the roster the host publishes is the host alone")
	assert_true(_host.multiplayer.get_peers().has(client_id), "ENet still lists the peer until its disconnect completes")
	assert_false(_host._broadcast_targets().has(client_id), "but no broadcast addresses it")
	# A republish by a net_peer_left listener (the lobby does) is a broadcast too.
	_host.set_lobby_data({"map_variant": 1})
	# Let the disconnect complete and a few frames pass.
	await _wait_until(func() -> bool: return _host.multiplayer.get_peers().is_empty(), 120)
	assert_true(_host.multiplayer.get_peers().is_empty(), "the disconnect completes")
	assert_eq(get_signal_emit_count(Events, "net_roster_changed"), 1, "the kicked client was sent no roster either")


func test_kicking_one_of_two_connected_peers_still_tells_the_other_over_enet() -> void:
	var port: int = _take_port()
	assert_eq(_host.host_game(port, "Hostie"), OK)
	var second: Variant = _make_side("SecondNet")
	assert_eq(_client.join_game("127.0.0.1", port, "Clienty"), OK)
	assert_eq(second.join_game("127.0.0.1", port, "Seconda"), OK)
	var seated: bool = await _wait_until(func() -> bool:
		return _host.peer_ids().size() == 3 and _client.peer_ids().size() == 3 and second.peer_ids().size() == 3
	)
	assert_true(seated, "all three settle on a 3-peer roster")
	var kicked_id: int = _client.local_peer_id()
	var kept_id: int = second.local_peer_id()
	_host.kick_peer(kicked_id)
	var told: bool = await _wait_until(func() -> bool:
		return second.peer_ids().size() == 2 and not second.peer_ids().has(kicked_id)
	)
	assert_true(told, "the peer that stays hears the roster without the kicked one")
	assert_eq(second.local_slot(), 1, "and its seat closed up behind the kicked peer")
	assert_eq(_host.slot_of_peer(kept_id), 1)
	second.leave()


## kick_peer for an id the transport does not hold (a fake peer, or one that already
## dropped) has nothing to disconnect: no engine error, and nothing left marked.
func test_kicking_a_peer_the_transport_does_not_hold_raises_no_engine_error() -> void:
	_host_with_peers({5: 1, 6: 2})
	watch_signals(Events)
	_host.kick_peer(5)
	assert_false(_host.peer_ids().has(5))
	assert_eq(get_signal_emit_count(Events, "net_peer_left"), 1)
	assert_true(_host._disconnecting_peers.is_empty(), "nothing is waiting on a disconnect that never started")


func test_a_lobby_disconnect_compacts_before_net_peer_left_is_emitted() -> void:
	_host_with_named_peers({5: [1, ""], 6: [2, ""], 7: [3, ""]})
	var seen: Dictionary = {}
	var on_left: Callable = func(_peer_id: int, _slot_id: int, _reason: int) -> void:
		seen["slots"] = _slots_of(_host, [6, 7] as Array[int])
	Events.net_peer_left.connect(on_left)
	_host._on_peer_disconnected(5)
	Events.net_peer_left.disconnect(on_left)
	assert_eq(seen.get("slots"), [1, 2] as Array[int], "both departure paths publish the same table")


# --- NetConfig is sanitized where it is loaded (N1 review F3) ----------------------

func test_sanitize_changes_nothing_on_the_shipped_net_config() -> void:
	var shipped: NetConfig = load("res://config/net_config.tres") as NetConfig
	var sanitized: NetConfig = shipped.duplicate() as NetConfig
	sanitized.sanitize()
	for info: Dictionary in shipped.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var prop: StringName = StringName(info["name"])
		assert_eq(sanitized.get(prop), shipped.get(prop), "sanitize() must not alter the shipped %s (Net._ready now calls it)" % prop)


func test_net_ready_sanitizes_a_hand_edited_config() -> void:
	var edited: NetConfig = NetConfig.new()
	edited.seat_pref_burst = 0
	edited.seat_pref_refill_per_s = 0.0
	var side: Variant = _make_side("TunedNet", edited)
	assert_eq(side.config.seat_pref_burst, 1, "a zero burst would lock every client out of seat requests")
	assert_gt(side.config.seat_pref_refill_per_s, 0.0)


# --- FakeNet stub ---------------------------------------------------------------

func test_fakenet_records_seat_pref_requests() -> void:
	var fake: FakeNet = FakeNet.client(1)
	assert_eq(fake.request_seat_pref_calls.size(), 0)
	fake.request_seat_pref(2, -1)
	fake.request_seat_pref(-1, 3)
	fake.request_seat_pref()
	assert_eq(fake.request_seat_pref_calls.size(), 3)
	assert_eq(fake.request_seat_pref_calls[0], {"color_index": 2, "team_pick": -1})
	assert_eq(fake.request_seat_pref_calls[1], {"color_index": -1, "team_pick": 3})
	assert_eq(fake.request_seat_pref_calls[2], {"color_index": -1, "team_pick": -1})
