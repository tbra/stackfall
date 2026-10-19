extends GutTest
## net/session/NetTransport.gd: the peer factories, the dead-peer timeout, the
## link predicates, the disconnecting-peer set and the send targets that
## autoload/Net.gd used to carry as _make_*_peer / _apply_peer_timeout /
## _can_send / _broadcast_targets. The targets must equal NetFanout.targets() on
## the same inputs (parity): net/ nodes filter their own sends through NetFanout.


## A connected-by-default peer with no network behind it; a test lists remote ids
## on the API it is installed in by calling add_remote().
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


## What a net/ node sees of the Net autoload: only is_peer_disconnecting().
class Session:
	extends RefCounted
	var transport: NetTransport = null
	var api: MultiplayerAPI = null

	func is_peer_disconnecting(peer_id: int) -> bool:
		return transport.is_peer_disconnecting(api, peer_id)


var _transport: NetTransport = null
var _config: NetConfig = null


func before_each() -> void:
	_transport = NetTransport.new()
	_config = NetConfig.new()


func _api_with(peer: MultiplayerPeer) -> MultiplayerAPI:
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	api.multiplayer_peer = peer
	return api


## A stub peer installed in a fresh API with `remote_ids` listed as connected.
func _stub_api(remote_ids: Array[int]) -> Array:
	var stub: StubPeer = StubPeer.new()
	var api: MultiplayerAPI = _api_with(stub)
	for peer_id: int in remote_ids:
		stub.add_remote(peer_id)
	return [api, stub]


# --- Factories ---------------------------------------------------------------

func test_host_and_client_peers_are_enet_and_a_taken_port_is_null() -> void:
	var port: int = AgentProbe.free_udp_port()
	var host: MultiplayerPeer = _transport.make_host_peer(port, _config.max_peers, true)
	assert_not_null(host, "a free port yields a server")
	assert_true(host is ENetMultiplayerPeer)
	var client: MultiplayerPeer = _transport.make_client_peer("127.0.0.1", port)
	assert_not_null(client)
	assert_true(client is ENetMultiplayerPeer)
	host.close()
	client.close()


func test_steam_peers_are_never_built_without_init_or_for_a_fake_provider() -> void:
	assert_null(_transport.make_steam_host_peer(false, true), "Steam not initialised")
	assert_null(_transport.make_steam_host_peer(true, false), "a FakeSteam provider")
	assert_null(_transport.make_steam_client_peer(76561198000000000, false, true))
	assert_null(_transport.make_steam_client_peer(76561198000000000, true, false))


func test_steam_host_peer_factory_seam_answers_before_the_safety_gate() -> void:
	assert_false(_transport.steam_host_peer_factory.is_valid(), "unset by default")
	var stub: StubPeer = StubPeer.new()
	_transport.steam_host_peer_factory = func() -> MultiplayerPeer: return stub
	assert_eq(_transport.make_steam_host_peer(false, false), stub, "even with Steam not ready")
	_transport.steam_host_peer_factory = Callable()
	assert_null(_transport.make_steam_host_peer(false, false), "cleared: back to the real gate")


# --- Link state --------------------------------------------------------------

func test_link_up_and_down_follow_the_connection_status() -> void:
	assert_false(_transport.is_link_up(null))
	assert_true(_transport.is_link_down(null))
	assert_false(_transport.is_link_up(_api_with(null)), "no peer")
	var made: Array = _stub_api([])
	var api: MultiplayerAPI = made[0]
	var stub: StubPeer = made[1]
	assert_true(_transport.is_link_up(api))
	assert_false(_transport.is_link_down(api))
	stub.status = MultiplayerPeer.CONNECTION_CONNECTING
	assert_false(_transport.is_link_up(api))
	assert_false(_transport.is_link_down(api), "a live attempt is not down")
	stub.status = MultiplayerPeer.CONNECTION_DISCONNECTED
	assert_true(_transport.is_link_down(api))


func test_a_non_enet_peer_is_always_sendable() -> void:
	var made: Array = _stub_api([2])
	var api: MultiplayerAPI = made[0]
	assert_true(_transport.is_peer_sendable(api, 2))
	assert_true(_transport.is_peer_sendable(api, 99), "Steam has no per-link view")


# --- Disconnecting set -------------------------------------------------------

func test_marks_clear_and_unmark() -> void:
	_transport.mark_disconnecting(5)
	_transport.mark_disconnecting(6)
	assert_true(_transport.is_marked_disconnecting(5))
	assert_eq(_transport.disconnecting_marks().size(), 2)
	_transport.unmark_disconnecting(5)
	assert_false(_transport.is_marked_disconnecting(5))
	_transport.clear_disconnecting()
	assert_true(_transport.disconnecting_marks().is_empty())


