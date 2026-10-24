extends GutTest
## net/session/NetSteamSession.gd: the Steam lobby session behind Net (spec 2.6).
## Driven only through a FakeSteam (a SteamClient with no Steam singleton behind
## it): the session's calls into the fake, its answers to the fake's queued
## lobby answers (delivered by one run_callbacks() frame), and what it leaves in
## the signals it emits for Net (host_ready, request_failed, join_refused,
## lobbies_discovered). Net's seams are stood in for by the fields above.

const _HOST_LOBBY: int = 4242
const _OTHER_LOBBY: int = 777
const _RESULT_FAILED: int = 2
const _RESPONSE_FULL: int = 3
const _VERSION: String = "test-build"
const _HOST_NAME: String = "Hostie"

var _fake: FakeSteam
var _transport: NetTransport
var _session: NetSteamSession
var _host_peer_builds: int = 0
## What Net tells the session through its seams: whether it has no session yet.
var _offline: bool = true
var _lobby_settings: Dictionary = {"map_variant": 2, "player_count": 4}
var _hosted: Array[Dictionary] = []
var _failed: Array[Array] = []
var _refused: Array[Array] = []
var _discovered: Array = []


func before_each() -> void:
	_fake = FakeSteam.new()
	_transport = NetTransport.new()
	_host_peer_builds = 0
	_offline = true
	_hosted.clear()
	_failed.clear()
	_refused.clear()
	_discovered.clear()
	_session = NetSteamSession.new(_fake, _transport)
	_session.seams.is_offline = func() -> bool: return _offline
	_session.seams.is_host = func() -> bool: return true
	_session.seams.leave_session = func() -> void:
		_offline = true
		_session.leave()
	_session.seams.lobby_data = func() -> Dictionary: return _lobby_settings
	_session.seams.build_version = func() -> String: return _VERSION
	_session.seams.local_name = func(typed: String) -> String: return typed
	# Net seats the session when the peer is ready.
	_session.host_ready.connect(func(peer: MultiplayerPeer, lobby_id: int, host_name: String) -> void:
		_offline = false
		_hosted.append({"peer": peer, "lobby_id": lobby_id, "host_name": host_name}))
	_session.request_failed.connect(func(error: int, detail: String) -> void: _failed.append([error, detail]))
	_session.join_refused.connect(func(error: int, detail: String) -> void: _refused.append([error, detail]))
	_session.lobbies_discovered.connect(func(lobbies: Array[Dictionary]) -> void: _discovered.append(lobbies))


## Steam initialised and a host peer the session can take (a connected stub:
## SteamMultiplayerPeer is never built in a test).
func _ready_steam() -> void:
	_session.init()
	_transport.steam_host_peer_factory = func() -> MultiplayerPeer:
		_host_peer_builds += 1
		return _StubPeer.new()


class _StubPeer:
	extends MultiplayerPeerExtension

	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return MultiplayerPeer.CONNECTION_CONNECTED

	func _get_unique_id() -> int:
		return NetRoster.HOST_PEER_ID

	func _get_available_packet_count() -> int:
		return 0

	func _poll() -> void:
		pass

	func _close() -> void:
		pass


## One frame: what Net._process does for the session.
func _frame() -> void:
	_session.process(0.0)


## Every failure the session reported, requests and refused joins together.
func _failure_count() -> int:
	return _failed.size() + _refused.size()


## A hosted session: host_online() answered with `lobby_id`.
func _host_live(lobby_id: int = _HOST_LOBBY) -> void:
	_ready_steam()
	assert_eq(_session.host_online("Hostie"), OK)
	_fake.queue_create_answer(FakeSteam.RESULT_OK, lobby_id)
	_frame()
	assert_eq(_hosted.size(), 1, "the session handed Net a host peer")
	assert_true(_session.is_live())


func _seed_lobby(lobby_id: int, game: String, version: String, host_name: String, members: int, map: String = "") -> void:
	_fake.seed_lobby(lobby_id, 1, members, {
		String(SteamClient.KEY_GAME): game,
		String(SteamClient.KEY_VERSION): version,
		String(SteamClient.KEY_HOST_NAME): host_name,
		String(SteamClient.KEY_MAP): map,
	})


