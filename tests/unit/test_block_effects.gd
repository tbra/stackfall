extends GutTest
## Bontago-xtq.29 (M7 P4, spec 2.10 "effects + camera shake"):
## game/BlockEffectsManager.gd's one-shot kill-plane burst and landing-dust/
## impact burst. Events.block_removed and Events.block_impacted_at are both
## global Events autoload signals, so this test connects a real
## BlockEffectsManager instance to them directly -- no Field/physics needed,
## the same reason tests/unit/test_field.gd builds Field.new() directly
## rather than loading Field.tscn (which now also contains this manager as a
## child; see that scene).


## The manager expires bursts by wall clock (Time.get_ticks_msec), and the runners use
## --fixed-fps (frames outrun the wall), so wait real time then let a frame run.
func _wait_wall_s(seconds: float) -> void:
	OS.delay_msec(int(ceil(seconds * 1000.0)))
	await get_tree().process_frame


func _make_manager() -> BlockEffectsManager:
	var manager: BlockEffectsManager = BlockEffectsManager.new()
	add_child_autofree(manager)
	return manager


func _make_block() -> RigidBody3D:
	var block: RigidBody3D = autofree(RigidBody3D.new())
	add_child_autofree(block)
	block.global_position = Vector3(3.0, 1.0, -2.0)
	return block


func test_kill_plane_removal_spawns_exactly_one_effect() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var block: RigidBody3D = _make_block()

	Events.block_removed.emit(block, String(Events.REASON_KILL_PLANE))

	assert_eq(manager.active_effect_count(), 1, "a kill-plane removal should spawn exactly one burst effect.")


func test_a_non_kill_plane_removal_spawns_no_effect() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var block: RigidBody3D = _make_block()

	Events.block_removed.emit(block, "some_other_reason")

	assert_eq(manager.active_effect_count(), 0, "only kill_plane removals should trigger a burst effect.")


func test_effect_spawns_at_the_blocks_last_position() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var block: RigidBody3D = _make_block()

	Events.block_removed.emit(block, String(Events.REASON_KILL_PLANE))

	var effect: Node3D = manager.get_child(0) as Node3D
	assert_true(effect.global_position.is_equal_approx(block.global_position), "the burst must spawn at the block's own last position, not the manager's origin.")


func test_impact_above_threshold_spawns_dust_at_position() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var position: Vector3 = Vector3(1.5, 0.0, 4.0)

	Events.block_impacted_at.emit(manager.config.dust_impact_speed_threshold * 3.0, position)

	assert_eq(manager.active_effect_count(), 1, "an impact well above the dust threshold should spawn exactly one burst.")
	var effect: Node3D = manager.get_child(0) as Node3D
	assert_true(effect.global_position.is_equal_approx(position), "the landing-dust burst must spawn at the impact position the signal carried.")


func test_impact_below_threshold_spawns_no_effect() -> void:
	var manager: BlockEffectsManager = _make_manager()

	Events.block_impacted_at.emit(manager.config.dust_impact_speed_threshold * 0.5, Vector3(1.0, 0.0, 1.0))

	assert_eq(manager.active_effect_count(), 0, "a soft impact below the dust threshold must not spawn a burst.")


func test_landing_burst_wraps_cubelet_and_dust_under_one_effect() -> void:
	## Bontago-mp0.3.4: the landing burst now spawns a team-colored cubelet
	## shower AND the original dust puff, but active_effect_count() (the
	## manager's own child count) must still read one effect per impact.
	var manager: BlockEffectsManager = _make_manager()

	Events.block_impacted_at.emit(manager.config.dust_impact_speed_threshold * 2.0, Vector3(2.0, 0.0, -1.0))

	assert_eq(manager.active_effect_count(), 1, "one impact must still be exactly one wrapped effect.")
	var wrapper: Node3D = manager.get_child(0) as Node3D
	assert_eq(wrapper.get_child_count(), 2, "the wrapper must hold both the cubelet shower and the dust puff.")


