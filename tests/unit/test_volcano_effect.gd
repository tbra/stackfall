extends GutTest
## VolcanoEffect / VolcanoOrbEffect (spec 2.6 "erupts, launching a spray of
## small lava-orb blocks that each explode"; docs/M4_SPECIALS_PACKAGES.md's
## P4-VOLCANO package). The eruption-timing/orb-spawning tests below reuse
## tests/unit/test_match_special_spawn.gd's own real host Match+MatchPlacement
## fixture (tiny map, TinyMapMatchConfig, manual countdown drive) verbatim,
## per that package's own brief -- VolcanoEffect.physics_tick() spawns real
## orbs through Match.spawn_special_projectile(), so a live host world is what
## makes that path exercised rather than silently no-op'd (off-host/no-world
## it returns null without error, which is a separate, deliberate case this
## file does not need to special-case). VolcanoOrbEffect's own chain-depth-cap
## test needs no Match world at all and instead mirrors
## tests/unit/test_bomb_effect.gd's bare Block+CollisionShape fixture.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _tuning: SpecialTuning


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	_tuning = (load("res://config/special_tuning.tres") as SpecialTuning).duplicate(true) as SpecialTuning


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	# Free synchronously (see test_match_special_spawn.gd's own after_each()
	# comment) -- GUT's end-of-script orphan check runs before the next idle
	# frame does.
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 13579
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func _cube_shape() -> BlockShape:
	return load("res://config/blocks/cube.tres") as BlockShape


func _pillar_shape() -> BlockShape:
	return load("res://config/blocks/pillar.tres") as BlockShape


## Review fix regression (Bontago-1en.3): the world-space AABB of `block`'s
## own actual CollisionShape3D children -- independent of VolcanoEffect's own
## _collision_top_y()/_shape_local_corners(), so this test verifies the real
## spawned volcano's collision geometry rather than re-deriving the same
## formula the production code uses. Only handles BoxShape3D (every shipped
## BlockShape's own collision) -- sufficient for pillar.tres, which has none
## of the dead sloped-cell branch's ConvexPolygonShape3D shapes.
func _block_world_aabb(block: Block) -> AABB:
	var aabb: AABB = AABB()
	var first: bool = true
	for child: Node in block.get_children():
		if not (child is CollisionShape3D):
			continue
		var collision: CollisionShape3D = child as CollisionShape3D
		var box: BoxShape3D = collision.shape as BoxShape3D
		if box == null:
			continue
		var half: Vector3 = box.size * 0.5
		for sign_combo: Vector3 in [
			Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1),
			Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(-1, 1, 1), Vector3(1, 1, 1),
		]:
			var corner: Vector3 = collision.global_transform * (half * sign_combo)
			if first:
				aabb = AABB(corner, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(corner)
	return aabb


func _volcano_def(effect: VolcanoEffect) -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = &"volcano_test"
	def.arm_delay = 0.0
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	def.effect = effect
	return def


func _find_behavior(block: Block) -> SpecialBehavior:
	for child: Node in block.get_children():
		if child is SpecialBehavior:
			return child as SpecialBehavior
	return null


# --- wants_early_trigger: false, then true at eruption_duration_s -----------

func test_wants_early_trigger_false_until_eruption_duration_elapses() -> void:
	Match.start_match(_config())
	_run_countdown()
	var effect: VolcanoEffect = VolcanoEffect.new()
	effect.eruption_duration_s = 1.0
	effect.min_orb_count = 1
	effect.max_orb_count = 1
	var volcano_block: Block = Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(0), Basis.IDENTITY, 0,
		Vector3.ZERO, _volcano_def(effect), _tuning
	)
	var behavior: SpecialBehavior = _find_behavior(volcano_block)
	assert_not_null(behavior, "fixture: a SpecialBehavior must be bound to the erupting block")
	var delta: float = 1.0 / Engine.physics_ticks_per_second

	for _i: int in range(int(ceil(effect.eruption_duration_s / delta)) - 1):
		behavior.advance(delta)
	assert_false(behavior.is_triggered(), "must not trigger before eruption_duration_s elapses")

	for _i: int in range(5):
		behavior.advance(delta)
	assert_true(behavior.is_triggered(), "must trigger once eruption_duration_s elapses")