# --- Targets and the NetFanout parity ----------------------------------------

func _fanout_targets(api: MultiplayerAPI) -> Array[int]:
	var session: Session = Session.new()
	session.transport = _transport
	session.api = api
	return NetFanout.targets(api, session)


func test_targets_skip_marked_peers_and_equal_netfanout_targets() -> void:
	var made: Array = _stub_api([2, 3, 4])
	var api: MultiplayerAPI = made[0]
	var all_ids: Array[int] = [2, 3, 4]
	assert_eq(_transport.broadcast_targets(api, true), all_ids)
	assert_eq(_transport.broadcast_targets(api, true), _fanout_targets(api), "parity, nobody marked")
	_transport.mark_disconnecting(3)
	var without_three: Array[int] = [2, 4]
	assert_eq(_transport.broadcast_targets(api, true), without_three)
	assert_eq(_transport.broadcast_targets(api, true), _fanout_targets(api), "parity, one marked")
	_transport.mark_disconnecting(2)
	_transport.mark_disconnecting(4)
	assert_true(_transport.broadcast_targets(api, true).is_empty())
	assert_eq(_transport.broadcast_targets(api, true), _fanout_targets(api), "parity, all marked")
	assert_false(_transport.can_broadcast(api, true), "nobody left to address")


func test_targets_are_empty_for_a_client_a_down_link_or_no_api() -> void:
	var made: Array = _stub_api([2])
	var api: MultiplayerAPI = made[0]
	var stub: StubPeer = made[1]
	assert_true(_transport.broadcast_targets(api, false).is_empty(), "host only")
	assert_true(_transport.broadcast_targets(null, true).is_empty())
	assert_true(_fanout_targets(null).is_empty(), "NetFanout agrees on a null api")
	stub.status = MultiplayerPeer.CONNECTION_CONNECTING
	assert_true(_transport.broadcast_targets(api, true).is_empty(), "link not connected")
	assert_false(_transport.can_broadcast(api, true))


# --- Real ENet loopback ------------------------------------------------------

## Polls every API until `condition` holds (manual polling: these APIs are not in the tree).
func _pump_until(apis: Array[MultiplayerAPI], condition: Callable, frames: int = 300) -> bool:
	for _i: int in range(frames):
		for api: MultiplayerAPI in apis:
			api.poll()
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func test_enet_targets_timeouts_and_parity_over_loopback() -> void:
	var port: int = AgentProbe.free_udp_port()
	var host_peer: MultiplayerPeer = _transport.make_host_peer(port, _config.max_peers, true)
	var client_peer: MultiplayerPeer = _transport.make_client_peer("127.0.0.1", port)
	var host_api: MultiplayerAPI = _api_with(host_peer)
	var client_api: MultiplayerAPI = _api_with(client_peer)
	var both: Array[MultiplayerAPI] = [host_api, client_api]
	var linked: bool = await _pump_until(both, func() -> bool:
		return host_api.get_peers().size() == 1 and client_api.get_peers().size() == 1)
	assert_true(linked, "client and host connect")
	var client_id: int = host_api.get_peers()[0]
	var just_client: Array[int] = [client_id]
	assert_true(_transport.is_link_up(host_api))
	assert_true(_transport.is_peer_sendable(host_api, client_id), "an established ENet link is sendable")
	assert_false(_transport.is_peer_sendable(host_api, 987654), "an id the host holds no link to is not")
	assert_eq(_transport.broadcast_targets(host_api, true), just_client)
	assert_eq(_transport.broadcast_targets(host_api, true), _fanout_targets(host_api), "parity over a real link")
	# The timeout setter touches only a link this side holds, and never errors on others.
	_transport.apply_peer_timeout(host_api, host_peer, client_id, true, _config)
	_transport.apply_peer_timeout(host_api, host_peer, 987654, true, _config)
	_transport.apply_peer_timeout(client_api, client_peer, MultiplayerPeer.TARGET_PEER_SERVER, false, _config)
	_transport.apply_peer_timeout(client_api, client_peer, 987654, false, _config)
	_transport.apply_peer_timeout(host_api, StubPeer.new(), client_id, true, _config)
	# A kick in flight: the peer is still listed, but no longer a target, in both views.
	_transport.mark_disconnecting(client_id)
	host_peer.disconnect_peer(client_id)
	assert_true(host_api.get_peers().has(client_id), "ENet still lists the peer")
	assert_true(_transport.broadcast_targets(host_api, true).is_empty())
	assert_eq(_transport.broadcast_targets(host_api, true), _fanout_targets(host_api), "parity while disconnecting")
	await _pump_until(both, func() -> bool: return host_api.get_peers().is_empty())
	host_peer.close()
	client_peer.close()
