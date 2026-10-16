extends GutTest
## BombEffect after the 2026-10-05 owner decision (Bontago-1pi.85.10, docs/SPEC.md 2.6,
## docs/GIFT_EFFECTS_PLAN.md section 3): the Bomb blinks for blink_duration_s from the drop,
## then blasts with ExplosionFx, regardless of impacts; a chain trigger still sets it off
## early. Two fixture shapes:
##
## - Real Block/RigidBody3D bodies in the test's own tree (physics smoke test) for the blast,
##   exclusion, radius cutoff, mass independence and chain.
## - A stub Block driven through SpecialBehavior.advance() (no physics stepping) for the
##   timeline: no explosion before the blink ends, impacts ignored, host blink start.
## The six-neighbour Field acceptance lives in test_gift_blast_blocks.gd.

const TICK: float = 1.0 / 60.0
const NEAR_FRACTION: float = 0.4
const MIN_PUSH_MPS: float = 3.0
const HEAVY_MASS: float = 8.0
const MASS_TOLERANCE_MPS: float = 0.5
const FAR_FACTOR: float = 1.5
var _bodies: Array[Node3D] = []


## Synchronous free() -- not queue_free() -- so no stale collider lingers in the physics
## world for even one frame into the next test.
func after_each() -> void:
	for body: Node3D in _bodies:
		if is_instance_valid(body):
			body.free()
	_bodies.clear()


func _bomb_def() -> SpecialDef:
	return load("res://config/gifts/specials/bomb.tres") as SpecialDef


## A real Block (not a bare RigidBody3D) with a small sphere collider, so detonate() can call
## block.get_world_3d()/block.get_rid() exactly like the production path does. Gravity and
## damping are turned off so a one-frame velocity read reflects only the blast.
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
	# add_child() before setting global_position: Node3D.global_position needs
	# is_inside_tree() to resolve a global transform.
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


## Binds a SpecialBehavior to `block` with the shipped bomb.tres def (arm_delay 0.4, blink 3.0 s).
## Ticking is driven explicitly (advance()/trigger()), never by the scene tree.
func _make_behavior(block: Block, def: SpecialDef = null) -> SpecialBehavior:
	var use_def: SpecialDef = def if def != null else _bomb_def()
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	behavior.bind(block, use_def, SpecialTuning.new())
	behavior.set_physics_process(false)
	return behavior


func _radius() -> float:
	return (_bomb_def().effect as BombEffect).blast.radius_m


# --- the blast: outward, mass independent, bounded --------------------------

func test_detonate_pushes_a_nearby_real_body_outward() -> void:
	var bomb_block: Block = _make_block(Vector3.ZERO)
	var nearby: RigidBody3D = _make_rigid_body(Vector3(_radius() * NEAR_FRACTION, 0.0, 0.0))
	var behavior: SpecialBehavior = _make_behavior(bomb_block)
	await wait_physics_frames(1)

	behavior.trigger(0)
	await wait_physics_frames(1)

	assert_gt(nearby.linear_velocity.x, MIN_PUSH_MPS, "a nearby body is blown outward, away from the bomb")


func test_blast_is_independent_of_mass() -> void:
	var bomb_block: Block = _make_block(Vector3.ZERO)
	var light: RigidBody3D = _make_rigid_body(Vector3(_radius() * NEAR_FRACTION, 0.0, 0.0), 1.0)
	var heavy: RigidBody3D = _make_rigid_body(Vector3(-_radius() * NEAR_FRACTION, 0.0, 0.0), HEAVY_MASS)
	var behavior: SpecialBehavior = _make_behavior(bomb_block)
	await wait_physics_frames(1)

	behavior.trigger(0)
	await wait_physics_frames(1)

	assert_gt(-heavy.linear_velocity.x, MIN_PUSH_MPS, "an 8 kg body is blown away as well")
	assert_almost_eq(
		light.linear_velocity.x, -heavy.linear_velocity.x, MASS_TOLERANCE_MPS, "same distance, same delta-v whatever the mass"
	)


func test_body_beyond_radius_is_untouched() -> void:
	var bomb_block: Block = _make_block(Vector3.ZERO)
	var far_body: RigidBody3D = _make_rigid_body(Vector3(_radius() * FAR_FACTOR, 0.0, 0.0))
	var behavior: SpecialBehavior = _make_behavior(bomb_block)
	await wait_physics_frames(1)

	behavior.trigger(0)
	await wait_physics_frames(1)

	assert_eq(far_body.linear_velocity, Vector3.ZERO, "a body beyond the blast radius is untouched")


# --- chain trigger -----------------------------------------------------------

func test_trigger_chains_into_a_nearby_special_one_depth_deeper() -> void:
	var bomb_block: Block = _make_block(Vector3.ZERO)
	var neighbor_block: Block = _make_block(Vector3(_radius() * NEAR_FRACTION, 0.0, 0.0))
	var bomb_behavior: SpecialBehavior = _make_behavior(bomb_block)
	var neighbor_behavior: SpecialBehavior = _make_behavior(neighbor_block)
	await wait_physics_frames(1)

	bomb_behavior.trigger(0)
	await wait_physics_frames(1)

	assert_true(neighbor_behavior.is_triggered(), "a blast sets off a special within its radius, blink or not")
	assert_eq(neighbor_behavior.chain_depth(), 1, "a chained trigger is exactly one depth deeper")


## Advances `behavior` tick by tick until it triggers or `limit_s` of simulated time passed;
## returns the behaviour's age at that point.
func _run_until_triggered(behavior: SpecialBehavior, limit_s: float) -> float:
	var steps: int = int(ceil(limit_s / TICK))
	for _i: int in range(steps):
		if behavior.is_triggered():
			break
		behavior.advance(TICK)
	return behavior.age()


func test_no_explosion_before_the_blink_ends_then_it_explodes() -> void:
	var effect: BombEffect = _bomb_def().effect as BombEffect
	var block: Block = _make_block(Vector3.ZERO)
	var behavior: SpecialBehavior = _make_behavior(block)

	var age: float = _run_until_triggered(behavior, effect.blink_duration_s - 2.0 * TICK)
	assert_false(behavior.is_triggered(), "still blinking at %.2f s" % age)

	age = _run_until_triggered(behavior, 4.0 * TICK)
	assert_true(behavior.is_triggered(), "explodes once the blink is over")
	assert_almost_eq(age, effect.blink_duration_s, 2.0 * TICK, "explosion lands at the end of the blink")


func test_the_carrier_is_removed_at_the_explosion_without_a_linger() -> void:
	var block: Block = _make_block(Vector3.ZERO)
	var behavior: SpecialBehavior = _make_behavior(block)
	behavior.despawn_when_done = true
	watch_signals(behavior)
	behavior.trigger(0)
	assert_signal_emit_count(behavior, "completed", 1, "completed right at trigger (detaches)")
