extends GutTest
## autoload/Net.gd: session lifecycle, handshake, roster, disconnect and
## command-line parsing (spec 2.6).
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

## Minimum wall-clock budget of every _wait_until before it reports failure.
const _WAIT_FLOOR_MSEC: int = 8000
## Wall-clock budget of one host+join attempt, and how many attempts to make.
const _PAIR_ATTEMPT_MSEC: int = 4000
const _PAIR_ATTEMPTS: int = 3


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
	# A host closes a refused connection a couple of frames after the refusal
	# was sent (the refusal RPC must reach the wire first). Give it that time before add_child_
	# autofree() frees the node out from under the still-awaiting coroutine.
	await get_tree().process_frame
	await get_tree().process_frame


func _take_port() -> int:
	# Parallel gate shards (tools/full_gate.py) run several Godot processes at
	# once; a fixed port sequence collided, so ask the OS for a free port.
	return AgentProbe.free_udp_port()


## Polls until `condition` (a Callable returning bool) is true. Gives up only
## once `frames` process frames AND `_WAIT_FLOOR_MSEC` of wall clock have both
## passed: headless frames are uncapped (200 can elapse in milliseconds), while
## an ENet handshake needs real time, so a frame-only deadline flaked when
## parallel gate shards loaded the CPU. Returns success.
func _wait_until(condition: Callable, frames: int = 200) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + _WAIT_FLOOR_MSEC
	var spent: int = 0
	while spent < frames or Time.get_ticks_msec() < deadline_msec:
		if condition.call():
			return true
		await get_tree().process_frame
		spent += 1
	return condition.call()


## Hosts and joins on `port`, waits for the seated handshake, and returns the
## port that worked. one gate run saw a loopback join never land in
## a sharded run (no log evidence of a collision; passes alone), so a pair that
## has not seated within `_PAIR_ATTEMPT_MSEC` is torn down and retried on a fresh
## OS-chosen port, up to `_PAIR_ATTEMPTS` times. The last attempt's state is left
## in place for the test's own assertions and the first failure is printed with
## its port and modes so a recurrence is attributable.
func _connect_host_and_client(port: int, max_peers: int = -1) -> int:
	if max_peers > 0:
		var host_config: NetConfig = load("res://config/net/net_config.tres").duplicate() as NetConfig
		host_config.max_peers = max_peers
		_host.config = host_config
	var use_port: int = port
	for attempt: int in _PAIR_ATTEMPTS:
		if attempt > 0:
			_client.leave()
			_host.leave()
			await get_tree().process_frame
			await get_tree().process_frame
			use_port = _take_port()
		assert_eq(_host.host_game(use_port, "Hostie"), OK)
		assert_eq(_client.join_game("127.0.0.1", use_port, "Clienty"), OK)
		var seated: bool = await _wait_until_msec(func() -> bool:
			return _host.peer_ids().size() == 2 and _client.local_slot() == 1,
			_PAIR_ATTEMPT_MSEC
		)
		if seated:
			return use_port
		print("net-flake: pair attempt %d on port %d did not seat (host mode %d peers %d, client mode %d slot %d)" % [
			attempt, use_port, _host.mode(), _host.peer_ids().size(), _client.mode(), _client.local_slot()])
	return use_port


## Polls `condition` every frame until true or `msec` of wall clock has passed.
func _wait_until_msec(condition: Callable, msec: int) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < deadline_msec:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


# --- Connect, handshake, roster ---------------------------------------------

func test_host_and_client_appear_in_each_others_roster() -> void:
	var port: int = _take_port()
	port = await _connect_host_and_client(port)

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


# --- Version handshake -------------------------------------------------------

func test_mismatched_build_version_is_refused_and_disconnected() -> void:
	# DECISION (autoload/Net.gd): host_game() snapshots build_version() once,
	# into _host_build_version, instead of re-reading ProjectSettings live in
	# _rpc_handshake — a host's advertised version cannot legitimately change
	# mid-session anyway, and it is what makes the version bump below
	# race-free to test in one process: it reproduces spec 2.6's "Compare the
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


