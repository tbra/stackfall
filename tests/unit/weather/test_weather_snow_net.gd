extends GutTest
## Snow: replication surface net/SnowNet.gd. A client draws
## caps from the host's compact state without ever building a collider,
## refuses malformed or out-of-event states, clears on every end path; the
## host throttles, flushes empty states at once and serves late joiners.

const NET_ID: int = 55
const LATE_NET_ID: int = 56
const FIELD_RADIUS_M: float = 6.0
const FLUSH_WAIT_FRAMES: int = 120
const BIG_BUDGET: int = 1000
const LINK_WAIT_S: float = 10.0
const HOST_ROOT: String = "SnowHostRoot"
const CLIENT_ROOT: String = "SnowClientRoot"
const SNOW_NODE: String = "SnowNet"
## Wire ints per block record (net_id, face axis, one (cell, level) pair, in SnowGeometry's layout).
const SINGLE_STATE_WIRE_SIZE: int = 5
const DOUBLE_STATE_WIRE_SIZE: int = 10


## The host port spy answering the four reads SnowNet makes: field, registry, weather, state.
class SnowHost:
	extends FakeHostPort
	var field_ref: Field = null
	var registry_ref: BlockRegistry = null
	var weather_ref: MatchWeather = null
	var state_value: int = MatchAutoload.State.PLAYING

	func field() -> FieldBody:
		return field_ref

	func registry() -> Node:
		return registry_ref

	func weather() -> RefCounted:
		return weather_ref

	func state() -> int:
		return state_value


var _net: FakeNet = null
var _match: SnowHost = null
var _snow_net: SnowNet = null
var _snow: SnowTuning = null
var _field: Field = null
var _registry: BlockRegistry = null
var _weather: MatchWeather = null
var _physics: PhysicsTuning = null


## An offline session (nothing is sent) that is, or is not, its own host.
func _fake_net(host: bool) -> FakeNet:
	var fake: FakeNet = FakeNet.offline()
	fake.is_host_value = host
	return fake


func before_each() -> void:
	_physics = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	_snow = (load("res://config/weather/snow.tres") as SnowTuning).duplicate() as SnowTuning
	_field = Field.new()
	_field.map_def = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_field.map_def.field_radius = FIELD_RADIUS_M
	add_child_autofree(_field)
	_registry = BlockRegistry.new()
	_weather = MatchWeather.new()
	WeatherTestHost.bind_host(self, _weather, false)
	var defs: Array[WeatherTuning] = [_snow]
	_weather.set_defs(defs)
	_net = _fake_net(false)
	_match = SnowHost.new()
	_match.field_ref = _field
	_match.registry_ref = _registry
	_match.weather_ref = _weather
	_snow_net = SnowNet.new()
	assert_true(_snow_net.bind(FakeSessionPort.new(_net), _match), "spy ports bind")
	_snow_net._tuning = _snow
	add_child_autofree(_snow_net)


func after_each() -> void:
	_weather.reset()
	_registry.free()


func _start_client_snow() -> void:
	var applied: bool = _weather.apply_replicated_state({
		"v": MatchWeather.WIRE_VERSION, "epoch": 1, "seed": 5,
		"mode": MatchConfig.WeatherMode.SNOW, "sched": MatchWeather.Sched.EVENT,
		"left": 30.0, "id": "snow", "phase": WeatherTuning.Phase.HOLD, "t": 0.0, "ev": 0,
	}, true)
	assert_true(applied, "client weather is snowing")


func _client_block(net_id: int, pos: Vector3) -> Block:
	var block: Block = BlockFactory.build(load("res://config/blocks/cube.tres") as BlockShape, _physics)
	block.freeze = true
	add_child_autofree(block)
	block.global_position = pos
	_registry.bind_net_id(block, net_id)
	return block


static func _cap_mesh(holder: Node, cap_name: StringName) -> MeshInstance3D:
	var cap: Node = holder.get_node_or_null(NodePath(String(cap_name)))
	if cap == null:
		return null
	return cap.get_node_or_null(NodePath(String(SnowCaps.CAP_MESH_NAME))) as MeshInstance3D


