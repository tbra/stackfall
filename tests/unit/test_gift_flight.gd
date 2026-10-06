extends GutTest

class CursorProvider:
	extends RefCounted
	var poses: Dictionary = {}
	func cursor_for_slot(slot_id: int) -> Dictionary:
		return poses.get(slot_id, {})

var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
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
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match._gifts._gift_config = load("res://config/gift_config.tres") as GiftConfig
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _start() -> void:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = 2
	config.hot_seat = false
	config.rng_seed = 4242
	config.gifts_enabled = true
	config.special_frequency = 0
	Match.start_match(config)
	for index: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig


func _spawn(point: Vector2) -> int:
	var gift_id: int = Match._gifts._next_gift_id
	Match._gifts._spawn_crate_at(point)
	return gift_id


func test_flight_lands_then_expires_at_exact_configured_life_boundary() -> void:
	_start()
	Match._gifts._gift_config.relocate_min_distance_m = 1000.0
	var gift_id: int = _spawn(Vector2(0.0, 15.0))
	var initial: Dictionary = Match.gift_state(gift_id)
	assert_eq(int(initial["phase"]), MatchGifts.FALLING)
	assert_almost_eq(float(initial["origin"].y - initial["landing"].y), 18.0, 0.001)
	Match._gifts.tick_host(4.5)
	assert_eq(int(Match.gift_state(gift_id)["phase"]), MatchGifts.FALLING)
	Match._gifts.tick_host(4.5)
	assert_eq(int(Match.gift_state(gift_id)["phase"]), MatchGifts.LANDED)
	assert_eq(float(Match.gift_state(gift_id)["landed_age"]), 0.0)
	var life_s: float = Match._gifts._gift_config.life_s
	Match._gifts.tick_host(life_s - 0.001)
	assert_true(Match._gifts._crates.has(gift_id))
	Match._gifts.tick_host(0.001)
	assert_false(Match._gifts._crates.has(gift_id))


## Bontago-mp0.139: the parachute visuals follow the falling/landed state and
## change nothing about the descent itself (positions, phases, timing).
func test_host_crate_parachute_deploys_on_spawn_and_collapses_on_landing() -> void:
	_start()
	Match._gifts._gift_config.relocate_min_distance_m = 1000.0
	var gift_id: int = _spawn(Vector2(0.0, 15.0))
	var crate: GiftCrate = Match._gifts._crates[gift_id]["node"]
	var chute: GiftParachute = crate.parachute()
	assert_true(crate.is_falling())
	assert_eq(chute.phase(), ParachuteAnim.Phase.DEPLOYING)
	assert_true(chute.visible)
	Match._gifts.tick_host(4.5)
	assert_eq(int(Match.gift_state(gift_id)["phase"]), MatchGifts.FALLING, "descent timing is unchanged")
	assert_true(crate.is_falling())
	Match._gifts.tick_host(4.5)
	assert_eq(int(Match.gift_state(gift_id)["phase"]), MatchGifts.LANDED, "landing timing is unchanged")
	assert_false(crate.is_falling())
	assert_eq(chute.phase(), ParachuteAnim.Phase.COLLAPSING)
	assert_true(chute.visible, "the canopy collapses on screen instead of vanishing")
	chute.advance(Match._gifts._gift_config.life_s)
	assert_false(chute.visible)


func test_client_crate_parachute_follows_the_replicated_flight_and_landing() -> void:
	_start()
	Match.set_net_provider(FakeNet.client(0))
	var origin: Vector3 = Vector3(0.0, 10.0, 15.0)
	var landing: Vector3 = Vector3(0.0, 1.0, 15.0)
	Match._gifts.apply_replicated_flight(301, origin, landing)
	var crate: GiftCrate = Match._gifts._crates[301]["node"]
	assert_eq(crate.parachute().phase(), ParachuteAnim.Phase.DEPLOYING, "flight event inflates the canopy")
	Match._gifts.apply_replicated_flight(301, origin, landing)
	assert_eq(crate.parachute().phase(), ParachuteAnim.Phase.DEPLOYING, "a duplicate flight event is ignored")
	Match._gifts.apply_replicated_landing(301, landing)
	assert_eq(crate.parachute().phase(), ParachuteAnim.Phase.COLLAPSING, "landing event deflates it")
	assert_true(crate.parachute().visible)


