extends GutTest
## A gift crate is drawn on the LIVE disc surface. The disc can tilt after the crate spawned
## (an earthquake, a heavy stack, the host's replicated pose on a client), so a falling crate
## lerps toward the live landing, a landed crate rides the surface, and the host's air-catch
## test uses the crate where it is drawn. Observed through the crate node, Match.gift_state,
## the wire events a client receives and the claims the host makes.

const MatchNetScript := preload("res://net/MatchNet.gd")
const CRATE_POINT: Vector2 = Vector2(0.0, 15.0)
const TILT_RAD: float = 0.21
const MIN_SHIFT_M: float = 1.5
const FALL_TICK_S: float = 0.5
const NEAR_LANDING_TICKS: int = 16
const TOUCH_DROP_M: float = 0.5
const LOCAL: int = 0
const CLIENT_SLOT: int = 1
const WIRE_GIFT_ID: int = 41

var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _map: MapDef
var _cube: BlockShape
var _net: MatchNetScript


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_cube = load("res://config/blocks/cube.tres") as BlockShape
	_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	_net = null
	Match._net_provider = null
	MatchContext.current().local_held().clear()
	Match._gifts._gift_config = load("res://config/gifts/gift_config.tres") as GiftConfig
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = 2
	config.rng_seed = 4242
	config.sandbox = true
	config.gifts_enabled = true
	config.special_frequency = 0
	return config


func _run_countdown() -> void:
	for index: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


## Sway is switched off so a falling crate is exactly the origin-to-landing lerp.
func _calm_gifts() -> void:
	var gift_config: GiftConfig = Match._gifts._gift_config.duplicate() as GiftConfig
	gift_config.sway_amplitude_m = 0.0
	Match._gifts._gift_config = gift_config


func _start_host() -> void:
	var config: MatchConfig = _config()
	Match.start_match(config)
	_run_countdown()
	_calm_gifts()
	for slot: int in range(2):
		Match._feed.debug_force_next_shape(slot, _cube.id)


func _start_client() -> void:
	Match.start_match(_config())
	_run_countdown()
	_calm_gifts()
	Match._net_provider = FakeNet.client(CLIENT_SLOT)
	_net = MatchNetScript.new()
	_net.set_process(false)
	add_child_autofree(_net)
	assert_true(_net.bind_ports(FakeSessionPort.new(Match._net_provider), MatchHostPort.new(Match), MatchReplicaPort.new(Match)))
	Match._gifts.reset()


func _spawn() -> int:
	var gift_id: int = Match._gifts._next_gift_id
	Match._gifts._spawn_crate_at(CRATE_POINT)
	return gift_id


