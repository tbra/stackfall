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
const FAR_AWAY_M: float = 200.0

var _bodies: Array[Node3D] = []


## Synchronous free() -- not queue_free() -- so no stale collider lingers in the physics
## world for even one frame into the next test.
func after_each() -> void:
	for body: Node3D in _bodies:
		if is_instance_valid(body):
			body.free()
	_bodies.clear()


func _bomb_def() -> SpecialDef:
	return load("res://config/specials/bomb.tres") as SpecialDef


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


func test_detonate_does_not_push_the_bomb_itself() -> void:
	var bomb_block: Block = _make_block(Vector3.ZERO)
	var behavior: SpecialBehavior = _make_behavior(bomb_block)
	await wait_physics_frames(1)

	behavior.trigger(0)
	await wait_physics_frames(1)

	assert_eq(bomb_block.linear_velocity, Vector3.ZERO, "the bomb's own body is excluded from its blast")


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


func test_trigger_does_not_chain_into_a_special_beyond_radius() -> void:
	var bomb_block: Block = _make_block(Vector3.ZERO)
	var far_block: Block = _make_block(Vector3(_radius() * FAR_FACTOR, 0.0, 0.0))
	var bomb_behavior: SpecialBehavior = _make_behavior(bomb_block)
	var far_behavior: SpecialBehavior = _make_behavior(far_block)
	await wait_physics_frames(1)

	bomb_behavior.trigger(0)
	await wait_physics_frames(1)

	assert_false(far_behavior.is_triggered(), "a special beyond the radius is not chained into")


# --- timeline: blink, then blast; impacts never trigger it ------------------

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


func test_blink_timeline_is_frame_rate_independent() -> void:
	var effect: BombEffect = _bomb_def().effect as BombEffect
	var block_a: Block = _make_block(Vector3(-FAR_AWAY_M, 0.0, 0.0))
	var behavior_a: SpecialBehavior = _make_behavior(block_a)
	var block_b: Block = _make_block(Vector3(FAR_AWAY_M, 0.0, 0.0))
	var behavior_b: SpecialBehavior = _make_behavior(block_b)
	var coarse: float = 0.05
	var fine: float = 0.01
	var time_a: float = 0.0
	while not behavior_a.is_triggered() and time_a < 2.0 * effect.blink_duration_s:
		behavior_a.advance(coarse)
		time_a += coarse
	var time_b: float = 0.0
	while not behavior_b.is_triggered() and time_b < 2.0 * effect.blink_duration_s:
		behavior_b.advance(fine)
		time_b += fine
	assert_true(behavior_a.is_triggered() and behavior_b.is_triggered())
	assert_almost_eq(time_a, time_b, coarse + fine, "trigger time follows simulated time, not tick count")


## A hard landing used to detonate the Bomb. It must not any more ("regardless of impacts").
func test_a_hard_impact_does_not_trigger_the_bomb() -> void:
	var block: Block = _make_block(Vector3.ZERO)
	var behavior: SpecialBehavior = _make_behavior(block)
	behavior.advance(0.5)  # armed (arm_delay 0.4), decel sampled against itself
	block.linear_velocity = Vector3(10.0, 0.0, 0.0)
	behavior.advance(TICK)
	block.linear_velocity = Vector3.ZERO  # mass 1 * (10 - 0) = 10 >= arm_impulse 5
	behavior.advance(TICK)
	assert_false(behavior.is_triggered(), "an impact does not set the Bomb off")


# --- hooks, blink, despawn ---------------------------------------------------

func test_lifecycle_hooks() -> void:
	var effect: BombEffect = _bomb_def().effect as BombEffect
	assert_false(effect.triggers_on_impact(), "never triggers on impact")
	assert_true(effect.detaches(), "the spent carrier goes at the explosion")
	assert_false(effect.needs_landing(), "blink and blast are anchored to the drop, not to a landing")
	assert_eq(effect.effect_lifetime_s(), effect.blink_duration_s)


func test_the_carrier_is_removed_at_the_explosion_without_a_linger() -> void:
	var block: Block = _make_block(Vector3.ZERO)
	var behavior: SpecialBehavior = _make_behavior(block)
	behavior.despawn_when_done = true
	watch_signals(behavior)
	behavior.trigger(0)
	assert_signal_emit_count(behavior, "completed", 1, "completed right at trigger (detaches)")


