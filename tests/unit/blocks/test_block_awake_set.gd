extends GutTest
## the shared awake set (Block.awake_blocks()) and its
## consumers: BlockRegistry's settle loop, BlockEffectsManager's trail scan and
## the per-tick BlockStepBatch pass (was Block's own callback).

const TICK: float = 1.0 / 60.0
const SLEEP_WAIT_FRAMES: int = 60

var _tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")


func before_each() -> void:
	Block.clear_awake_set_for_tests()


func _block() -> Block:
	var block: Block = Block.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	block.add_child(collision)
	block.gravity_scale = 0.0
	add_child_autofree(block)
	return block


func _frozen_block(parent: Node) -> Block:
	var block: Block = Block.new()
	block.freeze = true
	block.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	parent.add_child(block)
	return block


func test_awake_set_tracks_enter_sleep_wake_freeze_and_remove() -> void:
	var block: Block = _block()
	assert_true(Block.is_awake_registered(block), "a block entering the tree starts awake")
	# no per-node tick callback; BlockStepBatch visits the set.
	assert_false(block.is_physics_processing(), "no per-node physics callback")

	# Zero gravity and no velocity: Jolt puts it to sleep by itself.
	block.sleeping = true
	await wait_physics_frames(SLEEP_WAIT_FRAMES)
	assert_false(Block.is_awake_registered(block), "sleeping_state_changed removes it")

	block.wake()
	await wait_physics_frames(3)
	assert_true(Block.is_awake_registered(block), "waking re-adds it")
	assert_false(block.is_physics_processing(), "still no per-node physics callback")

	await wait_physics_frames(SLEEP_WAIT_FRAMES)
	assert_false(Block.is_awake_registered(block), "a script-woken body that falls asleep again leaves the set")
	block.wake()
	block.request_freeze_static(Block.FREEZE_REASON_STABLE)
	assert_false(Block.is_awake_registered(block), "a statically frozen block leaves the set")
	block.release_freeze_static(Block.FREEZE_REASON_STABLE)
	assert_true(Block.is_awake_registered(block), "unfreezing re-adds it")

	var id: int = block.get_instance_id()
	block.get_parent().remove_child(block)
	for other: Block in Block.awake_blocks():
		assert_ne(other.get_instance_id(), id, "a block out of the tree is gone from the set")
	block.free()


## Scripted scene: frozen (kinematic) blocks whose velocities are written per
## tick, some "sleeping" via the awake set. The registry result must equal a
## full scan with the old per-entry rule.
func test_registry_settle_and_revision_match_a_full_scan() -> void:
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	registry.set_physics_process(false)
	var host: Node3D = Node3D.new()
	add_child_autofree(host)
	var blocks: Array[Block] = []
	var settled_log: Array[int] = []
	registry.block_settled.connect(func(slot: int, _h: float) -> void: settled_log.append(slot))
	var count: int = 10
	for i: int in range(count):
		var block: Block = _frozen_block(host)
		block.owner_slot = i
		blocks.append(block)
		Events.block_placed.emit(block, &"cube")

	var oracle_time: Array[float] = []
	var oracle_settled: Array[bool] = []
	var oracle_log: Array[int] = []
	for i: int in range(count):
		oracle_time.append(0.0)
		oracle_settled.append(false)
	var oracle_revision: int = count  # one bump per placement
	var start_revision: int = registry.territory_revision() - count
	var lin_sq: float = _tuning.sleep_linear_threshold * _tuning.sleep_linear_threshold
	var ang_sq: float = _tuning.sleep_angular_threshold * _tuning.sleep_angular_threshold

	for tick: int in range(120):
		for i: int in range(count):
			var block: Block = blocks[i]
			var asleep: bool = false
			var speed: float = 0.0
			match i % 5:
				0:
					speed = 0.0  # settles early, sleeps after settling
					asleep = tick >= 45
				1:
					speed = 0.0  # sleeps BEFORE settle time has elapsed
					asleep = tick >= 5
				2:
					speed = 1.0 if tick < 70 else 0.0  # moving, then rests
					asleep = tick >= 100
				3:
					speed = 1.0 if (tick % 40) < 20 else 0.0  # keeps resetting
					asleep = false
				4:
					speed = 0.05 if tick < 60 else 0.0  # slow but awake: counts as settled
					asleep = tick >= 90
			if asleep:
				speed = 0.0
			block.linear_velocity = Vector3(speed, 0.0, 0.0)
			block._apply_awake(not asleep)
			var below: bool = (block.linear_velocity.length_squared() < lin_sq
				and block.angular_velocity.length_squared() < ang_sq)
			if below:
				oracle_time[i] += TICK
			else:
				oracle_time[i] = 0.0
			var now_settled: bool = oracle_time[i] >= _tuning.sleep_settle_time
			if now_settled != oracle_settled[i]:
				oracle_revision += 1
				if now_settled:
					oracle_log.append(i)
				oracle_settled[i] = now_settled
		registry._physics_process(TICK)
		for i: int in range(count):
			var entry: Variant = registry._entries[blocks[i].get_instance_id()]
			assert_eq(entry.is_settled, oracle_settled[i], "tick %d block %d settled flag" % [tick, i])
	assert_eq(registry.territory_revision() - start_revision, oracle_revision, "revision bumps match")
	settled_log.sort()
	oracle_log.sort()
	assert_eq(settled_log, oracle_log, "block_settled emitted for the same blocks, once per transition")
	assert_true(oracle_log.size() > 0, "fixture settles something")
	Events.block_removed.emit(blocks[0], "test")


## Real Jolt: which mechanisms wake a sleeping Block and raise
## sleeping_state_changed (so it re-enters the awake set without Block.wake()).
func _sleeping_block() -> Block:
	var block: Block = _block()
	block.sleeping = true
	await wait_physics_frames(SLEEP_WAIT_FRAMES)
	assert_false(Block.is_awake_registered(block), "fixture: asleep and out of the set")
	return block


func test_central_impulse_wakes_sleeping_block() -> void:
	var block: Block = await _sleeping_block()
	block.apply_central_impulse(Vector3(0.0, 5.0, 0.0))
	await wait_physics_frames(3)
	assert_false(block.sleeping, "engine woke the body")
	assert_true(Block.is_awake_registered(block), "central impulse: signal re-adds to set")


func test_linear_velocity_assignment_wakes_sleeping_block() -> void:
	var block: Block = await _sleeping_block()
	block.linear_velocity = Vector3(0.0, 5.0, 0.0)
	await wait_physics_frames(3)
	assert_false(block.sleeping)
	assert_true(Block.is_awake_registered(block), "velocity write: signal re-adds to set")