## Two different fixed step sizes must trigger within about one coarse tick's
## worth of simulated time of each other -- driven by simulation time, not
## tick count, same shape as test_propeller_effect.gd's/test_earthquake_
## effect.gd's own frame-rate-independence tests.
func test_eruption_trigger_time_is_frame_rate_independent() -> void:
	Match.start_match(_config())
	_run_countdown()

	var effect_a: VolcanoEffect = VolcanoEffect.new()
	effect_a.eruption_duration_s = 1.0
	effect_a.min_orb_count = 1
	effect_a.max_orb_count = 1
	var block_a: Block = Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(0), Basis.IDENTITY, 0,
		Vector3.ZERO, _volcano_def(effect_a), _tuning
	)
	var behavior_a: SpecialBehavior = _find_behavior(block_a)

	var effect_b: VolcanoEffect = VolcanoEffect.new()
	effect_b.eruption_duration_s = 1.0
	effect_b.min_orb_count = 1
	effect_b.max_orb_count = 1
	var block_b: Block = Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(1), Basis.IDENTITY, 1,
		Vector3.ZERO, _volcano_def(effect_b), _tuning
	)
	var behavior_b: SpecialBehavior = _find_behavior(block_b)

	var dt_a: float = 0.05
	var dt_b: float = 0.01
	var real_time_a: float = 0.0
	while not behavior_a.is_triggered() and real_time_a < 5.0:
		behavior_a.advance(dt_a)
		real_time_a += dt_a
	var real_time_b: float = 0.0
	while not behavior_b.is_triggered() and real_time_b < 5.0:
		behavior_b.advance(dt_b)
		real_time_b += dt_b

	assert_true(behavior_a.is_triggered(), "coarse ticks must eventually reach eruption_duration_s")
	assert_true(behavior_b.is_triggered(), "fine ticks must eventually reach eruption_duration_s")
	assert_almost_eq(
		real_time_a, real_time_b, dt_a + dt_b,
		"trigger time must be frame-rate independent within about one coarse tick"
	)


# --- exactly orb_count orbs spawn over the eruption window ------------------

func test_exactly_orb_count_orbs_spawn_over_the_eruption_window() -> void:
	Match.start_match(_config())
	_run_countdown()
	var effect: VolcanoEffect = VolcanoEffect.new()
	effect.eruption_duration_s = 1.0
	effect.min_orb_count = 8
	effect.max_orb_count = 14
	effect.orb_impulse = 6.0
	var volcano_block: Block = Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(0), Basis.IDENTITY, 0,
		Vector3.ZERO, _volcano_def(effect), _tuning
	)
	var behavior: SpecialBehavior = _find_behavior(volcano_block)
	var before_count: int = _blocks_root.get_child_count()  # includes the volcano block itself
	var delta: float = 1.0 / Engine.physics_ticks_per_second
	var ticks: int = int(ceil(effect.eruption_duration_s / delta)) + 5
	for _i: int in range(ticks):
		behavior.advance(delta)

	assert_true(behavior.is_triggered(), "fixture: the eruption window must have fully elapsed")
	var drawn_orb_count: int = int(volcano_block.get_meta(&"volcano_orb_count"))
	assert_true(
		drawn_orb_count >= effect.min_orb_count and drawn_orb_count <= effect.max_orb_count,
		"drawn orb_count=%d must be within [min_orb_count, max_orb_count]" % drawn_orb_count
	)
	var spawned: int = _blocks_root.get_child_count() - before_count
	assert_eq(
		spawned, drawn_orb_count,
		"exactly the drawn orb_count must have spawned by the end of the eruption window"
	)


# --- each orb's velocity is inside the cone, at orb_impulse's magnitude -----

