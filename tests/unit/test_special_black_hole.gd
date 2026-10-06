extends GutTest
## Black hole special (Bontago-8or.25): pull inside the radius (all teams),
## nothing outside, expiry after lifetime_s, optional core consumption, and a
## client building the visual from the replicated special_triggered.

const MatchNetScript := preload("res://net/MatchNet.gd")
const RADIUS: float = 6.0
const CAPTURE_START_M: float = 6.0
const CAPTURE_MASS_KG: float = 8.0
const SETTLE_FRAMES: int = 20

var _bodies: Array[Node3D] = []


func after_each() -> void:
	for body: Node3D in _bodies:
		if is_instance_valid(body):
			body.free()
	_bodies.clear()


func _effect() -> BlackHoleEffect:
	var effect: BlackHoleEffect = BlackHoleEffect.new()
	effect.pull.radius_m = RADIUS
	effect.lifetime_s = 2.0
	return effect


func _make_block(position: Vector3, slot: int) -> Block:
	var block: Block = Block.new()
	block.mass = 1.0
	block.owner_slot = slot
	block.gravity_scale = 0.0
	block.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	block.linear_damp = 0.0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.3
	collision.shape = shape
	block.add_child(collision)
	add_child(block)
	block.global_position = position
	_bodies.append(block)
	return block


func _make_field(effect: BlackHoleEffect) -> BlackHoleField:
	var field: BlackHoleField = BlackHoleField.new()
	field.configure(effect, [])
	add_child(field)
	# Godot re-enables _physics_process on READY; manual ticks must be the only ones.
	field.set_physics_process(false)
	field.global_position = Vector3.ZERO
	_bodies.append(field)
	return field


func test_blocks_inside_radius_of_every_team_are_pulled_and_outside_is_not() -> void:
	var near_a: Block = _make_block(Vector3(3.0, 0.0, 0.0), 0)
	var near_b: Block = _make_block(Vector3(-3.0, 0.0, 0.0), 1)
	var far: Block = _make_block(Vector3(RADIUS + 3.0, 0.0, 0.0), 1)
	var field: BlackHoleField = _make_field(_effect())
	await wait_physics_frames(1)
	field.tick(0.1)
	await wait_physics_frames(1)
	assert_lt(near_a.linear_velocity.x, 0.0, "team 0 block pulled toward centre")
	assert_gt(near_b.linear_velocity.x, 0.0, "team 1 block pulled toward centre")
	assert_eq(far.linear_velocity, Vector3.ZERO, "block outside the radius untouched")


func test_pull_is_mass_independent_and_stronger_closer() -> void:
	var effect: BlackHoleEffect = _effect()
	var close: Block = _make_block(Vector3(1.5, 0.0, 0.0), 0)
	var farther: Block = _make_block(Vector3(0.0, 0.0, 5.0), 0)
	var heavy: Block = _make_block(Vector3(0.0, 0.0, -5.0), 0)
	heavy.mass = 8.0
	var field: BlackHoleField = _make_field(effect)
	await wait_physics_frames(1)
	field.tick(0.1)
	await wait_physics_frames(1)
	var accel_close: float = effect.pull.accel_mps2 * (1.0 - 1.5 / RADIUS) + effect.pull.friction_compensation
	var accel_far: float = effect.pull.accel_mps2 * (1.0 - 5.0 / RADIUS) + effect.pull.friction_compensation
	assert_almost_eq(
		close.linear_velocity.length() / farther.linear_velocity.length(), accel_close / accel_far, 0.01,
		"speed gained follows acceleration x dt (falloff plus friction compensation)"
	)
	assert_gt(close.linear_velocity.length(), farther.linear_velocity.length(), "stronger closer")
	assert_almost_eq(heavy.linear_velocity.length(), farther.linear_velocity.length(), 0.05, "8 kg pulled like 1 kg")


func test_field_expires_after_lifetime() -> void:
	var effect: BlackHoleEffect = _effect()
	var field: BlackHoleField = _make_field(effect)
	field.tick(effect.lifetime_s - 0.5)
	assert_false(field.is_expired())
	field.tick(0.6)
	assert_true(field.is_expired())
	assert_true(field.is_queued_for_deletion())


