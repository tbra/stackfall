extends GutTest
## VolcanoStructure (Bontago-1pi.85.14): rise, footprint push, 20 s+ eruption through
## BlockSpawner, cap, match reset, client visual without a body.
## Field is an AnimatableBody3D with sync_to_physics: no test writes its transform.

const TICK: float = 1.0 / 60.0

var _field: Field
var _blocks: Node3D
var _registry: BlockRegistry
var _map: MapDef
var _effect: VolcanoEffect


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _map
	add_child_autofree(_field)
	_blocks = autofree(Node3D.new())
	add_child_autofree(_blocks)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks)
	_effect = VolcanoEffect.new()


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	for child: Node in _blocks.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _start() -> void:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true)
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = 2
	config.hot_seat = false
	config.gifts_enabled = false
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(TICK)


func _origin() -> Vector3:
	return _field.world_from_disk_local(Match.slot(0).home_position, _field.surface_y())


## Stops the node's own physics callback so tests step it by hand.
func _manual(structure: VolcanoStructure) -> VolcanoStructure:
	structure.set_physics_process(false)
	return structure


func _step(structure: VolcanoStructure, seconds: float) -> void:
	for _i: int in range(int(ceil(seconds / TICK))):
		structure.tick(TICK)


func test_rises_over_rise_s_to_height_with_a_cone_collider_on_the_beacon_layer() -> void:
	_start()
	var structure: VolcanoStructure = _manual(VolcanoStructure.spawn_host(_effect, _origin(), 0))
	assert_not_null(structure)
	assert_eq(structure.get_parent(), _field, "rides the disc as a Field child")
	assert_true(structure.has_body())
	assert_eq(structure.body().collision_layer, Field.BEACON_COLLISION_LAYER)
	assert_eq(structure.body().collision_mask, 0)
	assert_lt(structure.current_height(), 0.1)
	_step(structure, _effect.rise_s * 0.5)
	assert_almost_eq(structure.current_height(), _effect.height_m * 0.5, 0.1)
	_step(structure, _effect.rise_s * 0.5 + TICK)
	assert_almost_eq(structure.current_height(), _effect.height_m, 0.001)
	assert_false(structure.is_rising())
	var hull: ConvexPolygonShape3D = (structure.body().get_child(0) as CollisionShape3D).shape as ConvexPolygonShape3D
	var top: float = 0.0
	for point: Vector3 in hull.points:
		top = maxf(top, point.y)
	assert_almost_eq(top, _effect.height_m, 0.001, "the hull's apex reached the full height")


func test_erupts_for_at_least_20_s_of_sim_time_with_owner_cubes_and_no_stat_bump() -> void:
	_start()
	var placed_before: int = Match._stats.blocks_placed(1)
	var structure: VolcanoStructure = _manual(VolcanoStructure.spawn_host(_effect, _origin(), 1))
	_step(structure, _effect.rise_s)
	assert_eq(_blocks.get_child_count(), 0, "nothing erupts while rising")
	_step(structure, 20.0)
	assert_false(structure.is_expired(), "still alive 20 s after the rise")
	assert_gt(_blocks.get_child_count(), 20, "bursts of 1-3 blocks every 0.4-1.2 s over 20 s")
	for child: Node in _blocks.get_children():
		var block: Block = child as Block
		assert_eq(block.owner_slot, 1, "owner-coloured")
		assert_eq(block.get_child_count() > 0, true)
	assert_eq(Match._stats.blocks_placed(1), placed_before, "not counted as placements")
	_step(structure, _effect.eruption_duration_s)
	assert_true(structure.is_expired())


func test_eruption_stops_at_the_block_cap() -> void:
	_start()
	_effect.block_cap = 6
	var structure: VolcanoStructure = _manual(VolcanoStructure.spawn_host(_effect, _origin(), 0))
	_step(structure, _effect.rise_s + 10.0)
	assert_lte(_blocks.get_child_count(), 6, "never more than block_cap children")
	assert_gt(_blocks.get_child_count(), 0)


func test_removed_when_the_match_is_no_longer_live() -> void:
	_start()
	var structure: VolcanoStructure = _manual(VolcanoStructure.spawn_host(_effect, _origin(), 0))
	structure.tick(TICK)
	assert_false(structure.is_queued_for_deletion())
	Match.abort_match()
	structure.tick(TICK)
	assert_true(structure.is_queued_for_deletion(), "match reset removes the structure")


func test_client_visual_has_no_body_and_spawns_nothing() -> void:
	_start()
	var visual: VolcanoStructure = VolcanoStructure.new()
	visual.configure(_effect, 0, false)
	_field.add_child(visual)
	_manual(visual)
	assert_false(visual.has_body(), "clients get no physics body")
	_step(visual, _effect.rise_s + 5.0)
	assert_eq(_blocks.get_child_count(), 0, "a visual-only structure never spawns blocks")
	assert_almost_eq(visual.current_height(), _effect.height_m, 0.001)
	assert_null(VolcanoStructure.build_client_visual(_effect, _origin(), 0), "host draws its own structure")


