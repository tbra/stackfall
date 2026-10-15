extends GutTest
## flipbook dust puff (game/blocks/ImpactPuff.gd) spawned from
## BlockEffectsManager's replicated impact event.


func _make_manager() -> BlockEffectsManager:
	var manager: BlockEffectsManager = BlockEffectsManager.new()
	add_child_autofree(manager)
	return manager


func _impact(manager: BlockEffectsManager, intensity: float, position: Vector3 = Vector3.ZERO) -> void:
	Events.block_impacted_at.emit(manager.config.dust_impact_speed_threshold * intensity, position)


func test_impact_spawns_puff_at_contact_point() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_impact(manager, 2.0, Vector3(2.0, 0.5, -1.0))
	assert_eq(manager.active_puff_count(), 1)
	assert_true(manager.puffs()[0].global_position.is_equal_approx(Vector3(2.0, 0.5, -1.0)))
	assert_true(manager.puffs()[0].visible)


func test_below_threshold_spawns_no_puff() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_impact(manager, 0.5)
	assert_eq(manager.active_puff_count(), 0)


func test_pool_cap_respected() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var cap: int = int(floorf(float(manager.config.puff_max_active) * manager._particle_budget_scale))
	for i: int in range(cap + 10):
		_impact(manager, 2.0)
	assert_eq(manager.active_puff_count(), cap)
	assert_eq(manager.puffs().size(), cap, "no puff beyond the cap is ever built.")


func test_puff_recycles_after_flipbook_ends() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_impact(manager, 2.0)
	var puff: ImpactPuff = manager.puffs()[0]
	assert_true(puff.advance(0.1), "still playing mid-flipbook.")
	var duration: float = float(manager.config.puff_frame_count) / manager.config.puff_fps
	assert_false(puff.advance(duration), "terminal frame retires the puff.")
	assert_eq(manager.active_puff_count(), 0)
	assert_false(puff.visible)
	_impact(manager, 2.0)
	assert_eq(manager.puffs().size(), 1, "the retired puff is reused, not rebuilt.")
	assert_eq(manager.active_puff_count(), 1)


func test_disabled_config_spawns_nothing() -> void:
	var manager: BlockEffectsManager = _make_manager()
	manager.config = manager.config.duplicate() as BlockEffectsConfig
	manager.config.puff_enabled = false
	_impact(manager, 2.0)
	assert_eq(manager.active_puff_count(), 0)