func _host_registry() -> BlockRegistry:
	var root: Node3D = autofree(Node3D.new())
	add_child_autofree(root)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	registry.set_host_authority(true)
	Match.register_world(null, registry, root)
	return registry


func test_a_block_reaching_the_core_is_captured_once_through_the_shared_hole_dissolve() -> void:
	Match.set_process(false)
	Match.abort_match()
	var registry: BlockRegistry = _host_registry()
	var effect: BlackHoleEffect = _effect()
	var core: Block = _make_block(Vector3(effect.pull.core_radius_m * 0.5, 0.0, 0.0), 0)
	var outside: Block = _make_block(Vector3(effect.pull.core_radius_m * 3.0, 0.0, 0.0), 0)
	var field: BlackHoleField = _make_field(effect)
	await wait_physics_frames(1)
	var started: Array[int] = [0]
	var count_started: Callable = func(_b: RigidBody3D, _n: int, _d: float) -> void: started[0] += 1
	Events.block_dissolve_started.connect(count_started)
	field.tick(0.1)
	field.tick(0.1)
	Events.block_dissolve_started.disconnect(count_started)
	assert_true(registry.hole_dissolver().is_dissolving(core), "captured: same pending dissolve a hole starts")
	assert_false(registry.hole_dissolver().is_dissolving(outside), "outside the core: still being pulled")
	assert_eq(registry.hole_dissolver().dissolves_started, 1, "captured once, not per tick")
	assert_eq(started[0], 1, "the fade event the territory holes use is emitted")
	assert_false(core.is_queued_for_deletion(), "removal waits for the dissolve fade")
	var no_candidates: Array[Block] = []
	registry.hole_dissolver().physics_tick(1.0, no_candidates)
	Match.register_world(null, null, null)


func test_capture_without_a_registry_leaves_the_block_at_the_core() -> void:
	Match.set_process(false)
	Match.abort_match()
	Match.register_world(null, null, null)
	var core: Block = _make_block(Vector3(0.1, 0.0, 0.0), 0)
	var field: BlackHoleField = _make_field(_effect())
	await wait_physics_frames(1)
	field.tick(0.1)
	assert_false(core.is_queued_for_deletion(), "no dissolver: nothing removes it")
	assert_false(HoleDissolver.request_dissolve(core))


## Plan section 5 E: an 8 kg block on the real disc, 6 m out, reaches the core within
## lifetime_s and is captured (friction is overcome, unlike the old 14 m/s^2 / 60 N pull).
func test_real_disc_8kg_block_from_6m_reaches_the_core_within_lifetime() -> void:
	Match.set_process(false)
	Match.abort_match()
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_black_hole_disc"
	map_def.field_radius = 14.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	var disc: Field = autofree(Field.new())
	disc.map_def = map_def
	add_child_autofree(disc)
	var shape: BlockShape = load("res://config/blocks/bar4.tres") as BlockShape
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var heavy: Block = BlockFactory.build(shape, tuning, 1)
	add_child_autofree(heavy)
	var rest_y: float = disc.surface_y() + 0.6
	heavy.global_position = Vector3(CAPTURE_START_M, rest_y, 0.0)
	assert_almost_eq(heavy.mass, CAPTURE_MASS_KG, 0.001, "fixture: an 8 kg block")
	await wait_physics_frames(SETTLE_FRAMES)
	var effect: BlackHoleEffect = (SpecialDef.find_by_id(&"black_hole").effect as BlackHoleEffect)
	var hole: BlackHoleField = BlackHoleField.new()
	hole.configure(effect, [])
	add_child_autofree(hole)
	hole.set_physics_process(false)
	hole.global_position = Vector3(0.0, rest_y, 0.0)
	var frames: int = 0
	var limit: int = int(effect.lifetime_s * float(Engine.physics_ticks_per_second)) - 1
	# Sandbox: no registry, so the dissolve is refused and the block is (correctly) not
	# flagged captured; reaching the core is checked by distance instead.
	var core_m: float = effect.pull.core_radius_m
	while frames < limit and heavy.global_position.distance_to(hole.global_position) > core_m:
		hole.tick(1.0 / float(Engine.physics_ticks_per_second))
		await wait_physics_frames(1)
		frames += 1
	assert_lte(heavy.global_position.distance_to(hole.global_position), core_m, "reached the core (frames=%d)" % frames)
	assert_false(heavy.has_meta(RadialPull.CAPTURED_META), "refused dissolve leaves no capture flag")