func test_client_legacy_landed_spawn_shows_no_canopy() -> void:
	_start()
	Match.set_net_provider(FakeNet.client(0))
	Match._gifts.apply_replicated_spawn(302, Vector2(0.0, 15.0))
	var crate: GiftCrate = Match._gifts._crates[302]["node"]
	assert_false(crate.is_falling())
	assert_false(crate.parachute().visible, "a crate that never fell must not wear a parachute")


func test_owned_landing_claims_once() -> void:
	_start()
	var gift_id: int = _spawn(Match.slot(0).home_position)
	watch_signals(Events)
	Match._gifts.tick_host(9.0)
	assert_false(Match._gifts._crates.has(gift_id))
	assert_signal_emit_count(Events, "gift_claimed", 1)
	Match._gifts.tick_host(1.0)
	assert_signal_emit_count(Events, "gift_claimed", 1)


func test_seeded_spawn_and_reset_repeat_flight_origin() -> void:
	_start()
	Match._gifts._rng.seed = 777
	var point_a: Vector2 = GiftSpawner.pick_spawn_point(Match.raster(), Match.cell_grid(), Match._gifts._rng, Match._gifts._gift_config)
	var id_a: int = _spawn(point_a)
	var origin_a: Vector3 = Match.gift_state(id_a)["origin"]
	Match._gifts.reset()
	assert_true(Match.gift_states().is_empty())
	Match._gifts._rng.seed = 777
	var point_b: Vector2 = GiftSpawner.pick_spawn_point(Match.raster(), Match.cell_grid(), Match._gifts._rng, Match._gifts._gift_config)
	var id_b: int = _spawn(point_b)
	assert_eq(id_b, id_a)
	assert_eq(point_b, point_a)
	assert_eq(Match.gift_state(id_b)["origin"], origin_a)


func test_sway_is_bounded_and_host_client_follow_the_same_path() -> void:
	_start()
	var gift_id: int = _spawn(Vector2(0.0, 15.0))
	var state: Dictionary = Match.gift_state(gift_id)
	var origin: Vector3 = state["origin"]
	var landing: Vector3 = state["landing"]
	var crate: GiftCrate = Match._gifts._crates[gift_id]["node"]
	Match._gifts.tick_host(2.0)
	var host_position: Vector3 = crate.global_position
	var straight: Vector3 = origin.lerp(landing, 2.0 / 9.0)
	assert_almost_eq(host_position.y, straight.y, 0.001, "sway changes only the horizontal position")
	assert_gt(Vector2(host_position.x - straight.x, host_position.z - straight.z).length(), 0.01)
	assert_lte(Vector2(host_position.x - straight.x, host_position.z - straight.z).length(), 0.64)
	Match._gifts._crates[gift_id]["elapsed"] = 0.0
	crate.global_position = origin
	Match.set_net_provider(FakeNet.client(0))
	Match._gifts.tick_client(2.0)
	assert_eq(crate.global_position, host_position, "client uses the same id/time-derived sway")
	assert_eq(Match._gifts._flight_position(gift_id, origin, landing, 9.0, 1.0), landing)
	var max_horizontal_lag: float = 0.0
	for step in range(1, 91):
		var host_elapsed: float = float(step) * 0.1
		var client_elapsed: float = maxf(host_elapsed - 0.1, 0.0)
		var host_visual: Vector3 = Match._gifts._flight_position(gift_id, origin, landing,
			host_elapsed, minf(host_elapsed / 9.0, 1.0))
		var delayed_visual: Vector3 = Match._gifts._flight_position(gift_id, origin, landing,
			client_elapsed, minf(client_elapsed / 9.0, 1.0))
		max_horizontal_lag = maxf(max_horizontal_lag,
			Vector2(host_visual.x - delayed_visual.x, host_visual.z - delayed_visual.z).length())
	assert_lte(max_horizontal_lag, 0.2, "100 ms delivery lag keeps sway within 20 cm")


