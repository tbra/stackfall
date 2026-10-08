extends GutTest
## Bontago-1pi.134 (owner decision 1pi.133 = A) and 1pi.135: a held throwable gift is thrown
## along the player's last known aim at timer expiry, exactly like a manual release; bots pick
## release points for the map's throw range. Fixture family of test_gift_throw.gd.

const MatchNetScript := preload("res://net/MatchNet.gd")
const REMOTE_PEER: int = 2
const REMOTE_SLOT: int = 1
const AIM: Vector3 = Vector3(1.0, 0.2, 0.0)
const GRAVITY: float = 9.8

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _net: MatchNetScript


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 13579
	return config


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func _make_def(id: StringName, mode: GiftThrow.Mode) -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = id
	def.throwable = mode == GiftThrow.Mode.THROW
	def.aimed_launch = mode == GiftThrow.Mode.AIMED
	def.arm_delay = 999.0
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	if mode == GiftThrow.Mode.AIMED:
		def.effect = RocketEffect.new()
	return def


func _start_with(id: StringName, mode: GiftThrow.Mode, slot_id: int = 0) -> void:
	Match.start_match(_config())
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	_hold(id, mode, slot_id)


func _hold(id: StringName, mode: GiftThrow.Mode, slot_id: int = 0) -> void:
	Match._gifts._ensure_capacity(slot_id)
	Match._gifts._held_specials[slot_id] = id
	Match._feed._held_is_gift[slot_id] = true
	Match._placement._special_defs_config = Match.config
	Match._placement._special_defs_by_id[id] = _make_def(id, mode)


func _expire(slot_id: int = 0, origin: Vector3 = Vector3.INF) -> StringName:
	var where: Vector3 = _home_world_position(slot_id) if origin == Vector3.INF else origin
	return Match.request_place(slot_id, where, 0, Quaternion.IDENTITY, true, Match.feed_seq(slot_id))


func _tuning() -> SpecialTuning:
	return Match._placement._special_tuning


func _scaled_throw(aim: Vector3) -> Vector3:
	return GiftAim.throw_velocity(aim, _tuning(), GiftAim.range_scale(_tiny_map.field_radius, _tuning()))


# --- host: expiry == manual release -----------------------------------------------

func test_expiry_throws_a_held_throwable_gift_along_the_last_aim() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	var seq: int = Match.feed_seq(0)
	Match.note_aim(0, AIM)
	assert_eq(_expire(), PlacementRules.REASON_OK)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_true(block.linear_velocity.is_equal_approx(_scaled_throw(AIM)), "%s" % block.linear_velocity)
	assert_eq(Match.feed_seq(0), seq + 1, "the held gift was consumed exactly once")
	assert_eq(_blocks_root.get_child_count(), 1)


func test_expiry_throw_equals_the_manual_release_at_the_same_aim() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	Match.note_aim(0, AIM)
	assert_eq(_expire(), PlacementRules.REASON_OK)
	var auto: Block = _blocks_root.get_child(0) as Block
	var auto_velocity: Vector3 = auto.linear_velocity
	var auto_position: Vector3 = auto.global_position
	_hold(&"gift_bomb", GiftThrow.Mode.THROW)
	var reason: StringName = Match.request_throw(
		0, _home_world_position(0), 0, Quaternion.IDENTITY, AIM, Match.feed_seq(0)
	)
	assert_eq(reason, PlacementRules.REASON_OK)
	var manual: Block = _blocks_root.get_child(1) as Block
	assert_true(manual.linear_velocity.is_equal_approx(auto_velocity), "same arc and range")
	assert_true(manual.global_position.is_equal_approx(auto_position), "same spawn point")


func test_expiry_throw_scales_with_the_map_range_like_a_manual_throw() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	var original: float = _tuning().gift_throw_reference_radius
	_tuning().gift_throw_reference_radius = _tiny_map.field_radius / 1.5
	Match.note_aim(0, AIM)
	var result: StringName = _expire()
	var expected: Vector3 = _scaled_throw(AIM)
	_tuning().gift_throw_reference_radius = original
	assert_eq(result, PlacementRules.REASON_OK)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_true(block.linear_velocity.is_equal_approx(expected))
	assert_gt(block.linear_velocity.length(), _tuning().gift_throw_speed_mps, "range_scale > 1 speeds it up")