const CUBE_COLUMN_COUNT: int = 12
const CUBE_COLUMN_SPACING_M: float = 1.2
const CUBE_COLUMN_START_M: float = 0.8
const CUBE_COLUMN_JITTER_M: float = 0.45
const PILE_RING_M: float = 1.0
const REMOVAL_MARGIN_S: float = 1.0


## Real disc, live host registry: builds the world and returns the registry.
func _live_world() -> Array:
	Match.set_process(false)
	Match.abort_match()
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_black_hole_pile"
	map_def.field_radius = 14.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	var disc: Field = autofree(Field.new())
	disc.map_def = map_def
	add_child_autofree(disc)
	var root: Node3D = autofree(Node3D.new())
	add_child_autofree(root)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	registry.set_host_authority(true)
	registry.configure(disc, map_def)
	Match.register_world(disc, registry, root)
	return [disc, registry, root]


## Drops the cubes, ticks the field with the physics loop and returns how many were
## removed (freed or queued) by the end of the effect lifetime plus a margin.
func _count_removed_after_lifetime(disc: Field, root: Node3D, positions: Array[Vector3]) -> int:
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var cube_ids: Array[int] = []
	for position: Vector3 in positions:
		var cube: Block = BlockFactory.build(shape, tuning, 0)
		root.add_child(cube)
		cube.global_position = position
		cube_ids.append(cube.get_instance_id())
	var effect: BlackHoleEffect = (SpecialDef.find_by_id(&"black_hole").effect as BlackHoleEffect)
	var hole: BlackHoleField = BlackHoleField.new()
	hole.configure(effect, [])
	add_child_autofree(hole)
	hole.set_physics_process(false)
	hole.global_position = Vector3(0.0, disc.surface_y() + 0.6, 0.0)
	var ticks: int = int((effect.lifetime_s + REMOVAL_MARGIN_S) * float(Engine.physics_ticks_per_second))
	var step: float = 1.0 / float(Engine.physics_ticks_per_second)
	for _i: int in ticks:
		if is_instance_valid(hole) and not hole.is_queued_for_deletion():
			hole.tick(step)
		await wait_physics_frames(1)
	var removed: int = 0
	for id: int in cube_ids:
		var alive: Object = instance_from_id(id)
		if alive == null or (alive as Node).is_queued_for_deletion():
			removed += 1
	return removed


func test_cube_column_above_the_hole_is_all_removed_within_the_lifetime() -> void:
	var world: Array = _live_world()
	var disc: Field = world[0] as Field
	var positions: Array[Vector3] = []
	for i: int in CUBE_COLUMN_COUNT:
		var angle: float = float(i) * 2.4
		var jitter: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * CUBE_COLUMN_JITTER_M
		positions.append(jitter + Vector3(0.0, disc.surface_y() + CUBE_COLUMN_START_M + float(i) * CUBE_COLUMN_SPACING_M, 0.0))
	var removed: int = await _count_removed_after_lifetime(disc, world[2] as Node3D, positions)
	assert_eq(removed, CUBE_COLUMN_COUNT, "every cube pulled into the vortex is destroyed")
	Match.register_world(null, null, null)


func test_cubes_piled_in_the_core_are_all_removed() -> void:
	var world: Array = _live_world()
	var disc: Field = world[0] as Field
	var positions: Array[Vector3] = []
	for i: int in CUBE_COLUMN_COUNT:
		var angle: float = float(i) * TAU / 4.0
		var ring: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * PILE_RING_M * float(i % 2)
		positions.append(ring + Vector3(0.0, disc.surface_y() + 0.6 + float(i / 4) * CUBE_COLUMN_SPACING_M, 0.0))
	var removed: int = await _count_removed_after_lifetime(disc, world[2] as Node3D, positions)
	assert_eq(removed, CUBE_COLUMN_COUNT, "a pile resting in the core is destroyed layer by layer")
	Match.register_world(null, null, null)


