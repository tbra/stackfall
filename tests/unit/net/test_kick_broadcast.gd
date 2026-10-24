extends GutTest
## a peer the host is kicking (Net.kick_peer) stays in
## multiplayer.get_peers() until ENet completes the disconnect, and a send that
## addresses it logs an engine error. Net's own fan-outs are already filtered; this
## covers every other host broadcast: MatchNet, SnapshotSync and the
## weather / snow / breeze relays. The only production kick is
## MatchWorldReplay.tick_timeouts (a mid-match joiner that never acked its replay).
##
## Real ENet over loopback, one host and two clients in this process, each a full
## Net instance on its own MultiplayerAPI (the test_net_session.gd pattern) with
## its own MatchNet / SnapshotSync mirrors as children, so an RPC addressed to the
## kicked peer goes through the real transport. GUT fails a test on an unexpected
## engine error, which is how the unfixed broadcasts show up.

const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")
const _MATCH_NET_SCRIPT: GDScript = preload("res://net/MatchNet.gd")
const _SNAPSHOT_SCRIPT: GDScript = preload("res://net/SnapshotSync.gd")
const JOINER_NAME: String = "Latey"
const HOST_PEER: int = 1
const ONE_SNAPSHOT_S: float = 1.0


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
	assert_true(match_net.bind_ports(SessionPort.new(net), MatchHostPort.new(Match), MatchReplicaPort.new(Match)))
	side.match_net = match_net
	side.weather = match_net.get("_weather_net") as WeatherNet
	assert_true(side.weather.bind(SessionPort.new(net), MatchHostPort.new(Match, WeatherNet.AUTHORITY_METHODS)))
	side.snow = side.weather.get_node("SnowNet") as SnowNet
	assert_true(side.snow.bind(SessionPort.new(net), MatchHostPort.new(Match, SnowNet.AUTHORITY_METHODS)))
	side.breeze = side.weather.get_node("BreezeNet") as BreezeNet
	assert_true(side.breeze.bind(SessionPort.new(net), MatchHostPort.new(Match, BreezeNet.AUTHORITY_METHODS)))
	var snapshot: Node = _SNAPSHOT_SCRIPT.new()
	snapshot.name = "SnapshotSync"
	net.add_child(snapshot)
	snapshot.call("bind_session", SessionPort.new(net))
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
	Match.set_process(true)
	MatchTestReset.clear_world()
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


## The per-peer (rpc_id) senders, aimed at every listed peer: the host's join handlers (MatchNet,
## weather, snow) each answer a seated peer with its own state, addressed to it alone.
func _fire_per_peer(rig: Rig) -> void:
	for peer_id: int in _peers_of(rig):
		Events.net_peer_joined.emit(peer_id, rig.net.slot_of_peer(peer_id), JOINER_NAME)


## One snapshot, through the production host tick (it addresses every listed peer).
func _fire_snapshot(rig: Rig) -> void:
	var registry: BlockRegistry = BlockRegistry.new()
	add_child_autofree(registry)
	rig.snapshot.begin_match(registry, MapDef.base())
	rig.snapshot.host_tick(ONE_SNAPSHOT_S)


func _fire_relays(rig: Rig) -> void:
	rig.weather._on_weather_state_changed({"phase": 1})
	rig.snow._send({})
	rig.breeze._on_gust_started({"id": 1})


func _fire_every_broadcast(rig: Rig) -> void:
	_fire_match_net(rig)
	_fire_snapshot(rig)
	_fire_relays(rig)
	_fire_per_peer(rig)


## Kicks the first client, fires `fire` while ENet still lists it (the window the
## engine errors come from), lets one transport poll pass and fires again if it is
## still listed, then waits for the disconnect to finish and checks nothing is left
## on the roster. GUT fails the test on any engine error raised along the way.
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
	assert_eq(_host.net.peer_ids().size(), 1, "and only the host is left on the roster")
	return kicked_id


# --- Reproduction: one test per broadcast family ----------------------------------

func test_every_host_broadcast_skips_a_peer_that_is_being_kicked() -> void:
	await _kick_then_fire(_fire_every_broadcast)


## A running match on the real Match with nothing replicated, so a mid-match join can owe a replay.
func _start_live_match() -> void:
	Match.set_process(false)
	Match.set_replicator(null)
	var field: Field = Field.new()
	field.map_def = MapDef.base().scaled(0.75)
	add_child_autofree(field)
	var blocks_root: Node3D = Node3D.new()
	add_child_autofree(blocks_root)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child_autofree(registry)
	Match.register_world(field, registry, blocks_root)
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.disc_size_step = 1
	config.player_count = 3
	config.ai_count = 0
	config.rng_seed = 4242
	config.allow_mid_match_join = true
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the match is running")


## The production trigger: MatchWorldReplay kicks a mid-match joiner that never acknowledged its
## world replay (time advanced on the clock the test hands it), and the host's next broadcast tick
## follows right behind it.
func test_a_replay_timeout_kick_is_followed_by_silent_broadcasts() -> void:
	var clients: Array[Rig] = await _connect(1)
	var kicked_id: int = clients[0].net.local_peer_id()
	_start_live_match()
	var now_s: Array[float] = [0.0]
	var seams: MatchWorldReplay.Seams = WorldReplaySeams.make(
		func(_peer_id: int, _method: StringName, _args: Array) -> bool: return true,
		func() -> float: return now_s[0]
	)
	var net_config: NetConfig = _host.match_net.config
	var replay: MatchWorldReplay = MatchWorldReplay.new(_host.net, Match, net_config, seams)
	replay.on_peer_joined(kicked_id, _host.net.slot_of_peer(kicked_id), JOINER_NAME)
	assert_true(replay.is_pending(kicked_id), "the joiner owes its replay ack")
	replay.tick_timeouts(now_s[0] + net_config.replay_ack_timeout * 0.5)
	assert_false(_host.net.is_peer_disconnecting(kicked_id), "nothing happens inside the timeout")
	replay.tick_timeouts(now_s[0] + net_config.replay_ack_timeout + 1.0)
	assert_false(replay.is_pending(kicked_id), "the replay timed out")
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
	clients[1].match_net.submit_cursor(clients[1].net.local_slot(), Vector3.ZERO, 0, Quaternion.IDENTITY)
	var heard: bool = await _wait_until(func() -> bool:
		return get_signal_emit_count(Events, "match_loading_announced") >= 1
	)
	assert_true(heard, "the kept client receives the broadcast")
	await _wait_until(func() -> bool: return _peers_of(_host).size() == 1, 120)
	assert_eq(_peers_of(_host), PackedInt32Array([kept_id]), "only the kept peer is left")
	assert_eq(get_signal_emit_count(Events, "match_loading_announced"), 1, "and it heard the broadcast exactly once")


# --- NetFanout and the snapshot peer list -----------------------------------------