func test_expiry_releases_a_held_rocket_as_an_aimed_launch() -> void:
	_start_with(&"gift_rocket", GiftThrow.Mode.AIMED)
	Match.note_aim(0, Vector3(0.0, 0.5, 1.5))
	var seq: int = Match.feed_seq(0)
	assert_eq(_expire(), PlacementRules.REASON_OK)
	assert_eq(Match.feed_seq(0), seq + 1)
	assert_eq(_blocks_root.get_child_count(), 1)


# --- fallbacks --------------------------------------------------------------------

func test_a_non_throwable_special_follows_its_manual_release_path() -> void:
	_start_with(&"gift_anvil", GiftThrow.Mode.NONE)
	Match.note_aim(0, AIM)
	var seq: int = Match.feed_seq(0)
	assert_eq(_expire(), PlacementRules.REASON_OK)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_eq(block.linear_velocity, Vector3.ZERO, "dropped in place, never thrown")
	assert_eq(Match.feed_seq(0), seq + 1)


func test_no_known_aim_falls_back_to_the_ordinary_drop() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	assert_eq(_expire(), PlacementRules.REASON_OK)
	assert_eq((_blocks_root.get_child(0) as Block).linear_velocity, Vector3.ZERO)


func test_an_invalid_aim_falls_back_to_the_ordinary_drop_and_still_consumes() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	Match.note_aim(0, Vector3(900.0, 0.0, 0.0))
	var seq: int = Match.feed_seq(0)
	assert_eq(_expire(), PlacementRules.REASON_OK)
	assert_eq((_blocks_root.get_child(0) as Block).linear_velocity, Vector3.ZERO)
	assert_eq(Match.feed_seq(0), seq + 1, "an expiry never leaves the piece held")


func test_a_cursor_off_the_disk_falls_back_to_the_forced_drop_not_a_throw() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	Match.note_aim(0, AIM)
	var seq: int = Match.feed_seq(0)
	_expire(0, _field.to_global(Vector3(500.0, 5.0, 0.0)))
	assert_eq(Match.feed_seq(0), seq + 1, "the forced drop still spends the piece")
	assert_eq(_blocks_root.get_child_count(), 1)
	assert_eq((_blocks_root.get_child(0) as Block).linear_velocity, Vector3.ZERO, "not thrown")


func test_note_aim_forgets_unusable_values_and_a_match_reset_clears_it() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	Match.note_aim(0, AIM)
	assert_eq(Match.noted_aim(0), AIM)
	Match.note_aim(0, Vector3(NAN, 0.0, 1.0))
	assert_eq(Match.noted_aim(0), Vector3.ZERO)
	Match.note_aim(99, AIM)
	assert_eq(Match.noted_aim(99), Vector3.ZERO)
	Match.note_aim(0, AIM)
	Match.abort_match()
	assert_eq(Match.noted_aim(0), Vector3.ZERO, "world teardown drops stale aim")


func test_a_stale_feed_seq_expiry_is_refused_before_any_throw() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	Match.note_aim(0, AIM)
	var stale: int = Match.feed_seq(0) + 5
	var reason: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, true, stale)
	assert_eq(reason, PlacementRules.REASON_NO_BLOCK)
	assert_eq(_blocks_root.get_child_count(), 0)


# --- wire: remote client's held gift at expiry --------------------------------------

func _make_host_net() -> MatchNetScript:
	var peer_slots: Dictionary = {1: 0, REMOTE_PEER: REMOTE_SLOT}
	var fake: FakeNet = FakeNet.host(peer_slots, [0])
	fake.slots_by_peer = peer_slots
	Match.set_net_provider(fake)
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(fake, Match)
	_net = node
	return node


func test_a_remote_clients_held_gift_is_thrown_at_expiry_from_its_cursor_aim() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW, REMOTE_SLOT)
	var where: Vector3 = _home_world_position(REMOTE_SLOT)
	net._handle_cursor_update(REMOTE_PEER, REMOTE_SLOT, where, 0, Quaternion.IDENTITY, AIM)
	var seq: int = Match.feed_seq(REMOTE_SLOT)
	net._on_feed_timer_expired(REMOTE_SLOT)
	assert_eq(Match.feed_seq(REMOTE_SLOT), seq + 1)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_true(block.linear_velocity.is_equal_approx(_scaled_throw(AIM)), "thrown, not dropped")


