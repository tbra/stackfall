extends GutTest
## game/StableBlockManager.gd (spec 3.5 "Stable-block optimization" [NEW],
## docs/M8_PLAN.md P5): a block asleep past PhysicsTuning.stable_freeze_delay_s
## gets frozen static; waking releases it; below the threshold it's left
## alone. Drives the manager deterministically through its own _tick(delta)
## seam (see that function's own doc comment) instead of waiting real seconds
## or real physics frames -- Net.is_host()/_physics_process() are never
## exercised here, only _tick()/_scan() themselves, the same "test the pure
## seam directly" approach test_physics_tuning.gd already uses for
## Block._damp_rebound().

var _tuning: PhysicsTuning = load("res://config/physics_tuning.tres")

## Bontago-mv0.3's own DECISION (tests/unit/test_block_registry.gd): a
## shrunk-radius duplicate of round_medium.tres, not the shared resource
## itself, so this fixture doesn't pay round_medium's own ~11 s field-build
## cost per test.
var _map_def: MapDef


func before_each() -> void:
	_map_def = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_map_def.field_radius = 20.0


func _make_field() -> Field:
	var field: Field = autofree(Field.new())
	field.map_def = _map_def
	add_child_autofree(field)
	return field


func _make_registry(field: Field) -> BlockRegistry:
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	registry.configure(field, _map_def)
	return registry


func _make_manager(registry: BlockRegistry) -> StableBlockManager:
	var manager: StableBlockManager = autofree(StableBlockManager.new())
	manager.tuning = _tuning
	add_child_autofree(manager)
	manager.setup(registry)
	return manager


func _place(field: Field, slot: int) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, _tuning, slot)
	field.add_child(block)
	Events.block_placed.emit(block, shape.id)
	return block


func test_block_asleep_past_the_delay_gets_frozen_static() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)

	var block: Block = _place(field, 0)
	block.sleeping = true

	# One _tick() call whose delta alone crosses both the scan interval and
	# the freeze delay -- see StableBlockManager._tick()'s own doc comment for
	# why a single call this large is equivalent to many smaller real ticks.
	manager._tick(_tuning.stable_freeze_delay_s + 1.0)

	assert_true(block.is_freeze_static(), "asleep past the delay is frozen static")
	assert_true(block.freeze)
	assert_eq(block.freeze_mode, RigidBody3D.FREEZE_MODE_STATIC)


func test_block_asleep_below_the_delay_is_left_untouched() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)

	var block: Block = _place(field, 0)
	block.sleeping = true

	manager._tick(_tuning.stable_freeze_delay_s - 1.0)

	assert_false(block.is_freeze_static(), "asleep, but not yet past the delay")
	assert_false(block.freeze)


func test_waking_a_frozen_block_releases_it() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)

	var block: Block = _place(field, 0)
	block.sleeping = true
	manager._tick(_tuning.stable_freeze_delay_s + 1.0)
	assert_true(block.is_freeze_static(), "sanity check: frozen first")

	block.sleeping = false
	manager._tick(_tuning.stable_freeze_scan_interval_s)

	assert_false(block.is_freeze_static(), "waking releases this manager's own reason")
	assert_false(block.freeze)
	assert_eq(
		block.freeze_mode,
		RigidBody3D.FREEZE_MODE_STATIC,
		"freeze_mode is left at STATIC after release -- it's inert once freeze is false, nothing resets it"
	)


func test_reaching_the_delay_across_several_ticks_still_freezes() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)

	var block: Block = _place(field, 0)
	block.sleeping = true

	# Several scans below the interval accumulate without ever running a scan
	# pass; once accumulated time crosses the interval, a scan runs and its
	# elapsed span is credited to the sleeping block. Repeating this until the
	# cumulative asleep time crosses stable_freeze_delay_s must still freeze
	# it, the same as one big _tick() call.
	var half_interval: float = _tuning.stable_freeze_scan_interval_s * 0.5
	var elapsed: float = 0.0
	while elapsed < _tuning.stable_freeze_delay_s + _tuning.stable_freeze_scan_interval_s:
		manager._tick(half_interval)
		elapsed += half_interval

	assert_true(block.is_freeze_static(), "accumulated asleep time across many small ticks still freezes")