# --- Lobby-only joining ---------------------------------------
#
# Spec 2.6: joining is lobby-only in M3a. Net does not know Match's state
# machine (Net must not name a gameplay concept), so the
# match flow flips set_accepting_joins(); these tests flip it directly. The
# "not accepting" window stands in for COUNTDOWN, PLAYING, SUDDEN_DEATH and
# END alike — Net treats every non-lobby state the same way.

func test_joins_resume_once_the_match_returns_to_the_lobby() -> void:
	# under a loaded gate shard the loopback connect sometimes never
	# landed within the wait (no refusal ever came, so the assert and the
	# parameters read failed). Same remedy as _connect_host_and_client: bound
	# each attempt, retry on a fresh port, and print the attempt on a miss.
	var port: int = _take_port()
	var refused: bool = false
	watch_signals(Events)
	for attempt: int in _PAIR_ATTEMPTS:
		if attempt > 0:
			_client.leave()
			_host.leave()
			await get_tree().process_frame
			await get_tree().process_frame
			port = _take_port()
			watch_signals(Events)
		assert_eq(_host.host_game(port, "Hostie"), OK)
		_host.set_accepting_joins(false)
		assert_eq(_client.join_game("127.0.0.1", port, "Clienty"), OK)
		refused = await _wait_until_msec(func() -> bool:
			return get_signal_emit_count(Events, "net_join_failed") > 0,
			_PAIR_ATTEMPT_MSEC
		)
		if refused:
			break
		print("net-flake: refusal attempt %d on port %d never arrived (host mode %d, client mode %d)" % [
			attempt, port, _host.mode(), _client.mode()])
	assert_true(refused, "refused while the match runs")
	if not refused:
		return
	assert_eq(get_signal_parameters(Events, "net_join_failed")[0], Net.JoinError.MATCH_IN_PROGRESS)
	assert_eq(_host.peer_ids().size(), 1, "the host is still alone")
	assert_eq(_client.mode(), Net.Mode.OFFLINE)

	# The match ends and the flow returns to the lobby. The host stays up
	# across the refusal here (unlike the tests above, where after_each tears
	# it down inside the refusal's two-frame grace), so this also covers the
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
	port = await _connect_host_and_client(port)
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


## reproduces the teardown-ordering race in isolation.
## Before the NetTransport.can_broadcast() guard, _broadcast_roster() called
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
	port = await _connect_host_and_client(port)
	await _wait_until(func() -> bool: return _host.peer_ids().size() == 2)
	var client_id: int = _client.local_peer_id()

	# Simulate the transport already closing while _mode is still HOST — the
	# exact ordering _on_peer_disconnected can race.
	_host.multiplayer.multiplayer_peer.close()
	_host.multiplayer.multiplayer_peer = null

	assert_false(_host.transport.can_broadcast(_host.multiplayer, _host.is_host()), "no live multiplayer_peer to send through")
	_host._on_peer_disconnected(client_id)
	await get_tree().process_frame
	# Reaching here without GUT recording an "Unexpected Errors" failure is
	# the assertion: the RPC attempt above must have been skipped.


# --- leave() idempotence -----------------------------------------------

# --- Command line -------------------------------------------------------

## apply_command_line() itself always reads the real OS.get_cmdline_user_args()
## (there is no OS.set_cmdline_user_args() to fake it with), so these drive
## the private _apply_command_line_args(args) it delegates to instead — the
## exact same parsing/dispatch code, with the argument list passed explicitly.

# --- Steam session (spec 2.6) --------------------------
#
# Every test below drives Net through a FakeSteam, never the real Steam
# singleton, so the suite is correct whether or not addons/godotsteam/ is
# installed in this checkout.
#
# steam_available() requires both steam_provider.is_available() *and* a
# successful init_result (see autoload/Net.gd's `_steam_ready`), matching
# real usage where game/main/Main.gd always calls Net.init_steam() before the menu
# can reach host_online()/join_lobby() — so every positive-path test below
# calls _ready_steam() first. Net.gd additionally refuses to ever construct a
# real SteamMultiplayerPeer for a fake provider, a hard safety rail this worker added after reproducing a
# real engine crash: calling SteamMultiplayerPeer.create_host()/create_client()
# without a prior successful steamInitEx() segfaults the process
# (netcode-F-probe_peer_no_init.log). That means the actual HOST/CLIENT mode
# transition after a successful lobby_created/lobby_joined is exactly the one
# step GUT genuinely cannot
# exercise — every test below asserts the (deterministic, safe) OFFLINE
# outcome for that step rather than skipping it.

