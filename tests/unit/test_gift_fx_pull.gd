extends GutTest
## RadialPull.pull (docs/GIFT_EFFECTS_PLAN.md section 5 A1): a block resting on a
## friction surface moves under the pull, filter respected, on_captured once.

const FRAMES_PER_SECOND: int = 60
const START_DISTANCE_M: float = 6.0
const MIN_MOVE_M: float = 1.0
const SETTLE_FRAMES: int = 20

var _field: Field
var _root: Node3D
var _captured: Array[RigidBody3D] = []


func before_each() -> void:
	_captured.clear()
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_fx_pull"
	map_def.field_radius = 14.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	_field = Field.new()
	_field.map_def = map_def
	add_child_autofree(_field)
	_root = Node3D.new()
	add_child_autofree(_root)


func _block(shape_id: String, at: Vector3, slot: int = 1) -> Block:
	var shape: BlockShape = load("res://config/blocks/%s.tres" % shape_id)
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var block: Block = BlockFactory.build(shape, tuning, slot)
	_root.add_child(block)
	block.global_position = at
	return block


func _rest_y() -> float:
	return _field.surface_y() + 0.6


func _space() -> PhysicsDirectSpaceState3D:
	return _field.get_world_3d().direct_space_state


func _on_captured(body: RigidBody3D) -> void:
	_captured.append(body)


func _run_pull(filter: Callable, seconds: float, on_captured: Callable = Callable()) -> void:
	var center: Vector3 = Vector3(0.0, _rest_y(), 0.0)
	var t: RadialPullTuning = RadialPullTuning.new()
	var delta: float = 1.0 / FRAMES_PER_SECOND
	for _i: int in int(seconds * FRAMES_PER_SECOND):
		RadialPull.pull(_space(), center, t, [], filter, delta, on_captured)
		await wait_physics_frames(1)


func test_resting_block_moves_at_least_one_metre_in_one_second() -> void:
	var block: Block = _block("cube", Vector3(START_DISTANCE_M, _rest_y(), 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	var start: Vector3 = block.global_position
	await _run_pull(Callable(), 1.0)
	var moved: float = Vector2(block.global_position.x - start.x, block.global_position.z - start.z).length()
	assert_gte(moved, MIN_MOVE_M, "moved %.2f m toward the centre" % moved)
	assert_lt(block.global_position.x, start.x, "moved toward the centre")


func test_heavy_block_also_moves() -> void:
	var block: Block = _block("L4", Vector3(START_DISTANCE_M, _rest_y(), 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	var start_x: float = block.global_position.x
	await _run_pull(Callable(), 1.0)
	assert_gte(start_x - block.global_position.x, MIN_MOVE_M, "mass-proportional pull moves 8 kg too")


func test_filter_skips_own_owner() -> void:
	var own: Block = _block("cube", Vector3(START_DISTANCE_M, _rest_y(), 0.0), 0)
	var enemy: Block = _block("cube", Vector3(-START_DISTANCE_M, _rest_y(), 0.0), 1)
	await wait_physics_frames(SETTLE_FRAMES)
	var own_x: float = own.global_position.x
	var enemy_x: float = enemy.global_position.x
	var filter: Callable = func(body: RigidBody3D) -> bool: return (body as Block).owner_slot != 0
	await _run_pull(filter, 1.0)
	assert_almost_eq(own.global_position.x, own_x, 0.05, "own block ignored")
	assert_gt(enemy.global_position.x, enemy_x + MIN_MOVE_M, "enemy block pulled")


func test_on_captured_fires_once_per_body() -> void:
	var block: Block = _block("cube", Vector3(1.5, _rest_y(), 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	await _run_pull(Callable(), 2.0, Callable(self, "_on_captured"))
	assert_eq(_captured.size(), 1, "captured exactly once")
	if _captured.size() == 1:
		assert_eq(_captured[0], block)


func test_no_capture_callback_means_no_capture_state() -> void:
	var block: Block = _block("cube", Vector3(1.5, _rest_y(), 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	await _run_pull(Callable(), 1.0)
	assert_false(block.has_meta(RadialPull.CAPTURED_META), "Magnet-style call leaves no capture flag")