# --- Availability ----------------------------------------------------------------

func test_host_online_and_join_are_refused_when_steam_is_not_available() -> void:
	_fake.available_value = false
	_session.init()
	assert_eq(_session.host_online("Hostie"), ERR_UNAVAILABLE)
	assert_eq(_session.join_lobby(_OTHER_LOBBY, "Clienty"), ERR_UNAVAILABLE)
	assert_true(_fake.create_lobby_calls.is_empty())
	assert_true(_fake.join_lobby_calls.is_empty())


func test_host_online_is_refused_when_steam_init_failed() -> void:
	_fake.init_status_value = 2 # client not running
	_session.init()
	assert_eq(_session.host_online("Hostie"), ERR_UNAVAILABLE)
	assert_true(_fake.create_lobby_calls.is_empty())


func test_refresh_lobby_list_is_a_no_op_when_steam_is_not_available() -> void:
	_fake.available_value = false
	_session.init()
	_session.refresh_lobby_list()
	assert_true(_fake.request_lobby_list_calls.is_empty())


# --- Hosting ---------------------------------------------------------------------

func test_host_online_asks_steam_for_one_lobby_of_the_configured_type_and_size() -> void:
	_ready_steam()
	assert_eq(_session.host_online("Hostie"), OK)
	assert_eq(_fake.create_lobby_calls.size(), 1)
	assert_eq(_fake.create_lobby_calls[0], {"lobby_type": _session.config.steam_lobby_type, "max_members": _session.config.max_peers})
	assert_true(_hosted.is_empty(), "the attempt only started: Steam has not answered")


func test_a_created_lobby_is_tagged_and_handed_to_net_as_a_host_peer() -> void:
	_host_live()
	var lobby: int = _HOST_LOBBY
	assert_eq(_fake.get_lobby_data(lobby, String(SteamClient.KEY_GAME)), String(NetIds.DISCOVERY_MAGIC))
	assert_eq(_fake.get_lobby_data(lobby, String(SteamClient.KEY_VERSION)), _VERSION)
	assert_eq(_fake.get_lobby_data(lobby, String(SteamClient.KEY_HOST_NAME)), _HOST_NAME, "the name Net resolves tags the lobby")
	var decoded: Dictionary = JSON.parse_string(_fake.get_lobby_data(lobby, String(SteamClient.KEY_MATCH_CONFIG))) as Dictionary
	assert_eq(int(decoded.get("map_variant")), 2, "the lobby settings are written under one JSON key")
	assert_eq(int(decoded.get("player_count")), 4)
	assert_eq(_fake.joinable_calls, [[lobby, true]], "the lobby is explicitly joinable")
	assert_eq(_host_peer_builds, 1)
	assert_eq(_hosted[0]["lobby_id"], lobby)
	assert_eq(_hosted[0]["host_name"], _HOST_NAME)
	assert_eq(_session.lobby_id(), lobby)
	assert_true(_fake.leave_lobby_calls.is_empty(), "a live lobby is kept")
	assert_eq(_failure_count(), 0)


func test_a_failed_create_reports_a_transport_error_and_leaves_no_lobby() -> void:
	_ready_steam()
	assert_eq(_session.host_online("Hostie"), OK)
	_fake.queue_create_answer(_RESULT_FAILED, _HOST_LOBBY)
	_frame()
	assert_eq(_failed.size(), 1, "a lobby that never existed is a request failure")
	assert_eq(_failed[0][0], Net.JoinError.TRANSPORT)
	assert_true(_hosted.is_empty())
	assert_true(_fake.set_lobby_data_calls.is_empty(), "nothing is tagged for a failed create")
	assert_true(_fake.leave_lobby_calls.is_empty(), "a failed create made no lobby to leave")
	assert_eq(_session.host_online("Hostie"), OK, "the failed attempt no longer blocks a new one")


