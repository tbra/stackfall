extends GutTest
## M7 P4, spec 1.10 "effects + camera shake":
## game/blocks/BlockEffectsManager.gd's one-shot kill-plane burst and landing-dust/
## impact burst. Events.block_removed and Events.block_impacted_at are both
## global Events autoload signals, so this test connects a real
## BlockEffectsManager instance to them directly -- no Field/physics needed,
## the same reason tests/unit/field/test_field.gd builds Field.new() directly
## rather than loading Field.tscn (which now also contains this manager as a
## child; see that scene).


func _make_manager() -> BlockEffectsManager:
	var manager: BlockEffectsManager = BlockEffectsManager.new()
	add_child_autofree(manager)
	return manager


## Pooled burst wrappers are the manager's plain children; a running burst is a visible one.
func _active_bursts(manager: BlockEffectsManager) -> int:
	var count: int = 0
	for child: Node in manager.get_children():
		if child is Node3D and (child as Node3D).visible:
			count += 1
	return count


func _make_block() -> RigidBody3D:
	var block: RigidBody3D = autofree(RigidBody3D.new())
	add_child_autofree(block)
	block.global_position = Vector3(3.0, 1.0, -2.0)
	return block


func test_kill_plane_removal_spawns_exactly_one_effect() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var block: RigidBody3D = _make_block()

	Events.block_removed.emit(block, String(Events.REASON_KILL_PLANE))

	assert_eq(_active_bursts(manager), 1, "a kill-plane removal should spawn exactly one burst effect.")


func test_a_non_kill_plane_removal_spawns_no_effect() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var block: RigidBody3D = _make_block()

	Events.block_removed.emit(block, "some_other_reason")

	assert_eq(_active_bursts(manager), 0, "only kill_plane removals should trigger a burst effect.")


func test_impact_above_threshold_spawns_dust_at_position() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var position: Vector3 = Vector3(1.5, 0.0, 4.0)

	Events.block_impacted_at.emit(manager.config.dust_impact_speed_threshold * 3.0, position)

	assert_eq(_active_bursts(manager), 1, "an impact well above the dust threshold should spawn exactly one burst.")
	var effect: Node3D = manager.get_child(0) as Node3D
	assert_true(effect.global_position.is_equal_approx(position), "the landing-dust burst must spawn at the impact position the signal carried.")


func test_impact_below_threshold_spawns_no_effect() -> void:
	var manager: BlockEffectsManager = _make_manager()

	Events.block_impacted_at.emit(manager.config.dust_impact_speed_threshold * 0.5, Vector3(1.0, 0.0, 1.0))

	assert_eq(_active_bursts(manager), 0, "a soft impact below the dust threshold must not spawn a burst.")


func test_find_block_at_resolves_the_impacting_blocks_owner() -> void:
	## _find_block_at() is BlockEffectsManager's own seam for resolving which
	## Block owns an impact -- Events.block_impacted_at only carries
	## (speed, position), not the block itself (see game/blocks/Block.gd, an
	## unowned file for this package).
	var manager: BlockEffectsManager = _make_manager()
	var position: Vector3 = Vector3(4.0, 2.0, -3.0)

	var block: Block = Block.new()
	block.owner_slot = 3
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3.ONE
	collision.shape = box
	block.add_child(collision)
	add_child_autofree(block)
	block.global_position = position

	await wait_physics_frames(4)

	var found: Block = manager._find_block_at(position)
	assert_not_null(found, "a physics point query at the block's own position must find it.")
	assert_eq(found.owner_slot, 3, "the resolved block must be the one actually standing at that position.")


func test_falling_trail_starts_above_speed_threshold_and_stops_below_it() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var block: Block = Block.new()
	add_child_autofree(block)
	block.global_position = Vector3(0.0, 20.0, 0.0)

	var fast_delta: float = 1.0 / 60.0
	# First call only seeds _prev_positions at the block's starting height --
	# there is no earlier sample to measure a fall speed from yet, so this
	# must not start a trail on its own.
	manager._update_falling_trails(fast_delta)
	assert_eq(manager._trails.size(), 0, "the very first tracked frame has no prior position to measure a fall speed from.")

	# One physics step, falling faster than trail_speed_threshold.
	var fall_distance: float = manager.config.trail_speed_threshold * fast_delta * 2.0
	block.global_position = Vector3(0.0, 20.0 - fall_distance, 0.0)
	manager._update_falling_trails(fast_delta)
	assert_eq(manager._trails.size(), 1, "a block falling above trail_speed_threshold must get an active trail.")

	# Now barely move (well below the threshold) -- the trail must release.
	block.global_position = Vector3(0.0, 20.0 - fall_distance - 0.0001, 0.0)
	manager._update_falling_trails(fast_delta)
	assert_eq(manager._trails.size(), 0, "a block no longer falling fast must have its trail released.")


func test_simultaneous_impacts_are_capped_by_the_per_frame_budget() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var speed: float = manager.config.dust_impact_speed_threshold * 2.0

	for i: int in range(50):
		Events.block_impacted_at.emit(speed, Vector3(float(i), 0.0, 0.0))

	var cap: int = mini(manager.config.burst_max_new_per_frame, manager.config.burst_max_active)
	assert_eq(_active_bursts(manager), cap, "50 same-frame impacts must start no more than the per-frame budget of bursts.")
	assert_eq(manager.get_child_count(), cap, "only budgeted bursts may allocate pooled nodes.")


func test_active_bursts_never_exceed_the_active_cap_across_frames() -> void:
	var manager: BlockEffectsManager = _make_manager()
	manager.config = manager.config.duplicate() as BlockEffectsConfig
	manager.config.burst_max_active = 3
	manager.config.burst_max_new_per_frame = 2
	var speed: float = manager.config.dust_impact_speed_threshold * 2.0

	for frame: int in range(5):
		for i: int in range(10):
			Events.block_impacted_at.emit(speed, Vector3(float(i), 0.0, 0.0))
		await wait_physics_frames(1)

	assert_eq(_active_bursts(manager), 3, "active bursts must stay at burst_max_active while earlier ones are alive.")


