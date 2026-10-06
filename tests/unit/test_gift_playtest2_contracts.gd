extends GutTest
## Bontago-1pi.85.35 (docs/GIFT_PLAYTEST2_PLAN.md P0): shared contracts for gift playtest 2.
## Defaults, callable stubs, SpecialBehavior.activates_in_place / landed_tuning, and the single
## request_place hook (consumes the feed only when MatchGiftActivation.try_activate says so).
## Fixture copied from test_match_throw.gd.

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


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 13579
	return config


class StubEffect:
	extends SpecialEffect
	var ticks: int = 0
	var landing_tuning: LandedTuning = null

	func needs_landing() -> bool:
		return true

	func landed_tuning() -> LandedTuning:
		return landing_tuning

	func physics_tick(_block: Block, _behavior: SpecialBehavior, _delta: float) -> void:
		ticks += 1


class ActivationDouble:
	extends MatchGiftActivation
	var result: bool = false
	var calls: int = 0
	var last_slot: int = -1
	var last_def: SpecialDef = null
	var last_origin: Vector2 = Vector2.ZERO

	func try_activate(slot_id: int, def: SpecialDef, disk_origin: Vector2) -> bool:
		calls += 1
		last_slot = slot_id
		last_def = def
		last_origin = disk_origin
		return result


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func _queue_special(slot_id: int, special_id: StringName) -> void:
	Match._gifts._ensure_capacity(slot_id)
	Match._gifts._held_specials[slot_id] = special_id
	Match._feed._held_is_gift[slot_id] = true


func _install_def(def: SpecialDef) -> void:
	Match._placement._special_defs_config = Match.config
	Match._placement._special_defs_by_id[def.id] = def


func _in_place_def(in_place: bool) -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = &"p0_test"
	def.activates_in_place = in_place
	def.arm_delay = 999.0
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	return def


# --- Defaults ---------------------------------------------------------------------

func test_special_def_defaults_keep_today_behaviour() -> void:
	var def: SpecialDef = SpecialDef.new()
	assert_false(def.activates_in_place)
	assert_eq(def.activation_scale, 1.0)


func test_special_tuning_defaults_and_shipped_resource() -> void:
	var tunings: Array[SpecialTuning] = [
		SpecialTuning.new(), load("res://config/special_tuning.tres") as SpecialTuning
	]
	for t: SpecialTuning in tunings:
		assert_eq(t.gift_aim_back_m, 8.0)
		assert_eq(t.gift_aim_min_height_m, 1.0)
		assert_eq(t.gift_throw_speed_mps, 22.0)
		assert_eq(t.gift_throw_up_ratio, 0.35)
		assert_eq(t.activation_mass_exponent, 1.0)
		assert_true(t.gift_throw_speed_mps <= t.throw_max_speed)


func test_effect_landed_tuning_defaults_to_null() -> void:
	assert_null(SpecialEffect.new().landed_tuning())


# --- Stub signatures --------------------------------------------------------------

func test_gift_aim_signatures_are_callable() -> void:
	var t: SpecialTuning = SpecialTuning.new()
	var cursor: Vector3 = Vector3(1.0, 2.0, 3.0)
	assert_eq(GiftAim.spawn_point(cursor, Vector3.FORWARD, 0.0, t), cursor)
	assert_eq(GiftAim.straight_velocity(Vector3.FORWARD, 10.0), Vector3.ZERO)
	assert_eq(GiftAim.throw_velocity(Vector3.FORWARD, t), Vector3.ZERO)


func test_shape_picker_stub_returns_cube() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var shape: BlockShape = GiftShapePicker.pick(rng, null)
	assert_not_null(shape)
	assert_eq(shape.resource_path, GiftShapePicker.CUBE_SHAPE_PATH)


func test_activation_stub_returns_false() -> void:
	assert_false(MatchGiftActivation.new().try_activate(0, SpecialDef.new(), Vector2.ZERO))


# --- SpecialBehavior --------------------------------------------------------------

func _behavior_for(def: SpecialDef) -> SpecialBehavior:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	autofree(behavior)
	behavior.bind(block, def, SpecialTuning.new())
	return behavior


func test_needs_landing_effect_waits_for_landing_by_default() -> void:
	var def: SpecialDef = _in_place_def(false)
	def.arm_delay = 0.0
	var stub: StubEffect = StubEffect.new()
	def.effect = stub
	var behavior: SpecialBehavior = _behavior_for(def)
	behavior.advance(0.1)
	assert_eq(stub.ticks, 0, "an airborne carrier has not landed, so the effect must not tick.")


func test_activates_in_place_bypasses_needs_landing() -> void:
	var def: SpecialDef = _in_place_def(true)
	def.arm_delay = 0.0
	var stub: StubEffect = StubEffect.new()
	def.effect = stub
	var behavior: SpecialBehavior = _behavior_for(def)
	behavior.advance(0.1)
	assert_eq(stub.ticks, 1, "an in-place gift ticks without waiting for landing.")


func test_probe_is_built_from_effect_landed_tuning() -> void:
	var def: SpecialDef = _in_place_def(false)
	var stub: StubEffect = StubEffect.new()
	stub.landing_tuning = LandedTuning.new()
	stub.landing_tuning.landed_speed_mps = 7.0
	def.effect = stub
	var behavior: SpecialBehavior = _behavior_for(def)
	assert_eq(behavior._landed_probe.tuning, stub.landing_tuning)
	def.effect = null
	assert_ne(_behavior_for(def)._landed_probe.tuning.landed_speed_mps, 7.0)


# --- request_place hook -----------------------------------------------------------

func _place_gift_at_home(slot_id: int, in_place: bool, result: bool) -> Array:
	Match.start_match(_config())
	_run_countdown()
	var def: SpecialDef = _in_place_def(in_place)
	_install_def(def)
	_queue_special(slot_id, def.id)
	var double: ActivationDouble = ActivationDouble.new()
	double.result = result
	Match._placement._activation = double
	var seq_before: int = Match.feed_seq(slot_id)
	var reason: StringName = Match.request_place(
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, false
	)
	return [reason, double, seq_before]


func test_hook_consumes_feed_and_spawns_no_body_when_activated() -> void:
	var out: Array = _place_gift_at_home(0, true, true)
	var double: ActivationDouble = out[1] as ActivationDouble
	assert_eq(out[0], PlacementRules.REASON_OK)
	assert_eq(double.calls, 1)
	assert_eq(double.last_slot, 0)
	assert_eq(double.last_def.id, &"p0_test")
	assert_eq(Match.feed_seq(0), (out[2] as int) + 1, "the feed advanced once.")
	assert_eq(_blocks_root.get_child_count(), 0, "no carrier body was spawned.")
	assert_eq(Match.held_special(0), &"", "the gift was consumed.")


func test_hook_falls_through_to_carrier_when_try_activate_declines() -> void:
	var out: Array = _place_gift_at_home(0, true, false)
	assert_eq(out[0], PlacementRules.REASON_OK)
	assert_eq((out[1] as ActivationDouble).calls, 1)
	assert_eq(_blocks_root.get_child_count(), 1, "declined activation keeps the normal carrier.")


func test_hook_not_consulted_for_a_normal_gift() -> void:
	var out: Array = _place_gift_at_home(0, false, true)
	assert_eq((out[1] as ActivationDouble).calls, 0)
	assert_eq(_blocks_root.get_child_count(), 1)