func test_a_hostile_cursor_aim_is_not_trusted_and_the_expiry_still_drops() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW, REMOTE_SLOT)
	var where: Vector3 = _home_world_position(REMOTE_SLOT)
	net._handle_cursor_update(REMOTE_PEER, REMOTE_SLOT, where, 0, Quaternion.IDENTITY, Vector3(INF, 0.0, 9999.0))
	net._on_feed_timer_expired(REMOTE_SLOT)
	assert_eq(_blocks_root.get_child_count(), 1)
	assert_eq((_blocks_root.get_child(0) as Block).linear_velocity, Vector3.ZERO)


func test_another_peers_cursor_cannot_set_this_slots_aim() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW, REMOTE_SLOT)
	net._handle_cursor_update(REMOTE_PEER, 0, _home_world_position(0), 0, Quaternion.IDENTITY, AIM)
	assert_eq(Match.noted_aim(0), Vector3.ZERO, "slot/peer mismatch is dropped before the aim is read")


# --- 1pi.135: clamp and bot range -----------------------------------------------------

func test_flat_range_scales_with_the_map_range_scale() -> void:
	var t: SpecialTuning = SpecialTuning.new()
	var base: float = GiftAim.flat_range(t, 1.0, GRAVITY)
	assert_gt(base, 0.0)
	assert_almost_eq(GiftAim.flat_range(t, 2.0, GRAVITY) / base, 2.0, 0.001)
	assert_almost_eq(GiftAim.flat_range(t, 0.5, GRAVITY) / base, 0.5, 0.001)
	assert_eq(GiftAim.flat_range(t, 1.0, 0.0), 0.0)


func test_the_speed_clamp_scaling_is_limited_to_the_ballistic_throw() -> void:
	# An AIMED gift is dropped with the aim handed to the effect, never given a launch velocity.
	_start_with(&"gift_rocket", GiftThrow.Mode.AIMED)
	var original: float = _tuning().throw_max_speed
	_tuning().throw_max_speed = 0.5
	var reason: StringName = Match.request_throw(
		0, _home_world_position(0), 0, Quaternion.IDENTITY, Vector3(0.0, 0.0, 1.0), Match.feed_seq(0)
	)
	_tuning().throw_max_speed = original
	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq((_blocks_root.get_child(0) as Block).linear_velocity, Vector3.ZERO)


func _bot_tuning() -> BotTuning:
	var tuning: BotTuning = BotTuning.new()
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.uses_defensive_specials = true
	profile.uses_offensive_specials = true
	tuning.easy = profile
	tuning.normal = profile
	tuning.hard = profile
	return tuning


func test_bot_bomb_release_point_lands_within_tolerance_on_small_medium_and_large_maps() -> void:
	var t: SpecialTuning = SpecialTuning.new()
	var cluster: Vector2 = Vector2(-70.0, 0.0)
	var points: PackedVector2Array = PackedVector2Array()
	for step: int in range(-69, 71):
		points.append(Vector2(float(step), 0.0))
	var enemies: PackedVector2Array = PackedVector2Array([cluster])
	for radius: float in [MapDef.RADIUS_SMALL, MapDef.RADIUS_MEDIUM, MapDef.RADIUS_LARGE]:
		var range_m: float = GiftAim.flat_range(t, GiftAim.range_scale(radius, t), GRAVITY)
		var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
			&"bomb", Vector2.ZERO, points, enemies, PackedVector2Array(), MatchConfig.AiDifficulty.HARD,
			_bot_tuning(), [], range_m
		)
		assert_true(action.should_throw, "radius %s" % radius)
		var landing_error: float = absf(action.throw_origin.distance_to(cluster) - range_m)
		assert_lte(landing_error, 1.0, "radius %s: landing %.1f m from the cluster" % [radius, landing_error])


func test_bot_bomb_without_a_range_keeps_the_nearest_release_point() -> void:
	var points: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(-30.0, 0.0)])
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"bomb", Vector2.ZERO, points, PackedVector2Array([Vector2(-60.0, 0.0)]), PackedVector2Array(),
		MatchConfig.AiDifficulty.HARD, _bot_tuning()
	)
	assert_eq(action.throw_origin, Vector2(-30.0, 0.0))
