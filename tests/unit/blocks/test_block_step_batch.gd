extends GutTest
## game/blocks/BlockStepBatch.gd: one batched pass per physics tick over the awake
## blocks (rebound damping, kick pass-through, impact detection), plus the
## one-shot release tilt that stays a per-body engine callback in Block.
## Real Block bodies in the live physics world, the same shape as
## test_block_rebound_physics.gd.

const CUBE_SHAPE_PATH: String = "res://config/blocks/cube.tres"
## Ticks a freshly added block needs before Jolt syncs it every tick.
const SETTLE_TICKS: int = 3
const FLOOR_SIZE_M: float = 30.0
const HIGH_DROP_M: float = 6.0
## Well inside one cube edge (the tilt's minimum release gap), so the gate keeps
## a nearly landed block untouched.
const LOW_DROP_M: float = 0.05
const SIDE_OFFSET_M: float = 6.0
const TILT_DEGREES: float = 2.0
const TILT_TOLERANCE_DEG: float = 0.1
## The tilt lands at the block's first state sync, then plain free fall keeps
## it; poll only a few ticks, before a landing can rock the cube flat.
const TILT_WATCH_TICKS: int = 6
const TILT_SEEN_DEG: float = 0.5

var _tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
var _nodes: Array[Node3D] = []


## Synchronous free() so no stale collider reaches the next test.
func after_each() -> void:
	for node: Node3D in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


func _cube(tuning: PhysicsTuning, at: Vector3) -> Block:
	var block: Block = BlockFactory.build(load(CUBE_SHAPE_PATH), tuning)
	add_child(block)
	block.global_position = at
	_nodes.append(block)
	return block


func _floor() -> void:
	var floor_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(FLOOR_SIZE_M, 1.0, FLOOR_SIZE_M)
	collision.shape = box
	floor_body.add_child(collision)
	add_child(floor_body)  # before global_position: Node3D needs is_inside_tree() to resolve it
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)
	_nodes.append(floor_body)


func _tilt_degrees(block: Block) -> float:
	return rad_to_deg(block.global_basis.y.angle_to(Vector3.UP))


## The hook runs after every body's state sync of the tick and before any other
## script reads or writes a block, so it must be the first physics_frame
## listener even though GUT's awaiter (and anything else) connected earlier.
func test_batch_hook_is_the_first_physics_frame_listener() -> void:
	_cube(_tuning, Vector3(0.0, HIGH_DROP_M, 0.0))
	await wait_physics_frames(SETTLE_TICKS)
	assert_not_null(BlockStepBatch._instance, "fixture: the first block entering the tree installs the hook")
	var connections: Array = get_tree().physics_frame.get_connections()
	assert_gt(connections.size(), 1, "fixture: GUT's awaiter listens too")
	var first: Callable = (connections[0] as Dictionary)["callable"]
	assert_eq(first.get_object(), BlockStepBatch._instance, "the batch runs before every other physics_frame listener")


## A kick marked after a tick's pass (a special's own write in _physics_process)
## or during that tick's sync phase is only due from the next tick: a pass in
## the same frame must leave it pending, and the next frame's pass consumes it.
func test_kick_marked_this_frame_is_consumed_by_the_next_frames_pass() -> void:
	var block: Block = _cube(_tuning, Vector3(0.0, HIGH_DROP_M, 0.0))
	await wait_physics_frames(SETTLE_TICKS)
	assert_not_null(BlockStepBatch._instance, "fixture: the hook is installed")

	block.mark_script_kick()
	assert_true(block._script_kick_pending, "fixture: the mark is pending")
	BlockStepBatch._instance._on_physics_frame()
	assert_true(block._script_kick_pending, "a pass in the frame of the mark does not consume it")

	await wait_physics_frames(1)
	assert_false(block._script_kick_pending, "the next frame's pass consumes it")


## Block._apply_release_tilt(): with release_tilt_degrees set, a block released
## well above the floor is tilted once at its first state sync; with the
## setting off, or a release inside the minimum gap, it is left exactly level.
func test_release_tilt_applies_only_above_the_minimum_gap_and_only_when_enabled() -> void:
	_floor()
	var tilt_tuning: PhysicsTuning = _tuning.duplicate() as PhysicsTuning
	tilt_tuning.release_tilt_degrees = TILT_DEGREES
	var level_tuning: PhysicsTuning = _tuning.duplicate() as PhysicsTuning
	level_tuning.release_tilt_degrees = 0.0
	var tilted: Block = _cube(tilt_tuning, Vector3(-SIDE_OFFSET_M, HIGH_DROP_M, 0.0))
	var disabled: Block = _cube(level_tuning, Vector3(0.0, HIGH_DROP_M, 0.0))
	var low: Block = _cube(tilt_tuning, Vector3(SIDE_OFFSET_M, LOW_DROP_M, 0.0))

	var ticks: int = 0
	while ticks < TILT_WATCH_TICKS and _tilt_degrees(tilted) < TILT_SEEN_DEG:
		await wait_physics_frames(1)
		ticks += 1

	assert_almost_eq(_tilt_degrees(tilted), TILT_DEGREES, TILT_TOLERANCE_DEG, "released high with the setting on: tilted by it")
	assert_almost_eq(_tilt_degrees(disabled), 0.0, TILT_TOLERANCE_DEG, "release_tilt_degrees 0: no tilt")
	assert_almost_eq(_tilt_degrees(low), 0.0, TILT_TOLERANCE_DEG, "released inside the minimum gap: no tilt")