func test_landing_burst_cubelet_amount_scales_with_impact_intensity() -> void:
	var manager: BlockEffectsManager = _make_manager()

	Events.block_impacted_at.emit(manager.config.dust_impact_speed_threshold, Vector3(0.0, 0.0, 0.0))
	var at_threshold_cubelets: GPUParticles3D = (manager.get_child(0) as Node3D).get_child(0) as GPUParticles3D
	assert_eq(at_threshold_cubelets.amount, manager.config.cubelet_max_particle_amount, "pooled systems are built at the maximum count.")
	assert_almost_eq(at_threshold_cubelets.amount_ratio, float(manager.config.cubelet_particle_amount) / float(manager.config.cubelet_max_particle_amount), 0.001, "an impact right at the threshold gets no intensity scale-up.")

	var manager2: BlockEffectsManager = _make_manager()
	Events.block_impacted_at.emit(manager2.config.dust_impact_speed_threshold * 1000.0, Vector3(0.0, 0.0, 0.0))
	var extreme_cubelets: GPUParticles3D = (manager2.get_child(0) as Node3D).get_child(0) as GPUParticles3D
	assert_eq(extreme_cubelets.amount, manager2.config.cubelet_max_particle_amount, "pooled systems are built at the maximum count.")
	assert_almost_eq(extreme_cubelets.amount_ratio, 1.0, 0.001, "an extreme impact must clamp to cubelet_max_particle_amount, not grow unbounded.")


func test_find_block_at_resolves_the_impacting_blocks_owner() -> void:
	## _find_block_at() is BlockEffectsManager's own seam for resolving which
	## Block owns an impact -- Events.block_impacted_at only carries
	## (speed, position), not the block itself (see game/Block.gd, an
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


func test_falling_trail_caps_at_max_concurrent() -> void:
	var manager: BlockEffectsManager = _make_manager()
	manager.config = manager.config.duplicate() as BlockEffectsConfig
	manager.config.trail_max_concurrent = 2

	var delta: float = 1.0 / 60.0
	var fall_distance: float = manager.config.trail_speed_threshold * delta * 2.0
	var blocks: Array[Block] = []
	for i: int in range(4):
		var block: Block = Block.new()
		add_child_autofree(block)
		block.global_position = Vector3(float(i) * 3.0, 20.0, 0.0)
		blocks.append(block)

	# Seed _prev_positions for every block first (see the previous test's own
	# doc on why the first tracked frame never starts a trail by itself).
	manager._update_falling_trails(delta)
	for block: Block in blocks:
		block.global_position.y -= fall_distance
	manager._update_falling_trails(delta)

	assert_eq(manager._trails.size(), 2, "trail_max_concurrent must cap the number of simultaneously active trails.")


func test_cleanup_fallback_frees_the_effect_after_its_lifetime() -> void:
	# GPUParticles3D.finished may not fire in this headless GUT run (no
	# renderer driving the particle system) -- exercising the
	# create_timer(lifetime + margin) fallback directly, per this package's
	# fix, is what actually proves active_effect_count() returns to 0.
	var manager: BlockEffectsManager = _make_manager()
	var block: RigidBody3D = _make_block()

	Events.block_removed.emit(block, String(Events.REASON_KILL_PLANE))
	assert_eq(manager.active_effect_count(), 1, "fixture: the burst must have spawned before it can be cleaned up.")

	await _wait_wall_s(manager.config.kill_lifetime_s + manager.config.cleanup_margin_s + 0.2)

	assert_eq(manager.active_effect_count(), 0, "the cleanup fallback must free the burst node well after its own lifetime, even headless.")


func test_simultaneous_impacts_are_capped_by_the_per_frame_budget() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var speed: float = manager.config.dust_impact_speed_threshold * 2.0

	for i: int in range(50):
		Events.block_impacted_at.emit(speed, Vector3(float(i), 0.0, 0.0))

	var cap: int = mini(manager.config.burst_max_new_per_frame, manager.config.burst_max_active)
	assert_eq(manager.active_effect_count(), cap, "50 same-frame impacts must start no more than the per-frame budget of bursts.")
	assert_eq(manager.pooled_burst_count(), cap, "only budgeted bursts may allocate pooled nodes.")


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

	assert_eq(manager.active_effect_count(), 3, "active bursts must stay at burst_max_active while earlier ones are alive.")


