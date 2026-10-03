extends GutTest
## Bontago-1pi.59: a peer the host is kicking (Net.kick_peer) stays in
## multiplayer.get_peers() until ENet completes the disconnect, and a send that
## addresses it logs an engine error. 1pi.57 filtered Net's own fan-outs; this
## covers every other host broadcast: MatchNet, SnapshotSync and the
## weather / snow / breeze relays. The only production kick is
## MatchNet._tick_replay_timeouts (a mid-match joiner that never acked its replay).
##
## Real ENet over loopback, one host and two clients in this process, each a full
## Net instance on its own MultiplayerAPI (the test_net_session.gd pattern) with
## its own MatchNet / SnapshotSync mirrors as children, so an RPC addressed to the
## kicked peer goes through the real transport. GUT fails a test on an unexpected
## engine error, which is how the unfixed broadcasts show up.

const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")
const _MATCH_NET_SCRIPT: GDScript = preload("res://net/MatchNet.gd")
const _SNAPSHOT_SCRIPT: GDScript = preload("res://net/SnapshotSync.gd")


## One instance's worth of nodes. `net` and `match_net` are Variant-typed for the
## reason test_net_session.gd documents: both scripts omit class_name.
class Rig:
	extends RefCounted
	var net: Variant = null
	var match_net: Variant = null
	var snapshot: Variant = null
	var weather: WeatherNet = null
	var snow: SnowNet = null
	var breeze: BreezeNet = null


var _host: Rig = null
var _sides: Array[Rig] = []


func _make_rig(node_name: String) -> Rig:
	var side: Rig = Rig.new()
	var net: Node = _NET_SCRIPT.new()
	net.name = node_name
	# Registered before the node enters the tree, so its _ready() binds to it.
	get_tree().set_multiplayer(
		MultiplayerAPI.create_default_interface(),
		NodePath(String(get_path()) + "/" + node_name)
	)
	add_child_autofree(net)
	side.net = net
	var match_net: Node = _MATCH_NET_SCRIPT.new()
	match_net.name = "MatchNet"
	match_net.set_process(false)
	net.add_child(match_net)
	match_net.set_providers(net, Match)
	side.match_net = match_net
	side.weather = match_net.get("_weather_net") as WeatherNet
	side.weather.set_providers(net, Match)
	side.snow = side.weather.get_node("SnowNet") as SnowNet
	side.snow.set_providers(net, Match)
	side.breeze = side.weather.get_node("BreezeNet") as BreezeNet
	side.breeze.set_providers(net, Match)
	var snapshot: Node = _SNAPSHOT_SCRIPT.new()
	snapshot.name = "SnapshotSync"
	net.add_child(snapshot)
	snapshot.call("set_net_provider", net)
	side.snapshot = snapshot
	_sides.append(side)
	return side


func before_each() -> void:
	_host = _make_rig("HostNet")


func after_each() -> void:
	for side: Rig in _sides:
		if side.net != null and is_instance_valid(side.net):
			side.net.leave()
	Match.set_replicator(null)
	Match.abort_match()
	_sides.clear()
	# Net._reject_peer() waits two frames before closing a refused connection.
	await get_tree().process_frame
	await get_tree().process_frame


func _peers_of(side: Rig) -> PackedInt32Array:
	return (side.net as Node).multiplayer.get_peers()


func _wait_until(condition: Callable, frames: int = 240) -> bool:
	for _i: int in range(frames):
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


## Host plus `client_count` joined clients, every roster settled.
func _connect(client_count: int) -> Array[Rig]:
	var port: int = AgentProbe.free_udp_port()
	assert_eq(_host.net.host_game(port, "Hostie"), OK)
	var clients: Array[Rig] = []
	for index: int in range(client_count):
		var client: Rig = _make_rig("ClientNet%d" % index)
		assert_eq(client.net.join_game("127.0.0.1", port, "Client%d" % index), OK)
		clients.append(client)
	var seated: bool = await _wait_until(func() -> bool:
		if _host.net.peer_ids().size() != client_count + 1:
			return false
		for client: Rig in clients:
			if client.net.peer_ids().size() != client_count + 1:
				return false
		return true
	)
	assert_true(seated, "host and every client settle on one roster")
	return clients


## One broadcast site per entry; the group name is the first word of each helper.
func _fire_match_net(rig: Rig) -> void:
	rig.match_net.replicate_match_loading()
	rig.match_net.replicate_match_event(_MATCH_NET_SCRIPT.EVENT_COUNTDOWN, [3])
	rig.match_net.replicate_despawn(7, "kick_test")
	rig.match_net.submit_cursor(0, Vector3.ZERO, 0, Quaternion.IDENTITY)


func _fire_snapshot(rig: Rig) -> void:
	rig.snapshot._send_packet(PackedByteArray([1, 2, 3, 4]))


func _fire_relays(rig: Rig) -> void:
	rig.weather._on_weather_state_changed({"phase": 1})
	rig.snow._send({})
	rig.breeze._on_gust_started({"id": 1})


func _fire_every_broadcast(rig: Rig) -> void:
	_fire_match_net(rig)
	_fire_snapshot(rig)
	_fire_relays(rig)


