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
	Match.set_net_provider(null)
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


func test_aim_maths_reject_unusable_forwards() -> void:
	var t: SpecialTuning = SpecialTuning.new()
	for bad: Vector3 in [Vector3.ZERO, Vector3(NAN, 0.0, 1.0), Vector3(INF, 0.0, 0.0)]:
		assert_eq(GiftAim.throw_velocity(bad, t), Vector3.ZERO)
		assert_eq(GiftAim.straight_velocity(bad, 10.0), Vector3.ZERO)
		assert_eq(GiftAim.spawn_point(Vector3(1.0, 2.0, 3.0), bad, 0.0, t), Vector3(1.0, 2.0, 3.0))


func test_spawn_point_is_back_along_the_aim_and_never_below_the_min_height() -> void:
	var t: SpecialTuning = SpecialTuning.new()
	var cursor: Vector3 = Vector3(0.0, 10.0, 0.0)
	var forward: Vector3 = Vector3(0.0, -1.0, -1.0).normalized()
	var p: Vector3 = GiftAim.spawn_point(cursor, forward, 0.0, t)
	assert_true(p.is_equal_approx(cursor - forward * t.gift_aim_back_m))
	var up_aim: Vector3 = GiftAim.spawn_point(Vector3(0.0, 0.2, 0.0), Vector3.UP, 0.0, t)
	assert_almost_eq(up_aim.y, t.gift_aim_min_height_m, 0.001, "clamped over the surface")


func test_sanitize_aim_rejects_non_finite_zero_and_out_of_range_vectors() -> void:
	var tuning: SpecialTuning = SpecialTuning.new()
	assert_eq(GiftThrow.sanitize_aim(Vector3.ZERO, tuning), Vector3.ZERO)
	assert_eq(GiftThrow.sanitize_aim(Vector3(NAN, 0.0, 1.0), tuning), Vector3.ZERO)
	assert_eq(GiftThrow.sanitize_aim(Vector3(INF, 0.0, 0.0), tuning), Vector3.ZERO)
	assert_eq(GiftThrow.sanitize_aim(Vector3(1000.0, 0.0, 0.0), tuning), Vector3.ZERO)
	assert_eq(GiftThrow.sanitize_aim(Vector3(0.01, 0.0, 0.0), tuning), Vector3.ZERO)
	assert_true(GiftThrow.sanitize_aim(Vector3(0.0, 0.0, 1.5), tuning).is_equal_approx(Vector3(0.0, 0.0, 1.0)))


func test_shipped_roster_flags_match_the_owner_answer() -> void:
	for id: StringName in [&"bomb", &"magnet", &"jumping_bean"]:
		assert_eq(GiftThrow.mode_for(SpecialDef.find_by_id(id)), GiftThrow.Mode.THROW, String(id))
	for id: StringName in [&"rocket", &"paintball"]:
		assert_eq(GiftThrow.mode_for(SpecialDef.find_by_id(id)), GiftThrow.Mode.AIMED, String(id))
	for id: StringName in [&"anvil", &"propeller", &"earthquake", &"volcano", &"glue", &"black_hole", &"stackfall"]:
		var def: SpecialDef = SpecialDef.find_by_id(id)
		if def != null:
			assert_eq(GiftThrow.mode_for(def), GiftThrow.Mode.NONE, String(id))


# --- host: camera-aimed ballistic throw -----------------------------------------

func test_throwable_gift_leaves_along_the_host_computed_velocity_whatever_the_client_sends() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	var forward: Vector3 = Vector3(1.0, 0.2, 0.0)
	assert_eq(_throw(forward * 1.7), PlacementRules.REASON_OK)
	var block: Block = _blocks_root.get_child(0) as Block
	var expected: Vector3 = GiftAim.throw_velocity(forward, _tuning())
	assert_true(block.linear_velocity.is_equal_approx(expected), "%s vs %s" % [block.linear_velocity, expected])


func test_the_aim_length_band_does_not_change_the_host_velocity() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	assert_eq(_throw(Vector3(0.6, 0.0, 0.0)), PlacementRules.REASON_OK)
	var first: Vector3 = (_blocks_root.get_child(0) as Block).linear_velocity
	Match._gifts._held_specials[0] = &"gift_bomb"
	assert_eq(_throw(Vector3(1.9, 0.0, 0.0)), PlacementRules.REASON_OK)
	var second: Vector3 = (_blocks_root.get_child(1) as Block).linear_velocity
	assert_true(first.is_equal_approx(second), "%s vs %s" % [first, second])


func test_a_client_speed_sized_velocity_is_refused_not_trusted() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	assert_eq(_throw(Vector3(900.0, 50.0, 0.0)), PlacementRules.REASON_NO_BLOCK, "outside the unit-aim band")
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.held_special(0), &"gift_bomb")


