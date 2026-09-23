extends GutTest
## RocketEffect (spec 2.6 "launches straight up, explodes when its fuel runs
## out"; docs/M4_SPECIALS_PACKAGES.md's P3-ROCKET package -- no homing, spec
## 2.6 explicitly drops the old plan's target lock). Two fixture shapes:
##
## - A stub-Block + real SpecialBehavior (no physics simulation) for the
##   armed/thrust/fuel-timer logic, mirroring
##   tests/unit/test_propeller_effect.gd's own fixture exactly (same
##   timed-effect pattern, driven by behavior.advance(delta) directly).
## - Real Block/RigidBody3D bodies added to the test's own tree (a physics
##   smoke test) for detonate(), mirroring tests/unit/test_bomb_effect.gd's
##   own fixture -- Rocket's detonate() is the identical
##   SpecialPhysics.explode() + trigger_others_in_range() shape, just with
##   Rocket's own numbers.

const TICK: float = 1.0 / 60.0


# --- stub-Block/def/behavior fixture (no physics, no scene tree) ------------

func _make_stub_block(position: Vector3 = Vector3.ZERO) -> Block:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	block.global_position = position
	block.mass = 1.0
	block.linear_velocity = Vector3.ZERO
	block.continuous_cd = false
	block.sleeping = false
	return block


func _make_def(effect: RocketEffect, arm_delay: float = 0.0) -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = &"rocket"
	def.arm_delay = arm_delay
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	def.effect = effect
	return def


func _make_behavior(block: Block, def: SpecialDef) -> SpecialBehavior:
	var tuning: SpecialTuning = SpecialTuning.new()
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	autofree(behavior)
	behavior.bind(block, def, tuning)
	return behavior


# --- inert before armed -------------------------------------------------------

func test_inert_before_armed() -> void:
	var effect: RocketEffect = RocketEffect.new()
	effect.launch_speed = 18.0
	var block: Block = _make_stub_block()
	block.linear_velocity = Vector3(0.0, -5.0, 0.0)  # falling
	var def: SpecialDef = _make_def(effect, 10.0)  # never arms within this test
	var behavior: SpecialBehavior = _make_behavior(block, def)

	behavior.advance(0.1)

	assert_eq(
		block.linear_velocity, Vector3(0.0, -5.0, 0.0), "must not thrust before arming"
	)
	assert_false(block.continuous_cd, "must not set continuous_cd before arming")
	assert_false(behavior.is_triggered())


# --- once armed: continuous thrust + continuous_cd every tick ---------------

func test_armed_tick_sets_velocity_to_launch_speed_and_continuous_cd() -> void:
	var effect: RocketEffect = RocketEffect.new()
	effect.launch_speed = 18.0
	var block: Block = _make_stub_block()
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect, 0.0))

	behavior.advance(0.1)

	assert_eq(block.linear_velocity, Vector3.UP * 18.0)
	assert_true(block.continuous_cd)


## Review-precedent guard (PropellerEffect.gd's Bontago-1en.6 fix): thrust
## must keep being written every armed tick even after the body looks "awake"
## (velocity manually reset to zero, as Jolt would after any external write),
## not just on the tick that first armed.
func test_thrust_and_continuous_cd_persist_every_tick_even_after_reset() -> void:
	var effect: RocketEffect = RocketEffect.new()
	effect.launch_speed = 18.0
	var block: Block = _make_stub_block()
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect, 0.0))

	behavior.advance(0.1)
	assert_eq(block.linear_velocity, Vector3.UP * 18.0)

	# Simulate an external reset (or Jolt-style wake) between ticks.
	block.linear_velocity = Vector3.ZERO
	block.continuous_cd = false

	for i: int in range(5):
		behavior.advance(0.1)
		assert_eq(
			block.linear_velocity, Vector3.UP * 18.0,
			"tick %d: must keep thrusting at launch_speed" % i
		)
		assert_true(block.continuous_cd, "tick %d: continuous_cd must stay true" % i)


# --- early-trigger exactly at fuel_duration_s, frame-rate independent -------

func test_wants_early_trigger_false_until_fuel_duration_s_elapses() -> void:
	var effect: RocketEffect = RocketEffect.new()
	effect.fuel_duration_s = 1.0
	var block: Block = _make_stub_block()
	var def: SpecialDef = _make_def(effect, 0.25)
	var behavior: SpecialBehavior = _make_behavior(block, def)

	for _i: int in range(4):
		behavior.advance(0.25)  # age reaches 1.0; elapsed-since-armed reaches 0.75
	assert_false(behavior.is_triggered(), "must not trigger before fuel_duration_s elapses")

	behavior.advance(0.25)  # age reaches 1.25 == arm_delay + fuel_duration_s
	assert_true(behavior.is_triggered(), "must trigger once fuel_duration_s elapses")