## Wires `fake` in as `node`'s steam_provider and runs it through
## init_steam() so steam_available() reads true afterward (fake's
## init_status_value defaults to 0, Steamworks' own "ok").
func _ready_steam(node: Variant, fake: FakeSteam) -> void:
	node.steam_provider = fake
	node.init_steam()


## Lets Net's own frame pump (_process -> run_callbacks) deliver what Steam queued.
func _steam_frames() -> void:
	for _i: int in range(2):
		await get_tree().process_frame


func _answer_created(fake: FakeSteam, lobby_id: int) -> void:
	fake.queue_lobby_created(FakeSteam.RESULT_OK, lobby_id)
	await _steam_frames()


func test_steam_unavailable_refuses_host_online_without_creating_a_lobby() -> void:
	var fake: FakeSteam = FakeSteam.new()
	fake.available_value = false
	_ready_steam(_host, fake)

	assert_false(_host.steam_available())
	assert_eq(_host.host_online("Hostie"), ERR_UNAVAILABLE)
	assert_eq(_host.mode(), Net.Mode.OFFLINE)
	assert_true(fake.create_lobby_calls.is_empty())


func test_lobby_created_tags_the_lobby_with_the_json_encoded_match_config() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_host, fake)
	# Set before hosting, the same way ui/lobby/Lobby.gd could prime settings
	# before host_online() actually finishes creating the lobby: is_host()
	# is true offline too, so this is accepted and stored locally.
	_host.set_lobby_data({"map_variant": 2, "player_count": 4})

	assert_eq(_host.host_online("Hostie"), OK)
	var lobby_id: int = 4242
	await _answer_created(fake, lobby_id)

	assert_eq(fake.get_lobby_data(lobby_id, String(SteamClient.KEY_GAME)), String(Net.DISCOVERY_MAGIC))
	assert_eq(fake.get_lobby_data(lobby_id, String(SteamClient.KEY_VERSION)), _host.build_version())
	assert_eq(fake.get_lobby_data(lobby_id, String(SteamClient.KEY_HOST_NAME)), "TestSteamUser")
	assert_eq(fake.joinable_calls, [[lobby_id, true]], "host lobby is explicitly joinable")

	var decoded: Dictionary = JSON.parse_string(
		fake.get_lobby_data(lobby_id, String(SteamClient.KEY_MATCH_CONFIG))
	) as Dictionary
	assert_eq(int(decoded.get("map_variant")), 2, "the JSON-encoded config must be written under one key")
	assert_eq(int(decoded.get("player_count")), 4)

	# The lobby is tagged unconditionally (see the block comment above), but
	# actually becoming HOST needs a real SteamMultiplayerPeer, which Net.gd
	# now refuses to construct for a FakeSteam-driven provider (crash safety;
	# see this file's own header comment above).
	assert_eq(_host.mode(), Net.Mode.OFFLINE, "no real SteamMultiplayerPeer is ever built for a FakeSteam provider")
	assert_false(_host.is_steam_session())


## Stand-in for a SteamMultiplayerPeer: a connected peer that never touches a network.
class StubSteamPeer:
	extends MultiplayerPeerExtension

	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return MultiplayerPeer.CONNECTION_CONNECTED

	func _get_unique_id() -> int:
		return Net.HOST_PEER_ID

	func _get_available_packet_count() -> int:
		return 0

	func _poll() -> void:
		pass

	func _close() -> void:
		pass