func test_throwable_gift_spawns_on_the_camera_line_not_at_the_cursor() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	var forward: Vector3 = Vector3(1.0, -0.2, 0.0).normalized()
	assert_eq(_throw(forward), PlacementRules.REASON_OK)
	var block: Block = _blocks_root.get_child(0) as Block
	var cursor: Vector3 = _home_world_position(0)
	assert_lt(block.global_position.x, cursor.x - 1.0, "moved back along the aim")
	assert_gte(block.global_position.y, _field.surface_y() + _tuning().gift_aim_min_height_m - 0.01)


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

func test_rocket_keeps_an_upward_aim_exactly() -> void:
	# Bontago-1pi.85.34 Q3: the Rocket flies where the camera aims, upward included.
	_start_with(&"gift_rocket", GiftThrow.Mode.AIMED)
	assert_eq(_throw(Vector3(0.0, 0.5, 1.5)), PlacementRules.REASON_OK)  # looks up
	var block: Block = _blocks_root.get_child(0) as Block
	assert_eq(block.linear_velocity, Vector3.ZERO, "an aimed gift is dropped, not thrown")
	var stored: Vector3 = block.get_meta(RocketEffect.LAUNCH_DIRECTION_META) as Vector3
	assert_true(stored.is_equal_approx(Vector3(0.0, 0.5, 1.5).normalized()), "upward kept, normalised: %s" % stored)


func test_rocket_accepts_a_straight_up_aim() -> void:
	_start_with(&"gift_rocket", GiftThrow.Mode.AIMED)
	assert_eq(_throw(Vector3(0.0, 1.0, 0.0)), PlacementRules.REASON_OK)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_true((block.get_meta(RocketEffect.LAUNCH_DIRECTION_META) as Vector3).is_equal_approx(Vector3.UP))


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

func test_unresolved_def_gift_never_launches_with_the_raw_client_velocity() -> void:
	Match.start_match(_config())
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	Match._gifts._ensure_capacity(0)
	Match._gifts._held_specials[0] = &"no_such_gift"
	Match._feed._held_is_gift[0] = true
	var hostile: Vector3 = Vector3(0.0, 24.0, 0.0)
	assert_eq(_throw(hostile), PlacementRules.REASON_NO_BLOCK, "outside the aim band: refused")
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.held_special(0), &"no_such_gift", "nothing consumed")
	var sent: Vector3 = Vector3(1.0, 1.0, 0.0)
	assert_eq(_throw(sent), PlacementRules.REASON_OK)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_true(block.linear_velocity.is_equal_approx(GiftAim.throw_velocity(sent, _tuning())))


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


func test_overlap_check_uses_the_basis_the_gift_actually_spawns_with() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	var tilted: Quaternion = Quaternion(Vector3.RIGHT, 1.0)
	assert_eq(_throw(Vector3(1.0, 0.0, 0.0), 5, tilted), PlacementRules.REASON_OK)
	var spawn_basis: Basis = (_blocks_root.get_child(0) as Block).global_transform.basis
	assert_true(spawn_basis.is_equal_approx(Basis.IDENTITY))
	assert_true(
		Match._placement._spawn_basis(&"gift_bomb", Basis(tilted)).is_equal_approx(spawn_basis),
		"the helper both the lift check and the spawn use yields the spawned basis"
	)
	assert_true(Match._placement._spawn_basis(&"", Basis(tilted)).is_equal_approx(Basis(tilted)), "plain blocks keep the pose")


# --- host: upright spawn ----------------------------------------------------------

func test_a_gift_spawns_upright_whatever_orientation_the_intent_carries() -> void:
	_start_with(&"gift_bomb", GiftThrow.Mode.THROW)
	assert_eq(_throw(Vector3(1.0, 0.0, 0.0), 5, Quaternion(Vector3.RIGHT, 1.0)), PlacementRules.REASON_OK)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_true(block.global_transform.basis.is_equal_approx(Basis.IDENTITY))


# --- Paintball aimed flight ---------------------------------------------------------

func test_paintball_launch_direction_is_sanitised_and_vetoes_the_velocity_drop_impact() -> void:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	var effect: PaintballEffect = PaintballEffect.new()
	assert_true(effect.impact_triggers(block, null), "no direction: the old velocity-drop impact still applies")
	assert_false(PaintballEffect.set_launch_direction(block, Vector3.ZERO))
	assert_false(PaintballEffect.set_launch_direction(block, Vector3(NAN, 0.0, 1.0)))
	assert_true(PaintballEffect.set_launch_direction(block, Vector3(0.0, 2.0, 3.0)))
	var stored: Vector3 = block.get_meta(PaintballEffect.LAUNCH_DIRECTION_META) as Vector3
	assert_true(stored.is_equal_approx(Vector3(0.0, 0.0, 1.0)), "not upward, unit length")
	assert_false(effect.impact_triggers(block, null), "a flying paintball ends by its contact probe")
