extends GutTest
## Bontago-xtq.29 (M7 P4, spec 2.10 "effects + camera shake"):
## game/BlockEffectsManager.gd's one-shot kill-plane burst and landing-dust/
## impact burst. Events.block_removed and Events.block_impacted_at are both
## global Events autoload signals, so this test connects a real
## BlockEffectsManager instance to them directly -- no Field/physics needed,
## the same reason tests/unit/test_field.gd builds Field.new() directly
## rather than loading Field.tscn (which now also contains this manager as a
## child; see that scene).


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


func test_cleanup_fallback_frees_the_effect_after_its_lifetime() -> void:
	# GPUParticles3D.finished may not fire in this headless GUT run (no
	# renderer driving the particle system) -- exercising the
	# create_timer(lifetime + margin) fallback directly, per this package's
	# fix, is what actually proves active_effect_count() returns to 0.
	var manager: BlockEffectsManager = _make_manager()
	var block: RigidBody3D = _make_block()

	Events.block_removed.emit(block, String(Events.REASON_KILL_PLANE))
	assert_eq(manager.active_effect_count(), 1, "fixture: the burst must have spawned before it can be cleaned up.")

	await wait_seconds(manager.config.kill_lifetime_s + manager.config.cleanup_margin_s + 0.2)

	assert_eq(manager.active_effect_count(), 0, "the cleanup fallback must free the burst node well after its own lifetime, even headless.")
