extends GutTest
## Spec 1.10 "effects + camera shake": BlockEffectsManager seen from outside.
## Events in (block_impacted_at, block_removed, graphics_preset_changed) and real
## Blocks in the tree; the node tree out (burst/trail wrappers, their particle
## systems, visibility and emitting). Bursts are plain children whose first child is
## a GPUParticles3D, trails are plain children whose first child is a MeshInstance3D;
## puffs live in an internal container and are covered by test_impact_puff.gd.

const PHYSICS_DT: float = 1.0 / 60.0

var _saved_context: MatchContext = null


func before_each() -> void:
	_saved_context = MatchContext.installed()


func after_each() -> void:
	MatchContext.install(_saved_context)


func _make_manager() -> BlockEffectsManager:
	var manager: BlockEffectsManager = BlockEffectsManager.new()
	add_child_autofree(manager)
	return manager


## Presets drive the manager through Settings' own signal, as in a live settings change.
func _apply_preset(budget_scale: float, trails: bool) -> void:
	var preset: GraphicsPreset = GraphicsPreset.new()
	preset.particle_budget_scale = budget_scale
	preset.volumetric_fog_enabled = trails
	Settings.graphics_preset_changed.emit(preset)


func _bursts(manager: BlockEffectsManager, only_visible: bool = true) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child: Node in manager.get_children():
		var wrapper: Node3D = child as Node3D
		if wrapper != null and wrapper.get_child_count() > 0 and wrapper.get_child(0) is GPUParticles3D:
			if wrapper.visible or not only_visible:
				result.append(wrapper)
	return result


func _trail_wrappers(manager: BlockEffectsManager) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child: Node in manager.get_children():
		var wrapper: Node3D = child as Node3D
		if wrapper != null and wrapper.get_child_count() > 0 and wrapper.get_child(0) is MeshInstance3D:
			if not wrapper.is_queued_for_deletion():
				result.append(wrapper)
	return result


