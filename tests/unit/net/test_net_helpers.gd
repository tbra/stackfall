extends GutTest
## NetFanout is the single owner of "is there a live peer to send to" and "which
## peers may a broadcast address"; the net/ nodes carry no private copies. Every
## helper takes the session as a SessionPort, the same typed adapter the nodes hold.

const PEER_A: int = 2
const PEER_B: int = 3
const PEER_C: int = 4
const SESSION_CALLS: PackedStringArray = ["is_host", "is_offline"]


## A session answering only what NetFanout asks of it.
class FakeSession:
	extends RefCounted
	var offline: bool = false

	func is_offline() -> bool:
		return offline

	func is_host() -> bool:
		return not offline


## The same, plus the per-peer "a kick is in flight" answer.
class KickingSession:
	extends FakeSession
	var disconnecting: Array[int] = []

	func is_peer_disconnecting(peer_id: int) -> bool:
		return disconnecting.has(peer_id)


## A connected-by-default peer with no network behind it; add_remote() lists a peer id.
class StubPeer:
	extends MultiplayerPeerExtension
	var status: int = MultiplayerPeer.CONNECTION_CONNECTED

	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return status as MultiplayerPeer.ConnectionStatus

	func _get_unique_id() -> int:
		return MultiplayerPeer.TARGET_PEER_SERVER

	func _poll() -> void:
		pass

	func _close() -> void:
		pass

	func add_remote(peer_id: int) -> void:
		peer_connected.emit(peer_id)


func _api_with(peer: MultiplayerPeer) -> MultiplayerAPI:
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	api.multiplayer_peer = peer
	return api


func _port(session: FakeSession) -> SessionPort:
	var port: SessionPort = SessionPort.new(session, SESSION_CALLS)
	assert_true(port.is_valid(), "fixture: the double answers the called subset")
	return port


func _listed_api(peer_ids: Array[int]) -> MultiplayerAPI:
	var peer: StubPeer = StubPeer.new()
	var api: MultiplayerAPI = _api_with(peer)
	for peer_id: int in peer_ids:
		peer.add_remote(peer_id)
	return api


# --- can_send ----------------------------------------------------------------

func test_null_api_or_peer_cannot_send() -> void:
	var session: SessionPort = _port(FakeSession.new())
	assert_false(NetFanout.can_send(null, session))
	assert_false(NetFanout.can_send(_api_with(null), session))


func test_connected_peer_can_send_and_disconnected_cannot() -> void:
	var session: SessionPort = _port(FakeSession.new())
	var peer: StubPeer = StubPeer.new()
	var api: MultiplayerAPI = _api_with(peer)
	assert_true(NetFanout.can_send(api, session))
	peer.status = MultiplayerPeer.CONNECTION_CONNECTING
	assert_false(NetFanout.can_send(api, session))


func test_an_offline_session_cannot_send_even_over_a_connected_peer() -> void:
	var fake: FakeSession = FakeSession.new()
	fake.offline = true
	assert_false(NetFanout.can_send(_api_with(StubPeer.new()), _port(fake)))


func test_the_engines_offline_peer_is_not_a_live_transport() -> void:
	assert_false(NetFanout.can_send(_api_with(OfflineMultiplayerPeer.new()), _port(FakeSession.new())))


# --- targets -----------------------------------------------------------------

func test_targets_list_every_connected_peer_when_nobody_is_disconnecting() -> void:
	var api: MultiplayerAPI = _listed_api([PEER_A, PEER_B, PEER_C])
	var all_ids: Array[int] = [PEER_A, PEER_B, PEER_C]
	assert_eq(NetFanout.targets(api, _port(KickingSession.new())), all_ids)


func test_targets_leave_out_a_peer_the_session_is_disconnecting() -> void:
	var api: MultiplayerAPI = _listed_api([PEER_A, PEER_B, PEER_C])
	var session: KickingSession = KickingSession.new()
	session.disconnecting = [PEER_B]
	var expected: Array[int] = [PEER_A, PEER_C]
	assert_eq(NetFanout.targets(api, _port(session)), expected)
	session.disconnecting = [PEER_A, PEER_B, PEER_C]
	assert_true(NetFanout.targets(api, _port(session)).is_empty(), "a kick of everyone leaves nobody")


func test_a_session_that_cannot_report_disconnecting_never_has_a_peer_in_that_state() -> void:
	var api: MultiplayerAPI = _listed_api([PEER_A, PEER_B])
	var all_ids: Array[int] = [PEER_A, PEER_B]
	assert_eq(NetFanout.targets(api, _port(FakeSession.new())), all_ids)


func test_targets_are_empty_without_an_api_or_a_peer() -> void:
	var session: SessionPort = _port(FakeSession.new())
	assert_true(NetFanout.targets(null, session).is_empty())
	var no_peer: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	no_peer.multiplayer_peer = null
	assert_true(NetFanout.targets(no_peer, session).is_empty())


# --- can_send_to / send_to -----------------------------------------------------

func test_a_listed_connected_peer_may_be_addressed() -> void:
	var api: MultiplayerAPI = _listed_api([PEER_A])
	assert_true(NetFanout.can_send_to(api, _port(KickingSession.new()), PEER_A))


func test_an_unlisted_peer_may_not_be_addressed() -> void:
	var api: MultiplayerAPI = _listed_api([PEER_A])
	assert_false(NetFanout.can_send_to(api, _port(KickingSession.new()), PEER_B))


func test_a_disconnecting_peer_may_not_be_addressed() -> void:
	var api: MultiplayerAPI = _listed_api([PEER_A, PEER_B])
	var session: KickingSession = KickingSession.new()
	session.disconnecting = [PEER_A]
	assert_false(NetFanout.can_send_to(api, _port(session), PEER_A))
	assert_true(NetFanout.can_send_to(api, _port(session), PEER_B), "only the kicked peer is skipped")


func test_no_peer_may_be_addressed_without_a_live_transport() -> void:
	var fake: FakeSession = FakeSession.new()
	fake.offline = true
	assert_false(NetFanout.can_send_to(_listed_api([PEER_A]), _port(fake), PEER_A))
	assert_false(NetFanout.can_send_to(null, _port(FakeSession.new()), PEER_A))


func test_send_to_a_refused_peer_queues_nothing() -> void:
	var node: Node = Node.new()
	add_child_autofree(node)
	var session: KickingSession = KickingSession.new()
	session.disconnecting = [PEER_A]
	assert_false(NetFanout.send_to(node, _port(session), PEER_A, &"net_nothing"), "a kick in flight")
	assert_false(NetFanout.send_to(node, _port(KickingSession.new()), PEER_B, &"net_nothing"), "an unlisted peer")