func test_two_held_blocks_touching_in_air_claim_once_in_slot_order() -> void:
	_start()
	var gift_id: int = _spawn(Vector2(0.0, 15.0))
	var provider: CursorProvider = CursorProvider.new()
	var cube: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	Match._held_shapes[0] = cube
	Match._held_shapes[1] = cube
	var pose: Vector3 = Match.gift_state(gift_id)["origin"] - Vector3.UP * 0.5
	var cursor: Dictionary = {"origin": pose, "orientation_index": 0,
		"free_quat": Quaternion.IDENTITY, "age": 0.0}
	provider.poses[0] = cursor
	provider.poses[1] = cursor
	Match.set_replicator(provider)
	watch_signals(Events)
	Match._gifts.tick_host(0.01)
	assert_false(Match._gifts._crates.has(gift_id))
	assert_eq(Match.held_special(0), &"")
	assert_eq(Match.pending_special_count(0), 1)
	assert_signal_emitted_with_parameters(Events, "gift_claimed", [gift_id, 0, Match._gifts._pending_queues[0][0]])
	assert_eq(Match.held_special(1), &"")
	assert_signal_emit_count(Events, "gift_claimed", 1)


func test_stale_cursor_cannot_claim_airborne_gift() -> void:
	_start()
	var gift_id: int = _spawn(Vector2(0.0, 15.0))
	var provider: CursorProvider = CursorProvider.new()
	Match._held_shapes[1] = load("res://config/blocks/cube.tres") as BlockShape
	provider.poses[1] = {"origin": Match.gift_state(gift_id)["origin"],
		"orientation_index": 0, "free_quat": Quaternion.IDENTITY, "age": 10.0}
	Match.set_replicator(provider)
	Match._gifts.tick_host(0.01)
	assert_true(Match._gifts._crates.has(gift_id))
	assert_eq(int(Match.gift_state(gift_id)["phase"]), MatchGifts.FALLING)


func test_landed_gift_claims_when_territory_arrives_later() -> void:
	_start()
	var point: Vector2 = Vector2(0.0, 15.0)
	var gift_id: int = _spawn(point)
	Match._gifts.tick_host(9.0)
	assert_eq(int(Match.gift_state(gift_id)["phase"]), MatchGifts.LANDED)
	assert_eq(Match.held_special(1), &"")
	var circles: Array[InfluenceCircle] = [InfluenceCircle.new(point, 3.0, 1, 1, true, -1)]
	Match.raster().update(circles, Match._solver.solve(circles), 0.1, true, false)
	Match._gifts.claim_or_expire_gifts(0.1)
	assert_false(Match._gifts._crates.has(gift_id))
	assert_eq(Match.held_special(1), &"")
	assert_eq(Match.pending_special_count(1), 1)


func test_air_touch_rejects_near_miss_outside_visible_box_margin() -> void:
	_start()
	var provider: CursorProvider = CursorProvider.new()
	Match._held_shapes[1] = load("res://config/blocks/cube.tres") as BlockShape
	var crate: Vector3 = Match._gifts._world_at(Vector2(0.0, 15.0), 12.0)
	provider.poses[1] = {"origin": crate + Vector3(1.08, -0.5, 0.0),
		"orientation_index": 0, "free_quat": Quaternion.IDENTITY, "age": 0.0}
	Match.set_replicator(provider)
	assert_false(Match._gifts._held_block_touches(1, crate),
		"0.6 m crate and 1 m cube have a visible gap past the 0.08 m touch margin")


func test_air_touch_accepts_rotated_cube_corner_contact() -> void:
	_start()
	var provider: CursorProvider = CursorProvider.new()
	Match._held_shapes[1] = load("res://config/blocks/cube.tres") as BlockShape
	var crate: Vector3 = Match._gifts._world_at(Vector2(0.0, 15.0), 12.0)
	provider.poses[1] = {"origin": crate + Vector3(1.05, -0.5, 0.0),
		"orientation_index": 0,
		"free_quat": Quaternion(Vector3.UP, PI * 0.25), "age": 0.0}
	Match.set_replicator(provider)
	assert_true(Match._gifts._held_block_touches(1, crate),
		"the rotated cube's extended corner meets the crate")