## NetTransport.steam_host_peer_factory is the seam that replaced the old
## steam_host_peer_override field: with it set, host_online() reaches the live
## Steam HOST state under a FakeSteam, and the factory's peer is what Net uses.
func test_steam_host_peer_factory_seam_reaches_the_host_state() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_host, fake)
	var stub: StubSteamPeer = StubSteamPeer.new()
	var calls: Array[int] = []
	_host.transport.steam_host_peer_factory = func() -> MultiplayerPeer:
		calls.append(1)
		return stub
	assert_eq(_host.host_online("Hostie"), OK)
	await _answer_created(fake, 4242)
	assert_eq(calls.size(), 1, "the factory built the host peer once")
	assert_eq(_host.mode(), Net.Mode.HOST, "the factory's peer carries the Steam HOST state")
	assert_true(_host.is_steam_session())
	assert_eq(_host.multiplayer.multiplayer_peer, stub)
	assert_true(fake.leave_lobby_calls.is_empty(), "the lobby is kept, not released as for a refused peer")


## An unset factory is the real path: a FakeSteam provider never gets a
## SteamMultiplayerPeer, and the lobby is released.
func test_steam_host_peer_without_a_factory_stays_unbuilt_for_a_fake_provider() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_host, fake)
	assert_false(_host.transport.steam_host_peer_factory.is_valid())
	assert_eq(_host.host_online("Hostie"), OK)
	await _answer_created(fake, 77)
	assert_eq(_host.mode(), Net.Mode.OFFLINE)
	assert_eq(fake.leave_lobby_calls, [77])


func test_lobby_joined_with_a_failure_response_refuses_and_returns_offline() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_client, fake)
	assert_eq(_client.join_lobby(9001, "Clienty"), OK)

	watch_signals(Events)
	fake.queue_lobby_joined(9001, 3) # k_EChatRoomEnterResponseFull-shaped failure, not 1
	await _steam_frames()

	assert_eq(get_signal_emit_count(Events, "net_join_failed"), 1)
	assert_eq(get_signal_parameters(Events, "net_join_failed")[0], Net.JoinError.REFUSED)
	assert_eq(_client.mode(), Net.Mode.OFFLINE)


func test_apply_connect_lobby_from_the_full_command_line_calls_join_lobby() -> void:
	var fake: FakeSteam = FakeSteam.new()
	_ready_steam(_client, fake)

	var started: bool = _client._apply_connect_lobby_args(
		PackedStringArray(["stackfall.exe", "+connect_lobby", "12345"])
	)
	assert_true(started)
	assert_eq(fake.join_lobby_calls, [12345])


# --- In-flight guard (finding B) ----------------------------
# host_online()/join_lobby() only kick off Steam's own async request; _mode
# stays OFFLINE the whole time that answer is pending (every test above
# already proves this). A second call in the meantime must not issue a
# second Steam request -- there would be no way to tell the two requests'
# eventual answers apart -- so it is refused with ERR_BUSY instead.

## REPRO: the case the test above does not cover -- a SECOND
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
	await _answer_created(fake, 111)
	assert_eq(fake.leave_lobby_calls, [111], "the first-delivered answer must be abandoned, not hosted")
	assert_true(
		fake.set_lobby_data_calls.is_empty(),
		"an abandoned answer must never be tagged as if it were the live attempt's own lobby"
	)
	assert_eq(_host.mode(), Net.Mode.OFFLINE, "attempt 2 must still be unresolved")
	assert_false(_host.is_steam_session())

	# Attempt 2's real answer, delivered afterward, must still be accepted --
	# not dropped as stale in its place (the exact bug this fix targets).
	await _answer_created(fake, 222)
	assert_eq(
		fake.get_lobby_data(222, String(SteamClient.KEY_HOST_NAME)), "TestSteamUser",
		"the attempt delivered second must be accepted as the live one, tagged with its own player name"
	)
	# 222 is still handed to leave_lobby() here too, but for an unrelated,
	# pre-existing reason every other P1 test already hits: NetTransport's Steam
	# host peer factory refuses to build a real SteamMultiplayerPeer for a FakeSteam-
	# driven provider (crash safety), so even the *accepted* lobby's peer
	# construction fails and the lobby is released. That is not this fix's
	# stale-answer path (which never reaches set_lobby_data() at all, proven
	# above for 111) -- get_lobby_data() above already proves 222 was tagged
	# as the live attempt first.
	assert_eq(fake.leave_lobby_calls, [111, 222])


