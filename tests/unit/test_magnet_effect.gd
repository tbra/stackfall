extends GutTest
## MagnetEffect (docs/SPEC.md ~line 252 "Pulls enemy blocks within 8 m toward
## itself for 3 s"; docs/M8_PLAN.md P1 package). Real Block bodies added
## directly to the test's own tree -- a physics smoke test, same shape as
## tests/unit/test_bomb_effect.gd/tests/unit/test_special_physics.gd --
## proving MagnetEffect.physics_tick() actually needs a real
## PhysicsDirectSpaceState3D (SpecialPhysics.query_bodies_in_range()'s own
## contract), so a bare stub Block with no collider would never be found by
## the query in the first place.

const RADIUS: float = 8.0
const FORCE: float = 20.0

var _bodies: Array[Node3D] = []


## Synchronous free() -- not queue_free() -- so no stale collider lingers in
## the physics world for even one frame into the next test, mirroring
## tests/unit/test_bomb_effect.gd's own after_each().
func after_each() -> void:
	for body: Node3D in _bodies:
		if is_instance_valid(body):
			body.free()
	_bodies.clear()


## A real Block (not a bare RigidBody3D) with a small sphere collider, so
## physics_tick() can call block.get_world_3d()/query the real space state
## exactly like the production path does. Gravity and damping are turned off
## so a one-tick velocity read reflects only the pull's own impulse.
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
	# DECISION (tests/unit/test_magnet_effect.gd, matches
	# tests/unit/test_special_physics.gd's own DECISION): add_child() before
	# setting global_position -- Node3D.global_position needs is_inside_tree()
	# to resolve a global transform.
	add_child(block)
	block.global_position = position
	_bodies.append(block)
	return block


func _make_behavior(block: Block, effect: MagnetEffect, arm_delay: float = 0.0) -> SpecialBehavior:
	var def: SpecialDef = SpecialDef.new()
	def.id = &"magnet"
	def.arm_delay = arm_delay
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	def.effect = effect
	var tuning: SpecialTuning = SpecialTuning.new()
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	# DECISION (tests/unit/test_magnet_effect.gd): SpecialBehavior defines
	# _physics_process(), so once `behavior` is inside the tree Godot's own
	# physics loop would call advance() with the real per-frame delta during
	# every `await wait_physics_frames(...)` below -- a hidden extra tick this
	# test's own hand-counted "advance(0.1) -> elapsed" comments don't
	# account for (found via test_pull_stops_once_pull_duration_elapses()
	# triggering one tick earlier than expected). Every test here drives
	# timing exclusively through explicit behavior.advance(delta) calls, so
	# the node's own automatic per-frame ticking must stay off.
	behavior.set_physics_process(false)
	behavior.bind(block, def, tuning)
	return behavior


# --- (a) an enemy block gets pulled toward the magnet ------------------------

func test_enemy_block_gets_pulled_toward_the_magnet() -> void:
	var magnet_block: Block = _make_block(Vector3.ZERO)
	magnet_block.owner_slot = 0
	var enemy_block: Block = _make_block(Vector3(RADIUS * 0.5, 0.0, 0.0))
	enemy_block.owner_slot = 1
	var effect: MagnetEffect = MagnetEffect.new()
	effect.pull_radius_m = RADIUS
	effect.pull_duration_s = 3.0
	effect.pull_force = FORCE
	var behavior: SpecialBehavior = _make_behavior(magnet_block, effect)
	await wait_physics_frames(1)

	behavior.advance(0.1)
	# DECISION (tests/unit/test_magnet_effect.gd, matches
	# tests/unit/test_bomb_effect.gd's own test_detonate_pushes_a_nearby_
	# real_body_outward): apply_impulse() called from a manual advance() (not
	# from inside an actual physics step) only reaches RigidBody3D's own
	# cached linear_velocity once the next physics frame syncs server state
	# back to the node -- so a frame must elapse before this reads correctly.
	await wait_physics_frames(1)

	assert_gt(
		enemy_block.linear_velocity.length(), 0.0, "an enemy block in range must gain velocity from the pull"
	)
	assert_gt(
		enemy_block.linear_velocity.dot(Vector3(-1.0, 0.0, 0.0)),
		0.0,
		"the pull must point inward, toward the magnet's own position"
	)