func test_impacts_allocate_no_new_materials_and_reuse_pooled_nodes() -> void:
	var manager: BlockEffectsManager = _make_manager()
	manager.config = manager.config.duplicate() as BlockEffectsConfig
	manager.config.cleanup_margin_s = 0.0
	manager.config.cubelet_lifetime_s = 0.1
	manager.config.dust_lifetime_s = 0.1
	var speed: float = manager.config.dust_impact_speed_threshold * 2.0

	Events.block_impacted_at.emit(speed, Vector3.ZERO)
	var wrapper: Node3D = manager.get_child(0) as Node3D
	var cubelets: GPUParticles3D = wrapper.get_child(0) as GPUParticles3D
	var dust: GPUParticles3D = wrapper.get_child(1) as GPUParticles3D
	var mesh_id: int = cubelets.draw_pass_1.get_instance_id()
	var cubelet_material_id: int = cubelets.process_material.get_instance_id()
	var dust_material_id: int = dust.process_material.get_instance_id()
	var dust_mesh_id: int = dust.draw_pass_1.get_instance_id()

	await _wait_wall_s(0.4)
	assert_eq(manager.active_effect_count(), 0, "fixture: the first burst must have expired back into the pool.")

	Events.block_impacted_at.emit(speed, Vector3(5.0, 0.0, 0.0))
	assert_eq(manager.pooled_burst_count(), 1, "a second impact must reuse the pooled burst, not create a new one.")
	assert_eq(manager.get_child_count(), 1, "no new wrapper node may be instantiated.")
	assert_eq(manager.active_effect_count(), 1, "the reused burst is active again.")
	assert_eq(cubelets.draw_pass_1.get_instance_id(), mesh_id, "same-colour impacts share one cubelet mesh/material.")
	assert_eq(cubelets.process_material.get_instance_id(), cubelet_material_id, "the process material is reused.")
	assert_eq(dust.process_material.get_instance_id(), dust_material_id, "the dust process material is reused.")
	assert_eq(dust.draw_pass_1.get_instance_id(), dust_mesh_id, "the dust mesh/material is shared.")
	assert_true(wrapper.global_position.is_equal_approx(Vector3(5.0, 0.0, 0.0)), "the reused burst must move to the new impact position.")


func test_reused_burst_keeps_amount_and_rescales_amount_ratio() -> void:
	var manager: BlockEffectsManager = _make_manager()
	manager.config = manager.config.duplicate() as BlockEffectsConfig
	manager.config.cleanup_margin_s = 0.0
	manager.config.cubelet_lifetime_s = 0.1
	manager.config.dust_lifetime_s = 0.1
	var threshold: float = manager.config.dust_impact_speed_threshold

	Events.block_impacted_at.emit(threshold, Vector3.ZERO)
	var cubelets: GPUParticles3D = (manager.get_child(0) as Node3D).get_child(0) as GPUParticles3D
	var dust: GPUParticles3D = (manager.get_child(0) as Node3D).get_child(1) as GPUParticles3D
	var cubelet_amount: int = cubelets.amount
	var dust_amount: int = dust.amount
	var soft_ratio: float = cubelets.amount_ratio
	await _wait_wall_s(0.4)

	Events.block_impacted_at.emit(threshold * 1000.0, Vector3(5.0, 0.0, 0.0))
	assert_eq(manager.pooled_burst_count(), 1, "fixture: the burst was reused.")
	assert_eq(cubelets.amount, cubelet_amount, "reuse must not change cubelet amount (buffer reallocation).")
	assert_eq(dust.amount, dust_amount, "reuse must not change dust amount.")
	assert_almost_eq(cubelets.amount_ratio, 1.0, 0.001, "a harder impact raises the cubelet ratio to the max.")
	assert_gt(cubelets.amount_ratio, soft_ratio, "ratio must differ between the two impacts.")
	assert_almost_eq(dust.amount_ratio, minf(1.0, float(int(round(float(manager.config.dust_particle_amount) * manager.config.impact_intensity_max))) / float(dust_amount)), 0.001, "dust ratio follows intensity.")


func test_release_pool_frees_pooled_nodes() -> void:
	var manager: BlockEffectsManager = _make_manager()
	Events.block_impacted_at.emit(manager.config.dust_impact_speed_threshold * 2.0, Vector3.ZERO)
	assert_eq(manager.pooled_burst_count(), 1, "fixture: one pooled burst exists.")

	manager.release_pool()

	assert_eq(manager.pooled_burst_count(), 0, "release_pool() must empty the pool.")
	assert_eq(manager.active_effect_count(), 0, "release_pool() must leave no active bursts.")