## Two different fixed step sizes must reach fuel_duration_s within about one
## tick's worth of simulated time of each other -- driven by simulation time,
## not tick count, mirroring test_propeller_effect.gd's own frame-rate test.
func test_fuel_duration_is_frame_rate_independent_at_two_fixed_deltas() -> void:
	var dt_a: float = 0.05
	var dt_b: float = 0.01

	# DECISION (tests/unit/test_rocket_effect.gd): unlike PropellerEffect's own
	# frame-rate test (detonate() is a no-op there), RocketEffect.detonate()
	# genuinely explodes and calls trigger_others_in_range() -- two blocks at
	# the shared Vector3.ZERO default position would have block_a's own
	# fuel-out explosion instantly chain-trigger block_b (distance 0 is always
	# within explosion_radius), making behavior_b look "already triggered"
	# before its own while loop below ever runs. Placed far enough apart
	# (200 m) that neither default explosion_radius (3.0) reaches the other.
	var effect_a: RocketEffect = RocketEffect.new()
	effect_a.fuel_duration_s = 1.0
	var block_a: Block = _make_stub_block(Vector3(-100.0, 0.0, 0.0))
	var behavior_a: SpecialBehavior = _make_behavior(block_a, _make_def(effect_a, 0.0))

	var effect_b: RocketEffect = RocketEffect.new()
	effect_b.fuel_duration_s = 1.0
	var block_b: Block = _make_stub_block(Vector3(100.0, 0.0, 0.0))
	var behavior_b: SpecialBehavior = _make_behavior(block_b, _make_def(effect_b, 0.0))

	var real_time_a: float = 0.0
	while not behavior_a.is_triggered() and real_time_a < 5.0:
		behavior_a.advance(dt_a)
		real_time_a += dt_a

	var real_time_b: float = 0.0
	while not behavior_b.is_triggered() and real_time_b < 5.0:
		behavior_b.advance(dt_b)
		real_time_b += dt_b

	assert_true(behavior_a.is_triggered(), "coarse ticks must eventually reach fuel_duration_s")
	assert_true(behavior_b.is_triggered(), "fine ticks must eventually reach fuel_duration_s")
	assert_almost_eq(
		real_time_a, real_time_b, dt_a + dt_b,
		"trigger time must be frame-rate independent within about one coarse tick"
	)


# --- two blocks sharing the effect keep independent fuel timers -------------

func test_two_blocks_with_the_same_def_keep_independent_fuel_timers() -> void:
	var effect: RocketEffect = RocketEffect.new()
	effect.fuel_duration_s = 1.0
	var shared_def: SpecialDef = _make_def(effect, 0.25)  # one SpecialDef/effect instance

	# DECISION (tests/unit/test_rocket_effect.gd): far enough apart (200 m)
	# that block_a's own fuel-out explosion/chain (RocketEffect.detonate()
	# is NOT a no-op, unlike Propeller's) cannot reach block_b -- see the
	# identical DECISION on test_fuel_duration_is_frame_rate_independent_at_
	# two_fixed_deltas() above for the full reasoning.
	var block_a: Block = _make_stub_block(Vector3(-100.0, 0.0, 0.0))
	var behavior_a: SpecialBehavior = _make_behavior(block_a, shared_def)

	var block_b: Block = _make_stub_block(Vector3(100.0, 0.0, 0.0))
	var behavior_b: SpecialBehavior = _make_behavior(block_b, shared_def)

	for _i: int in range(4):
		behavior_a.advance(0.25)  # block_a reaches age 1.0 (elapsed-since-armed 0.75)

	assert_false(behavior_a.is_triggered(), "setup: block_a not at fuel_duration_s yet either")
	assert_false(behavior_b.is_triggered(), "block_b's own timer must not have advanced at all")

	behavior_a.advance(0.25)  # block_a reaches age 1.25 == arm_delay + fuel_duration_s -> triggers
	assert_true(behavior_a.is_triggered(), "block_a's own elapsed timer must trigger it")
	assert_false(
		behavior_b.is_triggered(),
		"block_b's independent timer must not have been advanced by block_a's ticks"
	)


# --- physics-smoke fixture: real Block/RigidBody3D bodies in the test tree --

var _bodies: Array[Node3D] = []


## Synchronous free() -- not queue_free() -- mirroring tests/unit/
## test_special_physics.gd's/test_bomb_effect.gd's own after_each().
func after_each() -> void:
	for body: Node3D in _bodies:
		if is_instance_valid(body):
			body.free()
	_bodies.clear()


func _make_block(position: Vector3) -> Block:
	var block: Block = Block.new()
	block.mass = 1.0
	block.gravity_scale = 0.0
	block.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	block.linear_damp = 0.0
	block.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	block.angular_damp = 0.0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.3
	collision.shape = shape
	block.add_child(collision)
	add_child(block)
	block.global_position = position
	_bodies.append(block)
	return block


func _make_rigid_body(position: Vector3, mass: float = 1.0) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.mass = mass
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp = 0.0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.3
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	body.global_position = position
	_bodies.append(body)
	return body