func _block_with_gift_visual(position: Vector3) -> Block:
	var block: Block = _make_block(position)
	var visual: Node3D = Node3D.new()
	visual.name = BlockFactory.GIFT_VISUAL_NODE
	visual.add_child(MeshInstance3D.new())
	block.add_child(visual)
	return block


## Host fallback: with nobody having started the blink at spawn, the first armed tick starts it
## carrying the gift's age, exactly once.
func test_the_first_armed_tick_starts_the_blink_once_with_the_gifts_age() -> void:
	var block: Block = _block_with_gift_visual(Vector3.ZERO)
	var behavior: SpecialBehavior = _make_behavior(block)
	behavior.advance(0.2)
	assert_null(block.get_node_or_null(NodePath(String(GiftBlink.DRIVER_NAME))), "not armed yet: no blink")
	behavior.advance(0.3)  # age 0.5, armed
	var driver: Node = block.get_node_or_null(NodePath(String(GiftBlink.DRIVER_NAME)))
	assert_not_null(driver, "blink started on the first armed tick")
	assert_almost_eq(float(driver.get("age_s")), behavior.age(), 0.0001, "it carries the gift's age")
	behavior.advance(0.3)
	assert_eq(block.get_node_or_null(NodePath(String(GiftBlink.DRIVER_NAME))), driver, "not restarted")


func test_an_existing_blink_from_the_spawn_hook_is_left_alone() -> void:
	var block: Block = _block_with_gift_visual(Vector3.ZERO)
	var effect: BombEffect = _bomb_def().effect as BombEffect
	GiftBlink.apply(block, effect.blink_period_s, effect.blink_duration_s, effect.blink_tuning)
	var driver: Node = block.get_node(NodePath(String(GiftBlink.DRIVER_NAME)))
	var behavior: SpecialBehavior = _make_behavior(block)
	behavior.advance(0.5)
	assert_eq(block.get_node_or_null(NodePath(String(GiftBlink.DRIVER_NAME))), driver, "the spawn-started blink stays")


func test_start_for_gift_derives_the_blink_from_the_gift_id_alone() -> void:
	var block: Block = _block_with_gift_visual(Vector3.ZERO)
	block.gift_id = &"bomb"
	assert_true(GiftBlink.start_for_gift(block), "a Bomb carrier starts blinking from its gift id")
	var driver: Node = block.get_node_or_null(NodePath(String(GiftBlink.DRIVER_NAME)))
	assert_not_null(driver)
	assert_true(GiftBlink.start_for_gift(block), "idempotent")
	assert_eq(block.get_node_or_null(NodePath(String(GiftBlink.DRIVER_NAME))), driver)
	var other: Block = _block_with_gift_visual(Vector3(FAR_AWAY_M, 0.0, 0.0))
	other.gift_id = &"anvil"
	assert_false(GiftBlink.start_for_gift(other), "a gift that does not blink is ignored")
	assert_false(GiftBlink.start_for_gift(null))


# --- config/specials/bomb.tres ----------------------------------------------

func test_bomb_tres_loads_with_the_plan_numbers() -> void:
	var found: SpecialDef = null
	for def: SpecialDef in SpecialDef.load_all_specials():
		if def.id == &"bomb":
			found = def
			break
	assert_not_null(found, "config/specials/bomb.tres is found by load_all_specials()")
	assert_true(found.effect is BombEffect, "bomb.tres's effect is a BombEffect")
	var effect: BombEffect = found.effect as BombEffect
	assert_eq(effect.blink_duration_s, 3.0)
	assert_eq(effect.blink_period_s, 0.25)
	assert_eq(effect.blast.radius_m, 5.0)
	assert_eq(effect.blast.peak_speed_mps, 12.0)
	assert_eq(effect.blast.falloff_exponent, 1.5)
	assert_eq(effect.blast.upward_bias, 0.35)
	assert_eq(effect.blast.max_delta_v_mps, 16.0)
	assert_eq(effect.blink_tuning.end_period_ratio, 0.4)
	assert_eq(effect.blink_tuning.flash_color, Color(1.0, 0.25, 0.1))
	assert_eq(effect.blink_tuning.flash_max_alpha, 0.55)