## Every disc drift mesh instance under `field`.
static func _disc_cap_meshes(field: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child: Node in field.get_children():
		if String(child.name).begins_with(SnowCaps.DISC_CAP_PREFIX):
			var instance: MeshInstance3D = _cap_mesh(field, child.name)
			if instance != null:
				out.append(instance)
	return out


## The live disc cover (null when none, or when it is only fading out).
static func _disc_cover(field: Node) -> SnowDiscCover:
	return field.get_node_or_null(NodePath(String(SnowCaps.DISC_COVER_NAME))) as SnowDiscCover


func _state(net_ids: Array[int], disc_cell: int) -> Dictionary:
	var b: PackedInt32Array = PackedInt32Array()
	for net_id: int in net_ids:
		SnowGeometry.append_block_record(b, net_id, SnowGeometry.AXIS_UP, PackedInt32Array([0]), PackedInt32Array([3]))
	var d: PackedInt32Array = PackedInt32Array()
	if disc_cell >= 0:
		d.append_array(PackedInt32Array([disc_cell, 2]))
	return SnowGeometry.make_state(99, 2, b, d)


func _empty_state() -> Dictionary:
	return SnowGeometry.make_state(99, 0, PackedInt32Array(), PackedInt32Array())


func _a_disc_cell() -> int:
	return _field.grid().in_disk_cells()[0]


func test_client_draws_caps_but_never_colliders() -> void:
	_start_client_snow()
	var block: Block = _client_block(NET_ID, Vector3.ZERO)
	assert_true(_snow_net.apply_state(_state([NET_ID], _a_disc_cell())))
	assert_null(_cap_mesh(block, SnowCaps.CAP_NAME), "drawing is amortised over frames")
	_snow_net.step_client(BIG_BUDGET)
	assert_not_null(_cap_mesh(block, SnowCaps.CAP_NAME), "cap drawn on the client's block")
	assert_eq(SnowCaps.lump_colliders(block).size(), 0, "no collider on a client block")
	assert_false(_disc_cap_meshes(_field).is_empty(), "disc snow drawn")
	assert_true(SnowCaps.disc_bodies(_field).is_empty(), "no disc collider body on a client")
	assert_not_null(_disc_cover(_field), "disc cover drawn from the state")
	assert_eq(_disc_cover(_field).level(), 2)


func test_client_refuses_bad_or_out_of_event_states() -> void:
	var block: Block = _client_block(NET_ID, Vector3.ZERO)
	assert_false(_snow_net.apply_state(_state([NET_ID], -1)), "no snow event live")
	_start_client_snow()
	_match.state_value = MatchAutoload.State.END
	assert_false(_snow_net.apply_state(_state([NET_ID], -1)), "match over")
	_match.state_value = MatchAutoload.State.PLAYING
	assert_false(_snow_net.apply_state({"v": 1}), "malformed")
	var forged: Dictionary = _state([NET_ID], -1)
	var wire: PackedInt32Array = forged["b"]
	wire[4] = _snow.depth_levels + 5
	forged["b"] = wire
	assert_false(_snow_net.apply_state(forged), "level out of range")
	_snow_net.step_client(BIG_BUDGET)
	assert_null(_cap_mesh(block, SnowCaps.CAP_NAME), "nothing drawn")
	_net.is_host_value = true
	assert_false(_snow_net.apply_state(_state([NET_ID], -1)), "the host never applies a replicated state")


func test_empty_state_weather_stop_and_match_end_clear_the_client() -> void:
	_start_client_snow()
	var block: Block = _client_block(NET_ID, Vector3.ZERO)
	assert_true(_snow_net.apply_state(_state([NET_ID], _a_disc_cell())))
	_snow_net.step_client(BIG_BUDGET)
	assert_not_null(_cap_mesh(block, SnowCaps.CAP_NAME))
	assert_true(_snow_net.apply_state(_empty_state()), "empty accepted")
	_snow_net.step_client(BIG_BUDGET)
	assert_null(_cap_mesh(block, SnowCaps.CAP_NAME), "melted state clears the block")
	assert_true(_disc_cap_meshes(_field).is_empty(), "and the disc")
	assert_null(_disc_cover(_field), "and the cover")
	assert_true(_snow_net.apply_state(_state([NET_ID], -1)))
	_snow_net.step_client(BIG_BUDGET)
	Events.weather_stopped.emit(&"snow")
	assert_null(_cap_mesh(block, SnowCaps.CAP_NAME), "weather stop clears")
	assert_true(_snow_net.apply_state(_state([NET_ID], -1)))
	_snow_net.step_client(BIG_BUDGET)
	Events.match_state_changed.emit(MatchAutoload.State.PLAYING, MatchAutoload.State.END)
	assert_null(_cap_mesh(block, SnowCaps.CAP_NAME), "match end clears")


func test_host_throttles_flushes_empty_states_and_serves_late_joiners() -> void:
	_net.is_host_value = true
	var relay: SnowRelay = SnowRelay.instance()
	relay.publish(_state([NET_ID], -1))
	assert_eq(_sent_blocks(), SINGLE_STATE_WIRE_SIZE, "first state goes at once")
	relay.publish(_state([NET_ID, LATE_NET_ID], -1))
	assert_eq(_sent_blocks(), SINGLE_STATE_WIRE_SIZE, "second is held by the throttle")
	var frames: int = 0
	while _sent_blocks() != DOUBLE_STATE_WIRE_SIZE and frames < FLUSH_WAIT_FRAMES:
		await get_tree().process_frame
		frames += 1
	assert_eq(_sent_blocks(), DOUBLE_STATE_WIRE_SIZE, "held state flushed after the interval")
	relay.publish(_state([NET_ID], -1))
	relay.publish(_empty_state())
	assert_true(SnowRelay.is_empty_state(_snow_net.last_sent_state), "an empty state bypasses the throttle and replaces the held one")
	await get_tree().create_timer(_snow.send_min_interval_s * 2.0).timeout
	assert_true(SnowRelay.is_empty_state(_snow_net.last_sent_state), "nothing stale sent afterwards")
	relay.publish(_empty_state())


## Wire size of the block records in the last state the host sent (0 when none).
func _sent_blocks() -> int:
	if _snow_net.last_sent_state.is_empty():
		return 0
	return (_snow_net.last_sent_state["b"] as PackedInt32Array).size()


## A peer joining late is sent the relay's current state over a real ENet link and draws it.
func test_late_joiner_receives_the_current_state_over_the_wire() -> void:
	var host_root: Node = Node.new()
	host_root.name = HOST_ROOT
	var client_root: Node = Node.new()
	client_root.name = CLIENT_ROOT
	var host_api: SceneMultiplayer = SceneMultiplayer.new()
	var client_api: SceneMultiplayer = SceneMultiplayer.new()
	get_tree().set_multiplayer(host_api, NodePath(String(get_path()) + "/" + HOST_ROOT))
	get_tree().set_multiplayer(client_api, NodePath(String(get_path()) + "/" + CLIENT_ROOT))
	add_child_autofree(host_root)
	add_child_autofree(client_root)
	var host_net: SnowNet = SnowNet.new()
	host_net.name = SNOW_NODE
	var host_session: FakeNet = FakeNet.host({1: 0}, [0])
	assert_true(host_net.bind(FakeSessionPort.new(host_session), _match))
	host_root.add_child(host_net)
	var client_net: SnowNet = SnowNet.new()
	client_net.name = SNOW_NODE
	var client_session: FakeNet = FakeNet.client(0)
	assert_true(client_net.bind(FakeSessionPort.new(client_session), _match))
	client_root.add_child(client_net)
	# Published before the link exists, so only the join handler can deliver it.
	_start_client_snow()
	var block: Block = _client_block(NET_ID, Vector3.ZERO)
	SnowRelay.instance().publish(_state([NET_ID], -1))
	var port: int = AgentProbe.free_udp_port()
	var server: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(server.create_server(port), OK)
	host_api.multiplayer_peer = server
	var link: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(link.create_client("127.0.0.1", port), OK)
	client_api.multiplayer_peer = link
	var connected: bool = await wait_until(func() -> bool: return host_api.get_peers().size() == 1, LINK_WAIT_S)
	assert_true(connected, "fixture: the client reaches the host")
	Events.net_peer_joined.emit(host_api.get_peers()[0], 1, "late")
	var drawn: bool = await wait_until(func() -> bool:
		client_net.step_client(BIG_BUDGET)
		return _cap_mesh(block, SnowCaps.CAP_NAME) != null, LINK_WAIT_S)
	assert_true(drawn, "the late joiner got the current state and drew it")
	SnowRelay.instance().publish(_empty_state())
	host_api.multiplayer_peer = null
	client_api.multiplayer_peer = null


func test_bind_refuses_an_invalid_host_port() -> void:
	var bare: SnowNet = autofree(SnowNet.new()) as SnowNet
	var session: SessionPort = FakeSessionPort.new(_net)
	var authority: MatchHostPort = MatchHostPort.new(null)
	assert_false(authority.is_valid())
	assert_false(bare.bind(session, authority), "an invalid port is refused")
	assert_false(bare.bind(null, null), "null ports are refused")


func test_snow_net_is_a_port_bound_node_and_rebinding_swaps_the_session() -> void:
	assert_true(is_instance_of(_snow_net, PortBoundNode))
	_start_client_snow()
	assert_true(_snow_net.apply_state(_state([NET_ID], -1)), "bound as a client")
	assert_true(_snow_net.bind(FakeSessionPort.new(_fake_net(true)), _match))
	assert_false(_snow_net.apply_state(_state([NET_ID], -1)), "the new session is the host: it never applies a replicated state")


func test_a_refused_bind_keeps_the_previous_binding() -> void:
	var broken: MatchHostPort = MatchHostPort.new(null)
	assert_false(_snow_net.bind(FakeSessionPort.new(_fake_net(false)), broken))
	_start_client_snow()
	assert_true(_snow_net.apply_state(_state([NET_ID], -1)), "the earlier binding still answers")


func test_an_unbound_snow_net_reads_the_real_net() -> void:
	assert_true(Net.is_offline(), "fixture: the real Net is offline, so it is its own host")
	var bare: SnowNet = SnowNet.new()
	add_child_autofree(bare)
	bare.net_snow_state(_empty_state())
	_start_client_snow()
	var block: Block = _client_block(NET_ID, Vector3.ZERO)
	bare.net_snow_state(_state([NET_ID], -1))
	_snow_net.step_client(BIG_BUDGET)
	assert_null(_cap_mesh(block, SnowCaps.CAP_NAME), "no bind: the host check goes to the real Net, so nothing is drawn")