## Kicks the first client, fires `fire` while ENet still lists it (the window the
## engine errors come from), lets one transport poll pass and fires again if it is
## still listed, then waits for the disconnect to finish and checks nothing is left
## marked. GUT fails the test on any engine error raised along the way.
func _kick_then_fire(fire: Callable) -> int:
	var clients: Array[Rig] = await _connect(1)
	var kicked_id: int = clients[0].net.local_peer_id()
	_host.net.kick_peer(kicked_id)
	assert_true(_peers_of(_host).has(kicked_id), "the window is open: ENet still lists the kicked peer")
	fire.call(_host)
	await get_tree().process_frame
	if _peers_of(_host).has(kicked_id):
		fire.call(_host)
	var closed: bool = await _wait_until(func() -> bool: return _peers_of(_host).is_empty(), 120)
	assert_true(closed, "the disconnect completes")
	assert_true(_host.net._disconnecting_peers.is_empty(), "and nothing stays marked afterwards")
	return kicked_id


# --- Reproduction: one test per broadcast family ----------------------------------

func test_every_host_broadcast_skips_a_peer_that_is_being_kicked() -> void:
	await _kick_then_fire(_fire_every_broadcast)


func test_match_net_broadcasts_skip_a_peer_that_is_being_kicked() -> void:
	await _kick_then_fire(_fire_match_net)


func test_snapshot_sync_skips_a_peer_that_is_being_kicked() -> void:
	await _kick_then_fire(_fire_snapshot)


func test_weather_snow_and_breeze_relays_skip_a_peer_that_is_being_kicked() -> void:
	await _kick_then_fire(_fire_relays)


## The production trigger: MatchNet._tick_replay_timeouts kicks a mid-match joiner
## that never acknowledged its world replay, and the host's next broadcast tick
## follows right behind it.
func test_a_replay_timeout_kick_is_followed_by_silent_broadcasts() -> void:
	var clients: Array[Rig] = await _connect(1)
	var kicked_id: int = clients[0].net.local_peer_id()
	var match_net: Variant = _host.match_net
	match_net._replay_pending[kicked_id] = 1
	match_net._replay_age[kicked_id] = 0.0
	match_net._tick_replay_timeouts(match_net.config.replay_ack_timeout + 1.0)
	assert_eq(match_net.replays_timed_out, 1, "the replay timed out")
	assert_true(_host.net.is_peer_disconnecting(kicked_id), "and the host is kicking the peer")
	assert_true(_peers_of(_host).has(kicked_id), "which ENet still lists")
	_fire_every_broadcast(_host)
	await _wait_until(func() -> bool: return _peers_of(_host).is_empty(), 120)
	assert_true(_peers_of(_host).is_empty(), "the disconnect completes")


# --- The peer that stays, and the unchanged normal case ---------------------------

func test_the_peer_that_stays_still_hears_every_broadcast_while_the_other_is_kicked() -> void:
	var clients: Array[Rig] = await _connect(2)
	var kicked_id: int = clients[0].net.local_peer_id()
	var kept_id: int = clients[1].net.local_peer_id()
	watch_signals(Events)
	_host.net.kick_peer(kicked_id)
	assert_true(_peers_of(_host).has(kicked_id), "the window is open")
	_fire_every_broadcast(_host)
	# The relay of a kept peer's cursor to everyone else is a broadcast too.
	_host.match_net._handle_cursor_update(kept_id, _host.net.slot_of_peer(kept_id), Vector3.ZERO, 0, Quaternion.IDENTITY)
	var heard: bool = await _wait_until(func() -> bool:
		return get_signal_emit_count(Events, "match_loading_announced") >= 1
	)
	assert_true(heard, "the kept client receives the broadcast")
	await _wait_until(func() -> bool: return _peers_of(_host).size() == 1, 120)
	assert_eq(_peers_of(_host), PackedInt32Array([kept_id]), "only the kept peer is left")
	assert_eq(get_signal_emit_count(Events, "match_loading_announced"), 1, "and it heard the broadcast exactly once")


func test_with_nobody_being_kicked_every_peer_gets_exactly_one_copy() -> void:
	await _connect(2)
	watch_signals(Events)
	_host.match_net.replicate_match_loading()
	var heard: bool = await _wait_until(func() -> bool:
		return get_signal_emit_count(Events, "match_loading_announced") >= 2
	)
	assert_true(heard, "both clients receive it")
	await get_tree().process_frame
	assert_eq(get_signal_emit_count(Events, "match_loading_announced"), 2, "one copy per peer, none duplicated")


# --- NetFanout and the snapshot peer list -----------------------------------------

func test_targets_leave_out_exactly_the_peers_being_kicked() -> void:
	var clients: Array[Rig] = await _connect(2)
	var kicked_id: int = clients[0].net.local_peer_id()
	var kept_id: int = clients[1].net.local_peer_id()
	var api: MultiplayerAPI = (_host.net as Node).multiplayer
	var everyone: Array[int] = NetFanout.targets(api, _host.net)
	assert_eq(everyone.size(), 2, "nobody is being kicked yet")
	_host.net.kick_peer(kicked_id)
	assert_eq(NetFanout.targets(api, _host.net), [kept_id] as Array[int])
	assert_eq(NetFanout.targets(api, null).size(), 2, "a session that cannot say is treated as not kicking anyone")
	assert_eq(Array(_host.snapshot._remote_peers()), [kept_id], "SnapshotSync's peer list drops the kicked peer too")
	_host.net.kick_peer(kept_id)
	assert_true(NetFanout.targets(api, _host.net).is_empty(), "every peer kicked leaves nobody to address")
	assert_eq(_host.snapshot._remote_peer_count(), 0)


func test_targets_are_empty_without_a_transport() -> void:
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	assert_true(NetFanout.targets(api, null).is_empty())
	assert_true(NetFanout.targets(null, null).is_empty())
