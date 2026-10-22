extends GutTest
## Flipbook dust puff (game/blocks/ImpactPuff.gd) spawned by BlockEffectsManager
## from the replicated impact event: Events in, puff nodes out, advanced through
## ImpactPuff's public advance() (the same call its own _process makes).


func after_each() -> void:
	_apply_preset(1.0)


func _make_manager() -> BlockEffectsManager:
	var manager: BlockEffectsManager = BlockEffectsManager.new()
	add_child_autofree(manager)
	_apply_preset(1.0)
	return manager


func _apply_preset(budget_scale: float) -> void:
	var preset: GraphicsPreset = GraphicsPreset.new()
	preset.particle_budget_scale = budget_scale
	Settings.graphics_preset_changed.emit(preset)


## Puffs live in an internal container child of the manager.
func _all_puffs(manager: BlockEffectsManager) -> Array[ImpactPuff]:
	var puffs: Array[ImpactPuff] = []
	for child: Node in manager.get_children(true):
		for node: Node in child.get_children():
			if node is ImpactPuff:
				puffs.append(node as ImpactPuff)
	return puffs


func _active_puffs(manager: BlockEffectsManager) -> Array[ImpactPuff]:
	var active: Array[ImpactPuff] = []
	for puff: ImpactPuff in _all_puffs(manager):
		if puff.active:
			active.append(puff)
	return active


func _impact(manager: BlockEffectsManager, intensity: float, position: Vector3 = Vector3.ZERO) -> void:
	Events.block_impacted_at.emit(manager.config.dust_impact_speed_threshold * intensity, position)


func test_impact_spawns_puff_at_contact_point() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_impact(manager, 2.0, Vector3(2.0, 0.5, -1.0))
	assert_eq(_active_puffs(manager).size(), 1)
	assert_true(_all_puffs(manager)[0].global_position.is_equal_approx(Vector3(2.0, 0.5, -1.0)))
	assert_true(_all_puffs(manager)[0].visible)


func test_below_threshold_spawns_no_puff() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_impact(manager, 0.5)
	assert_eq(_all_puffs(manager).size(), 0)


func test_puffs_do_not_add_public_children() -> void:
	var manager: BlockEffectsManager = _make_manager()
	manager.config = manager.config.duplicate() as BlockEffectsConfig
	manager.config.burst_max_new_per_frame = 0
	_impact(manager, 2.0)
	assert_eq(_active_puffs(manager).size(), 1, "a puff is spawned even when the burst budget drops the burst.")
	assert_eq(manager.get_child_count(), 0, "puffs sit in an internal container, not among the public children.")


func test_pool_cap_respected() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var cap: int = manager.config.puff_max_active
	for i: int in range(cap + 10):
		_impact(manager, 2.0)
	assert_eq(_active_puffs(manager).size(), cap)
	assert_eq(_all_puffs(manager).size(), cap, "no puff beyond the cap is ever built.")


func test_a_lower_particle_budget_shrinks_the_puff_cap() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_apply_preset(0.5)
	for i: int in range(manager.config.puff_max_active + 10):
		_impact(manager, 2.0)
	assert_eq(_active_puffs(manager).size(), manager.config.puff_max_active / 2)


func test_a_zero_particle_budget_spawns_no_puffs() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_apply_preset(0.0)
	_impact(manager, 2.0)
	assert_eq(_all_puffs(manager).size(), 0)


func test_puff_recycles_after_flipbook_ends() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_impact(manager, 2.0)
	var puff: ImpactPuff = _all_puffs(manager)[0]
	assert_true(puff.advance(0.1), "still playing mid-flipbook.")
	var duration: float = float(manager.config.puff_frame_count) / manager.config.puff_fps
	assert_false(puff.advance(duration), "terminal frame retires the puff.")
	assert_eq(_active_puffs(manager).size(), 0)
	assert_false(puff.visible)
	_impact(manager, 2.0)
	assert_eq(_all_puffs(manager).size(), 1, "the retired puff is reused, not rebuilt.")
	assert_eq(_active_puffs(manager).size(), 1)


func test_an_idle_puff_does_not_advance() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_impact(manager, 2.0)
	var puff: ImpactPuff = _all_puffs(manager)[0]
	puff.stop()
	assert_false(puff.advance(0.1), "a retired puff reports not playing.")
	assert_false(puff.visible)


func test_puff_retires_on_its_own_as_frames_are_processed() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_impact(manager, 2.0)
	var duration: float = float(manager.config.puff_frame_count) / manager.config.puff_fps
	await wait_seconds(duration + 0.3)
	assert_eq(_active_puffs(manager).size(), 0, "the flipbook runs out by itself and the puff hides.")
	assert_false(_all_puffs(manager)[0].visible)


## Every manager listens to the global Events bus, so each puff comes from a manager of its own
## that is freed before the next impact is emitted.
func _puff_for(intensity: float) -> Dictionary:
	var manager: BlockEffectsManager = _make_manager()
	_impact(manager, intensity)
	var puff: ImpactPuff = _all_puffs(manager)[0]
	var result: Dictionary = {"hard": puff.hard, "size": puff.quad_size_m, "alpha": puff.alpha}
	manager.free()
	return result


func test_a_harder_impact_gives_a_bigger_hard_flipbook_puff() -> void:
	var config: BlockEffectsConfig = _make_manager().config
	var soft: Dictionary = _puff_for(1.0)
	var hard: Dictionary = _puff_for(config.impact_intensity_max)
	assert_false(soft["hard"], "a barely qualifying impact uses the soft atlas.")
	assert_true(hard["hard"], "a hard impact uses the hard atlas.")
	assert_gt(float(hard["size"]), float(soft["size"]))
	assert_gt(float(hard["alpha"]), float(soft["alpha"]))


func test_disabled_config_spawns_nothing() -> void:
	var manager: BlockEffectsManager = _make_manager()
	manager.config = manager.config.duplicate() as BlockEffectsConfig
	manager.config.puff_enabled = false
	_impact(manager, 2.0)
	assert_eq(_all_puffs(manager).size(), 0)
