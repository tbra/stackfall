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