# The generation/FIFO queue and the creator's-echo filter are covered through
# NetSteamSession in test_net_steam_session.gd.

# --- Lobby seat preferences ------------------------------------
#
# Net.request_seat_pref -> any_peer RPC -> host checks -> Events.net_seat_pref_requested.
# The host-side checks and the flood bucket are NetLobbyIntents (test_lobby_flood.gd);
# the cases here prove the RPC and the session lifecycle around the bucket over ENet.

## Hosts on a free port and seats fake peers: {peer_id: slot_id} (-1 = spectator).
func _host_with_peers(slots: Dictionary) -> void:
	assert_eq(_host.host_game(_take_port(), "Hostie"), OK)
	for peer_id: int in slots.keys():
		_host.net_roster.peers[peer_id] = {
			"peer_id": peer_id, "slot_id": int(slots[peer_id]), "name": "P%d" % peer_id,
			"ready": false, "ping_ms": 0.0, "build": "",
		}


func _seat_pref_count() -> int:
	return get_signal_emit_count(Events, "net_seat_pref_requested")


const _SEAT_PREF_FLOOD: int = 40


func test_seat_pref_from_a_client_reaches_the_lobby_with_the_senders_peer_id() -> void:
	var port: int = _take_port()
	port = await _connect_host_and_client(port)
	watch_signals(Events)
	_client.request_seat_pref(3, 2)
	var arrived: bool = await _wait_until(func() -> bool: return _seat_pref_count() == 1)
	assert_true(arrived, "a seated peer's in-range request goes through the RPC")
	assert_eq(get_signal_parameters(Events, "net_seat_pref_requested", 0), [_client.local_peer_id(), 3, 2])


func test_seat_pref_flood_over_the_wire_is_bounded_to_a_burst() -> void:
	var port: int = _take_port()
	port = await _connect_host_and_client(port)
	watch_signals(Events)
	var burst: int = _host.config.seat_pref_burst
	for i: int in _SEAT_PREF_FLOOD:
		_client._rpc_request_seat_pref.rpc_id(Net.HOST_PEER_ID, i % 8, -1)
	for _i: int in range(30):
		await get_tree().process_frame
	await _wait_until(func() -> bool: return _seat_pref_count() >= burst)
	# The +1 allows the token the wall clock refills while the test runs.
	assert_between(_seat_pref_count(), burst, burst + 1)


func test_a_peer_that_left_and_rejoined_gets_a_full_seat_pref_burst() -> void:
	var port: int = _take_port()
	port = await _connect_host_and_client(port)
	var burst: int = _host.config.seat_pref_burst
	watch_signals(Events)
	for i: int in _SEAT_PREF_FLOOD:
		_client._rpc_request_seat_pref.rpc_id(Net.HOST_PEER_ID, i % 8, -1)
	await _wait_until(func() -> bool: return _seat_pref_count() >= burst)
	for _i: int in range(30):
		await get_tree().process_frame
	var first_run: int = _seat_pref_count()
	assert_between(first_run, burst, burst + 1, "the flood was clipped at the burst")
	_client.leave()
	var gone: bool = await _wait_until(func() -> bool: return _host.peer_ids().size() == 1)
	assert_true(gone, "the host saw it leave")
	assert_eq(_client.join_game("127.0.0.1", port, "Clienty"), OK)
	var back: bool = await _wait_until(func() -> bool: return _host.peer_ids().size() == 2 and _client.local_slot() == 1)
	assert_true(back, "the same player is seated again")
	for i: int in _SEAT_PREF_FLOOD:
		_client._rpc_request_seat_pref.rpc_id(Net.HOST_PEER_ID, i % 8, -1)
	await _wait_until(func() -> bool: return _seat_pref_count() >= first_run + burst)
	for _i: int in range(30):
		await get_tree().process_frame
	assert_between(_seat_pref_count() - first_run, burst, burst + 1, "a rejoined peer starts with a full burst")


