extends GutTest
## Cat is a transient host body with a bounded owner-only laser target.

var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	var map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.player_count = 2
	config.hot_seat = false
	config.gifts_enabled = false
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _activation() -> Block:
	return Match.spawn_special_projectile(
		load("res://config/blocks/cube.tres") as BlockShape,
		_field.world_from_disk_local(Match.slot(0).home_position, 5.0),
		Basis.IDENTITY, 0, Vector3.ZERO, null, null)


func test_activation_uses_separate_host_body_and_owner_target() -> void:
	var block: Block = _activation()
	var effect: CatEffect = CatEffect.new()
	effect.target_range_m = 3.0
	effect.detonate(block, null, 0)
	var cat: CatController = Match.active_cat()
	assert_not_null(cat)
	assert_eq(cat.owner_slot, 0)
	assert_eq(_blocks_root.get_child_count(), 1)
	assert_false(cat.freeze)
	assert_false(Match.set_cat_target(1, cat.global_position + Vector3.RIGHT))
	assert_true(Match.set_cat_target(0, cat.global_position + Vector3.RIGHT * 30.0))
	assert_almost_eq(cat.target.distance_to(cat._origin), 3.0, 0.01)
	assert_false(Match.set_cat_target(0, Vector3.INF))
	cat.set_physics_process(false)
	cat._physics_process(effect.duration_s + 0.1)
	assert_null(Match.active_cat())


func test_body_cap_and_reset() -> void:
	var block: Block = _activation()
	var effect: CatEffect = CatEffect.new()
	effect.max_active_blocks = 1
	effect.detonate(block, null, 0)
	assert_null(Match.active_cat())


func test_host_body_pushes_a_physics_obstacle() -> void:
	var block: Block = _activation()
	var effect: CatEffect = CatEffect.new()
	effect.speed_mps = 12.0
	effect.detonate(block, null, 0)
	var cat: CatController = Match.active_cat()
	assert_not_null(cat)
	var obstacle: RigidBody3D = RigidBody3D.new()
	obstacle.gravity_scale = 0.0
	obstacle.lock_rotation = true
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3.ONE
	collider.shape = shape
	obstacle.add_child(collider)
	_blocks_root.add_child(obstacle)
	obstacle.global_position = cat.global_position + Vector3.RIGHT * 2.0
	var initial: Vector3 = obstacle.global_position
	assert_true(Match.set_cat_target(0, cat.global_position + Vector3.RIGHT * 6.0))
	for _frame: int in range(60):
		await get_tree().physics_frame
	assert_gt(obstacle.global_position.x, initial.x + 0.1)
	effect.max_active_blocks = 2
	effect.detonate(block, null, 0)
	assert_not_null(Match.active_cat())
	Match.abort_match()
	assert_null(Match.active_cat())


func test_client_mirror_has_no_physical_collisions() -> void:
	var block: Block = _activation()
	Match.set_net_provider(FakeNet.client(0))
	var effect: CatEffect = CatEffect.new()
	effect.detonate(block, null, 0)
	assert_null(Match.active_cat())
	var point: Vector3 = _field.world_from_disk_local(Vector2.ZERO, 1.0)
	assert_true(Match.apply_replicated_cat_start(1, 0, point, 5.0))
	var cat: CatController = Match.active_cat()
	assert_true(cat.freeze)
	assert_eq(cat.collision_layer, 0)
	Match.apply_replicated_cat_state(1, point + Vector3.RIGHT, Vector3.RIGHT, point, 4.0)
	assert_eq(cat.global_position, point + Vector3.RIGHT)
	Match.end_cat(1)
	assert_null(Match.active_cat())


func test_pointer_stays_on_solid_map_and_cat_survives_sudden_death() -> void:
	var block: Block = _activation()
	var effect: CatEffect = CatEffect.new()
	effect.target_range_m = 100.0
	assert_true(Match.start_cat(0, block.global_position, effect))
	var cat: CatController = Match.active_cat()
	assert_true(Match.set_cat_target(0, cat.global_position + Vector3.RIGHT * 100.0))
	assert_true(_field.map_def.shape_contains(_field.disk_local_from_world(cat.target)))
	cat.set_physics_process(false)
	Match._lifecycle._state = Match.State.SUDDEN_DEATH
	var before: float = cat.time_left
	assert_true(Match.set_cat_target(0, cat.global_position + Vector3.LEFT))
	cat._physics_process(0.1)
	assert_eq(Match.active_cat(), cat)
	assert_lt(cat.time_left, before)
