extends GutTest
## NetFanout.can_send() is the single owner of
## "is there a live peer to send to"; the net/ nodes no longer carry private copies.

class FakeSession:
	extends RefCounted
	var offline: bool = false

	func is_offline() -> bool:
		return offline

	func is_host() -> bool:
		return not offline


class StubPeer:
	extends MultiplayerPeerExtension
	var status: int = MultiplayerPeer.CONNECTION_CONNECTED

	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return status as MultiplayerPeer.ConnectionStatus


func _api_with(peer: MultiplayerPeer) -> MultiplayerAPI:
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	api.multiplayer_peer = peer
	return api


func test_null_api_or_peer_cannot_send() -> void:
	var session: FakeSession = FakeSession.new()
	assert_false(NetFanout.can_send(null, session))
	assert_false(NetFanout.can_send(_api_with(null), session))


func test_connected_peer_can_send_and_disconnected_cannot() -> void:
	var session: FakeSession = FakeSession.new()
	var peer: StubPeer = StubPeer.new()
	var api: MultiplayerAPI = _api_with(peer)
	assert_true(NetFanout.can_send(api, session))
	peer.status = MultiplayerPeer.CONNECTION_CONNECTING
	assert_false(NetFanout.can_send(api, session))