func test_a_host_peer_that_cannot_be_built_releases_the_lobby() -> void:
	_session.init()
	_transport.steam_host_peer_factory = func() -> MultiplayerPeer: return null
	assert_eq(_session.host_online("Hostie"), OK)
	_fake.queue_create_answer(FakeSteam.RESULT_OK, _HOST_LOBBY)
	_frame()
	assert_eq(_fake.leave_lobby_calls, [_HOST_LOBBY], "the lobby Steam made is not orphaned")
	assert_eq(_failed.size(), 1)
	assert_eq(_failed[0][0], Net.JoinError.TRANSPORT)
	assert_true(_hosted.is_empty())
	assert_false(_session.is_live())


func test_a_fake_provider_never_gets_a_real_steam_peer() -> void:
	_session.init() # no factory set: the real path
	assert_eq(_session.host_online(_HOST_NAME), OK)
	_fake.queue_create_answer(FakeSteam.RESULT_OK, _HOST_LOBBY)
	_frame()
	assert_true(_hosted.is_empty())
	assert_eq(_fake.leave_lobby_calls, [_HOST_LOBBY])
	assert_eq(_failed[0][0], Net.JoinError.TRANSPORT)


func test_a_granted_join_without_a_real_peer_leaves_the_lobby_and_is_refused() -> void:
	_session.init()
	assert_eq(_session.join_lobby(_OTHER_LOBBY, "Clienty"), OK)
	_fake.queue_lobby_joined(_OTHER_LOBBY, FakeSteam.CHAT_ROOM_ENTER_SUCCESS)
	_frame()
	assert_eq(_fake.leave_lobby_calls, [_OTHER_LOBBY])
	assert_eq(_refused.size(), 1)
	assert_eq(_refused[0][0], Net.JoinError.TRANSPORT)
	assert_false(_session.is_live())


# --- One attempt at a time -------------------------------------------------------

func test_a_second_attempt_while_one_is_pending_is_busy_and_issues_no_steam_call() -> void:
	_ready_steam()
	assert_eq(_session.host_online("Hostie"), OK)
	assert_eq(_session.host_online("Hostie"), ERR_BUSY)
	assert_eq(_session.join_lobby(_OTHER_LOBBY, "Clienty"), ERR_BUSY)
	assert_eq(_fake.create_lobby_calls.size(), 1)
	assert_true(_fake.join_lobby_calls.is_empty())


func test_a_pending_join_blocks_a_second_join_and_a_host_attempt() -> void:
	_ready_steam()
	assert_eq(_session.join_lobby(_OTHER_LOBBY, "Clienty"), OK)
	assert_eq(_fake.join_lobby_calls, [_OTHER_LOBBY])
	assert_eq(_session.join_lobby(_OTHER_LOBBY + 1, "Clienty"), ERR_BUSY)
	assert_eq(_session.host_online("Hostie"), ERR_BUSY)
	assert_eq(_fake.join_lobby_calls, [_OTHER_LOBBY])
	assert_true(_fake.create_lobby_calls.is_empty())


func test_a_refused_join_reports_refused_and_frees_the_next_attempt() -> void:
	_ready_steam()
	assert_eq(_session.join_lobby(_OTHER_LOBBY, "Clienty"), OK)
	_fake.queue_lobby_joined(_OTHER_LOBBY, _RESPONSE_FULL)
	_frame()
	assert_eq(_refused.size(), 1)
	assert_eq(_refused[0][0], Net.JoinError.REFUSED)
	assert_true(_failed.is_empty())
	assert_true(_fake.leave_lobby_calls.is_empty(), "a refused join entered no lobby")
	assert_eq(_session.join_lobby(_OTHER_LOBBY, "Clienty"), OK)


# --- Generation and FIFO queue ---------------------------------------------------

func test_leave_cancels_a_pending_attempt_and_frees_a_new_one() -> void:
	_ready_steam()
	assert_eq(_session.host_online("Hostie"), OK)
	_session.leave()
	assert_eq(_session.host_online("Hostie2"), OK, "the cancelled attempt does not make the new one busy")
	assert_eq(_fake.create_lobby_calls.size(), 2)


