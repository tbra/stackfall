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


class SnowFakeNet:
	extends RefCounted
	var host: bool = false

	func is_host() -> bool:
		return host

	func is_offline() -> bool:
		return true


class SnowFakeMatch:
	extends RefCounted
	var field_ref: Field = null
	var registry_ref: BlockRegistry = null
	var weather_ref: MatchWeather = null
	var state_value: int = MatchAutoload.State.PLAYING

	func field() -> Field:
		return field_ref

	func registry() -> BlockRegistry:
		return registry_ref

	func weather() -> MatchWeather:
		return weather_ref

	func state() -> int:
		return state_value


var _net: SnowFakeNet = null
var _match: SnowFakeMatch = null
var _snow_net: SnowNet = null
var _snow: SnowTuning = null
var _field: Field = null
var _registry: BlockRegistry = null
var _weather: MatchWeather = null
var _physics: PhysicsTuning = null


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
	_net = SnowFakeNet.new()
	_match = SnowFakeMatch.new()
	_match.field_ref = _field
	_match.registry_ref = _registry
	_match.weather_ref = _weather
	_snow_net = SnowNet.new()
	assert_true(_snow_net.bind(SessionPort.new(_net, SnowNet.SESSION_METHODS), MatchHostPort.new(_match, SnowNet.AUTHORITY_METHODS)), "narrow doubles bind")
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
	_net.host = true
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
	_net.host = true
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


func test_bind_refuses_a_double_missing_a_called_method() -> void:
	var bare: SnowNet = autofree(SnowNet.new()) as SnowNet
	var lacking: RefCounted = RefCounted.new()
	var session: SessionPort = SessionPort.new(_net, SnowNet.SESSION_METHODS)
	var authority: MatchHostPort = MatchHostPort.new(lacking, SnowNet.AUTHORITY_METHODS)
	assert_false(authority.is_valid())
	assert_false(bare.bind(session, authority), "an invalid port is refused")
	assert_false(bare.bind(null, null), "null ports are refused")
	assert_push_error_count(1, "N0d's conformance check logs once")


func test_set_providers_shim_binds_the_same_ports() -> void:
	var shimmed: SnowNet = SnowNet.new()
	shimmed.set_providers(_net, _match)
	shimmed._tuning = _snow
	add_child_autofree(shimmed)
	_start_client_snow()
	var block: Block = _client_block(NET_ID, Vector3.ZERO)
	assert_true(shimmed.apply_state(_state([NET_ID], -1)), "the shim reads the injected match")
	shimmed.step_client(BIG_BUDGET)
	assert_not_null(_cap_mesh(block, SnowCaps.CAP_NAME))
	_net.host = true
	assert_false(shimmed.apply_state(_state([NET_ID], -1)), "and the injected session")