func test_a_second_block_that_wakes_before_the_scan_interval_elapses_is_never_credited() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)

	var block: Block = _place(field, 0)
	block.sleeping = true

	# Below the scan interval: no scan pass has run yet, so nothing is
	# credited or released either way.
	manager._tick(_tuning.stable_freeze_scan_interval_s * 0.5)
	assert_false(block.is_freeze_static())

	block.sleeping = false
	manager._tick(_tuning.stable_freeze_scan_interval_s)
	assert_false(block.is_freeze_static(), "never asleep long enough to be frozen in the first place")


func test_tilting_field_releases_frozen_blocks_and_restarts_the_timer() -> void:
	# Bontago-sen.11: a frozen-static block does not ride a moving disc.
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)
	manager.check_field_motion()

	var block: Block = _place(field, 0)
	block.sleeping = true
	manager._tick(_tuning.stable_freeze_delay_s + 1.0)
	assert_true(block.is_freeze_static(), "sanity check: frozen first")

	field.transform = Transform3D(Basis(Vector3.RIGHT, 0.05), field.transform.origin)
	manager.check_field_motion()

	assert_false(block.is_freeze_static(), "disc motion releases the stable freeze")
	assert_false(block.freeze)
	assert_false(block.sleeping, "released block is awake so it rides the disc")

	block.sleeping = true
	manager._tick(_tuning.stable_freeze_delay_s - 1.0)
	assert_false(block.is_freeze_static(), "timer restarted; still inside the delay")
	manager.check_field_motion()
	manager._tick(2.0)
	assert_true(block.is_freeze_static(), "disc still: re-freezes after the normal delay")


func test_a_wake_that_does_not_move_the_block_keeps_its_freeze_timer() -> void:
	# Bontago-1pi.11.24: Jolt wakes a whole contact island on any landing; a
	# block that did not move must not lose its accumulated rest time.
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)
	var block: Block = _place(field, 0)
	block.sleeping = true
	manager._tick(_tuning.stable_freeze_delay_s - 2.0)
	block.sleeping = false
	manager._tick(_tuning.stable_freeze_scan_interval_s)
	assert_false(block.is_freeze_static(), "awake: never frozen while awake")
	block.sleeping = true
	manager._tick(3.0)
	assert_true(block.is_freeze_static(), "cumulative rest time across a still wake freezes it")


func test_a_wake_that_moves_the_block_restarts_its_freeze_timer() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)
	var block: Block = _place(field, 0)
	block.sleeping = true
	manager._tick(_tuning.stable_freeze_delay_s - 2.0)
	block.sleeping = false
	block.global_position += Vector3(_tuning.stable_freeze_rest_epsilon_m * 4.0, 0.0, 0.0)
	manager._tick(_tuning.stable_freeze_scan_interval_s)
	block.sleeping = true
	manager._tick(3.0)
	assert_false(block.is_freeze_static(), "moved beyond the epsilon: timer restarted")
	manager._tick(_tuning.stable_freeze_delay_s)
	assert_true(block.is_freeze_static(), "re-freezes after a full delay at the new pose")


