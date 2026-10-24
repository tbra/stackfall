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
	assert_eq(_snow_net.states_applied, 1)


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
	assert_eq(_snow_net.states_refused, 4)
	_net.is_host_value = true
	assert_false(_snow_net.apply_state(_state([NET_ID], -1)), "the host never applies a replicated state")


func test_a_client_awaiting_its_world_refuses_a_snow_state() -> void:
	var block: Block = _client_block(NET_ID, Vector3.ZERO)
	_start_client_snow()
	var awaiting: Array[bool] = [true]
	_snow_net.awaiting_world = func() -> bool: return awaiting[0]
	_snow_net.net_snow_state(_state([NET_ID], -1))
	_snow_net.step_client(BIG_BUDGET)
	assert_null(_cap_mesh(block, SnowCaps.CAP_NAME), "nothing drawn while awaiting")
	awaiting[0] = false
	_snow_net.net_snow_state(_state([NET_ID], -1))
	_snow_net.step_client(BIG_BUDGET)
	assert_not_null(_cap_mesh(block, SnowCaps.CAP_NAME), "the same state draws once the world is here")


func test_a_client_refuses_a_snow_state_from_a_peer_other_than_the_server() -> void:
	var block: Block = _client_block(NET_ID, Vector3.ZERO)
	_start_client_snow()
	var api: ForgedSenderApi = ForgedSenderApi.install(get_tree(), _snow_net, 7)
	_snow_net.net_snow_state(_state([NET_ID], -1))
	_snow_net.step_client(BIG_BUDGET)
	assert_null(_cap_mesh(block, SnowCaps.CAP_NAME), "a non-server sender draws nothing")
	api.sender_id = MultiplayerPeer.TARGET_PEER_SERVER
	_snow_net.net_snow_state(_state([NET_ID], -1))
	_snow_net.step_client(BIG_BUDGET)
	assert_not_null(_cap_mesh(block, SnowCaps.CAP_NAME), "the server's own message draws")



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
	assert_eq(_snow_net.states_sent, 1, "first state goes at once")
	relay.publish(_state([NET_ID, LATE_NET_ID], -1))
	assert_eq(_snow_net.states_sent, 1, "second is held by the throttle")
	var frames: int = 0
	while _snow_net.states_sent < 2 and frames < FLUSH_WAIT_FRAMES:
		await get_tree().process_frame
		frames += 1
	assert_eq(_snow_net.states_sent, 2, "held state flushed after the interval")
	assert_eq((_snow_net.last_sent_state["b"] as PackedInt32Array).size(), 10)
	relay.publish(_state([NET_ID], -1))
	relay.publish(_empty_state())
	assert_eq(_snow_net.states_sent, 3, "an empty state bypasses the throttle")
	assert_true(SnowRelay.is_empty_state(_snow_net.last_sent_state), "and replaces the held one")
	await get_tree().create_timer(_snow.send_min_interval_s * 2.0).timeout
	assert_eq(_snow_net.states_sent, 3, "nothing stale sent afterwards")
	relay.publish(_state([NET_ID], -1))
	var before: int = _snow_net.states_sent
	Events.net_peer_joined.emit(7, 1, "late")
	assert_eq(_snow_net.states_sent, before + 1, "late joiner gets the current state")
	relay.publish(_empty_state())


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
	assert_eq(bare.states_refused, 1, "no bind: the host check goes to the real Net")
	assert_eq(bare.states_applied, 0)