func test_each_orbs_velocity_is_within_the_cone_and_has_the_right_magnitude() -> void:
	Match.start_match(_config())
	_run_countdown()
	var effect: VolcanoEffect = VolcanoEffect.new()
	effect.eruption_duration_s = 1.0
	effect.min_orb_count = 10
	effect.max_orb_count = 10  # fixed, so every spawned block is a real orb to check
	effect.orb_impulse = 6.0
	effect.cone_angle_deg = 35.0
	var volcano_block: Block = Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(0), Basis.IDENTITY, 0,
		Vector3.ZERO, _volcano_def(effect), _tuning
	)
	var behavior: SpecialBehavior = _find_behavior(volcano_block)
	var delta: float = 1.0 / Engine.physics_ticks_per_second
	var ticks: int = int(ceil(effect.eruption_duration_s / delta)) + 5
	for _i: int in range(ticks):
		behavior.advance(delta)

	var orb_blocks: Array[Block] = []
	for child: Node in _blocks_root.get_children():
		if child is Block and child != volcano_block:
			orb_blocks.append(child as Block)
	assert_eq(orb_blocks.size(), 10, "fixture: min_orb_count == max_orb_count == 10")

	var cone_limit_rad: float = deg_to_rad(effect.cone_angle_deg) + 0.001
	for orb: Block in orb_blocks:
		var speed: float = orb.linear_velocity.length()
		assert_almost_eq(speed, effect.orb_impulse, 0.01, "orb speed must equal orb_impulse")
		var angle: float = orb.linear_velocity.angle_to(Vector3.UP)
		assert_true(
			angle <= cone_limit_rad,
			"orb velocity must stay within cone_angle_deg of UP (angle_deg=%.2f)" % rad_to_deg(angle)
		)


# --- Review fix regression: no orb spawns inside the volcano's own collision
# (Bontago-1en.3). Before the fix, _spawn_orb() added orb_spawn_height_offset_m
# (1.0 m) directly to block.global_position -- the shape's *bottom*-face
# centre -- so on a multi-cell shape (pillar: 3 stacked cubes, top ~2.5 m
# above that bottom centre) every orb spawned well inside the volcano's own
# collision box. Ran once before the fix: FAILED with
# "orb 0 spawned at (X, 6.0, Z) which is inside the volcano's own world AABB
# ... y=[5.0, 7.975]" (first orb of a pillar-shaped volcano at
# _home_world_position(0), y=5.0) -- exactly the reported bug.

func test_no_orb_spawns_inside_a_pillar_shaped_volcanos_own_collision() -> void:
	Match.start_match(_config())
	_run_countdown()
	var effect: VolcanoEffect = VolcanoEffect.new()
	effect.eruption_duration_s = 1.0
	effect.min_orb_count = 8
	effect.max_orb_count = 8  # fixed, so every spawn in this run is real
	effect.orb_impulse = 6.0
	var volcano_block: Block = Match.spawn_special_projectile(
		_pillar_shape(), _home_world_position(0), Basis.IDENTITY, 0,
		Vector3.ZERO, _volcano_def(effect), _tuning
	)
	var behavior: SpecialBehavior = _find_behavior(volcano_block)
	assert_not_null(behavior, "fixture: a SpecialBehavior must be bound to the erupting block")
	var volcano_aabb: AABB = _block_world_aabb(volcano_block)
	assert_true(volcano_aabb.size.y > 0.0, "fixture: pillar.tres must build a real collision AABB")

	var delta: float = 1.0 / Engine.physics_ticks_per_second
	var ticks: int = int(ceil(effect.eruption_duration_s / delta)) + 5
	for _i: int in range(ticks):
		behavior.advance(delta)

	assert_true(behavior.is_triggered(), "fixture: the eruption window must have fully elapsed")
	var orb_blocks: Array[Block] = []
	for child: Node in _blocks_root.get_children():
		if child is Block and child != volcano_block:
			orb_blocks.append(child as Block)
	assert_eq(orb_blocks.size(), 8, "fixture: min_orb_count == max_orb_count == 8")

	for i: int in range(orb_blocks.size()):
		var orb: Block = orb_blocks[i]
		assert_false(
			volcano_aabb.has_point(orb.global_position),
			(
				"orb %d spawned at %s which is inside the volcano's own world AABB "
				+ "position=%s size=%s"
			) % [i, orb.global_position, volcano_aabb.position, volcano_aabb.size]
		)


# --- Review fix regression: a spawn failure never over-counts _SPAWNED_META
# (Bontago-1en.3). Before the fix, physics_tick() incremented `spawned`
# unconditionally even when Match.spawn_special_projectile() returned null
# (e.g. mid-eruption the match stops being host/PLAYING), so the meta count
# and the real Block count silently diverged -- lost orbs with no trace. Ran
# once before the fix: FAILED with "meta says 8 orbs spawned but only 5 real
# Blocks exist" (5 real spawns while host, then 3 off-host ticks the old code
# still counted as spawned).

