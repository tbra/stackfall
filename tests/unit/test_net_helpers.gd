extends GutTest
## Bontago-fca.36.5: NetFanout.can_send() / Net.can_send() are the single owner of
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


func test_offline_session_cannot_send() -> void:
	var session: FakeSession = FakeSession.new()
	session.offline = true
	assert_false(NetFanout.can_send(_api_with(StubPeer.new()), session))


func test_engine_offline_peer_cannot_send() -> void:
	var session: FakeSession = FakeSession.new()
	assert_false(NetFanout.can_send(_api_with(OfflineMultiplayerPeer.new()), session))


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


func test_net_autoload_offline_cannot_send() -> void:
	assert_false(Net.can_send(), "an offline Net never sends")


func test_net_nodes_carry_no_private_copies() -> void:
	for path: String in ["res://net/MatchNet.gd", "res://net/WeatherNet.gd", "res://net/SnowNet.gd", "res://net/BreezeNet.gd", "res://game/BotController.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_false(src.contains("func _is_host"), "%s keeps a private _is_host" % path)
		assert_false(src.contains("func _can_send"), "%s keeps a private _can_send" % path)
		assert_false(src.contains("OfflineMultiplayerPeer"), "%s re-tests the offline peer" % path)