## Burst expiry is wall-clock based and a headless run advances frames far faster than real
## time, so wait on the clock itself.
func _wait_wall_clock(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await wait_physics_frames(1)


func _emitting_count(wrapper: Node3D) -> int:
	var count: int = 0
	for child: Node in wrapper.get_children():
		if child is GPUParticles3D and (child as GPUParticles3D).emitting:
			count += 1
	return count


func _impact(manager: BlockEffectsManager, intensity: float, position: Vector3 = Vector3.ZERO) -> void:
	Events.block_impacted_at.emit(manager.config.dust_impact_speed_threshold * intensity, position)


func _make_removed_body() -> RigidBody3D:
	var body: RigidBody3D = autofree(RigidBody3D.new())
	add_child_autofree(body)
	body.global_position = Vector3(3.0, 1.0, -2.0)
	return body


## A Block that stays where the test puts it: no gravity, no velocity.
func _make_hovering_block() -> Block:
	var block: Block = Block.new()
	block.gravity_scale = 0.0
	add_child_autofree(block)
	block.global_position = Vector3(0.0, 20.0, 0.0)
	return block


func test_kill_plane_removal_spawns_exactly_one_burst() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var body: RigidBody3D = _make_removed_body()

	Events.block_removed.emit(body, String(Events.REASON_KILL_PLANE))

	var bursts: Array[Node3D] = _bursts(manager)
	assert_eq(bursts.size(), 1, "a kill-plane removal should spawn exactly one burst.")
	assert_true(bursts[0].global_position.is_equal_approx(Vector3(3.0, 1.0, -2.0)), "the burst starts at the removed block's last position.")
	assert_eq(bursts[0].get_child_count(), 1, "the kill burst is a single particle system.")
	assert_eq(_emitting_count(bursts[0]), 1, "its particles are emitting.")


func test_a_non_kill_plane_removal_spawns_no_effect() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var body: RigidBody3D = _make_removed_body()

	Events.block_removed.emit(body, "some_other_reason")
	Events.block_removed.emit(body, String(Events.REASON_GIFT_DESPAWN))

	assert_eq(_bursts(manager, false).size(), 0, "only kill_plane removals trigger a burst.")


func test_a_null_removed_block_spawns_nothing() -> void:
	var manager: BlockEffectsManager = _make_manager()

	Events.block_removed.emit(null, String(Events.REASON_KILL_PLANE))

	assert_eq(_bursts(manager, false).size(), 0)


func test_impact_above_threshold_spawns_cubelets_and_dust_at_position() -> void:
	var manager: BlockEffectsManager = _make_manager()
	var position: Vector3 = Vector3(1.5, 0.0, 4.0)

	_impact(manager, 3.0, position)

	var bursts: Array[Node3D] = _bursts(manager)
	assert_eq(bursts.size(), 1, "an impact well above the dust threshold spawns exactly one burst.")
	assert_true(bursts[0].global_position.is_equal_approx(position), "the burst spawns at the impact position the signal carried.")
	assert_eq(bursts[0].get_child_count(), 2, "one landing effect holds a cubelet shower and a dust puff.")
	assert_eq(_emitting_count(bursts[0]), 2, "both particle systems are emitting.")


func test_impact_at_exactly_the_threshold_spawns_a_burst() -> void:
	var manager: BlockEffectsManager = _make_manager()

	_impact(manager, 1.0)

	assert_eq(_bursts(manager).size(), 1, "the threshold is inclusive.")


func test_impact_below_threshold_spawns_no_effect() -> void:
	var manager: BlockEffectsManager = _make_manager()

	_impact(manager, 0.5)

	assert_eq(_bursts(manager, false).size(), 0, "a soft impact below the dust threshold must not spawn a burst.")


## Every manager listens to the global Events bus, so each measurement uses a manager of its own
## and frees it before the next impact is emitted.
func _cubelet_ratio_for(intensity: float) -> float:
	var manager: BlockEffectsManager = _make_manager()
	_impact(manager, intensity)
	var cubelets: GPUParticles3D = _bursts(manager)[0].get_child(0) as GPUParticles3D
	var ratio: float = cubelets.amount_ratio
	manager.free()
	return ratio


func test_a_harder_impact_emits_more_cubelets_than_a_barely_qualifying_one() -> void:
	var config: BlockEffectsConfig = _make_manager().config
	var soft: float = _cubelet_ratio_for(1.0)
	var hard: float = _cubelet_ratio_for(config.impact_intensity_max)
	assert_gt(hard, soft, "intensity scales how much of the cubelet pool is emitted.")


func test_impact_beyond_the_intensity_cap_is_clamped() -> void:
	var config: BlockEffectsConfig = _make_manager().config
	var capped: float = _cubelet_ratio_for(config.impact_intensity_max)
	var extreme: float = _cubelet_ratio_for(config.impact_intensity_max * 10.0)
	assert_eq(extreme, capped, "a very hard impact is no bigger than the capped one.")


func test_cubelets_take_the_colour_of_the_block_that_landed() -> void:
	var fake: FakeMatchContext = FakeMatchContext.new()
	var team_colour: Color = Color(0.9, 0.1, 0.4)
	fake.slot_color_by_id[3] = team_colour
	MatchContext.install(fake)
	var manager: BlockEffectsManager = _make_manager()
	var position: Vector3 = Vector3(4.0, 2.0, -3.0)
	var block: Block = Block.new()
	block.owner_slot = 3
	block.gravity_scale = 0.0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3.ONE
	collision.shape = box
	block.add_child(collision)
	add_child_autofree(block)
	block.global_position = position
	await wait_physics_frames(4)

	_impact(manager, 2.0, position)

	var cubelets: GPUParticles3D = _bursts(manager)[0].get_child(0) as GPUParticles3D
	var material: ShaderMaterial = cubelets.draw_pass_1.material as ShaderMaterial
	assert_eq(material.get_shader_parameter(&"base_color"), team_colour, "the shower is tinted with the landing block's team colour.")


func test_cubelets_use_the_fallback_colour_when_no_block_is_there() -> void:
	var manager: BlockEffectsManager = _make_manager()

	_impact(manager, 2.0, Vector3(40.0, 0.0, 40.0))

	var cubelets: GPUParticles3D = _bursts(manager)[0].get_child(0) as GPUParticles3D
	var material: ShaderMaterial = cubelets.draw_pass_1.material as ShaderMaterial
	assert_eq(material.get_shader_parameter(&"base_color"), manager.config.cubelet_fallback_color)


func test_simultaneous_impacts_are_capped_by_the_per_frame_budget() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_apply_preset(1.0, true)

	for i: int in range(50):
		_impact(manager, 2.0, Vector3(float(i), 0.0, 0.0))

	var cap: int = mini(manager.config.burst_max_new_per_frame, manager.config.burst_max_active)
	assert_eq(_bursts(manager).size(), cap, "50 same-frame impacts start no more than the per-frame budget of bursts.")
	assert_eq(_bursts(manager, false).size(), cap, "only budgeted bursts allocate pooled nodes.")


func test_active_bursts_never_exceed_the_active_cap_across_frames() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_apply_preset(1.0, true)
	manager.config = manager.config.duplicate() as BlockEffectsConfig
	manager.config.burst_max_active = 3
	manager.config.burst_max_new_per_frame = 2

	for frame: int in range(5):
		for i: int in range(10):
			_impact(manager, 2.0, Vector3(float(i), 0.0, 0.0))
		await wait_physics_frames(1)

	assert_eq(_bursts(manager).size(), 3, "active bursts stay at burst_max_active while earlier ones are alive.")


func test_a_lower_particle_budget_thins_the_bursts() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_apply_preset(0.5, true)

	for i: int in range(50):
		_impact(manager, 2.0, Vector3(float(i), 0.0, 0.0))

	var full_cap: int = mini(manager.config.burst_max_new_per_frame, manager.config.burst_max_active)
	assert_lt(_bursts(manager).size(), full_cap, "half the particle budget starts fewer bursts per frame.")
	assert_gt(_bursts(manager).size(), 0)
	_apply_preset(1.0, true)


func test_a_finished_burst_is_hidden_and_reused() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_apply_preset(1.0, true)
	_impact(manager, 2.0)
	var wrapper: Node3D = _bursts(manager)[0]
	var lifetime: float = maxf(manager.config.cubelet_lifetime_s, manager.config.dust_lifetime_s)

	await _wait_wall_clock(lifetime + manager.config.cleanup_margin_s + 0.3)

	assert_false(wrapper.visible, "an expired burst is hidden.")
	assert_eq(_emitting_count(wrapper), 0, "and its particles stop emitting.")
	_impact(manager, 2.0)
	assert_eq(_bursts(manager, false).size(), 1, "the idle wrapper is reused, not rebuilt.")
	assert_true(wrapper.visible)


func test_falling_trail_starts_above_speed_threshold_and_is_freed_when_it_slows() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_apply_preset(1.0, true)
	var block: Block = _make_hovering_block()
	await wait_physics_frames(2)
	assert_eq(_trail_wrappers(manager).size(), 0, "a hovering block has no trail.")

	var fall_distance: float = manager.config.trail_speed_threshold * PHYSICS_DT * 2.0
	block.global_position = Vector3(0.0, 20.0 - fall_distance, 0.0)
	await wait_physics_frames(1)

	assert_eq(_trail_wrappers(manager).size(), 1, "a block falling faster than trail_speed_threshold gets one trail.")

	await wait_physics_frames(2)
	await wait_seconds(manager.config.trail_release_fade_s + manager.config.cleanup_margin_s + 0.3)
	assert_eq(_trail_wrappers(manager).size(), 0, "once the block stops falling fast its trail is freed.")


func test_a_slow_fall_gets_no_trail() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_apply_preset(1.0, true)
	var block: Block = _make_hovering_block()
	await wait_physics_frames(2)

	var slow_distance: float = manager.config.trail_speed_threshold * PHYSICS_DT * 0.25
	block.global_position = Vector3(0.0, 20.0 - slow_distance, 0.0)
	await wait_physics_frames(1)

	assert_eq(_trail_wrappers(manager).size(), 0)


func test_a_rising_block_gets_no_trail() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_apply_preset(1.0, true)
	var block: Block = _make_hovering_block()
	await wait_physics_frames(2)

	block.global_position = Vector3(0.0, 20.0 + manager.config.trail_speed_threshold * PHYSICS_DT * 4.0, 0.0)
	await wait_physics_frames(1)

	assert_eq(_trail_wrappers(manager).size(), 0, "only falling counts.")


func test_trail_follows_the_falling_block() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_apply_preset(1.0, true)
	var block: Block = _make_hovering_block()
	await wait_physics_frames(2)

	var fall_distance: float = manager.config.trail_speed_threshold * PHYSICS_DT * 2.0
	block.global_position = Vector3(0.0, 20.0 - fall_distance, 0.0)
	await wait_physics_frames(1)

	var trails: Array[Node3D] = _trail_wrappers(manager)
	assert_eq(trails.size(), 1)
	assert_true(trails[0].global_position.is_equal_approx(block.global_position), "the streak is centred on the block it follows.")


func test_trail_count_is_capped_at_the_concurrent_limit() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_apply_preset(1.0, true)
	var blocks: Array[Block] = []
	for i: int in range(manager.config.trail_max_concurrent + 3):
		var block: Block = _make_hovering_block()
		block.global_position = Vector3(float(i) * 3.0, 20.0, 0.0)
		blocks.append(block)
	await wait_physics_frames(2)

	for block: Block in blocks:
		block.global_position.y -= manager.config.trail_speed_threshold * PHYSICS_DT * 2.0
	await wait_physics_frames(1)

	assert_eq(_trail_wrappers(manager).size(), manager.config.trail_max_concurrent)


func test_a_preset_without_atmospheric_effects_drops_the_falling_trail() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_apply_preset(1.0, false)
	var block: Block = _make_hovering_block()
	await wait_physics_frames(2)

	block.global_position = Vector3(0.0, 20.0 - manager.config.trail_speed_threshold * PHYSICS_DT * 2.0, 0.0)
	await wait_physics_frames(1)

	assert_eq(_trail_wrappers(manager).size(), 0, "the Low preset drops the continuous trail.")
	_impact(manager, 2.0)
	assert_eq(_bursts(manager).size(), 1, "one-shot bursts stay on every preset.")
	_apply_preset(1.0, true)


func test_a_freed_block_releases_its_trail() -> void:
	var manager: BlockEffectsManager = _make_manager()
	_apply_preset(1.0, true)
	var block: Block = _make_hovering_block()
	await wait_physics_frames(2)
	block.global_position = Vector3(0.0, 20.0 - manager.config.trail_speed_threshold * PHYSICS_DT * 2.0, 0.0)
	await wait_physics_frames(1)
	assert_eq(_trail_wrappers(manager).size(), 1)

	block.free()
	await wait_physics_frames(2)
	await wait_seconds(manager.config.trail_release_fade_s + manager.config.cleanup_margin_s + 0.3)

	assert_eq(_trail_wrappers(manager).size(), 0, "a trail never outlives its block.")