func test_the_first_delivered_answer_resolves_the_cancelled_attempt_and_is_abandoned() -> void:
	_ready_steam()
	assert_eq(_session.host_online("Hostie"), OK)
	_session.leave()
	assert_eq(_session.host_online("Hostie2"), OK)

	_fake.queue_lobby_created(FakeSteam.RESULT_OK, 111)
	_frame()
	assert_eq(_fake.leave_lobby_calls, [111], "the cancelled attempt's lobby is left, not hosted")
	assert_true(_fake.set_lobby_data_calls.is_empty(), "an abandoned lobby is never tagged")
	assert_true(_hosted.is_empty())
	assert_eq(_session.host_online("Hostie3"), ERR_BUSY, "the live attempt is still pending")

	_fake.queue_lobby_created(FakeSteam.RESULT_OK, 222)
	_frame()
	assert_eq(_hosted.size(), 1, "the second answer is the live attempt's own")
	assert_eq(_fake.get_lobby_data(222, String(SteamClient.KEY_GAME)), String(NetIds.DISCOVERY_MAGIC))
	assert_eq(_fake.leave_lobby_calls, [111], "the live lobby is kept")


func test_three_attempts_two_cancelled_only_the_last_answer_goes_live() -> void:
	_ready_steam()
	assert_eq(_session.host_online("A"), OK)
	_session.leave()
	assert_eq(_session.host_online("B"), OK)
	_session.leave()
	assert_eq(_session.host_online("C"), OK)
	_fake.queue_lobby_created(FakeSteam.RESULT_OK, 1)
	_fake.queue_lobby_created(FakeSteam.RESULT_OK, 2)
	_fake.queue_lobby_created(FakeSteam.RESULT_OK, 3)
	_frame()
	assert_eq(_fake.leave_lobby_calls, [1, 2])
	assert_false(_hosted.is_empty())
	assert_eq(_fake.get_lobby_data(3, String(SteamClient.KEY_GAME)), String(NetIds.DISCOVERY_MAGIC))
	assert_eq(_fake.get_lobby_data(1, String(SteamClient.KEY_GAME)), "")


func test_a_cancelled_attempts_failed_answer_is_dropped_and_the_live_one_stays_pending() -> void:
	_ready_steam()
	assert_eq(_session.host_online("A"), OK)
	_session.leave()
	assert_eq(_session.host_online("B"), OK)
	_fake.queue_lobby_created(_RESULT_FAILED, 0)
	_frame()
	assert_eq(_failure_count(), 0, "a cancelled attempt reports nothing")
	assert_true(_fake.leave_lobby_calls.is_empty(), "a failure made no lobby to leave")
	assert_eq(_session.host_online("C"), ERR_BUSY, "attempt B is still waiting for its answer")


func test_join_answers_resolve_oldest_first_across_a_leave() -> void:
	_ready_steam()
	assert_eq(_session.join_lobby(10, "Clienty"), OK)
	_session.leave()
	assert_eq(_session.join_lobby(20, "Clienty"), OK)
	_fake.queue_lobby_joined(10, FakeSteam.CHAT_ROOM_ENTER_SUCCESS)
	_fake.queue_lobby_joined(20, _RESPONSE_FULL)
	_frame()
	assert_eq(_fake.leave_lobby_calls, [10], "the cancelled join's lobby is left")
	assert_eq(_refused.size(), 1, "only the live join reports")
	assert_eq(_refused[0][0], Net.JoinError.REFUSED)


func test_hosting_again_leaves_the_current_lobby_first() -> void:
	_host_live(10)
	assert_eq(_session.host_online("Hostie"), OK)
	assert_eq(_fake.leave_lobby_calls, [10])
	assert_false(_session.is_live())
	assert_eq(_fake.create_lobby_calls.size(), 2)


# --- Echo filter -----------------------------------------------------------------

func test_the_creators_own_lobby_enter_after_lobby_created_is_not_a_stray_join() -> void:
	_ready_steam()
	assert_eq(_session.host_online("Hostie"), OK)
	_fake.queue_create_answer(FakeSteam.RESULT_OK, _HOST_LOBBY) # lobby_created, then lobby_joined
	_frame()
	assert_false(_hosted.is_empty())
	assert_true(_fake.leave_lobby_calls.is_empty(), "the host must not leave its own fresh lobby")
	assert_eq(_failure_count(), 0)