func test_a_spawn_failure_never_makes_spawned_meta_exceed_real_blocks_created() -> void:
	Match.start_match(_config())
	_run_countdown()
	var effect: VolcanoEffect = VolcanoEffect.new()
	effect.eruption_duration_s = 1.0
	effect.min_orb_count = 10
	effect.max_orb_count = 10  # fixed, so the exact spawn cadence is known
	effect.orb_impulse = 6.0
	var volcano_block: Block = Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(0), Basis.IDENTITY, 0,
		Vector3.ZERO, _volcano_def(effect), _tuning
	)
	var behavior: SpecialBehavior = _find_behavior(volcano_block)
	var delta: float = 1.0 / Engine.physics_ticks_per_second

	# A few ticks on-host: some real orbs spawn normally.
	for _i: int in range(int(ceil(effect.eruption_duration_s / delta / 4.0))):
		behavior.advance(delta)

	# Simulate the off-host case mid-eruption (docs/M4_SPECIALS_PACKAGES.md's
	# own brief: "Off-host spawn_special_projectile returns null -- handle it
	# without error") for a few ticks -- elapsed simulation time (and `due`)
	# keeps climbing regardless, but no real Block can be created.
	Match.set_net_provider(FakeNet.client(0))
	for _i: int in range(int(ceil(effect.eruption_duration_s / delta / 4.0))):
		behavior.advance(delta)

	# Back on host for the rest of the window.
	Match.set_net_provider(null)
	var remaining_ticks: int = int(ceil(effect.eruption_duration_s / delta)) + 5
	for _i: int in range(remaining_ticks):
		behavior.advance(delta)

	assert_true(behavior.is_triggered(), "fixture: the eruption window must have fully elapsed")
	var real_orb_count: int = 0
	for child: Node in _blocks_root.get_children():
		if child is Block and child != volcano_block:
			real_orb_count += 1
	var spawned_meta: int = int(volcano_block.get_meta(&"volcano_orbs_spawned"))
	assert_eq(
		spawned_meta, real_orb_count,
		"meta says %d orbs spawned but only %d real Blocks exist" % [spawned_meta, real_orb_count]
	)


# --- VolcanoOrbEffect.detonate() respects the chain-depth cap ---------------
# Bare Block+CollisionShape fixture, no Match world -- mirrors
# tests/unit/test_bomb_effect.gd's own shape exactly.

func _make_bare_block(position: Vector3) -> Block:
	var block: Block = Block.new()
	block.mass = 1.0
	block.gravity_scale = 0.0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.3
	collision.shape = shape
	block.add_child(collision)
	# add_child() before setting global_position -- Node3D.global_position
	# needs is_inside_tree() to resolve a global transform.
	add_child(block)
	autofree(block)
	block.global_position = position
	return block


func _make_bare_behavior(block: Block, effect: SpecialEffect, tuning: SpecialTuning) -> SpecialBehavior:
	var def: SpecialDef = SpecialDef.new()
	def.arm_delay = 0.0
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	def.effect = effect
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	autofree(behavior)
	behavior.bind(block, def, tuning)
	return behavior


func test_volcano_orb_effect_detonate_respects_the_chain_depth_cap() -> void:
	var tuning: SpecialTuning = SpecialTuning.new()
	tuning.max_chain_depth = 2

	var orb_block: Block = _make_bare_block(Vector3.ZERO)
	var orb_effect: VolcanoOrbEffect = VolcanoOrbEffect.new()
	orb_effect.tuning = tuning
	orb_effect.explosion_radius = 3.0
	orb_effect.explosion_impulse = 10.0
	var orb_behavior: SpecialBehavior = _make_bare_behavior(orb_block, orb_effect, tuning)

	var neighbor_block: Block = _make_bare_block(Vector3(0.5, 0.0, 0.0))
	var neighbor_behavior: SpecialBehavior = _make_bare_behavior(
		neighbor_block, VolcanoOrbEffect.new(), tuning
	)
	await wait_physics_frames(1)

	orb_behavior.trigger(tuning.max_chain_depth)  # already at the cap
	await wait_physics_frames(1)

	assert_true(orb_behavior.is_triggered())
	assert_false(
		neighbor_behavior.is_triggered(),
		"a chain reaction at max_chain_depth must not extend to a nearby armed special"
	)


