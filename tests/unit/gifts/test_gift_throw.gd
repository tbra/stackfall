extends GutTest
## Bontago-1pi.85.16/85.29: gift throw policy. Bomb/Magnet/Jumping Bean are thrown along GiftAim's
## host-computed ballistic velocity from the camera forward (client speed is ignored), Rocket/Paintball
## fly along that forward (Rocket at any pitch, 1pi.85.34 Q3), every other gift refuses a throw.
## Fixture family of test_match_throw.gd (tiny map, real Field, injected SpecialDefs).

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
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
	Match.set_net_provider(null)
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
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


## Starts a match with `id` held by slot 0 and its def injected into the placement cache.
func _start_with(id: StringName, mode: GiftThrow.Mode) -> void:
	Match.start_match(_config())
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	Match._gifts._ensure_capacity(0)
	Match._gifts._held_specials[0] = id
	Match._feed._held_is_gift[0] = true
	Match._placement._special_defs_config = Match.config
	Match._placement._special_defs_by_id[id] = _make_def(id, mode)


func _throw(velocity: Vector3, orient: int = 0, quat: Quaternion = Quaternion.IDENTITY) -> StringName:
	return Match.request_throw(0, _home_world_position(0), orient, quat, velocity)


func _tuning() -> SpecialTuning:
	return Match._placement._special_tuning


# --- pure rules --------------------------------------------------------------

func test_throw_velocity_is_forward_plus_up_ratio_at_the_tuned_speed() -> void:
	var t: SpecialTuning = SpecialTuning.new()
	var v: Vector3 = GiftAim.throw_velocity(Vector3(0.0, 0.0, 7.0), t)
	assert_almost_eq(v.length(), t.gift_throw_speed_mps, 0.001)
	assert_almost_eq(v.y / v.z, t.gift_throw_up_ratio, 0.001)
	assert_true(GiftAim.throw_velocity(Vector3(0.0, 0.0, 0.1), t).is_equal_approx(v), "length of forward is irrelevant")


func test_throwable_gift_leaves_along_the_host_computed_velocity_whatever_the_client_sends() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	var forward: Vector3 = Vector3(1.0, 0.2, 0.0)
	assert_eq(_throw(forward * 1.7), PlacementRules.REASON_OK)
	var block: Block = _blocks_root.get_child(0) as Block
	var expected: Vector3 = GiftAim.throw_velocity(forward, _tuning(), GiftAim.range_scale(_tiny_map.field_radius, _tuning()))
	assert_true(block.linear_velocity.is_equal_approx(expected), "%s vs %s" % [block.linear_velocity, expected])


func test_a_client_speed_sized_velocity_is_refused_not_trusted() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	assert_eq(_throw(Vector3(900.0, 50.0, 0.0)), PlacementRules.REASON_NO_BLOCK, "outside the unit-aim band")
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.held_special(0), &"gift_bomb")


func test_throwable_gift_with_no_usable_forward_is_refused_and_stays_held() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	assert_eq(_throw(Vector3.ZERO), PlacementRules.REASON_NO_BLOCK)
	assert_eq(_throw(Vector3(NAN, 0.0, 1.0)), PlacementRules.REASON_NO_BLOCK)
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.held_special(0), &"gift_bomb")


func test_a_non_throwable_gift_refuses_the_throw_and_is_not_burned() -> void:
	_start_with(&"gift_anvil", GiftThrow.Mode.NONE)
	var seq: int = Match.feed_seq(0)
	assert_eq(_throw(Vector3(5.0, 0.0, 0.0)), ThrowRules.REASON_NOT_A_SPECIAL)
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.feed_seq(0), seq)
	assert_eq(Match.held_special(0), &"gift_anvil")


# --- host: aimed launch (Rocket/Paintball) --------------------------------------

func test_aimed_gift_refuses_malformed_directions_and_stays_held() -> void:
	_start_with(&"gift_rocket", GiftThrow.Mode.AIMED)
	var bad_vectors: Array[Vector3] = [
		Vector3.ZERO, Vector3(NAN, 0.0, 1.0), Vector3(0.0, 0.0, INF), Vector3(0.0, 0.0, 1.0e6), Vector3(0.0, 0.001, 0.0)
	]
	for bad: Vector3 in bad_vectors:
		assert_eq(_throw(bad), PlacementRules.REASON_NO_BLOCK, str(bad))
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.held_special(0), &"gift_rocket")


# --- Bontago-1pi.85.21: host validation findings -----------------------------------

func test_paintball_with_a_straight_up_aim_is_refused_and_stays_held() -> void:
	var def: SpecialDef = _make_def(&"gift_paintball", GiftThrow.Mode.AIMED)
	def.effect = PaintballEffect.new()
	_start_with(&"gift_paintball", GiftThrow.Mode.AIMED)
	Match._placement._special_defs_by_id[&"gift_paintball"] = def
	var seq: int = Match.feed_seq(0)
	assert_eq(_throw(Vector3(0.0, 1.0, 0.0)), PlacementRules.REASON_NO_BLOCK)
	assert_eq(_blocks_root.get_child_count(), 0, "nothing spawned")
	assert_eq(Match.feed_seq(0), seq, "the piece was not consumed")
	assert_eq(Match.held_special(0), &"gift_paintball")


func test_a_gift_spawns_upright_whatever_orientation_the_intent_carries() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	assert_eq(_throw(Vector3(1.0, 0.0, 0.0), 5, Quaternion(Vector3.RIGHT, 1.0)), PlacementRules.REASON_OK)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_true(block.global_transform.basis.is_equal_approx(Basis.IDENTITY))


# --- Paintball aimed flight ---------------------------------------------------------
