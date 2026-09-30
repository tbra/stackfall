extends GutTest
## Real collider smoke test for Paintball's host conversion radius.

var _field: Field
var _blocks: Node3D
var _registry: BlockRegistry


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	var map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = map
	add_child_autofree(_field)
	_blocks = autofree(Node3D.new())
	add_child_autofree(_blocks)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks)
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true)
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
	for child: Node in _blocks.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _block(slot_id: int, offset: Vector3) -> Block:
	return Match.spawn_special_projectile(
		load("res://config/blocks/cube.tres"),
		_field.world_from_disk_local(Match.slot(slot_id).home_position, 5.0) + offset,
		Basis.IDENTITY, slot_id, Vector3.ZERO, null, null
	)


func test_host_splash_converts_near_real_collider_but_not_far_block() -> void:
	var glob: Block = _block(0, Vector3.ZERO)
	var near: Block = _block(1, glob.global_position + Vector3(2.0, 0.0, 0.0) - _field.world_from_disk_local(Match.slot(1).home_position, 5.0))
	var far: Block = _block(1, glob.global_position + Vector3(10.0, 0.0, 0.0) - _field.world_from_disk_local(Match.slot(1).home_position, 5.0))
	for block: Block in [glob, near, far]:
		block.gravity_scale = 0.0
	await wait_physics_frames(1)
	var effect: PaintballEffect = PaintballEffect.new()
	effect.splash_radius_m = 3.5
	effect.detonate(glob, null, 0)
	assert_eq(near.owner_slot, 0)
	assert_eq(far.owner_slot, 1)
	assert_eq(_registry.block_for_net_id(near.net_id), near)


func test_shipped_paintball_is_enabled() -> void:
	var def: SpecialDef = load("res://config/specials/paintball.tres")
	assert_eq(def.id, &"paintball")
	assert_true(def.effect is PaintballEffect)
	assert_true(def.enabled_by_default)