func test_the_creators_lobby_enter_arriving_before_lobby_created_is_ignored() -> void:
	_ready_steam()
	assert_eq(_session.host_online("Hostie"), OK)
	_fake.queue_lobby_joined(_HOST_LOBBY, FakeSteam.CHAT_ROOM_ENTER_SUCCESS)
	_fake.queue_lobby_created(FakeSteam.RESULT_OK, _HOST_LOBBY)
	_frame()
	assert_false(_hosted.is_empty())
	assert_true(_fake.leave_lobby_calls.is_empty())


func test_a_repeat_lobby_enter_for_the_live_hosted_lobby_is_ignored() -> void:
	_host_live()
	_fake.queue_lobby_joined(_HOST_LOBBY, FakeSteam.CHAT_ROOM_ENTER_SUCCESS)
	_frame()
	assert_false(_hosted.is_empty())
	assert_true(_fake.leave_lobby_calls.is_empty())


func test_an_abandoned_lobbys_enter_echo_is_not_left_a_second_time() -> void:
	_ready_steam()
	assert_eq(_session.host_online("Hostie"), OK)
	_session.leave()
	_fake.queue_create_answer(FakeSteam.RESULT_OK, 111) # lobby_created + the echo
	_frame()
	assert_eq(_fake.leave_lobby_calls, [111], "left once, by the stale-answer path only")
	assert_eq(_failure_count(), 0)


func test_the_echo_of_a_created_lobby_does_not_resolve_a_pending_join() -> void:
	_host_live(10)
	_session.leave()
	_fake.leave_lobby_calls.clear()
	assert_eq(_session.join_lobby(20, "Clienty"), OK)
	_fake.queue_lobby_joined(10, FakeSteam.CHAT_ROOM_ENTER_SUCCESS) # late echo of the lobby this process created
	_frame()
	assert_true(_fake.leave_lobby_calls.is_empty(), "the echo is not a join answer")
	assert_eq(_session.join_lobby(30, "Clienty"), ERR_BUSY, "the join to lobby 20 is still pending")


func test_a_successful_enter_nobody_asked_for_is_left_rather_than_orphaned() -> void:
	_ready_steam()
	_fake.queue_lobby_joined(500, FakeSteam.CHAT_ROOM_ENTER_SUCCESS)
	_frame()
	assert_eq(_fake.leave_lobby_calls, [500])
	assert_true(_hosted.is_empty())


# --- Overlay invite ---------------------------------------------------------------

func test_an_accepted_overlay_invite_joins_that_lobby() -> void:
	_ready_steam()
	_fake.queue_join_requested(_OTHER_LOBBY, 99)
	_frame()
	assert_eq(_fake.join_lobby_calls, [_OTHER_LOBBY])


# --- Lobby list ------------------------------------------------------------------

func _filters_sent() -> Dictionary:
	var sent: Dictionary = {}
	for f: Dictionary in (_fake.request_lobby_list_calls[0] as Array):
		sent[String(f["key"])] = String(f["value"])
	return sent


func test_refresh_requests_only_this_game_and_this_version() -> void:
	_ready_steam()
	_session.refresh_lobby_list()
	assert_eq(_fake.request_lobby_list_calls.size(), 1)
	var sent: Dictionary = _filters_sent()
	assert_eq(sent.size(), 2)
	assert_eq(sent[String(SteamClient.KEY_GAME)], String(NetIds.DISCOVERY_MAGIC))
	assert_eq(sent[String(SteamClient.KEY_VERSION)], _VERSION)


func test_a_refresh_while_one_is_outstanding_waits_and_goes_out_once_answered() -> void:
	_ready_steam()
	_session.refresh_lobby_list()
	_session.refresh_lobby_list()
	assert_eq(_fake.request_lobby_list_calls.size(), 1, "Steam keeps one list request at a time")
	_fake.queue_lobby_match_list([])
	_frame()
	assert_eq(_fake.request_lobby_list_calls.size(), 2, "the coalesced refresh goes out after the answer")