func test_block_above_the_core_inside_the_height_band_is_captured_but_not_beyond_it() -> void:
	var world: Array = _live_world()
	var disc: Field = world[0] as Field
	var effect: BlackHoleEffect = _effect()
	var above: Block = _make_block(Vector3(0.5, effect.capture_height_m - 0.5, 0.0), 0)
	var too_high: Block = _make_block(Vector3(0.5, effect.capture_height_m + 1.0, 0.0), 0)
	above.freeze = true
	too_high.freeze = true
	var field: BlackHoleField = _make_field(effect)
	await wait_physics_frames(1)
	field.tick(effect.capture_hold_s + 0.05)
	assert_true((world[1] as BlockRegistry).hole_dissolver().is_dissolving(above), "pile layer above the old 0.8 m core")
	assert_false((world[1] as BlockRegistry).hole_dissolver().is_dissolving(too_high), "beyond the height band")
	assert_not_null(disc)
	Match.register_world(null, null, null)


func test_refused_dissolve_does_not_mark_the_block_and_hold_entries_are_cleaned() -> void:
	Match.set_process(false)
	Match.abort_match()
	Match.register_world(null, null, null)
	var effect: BlackHoleEffect = _effect()
	var core: Block = _make_block(Vector3(0.1, 0.0, 0.0), 0)
	var field: BlackHoleField = _make_field(effect)
	await wait_physics_frames(1)
	field.tick(effect.capture_hold_s + 0.1)
	assert_false(core.has_meta(RadialPull.CAPTURED_META), "refused: retried next tick")
	assert_true(field._hold_s.has(core.get_instance_id()))
	core.global_position = Vector3(effect.capture_radius_m + 3.0, 0.0, 0.0)
	await wait_physics_frames(1)
	field.tick(0.01)
	assert_false(field._hold_s.has(core.get_instance_id()), "left the volume: hold forgotten")


func test_shipped_resource_is_in_the_roster_with_a_black_hole_effect() -> void:
	var def: SpecialDef = SpecialDef.find_by_id(&"black_hole")
	assert_not_null(def)
	assert_true(def.effect is BlackHoleEffect)
	assert_gt(def.weight, 0.0)
	assert_true(def.enabled_by_default)
	var effect: BlackHoleEffect = def.effect as BlackHoleEffect
	assert_almost_eq(effect.pull.radius_m, 7.0, 0.0001)
	assert_almost_eq(effect.pull.accel_mps2, 26.0, 0.0001)
	assert_almost_eq(effect.pull.friction_compensation, 24.0, 0.0001, "above the ~22.5 breakaway value")
	assert_almost_eq(effect.pull.core_radius_m, 0.8, 0.0001)
	assert_almost_eq(effect.capture_radius_m, 2.0, 0.0001)
	assert_almost_eq(effect.capture_height_m, 3.0, 0.0001)
	assert_almost_eq(effect.capture_hold_s, 0.15, 0.0001)
	assert_almost_eq(effect.lifetime_s, 6.0, 0.0001)
	assert_true(effect.detaches(), "the field is a standalone world node")
	assert_almost_eq(effect.effect_lifetime_s(), -1.0, 0.0001, "the pre-trigger fuse is not stretched")


func test_detonate_spawns_a_field_at_the_block() -> void:
	var block: Block = _make_block(Vector3(1.0, 2.0, 3.0), 0)
	var effect: BlackHoleEffect = _effect()
	effect.detonate(block, null, 0)
	var fields: Array[Node] = []
	# Without a current_scene (GUT) the field falls back to the block's parent.
	fields.append_array(find_children("*", "BlackHoleField", true, false))
	assert_gt(fields.size(), 0, "detonate adds a BlackHoleField")
	for found: Node in fields:
		if is_instance_valid(found):
			found.free()