func test_volcano_orb_effect_chains_into_a_nearby_special_below_the_cap() -> void:
	var tuning: SpecialTuning = SpecialTuning.new()
	tuning.max_chain_depth = 4

	var orb_block: Block = _make_bare_block(Vector3.ZERO)
	var orb_effect: VolcanoOrbEffect = VolcanoOrbEffect.new()
	orb_effect.tuning = tuning
	orb_effect.explosion_radius = 3.0
	orb_effect.explosion_impulse = 10.0
	var orb_behavior: SpecialBehavior = _make_bare_behavior(orb_block, orb_effect, tuning)

	var neighbor_block: Block = _make_bare_block(Vector3(0.5, 0.0, 0.0))
	var neighbor_behavior: SpecialBehavior = _make_bare_behavior(
		neighbor_block, VolcanoOrbEffect.new(), tuning
	)
	await wait_physics_frames(1)

	orb_behavior.trigger(0)  # well below the cap
	await wait_physics_frames(1)

	assert_true(orb_behavior.is_triggered())
	assert_true(
		neighbor_behavior.is_triggered(),
		"a chain reaction below max_chain_depth must reach a nearby armed special"
	)
	assert_eq(neighbor_behavior.chain_depth(), 1)


# --- config/specials/volcano.tres loads with the contract defaults ----------

func test_volcano_tres_loads_with_contract_defaults() -> void:
	var defs: Array[SpecialDef] = SpecialDef.load_all_specials()
	var found: SpecialDef = null
	for def: SpecialDef in defs:
		if def.id == &"volcano":
			found = def
			break
	assert_not_null(found, "config/specials/volcano.tres must be found by load_all_specials()")
	assert_true(found.effect is VolcanoEffect, "volcano.tres's effect sub-resource must be a VolcanoEffect")
	var effect: VolcanoEffect = found.effect as VolcanoEffect
	assert_eq(effect.eruption_duration_s, 3.0)
	assert_eq(effect.min_orb_count, 8)
	assert_eq(effect.max_orb_count, 14)
	assert_eq(effect.orb_impulse, 6.0)
	assert_eq(effect.cone_angle_deg, 35.0)
	assert_eq(effect.orb_explosion_radius, 1.5)
	assert_eq(effect.orb_explosion_impulse_fraction, 0.5)
	assert_not_null(effect.tuning, "tuning must fall back to the preloaded config/special_tuning.tres")
	assert_eq(effect.tuning.max_explosion_impulse, 30.0)


# --- physics smoke: a hard landing on the arming tick must not detonate ----
# --- the volcano before the eruption ever ran (Bontago-1en.22) -------------

## Reproduces the reported bug with a real BlockFactory-built cube, this
## fixture's own real Field (before_each(), 20 m radius) and a real
## SpecialBehavior bound to the real config/specials/volcano.tres def
## (arm_delay = 0.4, arm_impulse = 5.0) -- dropped from ~2 m so it lands well
## after arm_delay has elapsed (fall time for 2 m under standard gravity is
## ~0.64 s > 0.4 s). Before the fix, the landing's own deceleration
## (comfortably over arm_impulse = 5.0) called trigger(0) before
## VolcanoEffect.physics_tick() ever ran a single armed tick, so the eruption
## silently never spawned an orb and the volcano just "activated" as a no-op
## detonate() the moment it touched down.
func test_real_physics_hard_landing_does_not_prematurely_impact_trigger() -> void:
	var defs: Array[SpecialDef] = SpecialDef.load_all_specials()
	var found: SpecialDef = null
	for def: SpecialDef in defs:
		if def.id == &"volcano":
			found = def
			break
	assert_not_null(found, "config/specials/volcano.tres must be found by load_all_specials()")

	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var block: Block = BlockFactory.build(_cube_shape(), tuning)
	add_child_autofree(block)
	block.global_position = Vector3(0.0, _field.surface_y() + 2.0, 0.0)  # disk centre, ~2 m drop

	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	autofree(behavior)
	behavior.bind(block, found, SpecialTuning.new())

	var settle_ticks: int = 0
	while not block.sleeping and settle_ticks < 180:
		await wait_physics_frames(1)
		settle_ticks += 1

	assert_true(block.sleeping, "setup: the volcano must settle from its ~2 m drop")
	assert_false(
		behavior.is_triggered(),
		"a hard landing on the arming tick must not detonate the volcano before the eruption ever ran"
	)
	assert_true(
		block.has_meta(&"volcano_start_age"),
		"physics_tick() must have run and seeded its own start-age instead of being skipped by a premature trigger"
	)