func test_the_list_keeps_only_lobbies_of_this_game_and_version() -> void:
	_ready_steam()
	var version: String = _VERSION
	_seed_lobby(1, String(NetIds.DISCOVERY_MAGIC), version, "Alpha", 3, "plains")
	_seed_lobby(2, String(NetIds.DISCOVERY_MAGIC), version + "-old", "Stale", 2)
	_seed_lobby(3, "otherGame", version, "Foreign", 2)
	_seed_lobby(4, String(NetIds.DISCOVERY_MAGIC), version, "Beta", 1)
	_fake.lobby_data_store[5] = {} # a lobby whose data never arrived
	_session.refresh_lobby_list()
	_fake.queue_lobby_match_list([1, 2, 3, 4, 5])
	_frame()
	assert_eq(_discovered.size(), 1)
	var rows: Array = _discovered[0]
	assert_eq(_session.discovered_lobbies(), rows, "the same list is readable afterwards")
	assert_eq(rows.size(), 2)
	assert_eq(rows[0], {"lobby_id": 1, "name": "Alpha", "players": 3, "max": _session.config.max_peers, "map": "plains"})
	assert_eq(int((rows[1] as Dictionary)["lobby_id"]), 4, "answer order is kept")
	assert_eq((rows[1] as Dictionary)["name"], "Beta")


func test_an_empty_answer_publishes_an_empty_list() -> void:
	_ready_steam()
	_session.refresh_lobby_list()
	_fake.queue_lobby_match_list([])
	_frame()
	assert_eq(_discovered.size(), 1)
	assert_eq((_discovered[0] as Array).size(), 0)


# --- Leave -----------------------------------------------------------------------

func test_leave_gives_up_the_hosted_lobby_once() -> void:
	_host_live()
	_session.leave()
	assert_eq(_fake.leave_lobby_calls, [_HOST_LOBBY])
	assert_false(_session.is_live())
	assert_eq(_session.lobby_id(), 0)
	_session.leave()
	assert_eq(_fake.leave_lobby_calls, [_HOST_LOBBY], "a second leave has nothing left to give up")


func test_leave_when_nothing_is_running_touches_no_lobby() -> void:
	_ready_steam()
	_session.leave()
	assert_true(_fake.leave_lobby_calls.is_empty())
	assert_eq(_failure_count(), 0)


func test_after_leave_the_session_can_host_again() -> void:
	_host_live(10)
	_session.leave()
	assert_eq(_session.host_online("Hostie"), OK)
	_fake.queue_create_answer(FakeSteam.RESULT_OK, 11)
	_frame()
	assert_false(_hosted.is_empty())
	assert_eq(_fake.get_lobby_data(11, String(SteamClient.KEY_GAME)), String(NetIds.DISCOVERY_MAGIC))


# --- Invites and published settings -------------------------------------------------

func test_the_invite_overlay_opens_only_for_a_live_lobby() -> void:
	_ready_steam()
	_session.open_invite_overlay()
	assert_true(_fake.activate_invite_overlay_calls.is_empty(), "no lobby yet")
	_host_live()
	_session.open_invite_overlay()
	assert_eq(_fake.activate_invite_overlay_calls, [_HOST_LOBBY])
	_session.leave()
	_session.open_invite_overlay()
	assert_eq(_fake.activate_invite_overlay_calls, [_HOST_LOBBY], "a left lobby is not offered")


func test_published_settings_reach_the_live_lobby_and_are_dropped_without_one() -> void:
	_ready_steam()
	_session.publish_match_config({"map_variant": 9})
	assert_true(_fake.set_lobby_data_calls.is_empty())
	_host_live()
	_session.publish_match_config({"map_variant": 9})
	var decoded: Dictionary = JSON.parse_string(_fake.get_lobby_data(_HOST_LOBBY, String(SteamClient.KEY_MATCH_CONFIG))) as Dictionary
	assert_eq(int(decoded.get("map_variant")), 9)


func test_the_frame_pump_only_runs_once_steam_is_ready() -> void:
	_session.process(0.0)
	assert_eq(_fake.run_callbacks_calls, 0)
	_session.init()
	_session.process(0.0)
	assert_eq(_fake.run_callbacks_calls, 1)