func test_real_physics_island_wakes_still_freeze_and_a_tilt_carries_the_released_pile() -> void:
	# Real frames: a 3-cube tower (one Jolt island) is woken every 0.75 s, so it
	# never sleeps a whole delay in a row, yet still freezes; a tilt impulse
	# then releases every frozen block and the base rides the disc (sen.11).
	var tuning: PhysicsTuning = _tuning.duplicate() as PhysicsTuning
	tuning.stable_freeze_delay_s = 1.5
	tuning.stable_freeze_scan_interval_s = 0.25
	var field: Field = _make_field()
	field.set_tilt_enabled(true)
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = autofree(StableBlockManager.new())
	manager.tuning = tuning
	add_child_autofree(manager)
	manager.setup(registry)
	var blocks: Array[Block] = []
	for i: int in range(3):
		var block: Block = _place(field, 0)
		block.global_position = Vector3(0.5, field.surface_y() + 0.5 + 1.0 * float(i), 0.5)
		blocks.append(block)
	var frozen_all: bool = false
	for f: int in range(60 * 12):
		await wait_physics_frames(1)
		if f % 45 == 0:
			blocks[2].sleeping = false
		frozen_all = true
		for block: Block in blocks:
			frozen_all = frozen_all and block.freeze
		if frozen_all:
			break
	assert_true(frozen_all, "the periodically woken tower still froze")
	var before_y: float = field.to_local(blocks[0].global_position).y
	field.apply_tilt_impulse(Vector2(0.0, 1.0), 0.04)
	await wait_physics_frames(30)
	for block: Block in blocks:
		assert_false(block.freeze, "a tilting disc released every frozen block")
	var after_y: float = field.to_local(blocks[0].global_position).y
	assert_almost_eq(after_y, before_y, 0.1, "the base block rode the disc, no clipping")


# --- Settle freeze (Bontago-e7o B): awake-but-still blocks ----------------------

func _awake_still_setup() -> Array:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)
	var block: Block = _place(field, 0)
	block.sleeping = false
	return [manager, block]


func test_awake_but_still_block_freezes_after_the_window() -> void:
	var parts: Array = _awake_still_setup()
	var manager: StableBlockManager = parts[0]
	var block: Block = parts[1]
	manager._tick(_tuning.stable_freeze_scan_interval_s)
	manager._tick(_tuning.settle_freeze_window_s - 1.0)
	assert_false(block.is_freeze_static(), "below the window: not frozen")
	manager._tick(2.0)
	assert_true(block.is_freeze_static(), "still for the whole window: frozen")
	assert_true(manager.is_stable_frozen(block))


func test_awake_block_that_moves_restarts_the_settle_window() -> void:
	var parts: Array = _awake_still_setup()
	var manager: StableBlockManager = parts[0]
	var block: Block = parts[1]
	manager._tick(_tuning.stable_freeze_scan_interval_s)
	manager._tick(_tuning.settle_freeze_window_s - 1.0)
	block.global_position += Vector3(_tuning.settle_freeze_move_epsilon_m * 4.0, 0.0, 0.0)
	manager._tick(2.0)
	assert_false(block.is_freeze_static(), "moved past the epsilon: window restarted")


func test_settle_freeze_off_leaves_awake_blocks_alone() -> void:
	var parts: Array = _awake_still_setup()
	var manager: StableBlockManager = parts[0]
	var block: Block = parts[1]
	var tuning: PhysicsTuning = _tuning.duplicate() as PhysicsTuning
	tuning.settle_freeze_enabled = false
	manager.tuning = tuning
	manager._tick(_tuning.stable_freeze_scan_interval_s)
	manager._tick(_tuning.settle_freeze_window_s + 5.0)
	assert_false(block.is_freeze_static())


func test_fast_neighbour_holds_back_a_still_block() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)
	var still: Block = _place(field, 0)
	var runner: Block = _place(field, 1)
	still.sleeping = false
	runner.sleeping = false
	runner.global_position = still.global_position + Vector3(1.0, 0.0, 0.0)
	runner.linear_velocity = Vector3(0.0, 0.0, _tuning.settle_freeze_fast_speed_mps * 4.0)
	manager._tick(_tuning.stable_freeze_scan_interval_s)
	manager._tick(_tuning.settle_freeze_window_s + 1.0)
	assert_false(still.is_freeze_static(), "a fast block next to it keeps it unfrozen")
	runner.linear_velocity = Vector3.ZERO
	manager._tick(_tuning.stable_freeze_scan_interval_s)
	assert_true(still.is_freeze_static(), "frozen on the first scan after the neighbour slows")