# --- (b) an own-owner block at the same distance is untouched ----------------

func test_own_owner_block_is_untouched() -> void:
	var magnet_block: Block = _make_block(Vector3.ZERO)
	magnet_block.owner_slot = 0
	var own_block: Block = _make_block(Vector3(RADIUS * 0.5, 0.0, 0.0))
	own_block.owner_slot = 0
	var effect: MagnetEffect = MagnetEffect.new()
	effect.pull_radius_m = RADIUS
	effect.pull_duration_s = 3.0
	effect.pull_force = FORCE
	var behavior: SpecialBehavior = _make_behavior(magnet_block, effect)
	await wait_physics_frames(1)

	behavior.advance(0.1)
	await wait_physics_frames(1)

	assert_eq(
		own_block.linear_velocity,
		Vector3.ZERO,
		"a block owned by the same slot as the magnet must be excluded from the pull"
	)


# --- (c) the pull stops once pull_duration_s has elapsed ---------------------

func test_pull_stops_once_pull_duration_elapses() -> void:
	var magnet_block: Block = _make_block(Vector3.ZERO)
	magnet_block.owner_slot = 0
	var enemy_block: Block = _make_block(Vector3(RADIUS * 0.5, 0.0, 0.0))
	enemy_block.owner_slot = 1
	var effect: MagnetEffect = MagnetEffect.new()
	effect.pull_radius_m = RADIUS
	effect.pull_duration_s = 0.2
	effect.pull_force = FORCE
	var behavior: SpecialBehavior = _make_behavior(magnet_block, effect)
	await wait_physics_frames(1)

	behavior.advance(0.1)  # arms + first physics_tick this same tick; start_age == 0.1
	assert_false(behavior.is_triggered(), "must not trigger before pull_duration_s has elapsed")
	behavior.advance(0.1)  # elapsed == 0.1, still short of 0.2
	assert_false(
		behavior.is_triggered(), "must still not trigger with elapsed short of pull_duration_s"
	)
	behavior.advance(0.1)  # elapsed == 0.2 >= pull_duration_s
	assert_true(
		behavior.is_triggered(), "must trigger once elapsed time reaches pull_duration_s"
	)


# --- Magnet keeps SpecialEffect's impact_triggers() vetoed, like Propeller ---

func test_impact_triggers_is_vetoed_so_a_hard_landing_cannot_skip_the_pull() -> void:
	var magnet_block: Block = _make_block(Vector3.ZERO)
	var effect: MagnetEffect = MagnetEffect.new()
	assert_false(
		effect.impact_triggers(magnet_block, null),
		"MagnetEffect must veto impact_triggers() like every other timed-effect special"
	)


# --- config/specials/magnet.tres loads with the contract defaults -----------

func test_magnet_tres_loads_with_expected_id_and_effect_defaults() -> void:
	var defs: Array[SpecialDef] = SpecialDef.load_all_specials()
	var found: SpecialDef = null
	for def: SpecialDef in defs:
		if def.id == &"magnet":
			found = def
			break
	assert_not_null(found, "config/specials/magnet.tres must be found by load_all_specials()")
	assert_true(found.effect is MagnetEffect, "magnet.tres's effect sub-resource must be a MagnetEffect")
	var effect: MagnetEffect = found.effect as MagnetEffect
	assert_eq(effect.pull_radius_m, 8.0)
	assert_eq(effect.pull_duration_s, 3.0)
	assert_eq(effect.pull_force, 20.0)
	assert_not_null(effect.tuning, "tuning must fall back to the preloaded config/special_tuning.tres")
