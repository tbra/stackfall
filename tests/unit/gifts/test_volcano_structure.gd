extends GutTest
## VolcanoStructure: rise, footprint push, 20 s+ eruption through
## BlockSpawner, cap, match reset, client visual without a body.
## Field is an AnimatableBody3D with sync_to_physics: the tilt test writes its pose from a PhysicsCallDriver.

const TICK: float = 1.0 / 60.0

var _field: Field
var _blocks: Node3D
var _registry: BlockRegistry
var _map: MapDef
var _effect: VolcanoEffect


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
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
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true)
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
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
	var collision: CollisionShape3D = structure.body().get_child(0) as CollisionShape3D
	var hull: ConvexPolygonShape3D = collision.shape as ConvexPolygonShape3D
	var top: float = 0.0
	for point: Vector3 in hull.points:
		top = maxf(top, point.y)
	assert_almost_eq(top * collision.scale.y, _effect.height_m, 0.001, "the hull's scaled apex reached the full height")


func test_structure_stays_seated_on_a_tilting_field() -> void:
	_start()
	var structure: VolcanoStructure = _manual(VolcanoStructure.spawn_host(_effect, _origin(), 0))
	_step(structure, _effect.rise_s + TICK)
	var local_before: Transform3D = _field.global_transform.affine_inverse() * structure.global_transform
	var tilt: Quaternion = Quaternion(Vector3(1.0, 0.0, 1.0).normalized(), deg_to_rad(12.0))
	var driver: PhysicsCallDriver = PhysicsCallDriver.new()
	driver.callable = Callable(_field, "apply_replicated_pose").bind(Vector3.ZERO, tilt)
	add_child_autofree(driver)
	await wait_physics_frames(2)
	assert_almost_eq(_field.global_basis.get_rotation_quaternion().angle_to(tilt), 0.0, 0.01, "the field tilted")
	var local_after: Transform3D = _field.global_transform.affine_inverse() * structure.global_transform
	assert_true(local_before.is_equal_approx(local_after), "structure keeps its pose in the field frame")
	assert_gt(structure.global_basis.y.angle_to(Vector3.UP), 0.1, "structure axis tilted with the disc")
	assert_almost_eq(structure.apex_world().distance_to(structure.global_position), _effect.height_m, 0.001)


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


## a 3-block burst launches along distinct directions at jittered speeds, spawns
## apart, and the blocks stay more than one cube width apart through the first half second.
const MIN_VELOCITY_DIFF_MPS: float = 2.0
const SEPARATION_FRAMES: int = 30


func _burst_blocks(structure: VolcanoStructure, burst_size: int) -> Array[Block]:
	var found: Array[Block] = []
	for _i: int in range(int(ceil(_effect.eruption_interval_max_s / TICK)) + 2):
		structure.tick(TICK)
		if _blocks.get_child_count() >= burst_size:
			break
	for child: Node in _blocks.get_children():
		if child is Block:
			found.append(child as Block)
	return found


func test_burst_blocks_launch_apart_and_stay_separated() -> void:
	_start()
	_effect.min_blocks_per_burst = 3
	_effect.max_blocks_per_burst = 3
	_effect.eruption_interval_min_s = 0.05
	_effect.eruption_interval_max_s = 0.05
	var structure: VolcanoStructure = _manual(VolcanoStructure.spawn_host(_effect, _origin(), 1))
	_step(structure, _effect.rise_s)
	var burst: Array[Block] = _burst_blocks(structure, 3)
	assert_gte(burst.size(), 3, "a full burst spawned")
	var cube: float = (preload("res://config/physics/physics_tuning.tres") as PhysicsTuning).cube_size
	for a: int in range(3):
		for b: int in range(a + 1, 3):
			var dv: float = (burst[a].linear_velocity - burst[b].linear_velocity).length()
			assert_gt(dv, MIN_VELOCITY_DIFF_MPS, "blocks %d/%d leave at clearly different velocities" % [a, b])
			assert_gt(burst[a].global_position.distance_to(burst[b].global_position), cube, "spawned apart")
	for _f: int in range(SEPARATION_FRAMES):
		await wait_physics_frames(1)
	var min_gap: float = INF
	for a: int in range(3):
		for b: int in range(a + 1, 3):
			min_gap = minf(min_gap, burst[a].global_position.distance_to(burst[b].global_position))
	assert_gt(min_gap, cube, "no two ejected blocks are within one cube width after 0.5 s (%.2f m)" % min_gap)


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


func _mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_mesh_instances(child, out)


func test_orb_leftovers_are_gone() -> void:
	for property: Dictionary in _effect.get_property_list():
		assert_ne(String(property["name"]), "orb_blast")