## DECISION (tests/unit/test_rocket_effect.gd): disables the behavior's own
## _physics_process() right after bind() -- unlike BombEffect (no
## physics_tick() override, so this distinction never mattered for
## test_bomb_effect.gd), RocketEffect.physics_tick() writes real thrust
## velocity every armed tick. Left enabled, the awaits below (needed so the
## *explosion*'s applied impulse becomes visible in linear_velocity, exactly
## like test_special_physics.gd/test_bomb_effect.gd) would also let the
## rocket's own SpecialBehavior auto-tick via the real scene tree, thrusting
## it to launch_speed BEFORE the test's own explicit trigger(0) call --
## contaminating "was the rocket's own body excluded from its blast" with
## unrelated thrust velocity. These physics-smoke tests only care about
## detonate()'s own explode()+chain behavior (already exercised
## frame-by-frame, without any real physics stepping, by the stub-block
## fixture above), so ticking is driven explicitly via trigger() only.
func _make_physics_behavior(block: Block, effect: RocketEffect) -> SpecialBehavior:
	var def: SpecialDef = SpecialDef.new()
	def.id = &"rocket"
	def.arm_delay = 0.0
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	def.effect = effect
	var tuning: SpecialTuning = SpecialTuning.new()
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	behavior.bind(block, def, tuning)
	behavior.set_physics_process(false)
	return behavior


# --- detonate() behaves like Bomb, with Rocket's own numbers ----------------

func test_detonate_pushes_a_nearby_real_body_outward_with_rockets_own_numbers() -> void:
	var rocket_block: Block = _make_block(Vector3.ZERO)
	var nearby: RigidBody3D = _make_rigid_body(Vector3(1.5, 0.0, 0.0))  # within 3.0 radius
	var effect: RocketEffect = RocketEffect.new()
	effect.explosion_radius = 3.0
	effect.explosion_impulse = 14.0
	var behavior: SpecialBehavior = _make_physics_behavior(rocket_block, effect)
	await wait_physics_frames(1)

	behavior.trigger(0)
	await wait_physics_frames(1)

	assert_gt(nearby.linear_velocity.length(), 0.0, "a nearby body must gain velocity")
	assert_gt(
		nearby.linear_velocity.dot(Vector3(1.0, 0.0, 0.0)), 0.0, "the push must point outward"
	)


func test_detonate_excludes_the_rocket_itself_and_respects_radius() -> void:
	var rocket_block: Block = _make_block(Vector3.ZERO)
	var far_body: RigidBody3D = _make_rigid_body(Vector3(6.0, 0.0, 0.0))  # beyond 3.0 radius
	var effect: RocketEffect = RocketEffect.new()
	effect.explosion_radius = 3.0
	effect.explosion_impulse = 14.0
	var behavior: SpecialBehavior = _make_physics_behavior(rocket_block, effect)
	await wait_physics_frames(1)

	behavior.trigger(0)
	await wait_physics_frames(1)

	assert_eq(rocket_block.linear_velocity, Vector3.ZERO, "the rocket's own body must be excluded")
	assert_eq(far_body.linear_velocity, Vector3.ZERO, "a body beyond explosion_radius must be untouched")


func test_detonate_chains_into_a_nearby_special_one_depth_deeper() -> void:
	var rocket_block: Block = _make_block(Vector3.ZERO)
	var neighbor_block: Block = _make_block(Vector3(1.5, 0.0, 0.0))

	var rocket_effect: RocketEffect = RocketEffect.new()
	rocket_effect.explosion_radius = 3.0
	rocket_effect.explosion_impulse = 14.0
	var rocket_behavior: SpecialBehavior = _make_physics_behavior(rocket_block, rocket_effect)

	var neighbor_effect: RocketEffect = RocketEffect.new()
	var neighbor_behavior: SpecialBehavior = _make_physics_behavior(neighbor_block, neighbor_effect)
	await wait_physics_frames(1)

	rocket_behavior.trigger(0)
	await wait_physics_frames(1)

	assert_true(neighbor_behavior.is_triggered(), "must chain into a special within explosion_radius")
	assert_eq(neighbor_behavior.chain_depth(), 1)


# --- config/specials/rocket.tres loads with the contract defaults ----------

func test_rocket_tres_loads_with_expected_id_and_effect_defaults() -> void:
	var defs: Array[SpecialDef] = SpecialDef.load_all_specials()
	var found: SpecialDef = null
	for def: SpecialDef in defs:
		if def.id == &"rocket":
			found = def
			break
	assert_not_null(found, "config/specials/rocket.tres must be found by load_all_specials()")
	assert_true(found.effect is RocketEffect, "rocket.tres's effect sub-resource must be a RocketEffect")
	var effect: RocketEffect = found.effect as RocketEffect
	assert_eq(effect.launch_speed, 18.0)
	assert_eq(effect.fuel_duration_s, 1.5)
	assert_eq(effect.explosion_radius, 3.0)
	assert_eq(effect.explosion_impulse, 14.0)
	assert_not_null(effect.tuning, "tuning must fall back to the preloaded config/special_tuning.tres")
	assert_eq(effect.tuning.max_explosion_impulse, 30.0)
