extends GutTest
## Stackfall activation uses the normal host spawn/registry path at a bounded rate.

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
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = 2
	config.hot_seat = false
	config.gifts_enabled = false
	config.rng_seed = 13579
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	for child: Node in Match.get_children():
		if child is StackfallRain:
			child.free()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _activation(slot_id: int = 0) -> Block:
	var home: Vector2 = Match.slot(slot_id).home_position
	return Match.spawn_special_projectile(
		load("res://config/blocks/cube.tres") as BlockShape,
		_field.world_from_disk_local(home, 5.0), Basis.IDENTITY, slot_id,
		Vector3.ZERO, null, null
	)


func _rain() -> StackfallRain:
	for child: Node in Match.get_children():
		if child is StackfallRain:
			return child as StackfallRain
	return null


func test_activation_rains_owned_registered_ordinary_blocks_at_bounded_rate() -> void:
	var activation: Block = _activation()
	var effect: StackfallEffect = StackfallEffect.new()
	effect.shape_weights = null
	effect.block_count = 4
	effect.blocks_per_second = 2.0
	effect.area_radius_m = 3.0
	effect.min_spacing_m = 1.0
	effect.detonate(activation, null, 0)
	var rain: StackfallRain = _rain()
	assert_not_null(rain)
	rain.set_physics_process(false)
	rain.advance(0.4)
	assert_eq(rain.spawned, 0)
	rain.advance(0.2)
	assert_eq(rain.spawned, 1)
	rain.advance(1.5)
	assert_eq(rain.spawned, 4)
	assert_eq(_blocks_root.get_child_count(), 5)
	for i: int in range(1, 5):
		var dropped: Block = _blocks_root.get_child(i) as Block
		assert_eq(dropped.owner_slot, 0)
		assert_eq(dropped.shape_id, &"cube")
		assert_gt(dropped.net_id, 0)
		assert_eq(_registry.block_for_net_id(dropped.net_id), dropped)
		assert_true(_map.shape_contains(_field.disk_local_from_world(dropped.global_position)))
		assert_gt(dropped.global_position.y, 10.0)
		var mesh: MeshInstance3D = dropped.get_node("BlockMesh") as MeshInstance3D
		var material: ShaderMaterial = mesh.material_override as ShaderMaterial
		assert_eq(material.get_shader_parameter(&"albedo_color"), Match.slot(0).color)
		for child: Node in dropped.get_children():
			assert_false(child is SpecialBehavior, "the rain uses ordinary blocks")


func test_body_cap_skips_excess_without_affecting_player_placement_stats() -> void:
	var activation: Block = _activation()
	var effect: StackfallEffect = StackfallEffect.new()
	effect.block_count = 4
	effect.blocks_per_second = 20.0
	effect.max_active_blocks = 2
	effect.detonate(activation, null, 0)
	var rain: StackfallRain = _rain()
	rain.set_physics_process(false)
	rain.advance(1.0)
	assert_eq(rain.attempted, 4)
	assert_eq(rain.spawned, 1)
	assert_eq(_blocks_root.get_child_count(), 2)
	assert_eq(Match._stats.blocks_placed(0), 0)


func test_off_host_does_not_start_rain() -> void:
	var activation: Block = _activation()
	Match.set_net_provider(FakeNet.client(0))
	var effect: StackfallEffect = StackfallEffect.new()
	effect.detonate(activation, null, 0)
	assert_null(_rain())


func test_rain_stops_and_cleans_up_on_match_abort() -> void:
	var activation: Block = _activation()
	var effect: StackfallEffect = StackfallEffect.new()
	effect.detonate(activation, null, 0)
	assert_not_null(_rain())
	Match.abort_match()
	await get_tree().process_frame
	assert_null(_rain())


func test_seeded_positions_repeat_and_respect_spacing() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var a: StackfallRain = StackfallRain.new()
	var b: StackfallRain = StackfallRain.new()
	a.bind(0, Vector2.ZERO, 9876, shape, 5, 2.0, 10.0, 18.0, 2.0, 40, 600)
	b.bind(0, Vector2.ZERO, 9876, shape, 5, 2.0, 10.0, 18.0, 2.0, 40, 600)
	for _i: int in range(5):
		var point_a: Vector2 = a._sample_position(_map)
		var point_b: Vector2 = b._sample_position(_map)
		assert_eq(point_a, point_b)
		assert_true(_map.shape_contains(point_a))
		for earlier: Vector2 in a._positions:
			assert_gte(point_a.distance_to(earlier), 2.0)
		a._positions.append(point_a)
		b._positions.append(point_b)
	a.free()
	b.free()


func test_shipped_special_is_available_to_the_roster() -> void:
	var def: SpecialDef = load("res://config/specials/stackfall.tres") as SpecialDef
	assert_eq(def.id, &"stackfall")
	assert_true(def.effect is StackfallEffect)
	assert_true(def.enabled_by_default)


func test_full_rain_spawns_every_block_from_height() -> void:
	var activation: Block = _activation()
	var effect: StackfallEffect = (load("res://config/specials/stackfall.tres") as SpecialDef).effect as StackfallEffect
	effect = effect.duplicate() as StackfallEffect
	effect.area_radius_m = 15.0
	effect.min_spacing_m = 0.5
	effect.detonate(activation, null, 0)
	var rain: StackfallRain = _rain()
	rain.set_physics_process(false)
	rain.advance(float(effect.block_count) / effect.blocks_per_second + 0.1)
	assert_eq(rain.attempted, effect.block_count)
	assert_eq(rain.spawned, effect.block_count)
	var highest: float = 0.0
	for i: int in range(1, _blocks_root.get_child_count()):
		highest = maxf(highest, (_blocks_root.get_child(i) as Block).global_position.y)
	assert_gt(highest, effect.spawn_height_m * 0.8)


## Bontago-1pi.85.24: only an in-place anchor makes Stackfall trigger on its own first tick; a
## falling carrier still waits for its impact.
func test_wants_early_trigger_only_for_an_in_place_anchor() -> void:
	var effect: StackfallEffect = StackfallEffect.new()
	var carrier: Block = _activation()
	assert_false(effect.wants_early_trigger(carrier, null))
	carrier.set_meta(MatchGiftActivation.IN_PLACE_META, true)
	assert_true(effect.wants_early_trigger(carrier, null))


## Bontago-1pi.85.31: the shipped rain mixes shapes (not only cubes), replicated as normal blocks.
func test_shipped_rain_spawns_a_mix_of_shapes() -> void:
	var seen: Dictionary = {}
	for _run: int in range(2):
		var activation: Block = _activation()
		var effect: StackfallEffect = (load("res://config/specials/stackfall.tres") as SpecialDef).effect as StackfallEffect
		effect = effect.duplicate() as StackfallEffect
		effect.area_radius_m = 15.0
		effect.detonate(activation, null, 0)
		var rain: StackfallRain = _rain()
		rain.set_physics_process(false)
		rain.advance(float(effect.block_count) / effect.blocks_per_second + 0.1)
		var ids: Array[StringName] = []
		for i: int in range(1, _blocks_root.get_child_count()):
			var dropped: Block = _blocks_root.get_child(i) as Block
			ids.append(dropped.shape_id)
			assert_eq(dropped.owner_slot, 0)
			assert_gt(dropped.net_id, 0)
		assert_gt(ids.size(), 10)
		var unique: Dictionary = {}
		for id: StringName in ids:
			unique[id] = true
		assert_gt(unique.size(), 2, "rain should not be only cubes")
		seen[_run] = ids
		rain.free()
		for child: Node in _blocks_root.get_children():
			child.free()
		break
	assert_true(seen.has(0))