func test_settle_frozen_block_releases_on_field_motion() -> void:
	var parts: Array = _awake_still_setup()
	var manager: StableBlockManager = parts[0]
	var block: Block = parts[1]
	manager._tick(_tuning.stable_freeze_scan_interval_s)
	manager._tick(_tuning.settle_freeze_window_s + 1.0)
	assert_true(block.is_freeze_static())
	assert_true(manager.wake_for_external_force(block), "the existing release path applies")
	assert_false(block.is_freeze_static())


func test_catchup_cap_toggle_sets_engine_steps_live() -> void:
	var parts: Array = _awake_still_setup()
	var manager: StableBlockManager = parts[0]
	var tuning: PhysicsTuning = _tuning.duplicate() as PhysicsTuning
	manager.tuning = tuning
	var original: int = Engine.max_physics_steps_per_frame
	tuning.catchup_cap_enabled = false
	manager.apply_catchup_cap()
	assert_eq(Engine.max_physics_steps_per_frame, tuning.catchup_steps_default)
	tuning.catchup_cap_enabled = true
	manager.apply_catchup_cap()
	assert_eq(Engine.max_physics_steps_per_frame, tuning.catchup_steps_capped)
	Engine.max_physics_steps_per_frame = original


func _real_never_sleeping_pile(settle_enabled: bool) -> Array[Block]:
	# Real Jolt frames, can_sleep = false: the engine never sleeps these awake-but-
	# still blocks, the case only the settle freeze can reach.
	var tuning: PhysicsTuning = _tuning.duplicate() as PhysicsTuning
	tuning.settle_freeze_window_s = 1.5
	tuning.settle_freeze_enabled = settle_enabled
	tuning.stable_freeze_scan_interval_s = 0.25
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = autofree(StableBlockManager.new())
	manager.tuning = tuning
	add_child_autofree(manager)
	manager.setup(registry)
	var blocks: Array[Block] = []
	for i: int in range(3):
		var block: Block = _place(field, 0)
		block.can_sleep = false
		block.global_position = Vector3(0.5, field.surface_y() + 0.5 + 1.0 * float(i), 0.5)
		blocks.append(block)
	return blocks


func test_real_physics_never_sleeping_pile_freezes_through_the_settle_path() -> void:
	var blocks: Array[Block] = _real_never_sleeping_pile(true)
	var frozen_all: bool = false
	for f: int in range(60 * 10):
		await wait_physics_frames(1)
		frozen_all = true
		for block: Block in blocks:
			frozen_all = frozen_all and block.freeze
		if frozen_all:
			break
	assert_true(frozen_all, "awake-but-still tower froze once its window passed")
	# Keep scanning well past the freeze: it must hold, not flap.
	await wait_physics_frames(60 * 4)
	for block: Block in blocks:
		assert_true(block.freeze, "stays frozen across further scans")


func test_real_physics_never_sleeping_pile_stays_awake_with_settle_off() -> void:
	var blocks: Array[Block] = _real_never_sleeping_pile(false)
	await wait_physics_frames(60 * 5)
	for block: Block in blocks:
		assert_false(block.freeze, "settle freeze off: the engine never sleeps it, so it never freezes")


func test_blocks_removed_while_awake_do_not_leak_settle_entries() -> void:
	var parts: Array = _awake_still_setup()
	var manager: StableBlockManager = parts[0]
	var block: Block = parts[1]
	manager._tick(_tuning.stable_freeze_scan_interval_s)
	assert_eq(manager._settle.tracked_count(), 1)
	Events.block_removed.emit(block, "test")
	block.free()
	manager._tick(_tuning.stable_freeze_scan_interval_s)
	assert_eq(manager._settle.tracked_count(), 0, "pruned with the removed block")