func _crate_node(gift_id: int) -> GiftCrate:
	var pending: Array[Node] = [get_tree().root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var crate: GiftCrate = node as GiftCrate
		if crate != null and crate.gift_id == gift_id:
			return crate
		pending.append_array(node.get_children())
	return null


func _surface(point: Vector2) -> Vector3:
	return _field.world_from_disk_local(point, GiftCrate.CRATE_SIZE.y * 0.5)


func _tilt() -> void:
	await _pose(Quaternion(Vector3.RIGHT, TILT_RAD))


## The replicated-pose write every peer's Field accepts; the sync body takes it on the next physics frame.
func _pose(tilt: Quaternion) -> void:
	_field.apply_replicated_pose(_field.global_position, tilt)
	await wait_physics_frames(2)


## Runs the host gift tick `count` times.
func _fall_ticks(count: int) -> void:
	for tick: int in range(count):
		Match._gifts.tick_host(FALL_TICK_S)


func _publish(origin: Vector3) -> void:
	MatchContext.current().local_held().publish(LOCAL, Match.held_shape(LOCAL), origin, 0, Quaternion.IDENTITY, true, 0.0)


func test_level_disc_crate_lands_on_the_spawn_surface_point() -> void:
	_start_host()
	var gift_id: int = _spawn()
	var node: GiftCrate = _crate_node(gift_id)
	_fall_ticks(40)
	assert_eq(Match.gift_state(gift_id)["phase"], MatchGifts.LANDED)
	assert_true(node.global_position.is_equal_approx(Match.gift_state(gift_id)["landing"]))
	assert_true(node.global_position.is_equal_approx(_surface(CRATE_POINT)))


func test_host_falling_crate_heads_for_the_live_surface_after_a_tilt() -> void:
	_start_host()
	var gift_id: int = _spawn()
	var node: GiftCrate = _crate_node(gift_id)
	var spawn_landing: Vector3 = Match.gift_state(gift_id)["landing"]
	await _tilt()
	var live: Vector3 = _surface(CRATE_POINT)
	assert_gt(live.distance_to(spawn_landing), MIN_SHIFT_M, "fixture: the tilt moved the surface point")
	_fall_ticks(NEAR_LANDING_TICKS)
	var state: Dictionary = Match.gift_state(gift_id)
	assert_eq(state["phase"], MatchGifts.FALLING, "fixture: still in the air")
	var distance: float = (state["origin"] as Vector3).distance_to(spawn_landing)
	var progress: float = float(state["elapsed"]) * Match._gifts._gift_config.fall_speed_m_s / distance
	assert_true(node.global_position.is_equal_approx((state["origin"] as Vector3).lerp(live, progress)),
		"the drawn crate is on the arc from the sky origin to the live landing")
	assert_eq(state["landing"], spawn_landing, "the flight record keeps its spawn-time landing")


func test_host_landed_crate_sits_on_the_live_surface_after_a_tilt() -> void:
	_start_host()
	var gift_id: int = _spawn()
	var node: GiftCrate = _crate_node(gift_id)
	_fall_ticks(40)
	assert_eq(Match.gift_state(gift_id)["phase"], MatchGifts.LANDED)
	await _tilt()
	_fall_ticks(1)
	assert_false(Match.gift_state(gift_id).is_empty(), "fixture: the crate is still waiting")
	assert_true(node.global_position.is_equal_approx(_surface(CRATE_POINT)))
	assert_gt(node.global_position.distance_to(Match.gift_state(gift_id)["landing"]), MIN_SHIFT_M)


func test_host_crate_landing_after_a_tilt_ends_on_the_live_surface() -> void:
	_start_host()
	var gift_id: int = _spawn()
	var node: GiftCrate = _crate_node(gift_id)
	await _tilt()
	_fall_ticks(40)
	assert_eq(Match.gift_state(gift_id)["phase"], MatchGifts.LANDED)
	assert_true(node.global_position.is_equal_approx(_surface(CRATE_POINT)))


func test_host_landed_crate_follows_a_second_tilt() -> void:
	_start_host()
	var gift_id: int = _spawn()
	var node: GiftCrate = _crate_node(gift_id)
	_fall_ticks(40)
	await _tilt()
	_fall_ticks(1)
	var first: Vector3 = node.global_position
	await _pose(Quaternion(Vector3.RIGHT, -TILT_RAD))
	_fall_ticks(1)
	assert_true(node.global_position.is_equal_approx(_surface(CRATE_POINT)))
	assert_gt(node.global_position.distance_to(first), MIN_SHIFT_M)


func test_air_catch_uses_the_crate_where_it_is_drawn() -> void:
	_start_host()
	var gift_id: int = _spawn()
	var node: GiftCrate = _crate_node(gift_id)
	await _tilt()
	_fall_ticks(NEAR_LANDING_TICKS)
	assert_eq(Match.gift_state(gift_id)["phase"], MatchGifts.FALLING, "fixture: still in the air")
	var drawn: Vector3 = node.global_position
	_publish(drawn - Vector3.UP * TOUCH_DROP_M)
	Match._gifts.tick_host(0.0001)
	assert_true(Match.gift_state(gift_id).is_empty(), "a block touching the drawn crate claims it")
	assert_eq(Match.pending_special_count(LOCAL), 1)


func test_air_catch_at_the_stale_spawn_position_misses() -> void:
	_start_host()
	var gift_id: int = _spawn()
	await _tilt()
	_fall_ticks(NEAR_LANDING_TICKS)
	var node: GiftCrate = _crate_node(gift_id)
	var wire: Dictionary = Match.gift_state(gift_id)
	assert_eq(wire["phase"], MatchGifts.FALLING, "fixture: still in the air")
	var untilted: Vector3 = (wire["origin"] as Vector3).lerp(wire["landing"], float(wire["elapsed"]) * Match._gifts._gift_config.fall_speed_m_s
		/ (wire["origin"] as Vector3).distance_to(wire["landing"]))
	assert_gt(untilted.distance_to(node.global_position), MIN_SHIFT_M, "fixture: the untilted arc is far from the drawn crate")
	_publish(untilted - Vector3.UP * TOUCH_DROP_M)
	Match._gifts.tick_host(0.0001)
	assert_false(Match.gift_state(gift_id).is_empty(), "the crate is not where the spawn-time arc says")
	assert_eq(Match.pending_special_count(LOCAL), 0)


func test_client_falling_crate_heads_for_the_live_surface_after_a_tilt() -> void:
	_start_client()
	var landing: Vector3 = _surface(CRATE_POINT)
	var origin: Vector3 = landing + Vector3.UP * Match._gifts._gift_config.drop_height_m
	_net.net_match_event(MatchWireEvents.GIFT_FLIGHT, [WIRE_GIFT_ID, origin, landing])
	var node: GiftCrate = _crate_node(WIRE_GIFT_ID)
	assert_not_null(node)
	await _tilt()
	var live: Vector3 = _surface(CRATE_POINT)
	assert_gt(live.distance_to(landing), MIN_SHIFT_M, "fixture: the tilt moved the surface point")
	Match._physics_process(NEAR_LANDING_TICKS * FALL_TICK_S)
	var state: Dictionary = Match.gift_state(WIRE_GIFT_ID)
	assert_eq(state["phase"], MatchGifts.FALLING)
	var progress: float = float(state["elapsed"]) * Match._gifts._gift_config.fall_speed_m_s / origin.distance_to(landing)
	assert_true(node.global_position.is_equal_approx(origin.lerp(live, progress)))
	Match._physics_process(100.0)
	assert_true(node.global_position.is_equal_approx(live), "at the end of the arc it is on the live surface")
	assert_eq(Match.gift_state(WIRE_GIFT_ID)["phase"], MatchGifts.FALLING, "reaching the end does not land it")


func test_client_applies_gift_landed_after_a_tilt_and_the_crate_sits_on_the_live_surface() -> void:
	_start_client()
	var landing: Vector3 = _surface(CRATE_POINT)
	var origin: Vector3 = landing + Vector3.UP * Match._gifts._gift_config.drop_height_m
	_net.net_match_event(MatchWireEvents.GIFT_FLIGHT, [WIRE_GIFT_ID, origin, landing])
	var node: GiftCrate = _crate_node(WIRE_GIFT_ID)
	await _tilt()
	Match._physics_process(FALL_TICK_S)
	watch_signals(Events)
	_net.net_match_event(MatchWireEvents.GIFT_LANDED, [WIRE_GIFT_ID, landing])
	assert_eq(Match.gift_state(WIRE_GIFT_ID)["phase"], MatchGifts.LANDED, "the host's landed event is accepted")
	assert_signal_emit_count(Events, "gift_landed", 1)
	assert_true(node.global_position.is_equal_approx(_surface(CRATE_POINT)))
	assert_eq(Match.gift_state(WIRE_GIFT_ID)["landing"], landing, "the flight keeps the wire landing")


func test_client_landed_crate_follows_later_tilts() -> void:
	_start_client()
	var landing: Vector3 = _surface(CRATE_POINT)
	var origin: Vector3 = landing + Vector3.UP * Match._gifts._gift_config.drop_height_m
	_net.net_match_event(MatchWireEvents.GIFT_FLIGHT, [WIRE_GIFT_ID, origin, landing])
	var node: GiftCrate = _crate_node(WIRE_GIFT_ID)
	_net.net_match_event(MatchWireEvents.GIFT_LANDED, [WIRE_GIFT_ID, landing])
	Match._physics_process(1.0 / 60.0)
	assert_true(node.global_position.is_equal_approx(landing), "level disc: unchanged")
	await _tilt()
	Match._physics_process(1.0 / 60.0)
	assert_true(node.global_position.is_equal_approx(_surface(CRATE_POINT)))
	assert_gt(node.global_position.distance_to(landing), MIN_SHIFT_M)
	assert_eq(Match.gift_state(WIRE_GIFT_ID)["phase"], MatchGifts.LANDED)


func test_client_crate_spawned_late_on_a_tilted_disc_rests_on_the_live_surface() -> void:
	_start_client()
	await _tilt()
	_net.net_match_event(MatchWireEvents.GIFT_SPAWNED, [WIRE_GIFT_ID, CRATE_POINT])
	var node: GiftCrate = _crate_node(WIRE_GIFT_ID)
	Match._physics_process(1.0 / 60.0)
	assert_true(node.global_position.is_equal_approx(_surface(CRATE_POINT)))
