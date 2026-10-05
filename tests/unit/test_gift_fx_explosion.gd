extends GutTest
## ExplosionFx.blast (docs/GIFT_EFFECTS_PLAN.md section 2/5 A1): mass-independent
## delta-v, distance falloff, radius cutoff, STATIC-frozen STABLE block is woken.
## Real Blocks on a real (flat, resting) Field.

const SETTLE_FRAMES: int = 20
const MIN_NEAR_DELTA_V: float = 4.0
const NEAR_DISTANCE_M: float = 2.0
const FAR_DISTANCE_M: float = 3.5
const OUTSIDE_DISTANCE_M: float = 7.0

var _field: Field
var _root: Node3D


func before_each() -> void:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_fx_explosion"
	map_def.field_radius = 14.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	_field = Field.new()
	_field.map_def = map_def
	add_child_autofree(_field)
	_root = Node3D.new()
	add_child_autofree(_root)


func _block(shape_id: String, at: Vector3) -> Block:
	var shape: BlockShape = load("res://config/blocks/%s.tres" % shape_id)
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var block: Block = BlockFactory.build(shape, tuning, 0)
	_root.add_child(block)
	block.global_position = at
	return block


func _tuning() -> ExplosionTuning:
	return ExplosionTuning.new()


func _space() -> PhysicsDirectSpaceState3D:
	return _field.get_world_3d().direct_space_state


func _above_surface() -> float:
	return _field.surface_y() + 1.5


## Horizontal velocity change caused by one blast (gravity-free), per block, after letting the blocks settle.
func _blast_and_measure(blocks: Array[Block], center: Vector3) -> Array[float]:
	await wait_physics_frames(SETTLE_FRAMES)
	var before: Array[Vector3] = []
	for b: Block in blocks:
		before.append(b.linear_velocity)
	ExplosionFx.blast(_space(), center, _tuning(), [])
	# Jolt applies the queued impulse on the next step.
	await wait_physics_frames(1)
	var out: Array[float] = []
	for i: int in blocks.size():
		var gain: Vector3 = blocks[i].linear_velocity - before[i]
		out.append(Vector2(gain.x, gain.z).length())
	return out


func test_light_and_heavy_blocks_gain_the_same_delta_v() -> void:
	var y: float = _above_surface()
	var center: Vector3 = Vector3(0.0, y, 0.0)
	var cube: Block = _block("cube", Vector3(NEAR_DISTANCE_M, y, 0.0))
	var heavy: Block = _block("L4", Vector3(-NEAR_DISTANCE_M, y, 0.0))
	assert_gt(heavy.mass, cube.mass * 2.0, "fixture: the tetromino is much heavier")
	var gains: Array[float] = await _blast_and_measure([cube, heavy], center)
	assert_gte(gains[0], MIN_NEAR_DELTA_V, "cube gains at least 4 m/s")
	assert_gte(gains[1], MIN_NEAR_DELTA_V, "8 kg block gains at least 4 m/s")
	assert_almost_eq(gains[0], gains[1], 0.5, "delta-v is mass independent")


func test_farther_body_gains_less() -> void:
	var y: float = _above_surface()
	var near: Block = _block("cube", Vector3(NEAR_DISTANCE_M, y, 0.0))
	var far: Block = _block("cube", Vector3(0.0, y, FAR_DISTANCE_M))
	var gains: Array[float] = await _blast_and_measure([near, far], Vector3(0.0, y, 0.0))
	assert_gt(gains[1], 0.0, "far body inside the radius still gets pushed")
	assert_lt(gains[1], gains[0], "falloff: farther body gains less")


func test_delta_v_is_clamped() -> void:
	var y: float = _above_surface()
	var block: Block = _block("cube", Vector3(0.0, y, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	var t: ExplosionTuning = _tuning()
	t.peak_speed_mps = 100.0
	var before: Vector3 = block.linear_velocity
	ExplosionFx.blast(_space(), Vector3(0.0, y - 0.2, 0.0), t, [])
	assert_lte((block.linear_velocity - before).length(), t.max_delta_v_mps + 0.01, "clamped to max_delta_v_mps")


func test_body_outside_radius_is_untouched() -> void:
	var y: float = _above_surface()
	var block: Block = _block("cube", Vector3(OUTSIDE_DISTANCE_M, y, 0.0))
	var gains: Array[float] = await _blast_and_measure([block], Vector3(0.0, y, 0.0))
	assert_almost_eq(gains[0], 0.0, 0.001, "outside radius: no delta-v")


func test_excluded_body_is_untouched() -> void:
	var y: float = _above_surface()
	var block: Block = _block("cube", Vector3(NEAR_DISTANCE_M, y, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	var before: Vector3 = block.linear_velocity
	var exclude: Array[RID] = [block.get_rid()]
	var hit: Array[RigidBody3D] = ExplosionFx.blast(_space(), Vector3(0.0, y, 0.0), _tuning(), exclude)
	assert_eq(hit.size(), 0)
	assert_eq(block.linear_velocity, before)


func test_static_frozen_stable_block_is_woken_and_pushed() -> void:
	var y: float = _above_surface()
	var block: Block = _block("cube", Vector3(NEAR_DISTANCE_M, y, 0.0))
	await wait_physics_frames(SETTLE_FRAMES)
	block.request_freeze_static(Block.FREEZE_REASON_STABLE)
	assert_true(block.is_freeze_static(), "fixture: block is STATIC-frozen")
	var hit: Array[RigidBody3D] = ExplosionFx.blast(_space(), Vector3(0.0, y, 0.0), _tuning(), [])
	assert_true(hit.has(block), "frozen block is found")
	assert_false(block.is_freeze_static(), "STABLE freeze released")
	assert_gte(block.linear_velocity.length(), MIN_NEAR_DELTA_V, "and it was pushed")