func test_the_hosts_own_seat_pref_is_not_flood_limited_and_stops_mid_match() -> void:
	_host_with_peers({})
	watch_signals(Events)
	var burst: int = _host.config.seat_pref_burst
	for i: int in burst + _SEAT_PREF_FLOOD:
		_host.request_seat_pref(i % 8, -1)
	assert_eq(_seat_pref_count(), burst + _SEAT_PREF_FLOOD, "the local human is trusted")
	_host.set_match_in_progress(true)
	_host.request_seat_pref(1, 1)
	assert_eq(_seat_pref_count(), burst + _SEAT_PREF_FLOOD, "the host's own request mid-match is refused")
	_host.set_match_in_progress(false)
	_host.request_seat_pref(1, 1)
	assert_eq(_seat_pref_count(), burst + _SEAT_PREF_FLOOD + 1, "back in the lobby it is accepted again")


func test_seat_pref_from_a_client_still_in_the_handshake_is_refused() -> void:
	# The connection exists (peer_connected fired) but no roster entry yet: the host
	# must not act on it. Model it by dropping the client's roster entry.
	var port: int = _take_port()
	port = await _connect_host_and_client(port)
	var joined: bool = await _wait_until(func() -> bool:
		return _host.peer_ids().size() == 2 and _client.local_slot() == 1
	)
	assert_true(joined)
	_host.net_roster.peers.erase(_client.local_peer_id())
	watch_signals(Events)
	_client.request_seat_pref(1, 1)
	# A request the host honours would arrive within a few frames; none must.
	for _i: int in range(20):
		await get_tree().process_frame
	assert_eq(_seat_pref_count(), 0)


# --- Lowest free lobby slot (plan R4) --------------------------------------------

func test_take_next_lobby_slot_reuses_the_lowest_free_slot_in_the_lobby() -> void:
	_host_with_peers({5: 1, 6: 2, 7: 3, 8: -1})
	assert_eq(_host.net_roster.take_next_lobby_slot(), 4, "no hole: the next slot up; a spectator holds nothing")
	_host.net_roster.peers.erase(6)
	assert_eq(_host.net_roster.take_next_lobby_slot(), 2, "a hole below the top is filled first")
	_host.net_roster.peers.erase(5)
	assert_eq(_host.net_roster.take_next_lobby_slot(), 1, "the lowest hole wins")
	_host.net_roster.reservations["token"] = 1
	assert_eq(_host.net_roster.take_next_lobby_slot(), 2, "a slot a rejoin reservation names is not free")
	_host.net_roster.peers.erase(Net.HOST_PEER_ID)
	assert_eq(_host.net_roster.take_next_lobby_slot(), 0, "slot 0 comes back too once nobody holds it (the host never leaves in practice)")


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