func test_build_rejects_a_point_off_the_disc_and_a_missing_effect() -> void:
	_start()
	assert_null(VolcanoStructure.spawn_host(null, _origin(), 0))
	assert_null(VolcanoStructure.spawn_host(_effect, Vector3(500.0, 0.0, 0.0), 0))
	assert_null(VolcanoStructure.spawn_host(_effect, Vector3(NAN, 0.0, 0.0), 0))


## A block resting inside the footprint is pushed outward as the cone rises.
func test_rising_cone_pushes_footprint_blocks_outward() -> void:
	_start()
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var block: Block = BlockFactory.build(load("res://config/blocks/cube.tres") as BlockShape, tuning)
	_blocks.add_child(block)
	var center: Vector3 = _origin()
	block.global_position = center + Vector3(1.0, 0.5, 0.0)
	await wait_physics_frames(2)
	var structure: VolcanoStructure = VolcanoStructure.spawn_host(_effect, center, 0)
	assert_not_null(structure)
	var start_flat: float = Vector2(block.global_position.x - center.x, block.global_position.z - center.z).length()
	await wait_physics_frames(int(ceil(_effect.rise_s * 60.0)))
	var end_flat: float = Vector2(block.global_position.x - center.x, block.global_position.z - center.z).length()
	assert_gt(end_flat, start_flat + 1.0, "pushed outward by the rising cone (%f -> %f)" % [start_flat, end_flat])


func _model_effect() -> VolcanoEffect:
	var def: SpecialDef = load("res://config/specials/volcano.tres") as SpecialDef
	return (def.effect as VolcanoEffect).duplicate(true) as VolcanoEffect


func _mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_mesh_instances(child, out)


## Union AABB of all meshes under the structure, in the structure's own space.
func _visual_bounds(structure: VolcanoStructure) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_mesh_instances(structure, meshes)
	var bounds: AABB = AABB()
	var first: bool = true
	for mesh: MeshInstance3D in meshes:
		var local: AABB = structure.global_transform.affine_inverse() * mesh.global_transform * mesh.mesh.get_aabb()
		bounds = local if first else bounds.merge(local)
		first = false
	return bounds


func _assert_model_fits(effect: VolcanoEffect, structure: VolcanoStructure) -> void:
	_step(structure, effect.rise_s + TICK)
	var bounds: AABB = _visual_bounds(structure)
	assert_almost_eq(bounds.size.x, effect.base_radius_m * 2.0, 0.05, "footprint x")
	assert_almost_eq(bounds.size.z, effect.base_radius_m * 2.0, 0.05, "footprint z")
	assert_almost_eq(bounds.size.y, effect.height_m, 0.05, "height")
	assert_almost_eq(bounds.position.y, 0.0, 0.05, "base sits on y = 0")
	assert_almost_eq(bounds.position.x + bounds.size.x * 0.5, 0.0, 0.05, "centred on x")


func test_host_instances_the_model_scaled_to_the_effect_dimensions() -> void:
	_start()
	var effect: VolcanoEffect = _model_effect()
	assert_not_null(effect.model_scene, "volcano.tres sets the model")
	var structure: VolcanoStructure = _manual(VolcanoStructure.spawn_host(effect, _origin(), 0))
	var meshes: Array[MeshInstance3D] = []
	_mesh_instances(structure, meshes)
	assert_gt(meshes.size(), 0)
	assert_false(meshes[0].mesh is CylinderMesh, "the model replaces the procedural cone")
	_assert_model_fits(effect, structure)


func test_client_visual_uses_the_model_without_a_body() -> void:
	_start()
	var effect: VolcanoEffect = _model_effect()
	var visual: VolcanoStructure = VolcanoStructure.new()
	visual.configure(effect, 0, false)
	_field.add_child(visual)
	_manual(visual)
	assert_false(visual.has_body())
	_assert_model_fits(effect, visual)


func test_model_grows_with_the_rise_fraction() -> void:
	_start()
	var effect: VolcanoEffect = _model_effect()
	var structure: VolcanoStructure = _manual(VolcanoStructure.spawn_host(effect, _origin(), 0))
	_step(structure, effect.rise_s * 0.5)
	assert_almost_eq(_visual_bounds(structure).size.y, effect.height_m * 0.5, 0.1)


func test_null_model_scene_falls_back_to_the_cone_mesh() -> void:
	_start()
	_effect.model_scene = null
	var structure: VolcanoStructure = _manual(VolcanoStructure.spawn_host(_effect, _origin(), 0))
	var meshes: Array[MeshInstance3D] = []
	_mesh_instances(structure, meshes)
	assert_eq(meshes.size(), 1)
	assert_true(meshes[0].mesh is CylinderMesh)
	_assert_model_fits(_effect, structure)