func test_client_builds_the_visual_from_the_replicated_trigger() -> void:
	Match.set_process(false)
	Match.abort_match()
	var tiny: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	tiny.field_radius = 20.0
	var field: Field = autofree(Field.new())
	field.map_def = tiny
	add_child_autofree(field)
	var blocks_root: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks_root)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	Match.register_world(field, registry, blocks_root)
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(tiny)
	config.player_count = 2
	config.hot_seat = false
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	var fake: FakeNet = FakeNet.client(1)
	Match.set_net_provider(fake)
	var net: MatchNetScript = MatchNetScript.new()
	net.set_process(false)
	add_child_autofree(net)
	net.set_providers(fake, Match)

	net.net_match_event(MatchNetScript.EVENT_SPECIAL_TRIGGERED, [7, &"black_hole", Vector3(1.0, 2.0, 3.0), 0])

	var visuals: Array[Node] = blocks_root.find_children("*", "BlackHoleVisual", true, false)
	assert_eq(visuals.size(), 1, "client draws the placeholder from the replicated activation")
	if visuals.size() == 1:
		assert_eq((visuals[0] as Node3D).global_position, Vector3(1.0, 2.0, 3.0))
	net.set_providers(null, null)
	Match.set_net_provider(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func test_match_bound_field_frees_itself_when_the_match_is_not_live() -> void:
	Match.set_process(false)
	Match.abort_match()
	var block: Block = _make_block(Vector3(2.0, 0.0, 0.0), 0)
	var field: BlackHoleField = _make_field(_effect())
	field.bind_to_match = true
	field.tick(0.1)
	assert_true(field.is_queued_for_deletion(), "field frees itself outside a live match")
	await wait_physics_frames(1)
	assert_eq(block.linear_velocity, Vector3.ZERO, "no pull while the match is not PLAYING")


func test_detonate_parents_the_field_under_the_match_world() -> void:
	Match.set_process(false)
	Match.abort_match()
	var blocks_root: Node3D = Node3D.new()
	add_child(blocks_root)
	Match.register_world(null, null, blocks_root)
	var block: Block = _make_block(Vector3(1.0, 2.0, 3.0), 0)
	_effect().detonate(block, null, 0)
	var fields: Array[Node] = blocks_root.find_children("*", "BlackHoleField", true, false)
	assert_eq(fields.size(), 1, "field lives in the per-match container")
	assert_true((fields[0] as BlackHoleField).bind_to_match)
	blocks_root.free()
	assert_eq(find_children("*", "BlackHoleField", true, false).size(), 0, "freed with the match world")


func test_vortex_growth_envelope_eases_in_and_collapses_out() -> void:
	assert_almost_eq(BlackHoleVisual.growth(0.0, 5.0, 0.4, 0.6), 0.0, 0.0001)
	assert_almost_eq(BlackHoleVisual.growth(1.0, 4.0, 0.4, 0.6), 1.0, 0.0001)
	assert_lt(BlackHoleVisual.growth(4.9, 0.1, 0.4, 0.6), 0.1, "nearly collapsed near the end")
	assert_almost_eq(BlackHoleVisual.growth(10.0, 0.0, 0.4, 0.6), 0.0, 0.0001)


func test_vortex_disc_matches_pull_radius_and_low_preset_drops_streaks() -> void:
	var def: SpecialDef = SpecialDef.find_by_id(&"black_hole")
	var effect: BlackHoleEffect = def.effect as BlackHoleEffect
	assert_not_null(def.held_scene, "black hole has a held gift model")
	assert_not_null(def.preview_icon, "black hole has a gift preview")
	var visual: BlackHoleVisual = BlackHoleVisual.new()
	add_child_autofree(visual)
	visual.setup(effect.visual_radius_m, effect.lifetime_s)
	var disc: MeshInstance3D = visual.get_child(0) as MeshInstance3D
	assert_eq((disc.mesh as PlaneMesh).size, Vector2.ONE * effect.pull_radius_m * 2.0, "disc covers the pull area")
	var material: ShaderMaterial = disc.material_override as ShaderMaterial
	var low: bool = not Settings.current_graphics_preset().ambient_life_enabled
	assert_eq(material.get_shader_parameter(&"streaks_on"), 0.0 if low else 1.0)
	var built: ShaderMaterial = visual._build_material(true)
	assert_eq(built.get_shader_parameter(&"streaks_on"), 0.0, "Low preset has no streaks")
	assert_lt(float(built.get_shader_parameter(&"arm_count")), float(visual._build_material(false).get_shader_parameter(&"arm_count")))
