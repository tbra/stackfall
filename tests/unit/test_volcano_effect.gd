extends GutTest
## VolcanoEffect (lifecycle hooks, config, landing -> structure)
## (Bontago-1pi.85.14). The structure itself is covered by
## test_volcano_structure.gd. Uses a real started host Match on a tiny map.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _tuning: SpecialTuning


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
	_tuning = (load("res://config/special_tuning.tres") as SpecialTuning).duplicate(true) as SpecialTuning


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	# Free synchronously (see test_match_special_spawn.gd's own after_each()
	# comment) -- GUT's end-of-script orphan check runs before the next idle
	# frame does.
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 13579
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func _cube_shape() -> BlockShape:
	return load("res://config/blocks/cube.tres") as BlockShape


func _volcano_def(effect: VolcanoEffect) -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = &"volcano_test"
	def.arm_delay = 0.0
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	def.effect = effect
	return def


func _find_behavior(block: Block) -> SpecialBehavior:
	for child: Node in block.get_children():
		if child is SpecialBehavior:
			return child as SpecialBehavior
	return null


# --- wants_early_trigger: false, then true at eruption_duration_s -----------


func _real_def() -> SpecialDef:
	for def: SpecialDef in SpecialDef.load_all_specials():
		if def.id == &"volcano":
			return def
	return null


func _make_bare_block(position: Vector3) -> Block:
	var block: Block = Block.new()
	block.mass = 1.0
	block.gravity_scale = 0.0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.3
	collision.shape = shape
	block.add_child(collision)
	add_child(block)
	autofree(block)
	block.global_position = position
	return block


func _make_bare_behavior(block: Block, effect: SpecialEffect, tuning: SpecialTuning) -> SpecialBehavior:
	var def: SpecialDef = SpecialDef.new()
	def.arm_delay = 0.0
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	def.effect = effect
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	autofree(behavior)
	behavior.bind(block, def, tuning)
	return behavior


func _structures() -> Array[VolcanoStructure]:
	var found: Array[VolcanoStructure] = []
	for child: Node in _field.get_children():
		if child is VolcanoStructure and not child.is_queued_for_deletion():
			found.append(child as VolcanoStructure)
	return found


# --- lifecycle hooks and config ---------------------------------------------

func test_hooks_declare_a_landed_detaching_timed_effect() -> void:
	var effect: VolcanoEffect = VolcanoEffect.new()
	assert_true(effect.needs_landing())
	assert_true(effect.detaches())
	assert_false(effect.triggers_on_impact())
	assert_false(effect.impact_triggers(null, null))
	assert_true(effect.wants_early_trigger(null, null), "runs only once landed, then triggers at once")
	assert_gte(effect.effect_lifetime_s(), effect.rise_s + 20.0, "the eruption lasts at least 20 s after the rise")


func test_volcano_tres_loads_with_a_usable_eruption() -> void:
	var found: SpecialDef = _real_def()
	assert_not_null(found, "config/specials/volcano.tres must be found by load_all_specials()")
	assert_true(found.effect is VolcanoEffect)
	var effect: VolcanoEffect = found.effect as VolcanoEffect
	assert_gt(effect.rise_s, 0.0)
	assert_gt(effect.eruption_duration_s, 0.0)
	assert_gt(effect.height_m, 0.0)
	assert_gt(effect.base_radius_m, 0.0)
	assert_gt(effect.cone_angle_deg, 0.0)
	assert_gt(effect.launch_speed_mps, 0.0)
	assert_gt(effect.eruption_interval_min_s, 0.0)
	assert_gte(effect.eruption_interval_max_s, effect.eruption_interval_min_s, "the eruption interval range is ordered")
	assert_gt(effect.block_cap, 0)
	assert_not_null(effect.particles, "eruption particle tuning")
	assert_not_null(effect.shape_weights, "shared gift shape weights")


func test_detonate_spawns_one_structure_on_the_field_for_the_owner() -> void:
	Match.start_match(_config())
	_run_countdown()
	var effect: VolcanoEffect = VolcanoEffect.new()
	var block: Block = Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(1), Basis.IDENTITY, 1, Vector3.ZERO, _volcano_def(effect), _tuning
	)
	var behavior: SpecialBehavior = _find_behavior(block)
	effect.detonate(block, behavior, 0)
	var found: Array[VolcanoStructure] = _structures()
	assert_eq(found.size(), 1, "the structure is a Field child so it rides the disc")
	assert_true(found[0].has_body(), "host structure carries the collision body")
	assert_eq(found[0]._owner_slot, 1)


## Real physics: a gift dropped on the disc lands, triggers at once and the
## carrier goes without the 0.75 s linger while the structure stands.
func test_real_landing_triggers_removes_carrier_and_raises_the_structure() -> void:
	Match.start_match(_config())
	_run_countdown()
	var block: Block = Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(0), Basis.IDENTITY, 0, Vector3.ZERO, _real_def(), _tuning
	)
	var behavior: SpecialBehavior = _find_behavior(block)
	assert_not_null(behavior)
	behavior.despawn_when_done = true
	watch_signals(behavior)
	var ticks: int = 0
	while not behavior.is_triggered() and ticks < 600:
		await wait_physics_frames(1)
		ticks += 1
	assert_true(behavior.is_triggered(), "volcano triggers once the carrier landed (ticks: %d)" % ticks)
	assert_eq(_structures().size(), 1, "the structure stands after the trigger")
	assert_signal_emit_count(behavior, "completed", 1, "detaches: completed right at trigger, no linger")