func test_a_lobby_leave_over_enet_moves_the_remaining_client_down_on_every_peer() -> void:
	var port: int = _take_port()
	port = await _connect_host_and_client(port)
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
		_host.net_roster.peers[peer_id] = {
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
	var next_label: String = PlayerNames.fallback_for_slot(_host.net_roster.take_next_lobby_slot())
	var taken: Array[String] = _names_of(_host, [Net.HOST_PEER_ID, 6, 7] as Array[int])
	assert_eq(next_label, "Player 4")
	assert_false(taken.has(next_label), "no seated human already carries the label the next seat gets")


# --- kick_peer announces the compacted table (N1 review F2) ----------------------

## kick_peer announced the new roster with a plain broadcast while
## the kicked peer was still in get_peers() (ENet only drops it once its disconnect
## completes), which the engine reports as an error ("Unable to send packet on
## channel 0, max channels: 0"). Over a real ENet connection; GUT fails a test on an
## unexpected engine error.
func test_kicking_a_connected_peer_over_enet_raises_no_engine_error() -> void:
	var port: int = _take_port()
	port = await _connect_host_and_client(port)
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
	assert_false(_host.transport.broadcast_targets(_host.multiplayer, _host.is_host()).has(client_id), "but no broadcast addresses it")
	# A republish by a net_peer_left listener (the lobby does) is a broadcast too.
	_host.set_lobby_data({"map_variant": 1})
	# Let the disconnect complete and a few frames pass.
	await _wait_until(func() -> bool: return _host.multiplayer.get_peers().is_empty(), 120)
	assert_true(_host.multiplayer.get_peers().is_empty(), "the disconnect completes")
	assert_eq(get_signal_emit_count(Events, "net_roster_changed"), 1, "the kicked client was sent no roster either")


# --- NetConfig is sanitized where it is loaded (N1 review F3) ----------------------

# --- FakeNet stub ---------------------------------------------------------------


func test_server_full_refuses_the_next_peer() -> void:
	var port: int = _take_port()
	port = await _connect_host_and_client(port, 2)
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


func test_leave_from_either_side_returns_both_to_offline_and_is_idempotent() -> void:
	var port: int = _take_port()
	port = await _connect_host_and_client(port)
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


# --- NetRoster: compaction, reservations and tokens (no sockets) -------------------

const _ROSTER_BUILD: String = "9.9.9"
const _ROSTER_TOKEN_CHARS: int = NetRoster.REJOIN_TOKEN_BYTES * 2


func _roster_with(seats: Dictionary) -> NetRoster:
	var roster: NetRoster = NetRoster.new(NetConfig.new())
	roster.add_host("Hostie", _ROSTER_BUILD, true)
	for peer_id: int in seats.keys():
		roster.accept(peer_id, _ROSTER_BUILD, "P%d" % peer_id, int(seats[peer_id]))
	return roster


func test_roster_compact_closes_holes_in_slot_order_and_leaves_spectators() -> void:
	var roster: NetRoster = _roster_with({5: 1, 6: 3, 7: 4, 8: -1})
	assert_eq(roster.compact(), 2, "the two peers above the hole moved down")
	assert_eq(roster.slot_of_peer(5), 1)
	assert_eq(roster.slot_of_peer(6), 2)
	assert_eq(roster.slot_of_peer(7), 3)
	assert_eq(roster.slot_of_peer(8), -1, "a spectator holds no seat and is left alone")
	assert_eq(roster.slot_of_peer(Net.HOST_PEER_ID), 0, "the host never moves")
	assert_eq(roster.compact(), 0, "already closed up")


func test_roster_compact_is_a_no_op_mid_match_and_when_not_hosting() -> void:
	var roster: NetRoster = _roster_with({5: 2})
	roster.set_match_phase(true)
	assert_eq(roster.compact(), 0, "a mid-match slot id is a PlayerSlot index the match built")
	assert_eq(roster.slot_of_peer(5), 2)
	var client_mirror: NetRoster = NetRoster.new(NetConfig.new())
	client_mirror.begin_client("Me")
	assert_eq(client_mirror.compact(), 0)


func test_roster_compact_rederives_only_auto_names() -> void:
	var roster: NetRoster = NetRoster.new(NetConfig.new())
	roster.add_host("Hostie", _ROSTER_BUILD, true)
	roster.accept(5, _ROSTER_BUILD, "", 2)
	roster.accept(6, _ROSTER_BUILD, "Player 4", 3)
	roster.compact()
	assert_eq(roster.name_of_peer(5), PlayerNames.fallback_for_slot(1), "an auto name follows its seat")
	assert_eq(roster.name_of_peer(6), "Player 4", "a name the player chose is never touched")


func test_roster_disconnect_mid_match_reserves_the_slot_for_the_token() -> void:
	var roster: NetRoster = _roster_with({5: 1})
	var token: String = roster.token_of(5)
	assert_eq(token.length(), _ROSTER_TOKEN_CHARS)
	roster.set_match_phase(true)
	assert_eq(roster.remove(5, roster.match_in_progress), 1)
	assert_eq(roster.reservations.get(token), 1)
	assert_false(roster.has_peer(5))
	assert_eq(roster.token_of(5), "", "the departed peer's bearer token left the table")


func test_roster_kick_and_lobby_leave_make_no_reservation() -> void:
	var roster: NetRoster = _roster_with({5: 1, 6: 2})
	assert_eq(roster.remove(5, false), 1)
	assert_true(roster.reservations.is_empty(), "a kicked peer forfeits its token")
	roster.set_match_phase(true)
	assert_eq(roster.remove(9, true), -1, "an unknown peer")
	var spectator: NetRoster = _roster_with({7: -1})
	spectator.set_match_phase(true)
	spectator.remove(7, true)
	assert_true(spectator.reservations.is_empty(), "a spectator holds no seat to reserve")


func test_roster_reclaim_consumes_the_reservation_and_reuses_the_token() -> void:
	var roster: NetRoster = _roster_with({5: 1})
	var token: String = roster.token_of(5)
	roster.set_match_phase(true)
	roster.remove(5, true)
	var seat_ok: Callable = func(_slot_id: int) -> bool: return true
	roster.can_reclaim_seat = seat_ok
	var back: HandshakePolicy.Decision = roster.handle_handshake(6, _ROSTER_BUILD, "Back", token, 0.0)
	assert_eq(back.kind, HandshakePolicy.Decision.Kind.RECLAIM)
	assert_eq(back.slot_id, 1)
	assert_eq(roster.accept(6, _ROSTER_BUILD, "Back", 1, token), 1)
	assert_true(roster.reservations.is_empty(), "reclaiming spends the reservation")
	assert_eq(roster.token_of(6), token, "the same token, so a second drop also works")
	var again: HandshakePolicy.Decision = roster.handle_handshake(7, _ROSTER_BUILD, "Other", token, 0.0)
	assert_ne(again.kind, HandshakePolicy.Decision.Kind.RECLAIM, "nothing is left to reclaim")


func test_roster_reservations_do_not_survive_a_phase_change() -> void:
	var roster: NetRoster = _roster_with({5: 1})
	roster.set_match_phase(true)
	roster.remove(5, true)
	roster.set_match_phase(false)
	assert_true(roster.reservations.is_empty())
	assert_eq(roster.take_next_lobby_slot(), 1, "the slot is free again")


func test_roster_return_to_lobby_reseats_spectators_closes_holes_and_clears_ready() -> void:
	var roster: NetRoster = _roster_with({5: 3, 6: -1})
	roster.set_match_phase(true)
	roster.set_ready(5, true)
	roster.set_match_phase(false)
	assert_true(roster.return_to_lobby())
	assert_eq(roster.slot_of_peer(6), 1, "the spectator is a player again, in the lowest free slot")
	assert_eq(roster.slot_of_peer(5), 2, "and the hole above it closed")
	assert_false(bool(roster.peer_info(5).get("ready")), "nobody is ready back in the lobby")
	assert_false(roster.return_to_lobby(), "a second call changes nothing")


func test_roster_set_ready_reports_a_change_and_all_ready_ignores_the_host() -> void:
	var roster: NetRoster = _roster_with({5: 1})
	assert_false(roster.all_ready())
	assert_true(roster.set_ready(5, true))
	assert_false(roster.set_ready(5, true), "unchanged")
	assert_false(roster.set_ready(99, true), "unknown peer")
	assert_true(roster.all_ready(), "the host's own flag is not required")


func test_roster_peer_ids_run_in_slot_order() -> void:
	var roster: NetRoster = _roster_with({9: 2, 4: 1, 6: -1})
	assert_eq(roster.peer_ids(), PackedInt32Array([6, Net.HOST_PEER_ID, 4, 9]))


# --- The handshake gate over ENet ---------------------------------------------------

func test_an_oversize_handshake_name_over_enet_is_dropped_without_a_reply() -> void:
	var port: int = _take_port()
	assert_eq(_host.host_game(port, "Hostie", false), OK)
	_host.set_accepting_joins(true)
	watch_signals(Events)
	assert_eq(_client.join_game("127.0.0.1", port, "Clienty"), OK)
	# A tampered client skips its own cleaning and sends a name past the raw cap.
	_client._pending_join_name = "Z".repeat(_host.config.handshake_name_max_length + 1)
	var connected: bool = await _wait_until(func() -> bool:
		return _host.multiplayer.get_peers().size() == 1
	)
	assert_true(connected, "the transport connection itself came up")
	# Give the handshake RPC time to arrive and be (not) answered.
	for _i: int in range(60):
		await get_tree().process_frame
	assert_eq(_host.peer_ids().size(), 1, "the oversize handshake seated nobody")
	assert_eq(get_signal_emit_count(Events, "net_join_failed"), 0, "and drew no refusal reply")
	assert_false(_client._joined_accepted)
