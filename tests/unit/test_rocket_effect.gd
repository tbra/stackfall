extends GutTest
## RocketEffect after the 2026-10-05 owner decision (Bontago-1pi.85.10, docs/SPEC.md 2.6,
## docs/GIFT_EFFECTS_PLAN.md section 3): on activation the Rocket flies a straight line along a
## host-side launch direction (camera direction, never upward) and explodes on the first contact
## with a block, the disc or the map; the safety fuel still fires. Fixtures:
##
## - A stub Block + real SpecialBehavior driven by advance() (no physics stepping) for the
##   launch, direction input, fuel timer and per-block state.
## - SpecialBehavior.impact_filter() on its own (the owner-grace contact filter).
## - Real bodies, a real StaticBody3D wall and a real Field, ticking through the scene tree, for
##   "explodes on first contact (block, disc), never mid-air, own blocks ignored during the grace".

const TICK: float = 1.0 / 60.0
const SPEED_TOLERANCE_MPS: float = 0.01
const MAX_RUN_FRAMES: int = 420
const WALL_X_M: float = 8.0
const WALL_HALF_THICKNESS_M: float = 0.5
const BODY_RADIUS_M: float = 0.3
const OWN_BLOCK_AHEAD_M: float = 1.2
const HEAVY_MASS_KG: float = 1000.0
const SETTLE_FRAMES: int = 20
const DISC_DROP_HEIGHT_M: float = 3.0
const DISC_CONTACT_SLACK_M: float = 1.3
const SHORT_FUEL_S: float = 0.5
const MIN_PUSH_MPS: float = 3.0

var _bodies: Array[Node3D] = []
## Where the most recent rocket exploded (SpecialBehavior.triggered carries the position).
var _trigger_position: Vector3 = Vector3.ZERO


## Synchronous free() -- not queue_free() -- so no stale collider lingers in the physics world
## for even one frame into the next test.
func after_each() -> void:
	for body: Node3D in _bodies:
		if is_instance_valid(body):
			body.free()
	_bodies.clear()


# --- stub-Block/def/behavior fixture (no physics stepping) ------------------

func _make_stub_block(position: Vector3 = Vector3.ZERO, slot: int = -1) -> Block:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	block.global_position = position
	block.mass = 1.0
	block.owner_slot = slot
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
	behavior.set_physics_process(false)
	return behavior


# --- inert before armed -------------------------------------------------------

func test_inert_before_armed() -> void:
	var effect: RocketEffect = RocketEffect.new()
	var block: Block = _make_stub_block()
	block.linear_velocity = Vector3(0.0, -5.0, 0.0)  # falling
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect, 10.0))  # never arms here

	behavior.advance(0.1)

	assert_eq(block.linear_velocity, Vector3(0.0, -5.0, 0.0), "no thrust before arming")
	assert_false(block.continuous_cd, "no continuous_cd before arming")
	assert_false(behavior.is_triggered())


# --- the launch direction is host-side input and is honoured ----------------

func test_armed_tick_launches_along_the_given_direction() -> void:
	var directions: Array[Vector3] = [
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, -1.0, 0.0),
		Vector3(0.6, -0.3, -0.8),
		Vector3(-1.0, -0.5, 2.0),
	]
	for direction: Vector3 in directions:
		var effect: RocketEffect = RocketEffect.new()
		var block: Block = _make_stub_block(Vector3(0.0, 5.0, 0.0))
		assert_true(RocketEffect.set_launch_direction(block, direction), "accepted: %s" % [direction])
		var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))

		behavior.advance(TICK)

		var expected: Vector3 = direction.normalized() * effect.thrust_speed_mps
		assert_almost_eq(block.linear_velocity.x, expected.x, SPEED_TOLERANCE_MPS, "x for %s" % [direction])
		assert_almost_eq(block.linear_velocity.y, expected.y, SPEED_TOLERANCE_MPS, "y for %s" % [direction])
		assert_almost_eq(block.linear_velocity.z, expected.z, SPEED_TOLERANCE_MPS, "z for %s" % [direction])
		assert_true(block.continuous_cd, "continuous collision detection armed")


func test_the_straight_line_is_held_every_tick_even_after_an_external_reset() -> void:
	var effect: RocketEffect = RocketEffect.new()
	var block: Block = _make_stub_block()
	RocketEffect.set_launch_direction(block, Vector3(0.0, -0.5, -1.0))
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))
	behavior.advance(TICK)
	var launched: Vector3 = block.linear_velocity

	block.linear_velocity = Vector3.ZERO  # an external reset between ticks
	block.continuous_cd = false
	for i: int in range(5):
		behavior.advance(TICK)
		assert_eq(block.linear_velocity, launched, "tick %d: same straight line, same speed" % i)
		assert_true(block.continuous_cd, "tick %d: continuous_cd stays on" % i)
		assert_lte(block.linear_velocity.y, 0.0, "never upward")


func test_default_direction_is_inward_pitched_down_and_never_upward() -> void:
	var effect: RocketEffect = RocketEffect.new()
	var block: Block = _make_stub_block(Vector3(6.0, 3.0, 0.0))
	var direction: Vector3 = effect.launch_direction_for(block)
	assert_almost_eq(direction.length(), 1.0, 0.0001, "unit length")
	assert_lt(direction.x, 0.0, "heads toward the middle of the field")
	assert_lt(direction.y, 0.0, "pitched down, not upward")
	assert_almost_eq(rad_to_deg(asin(-direction.y)), effect.default_pitch_down_deg, 0.01, "the tuned pitch")
	var centred: Block = _make_stub_block(Vector3.ZERO)
	assert_lt(effect.launch_direction_for(centred).z, 0.0, "dead centre falls back to forward")


func test_an_unset_direction_launches_along_the_default() -> void:
	var effect: RocketEffect = RocketEffect.new()
	var block: Block = _make_stub_block(Vector3(6.0, 3.0, 0.0))
	var expected: Vector3 = effect.launch_direction_for(block) * effect.thrust_speed_mps
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect))
	behavior.advance(TICK)
	assert_almost_eq(block.linear_velocity.x, expected.x, SPEED_TOLERANCE_MPS)
	assert_almost_eq(block.linear_velocity.y, expected.y, SPEED_TOLERANCE_MPS)


func test_unusable_directions_are_rejected_and_keep_the_previous_one() -> void:
	var block: Block = _make_stub_block()
	assert_true(RocketEffect.set_launch_direction(block, Vector3(0.0, 0.0, -1.0)))
	var rejected: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(NAN, 0.0, 1.0),
		Vector3(INF, 0.0, 0.0),
		Vector3.UP,  # nothing left once "not upward" is applied
		Vector3(0.0, 5.0, 0.0),
	]
	for direction: Vector3 in rejected:
		assert_false(RocketEffect.set_launch_direction(block, direction), "rejected: %s" % [direction])
	assert_eq(RocketEffect.new().launch_direction_for(block), Vector3(0.0, 0.0, -1.0), "the earlier input survives")
	assert_false(RocketEffect.set_launch_direction(null, Vector3.FORWARD))


func test_an_upward_component_is_dropped_and_the_result_normalised() -> void:
	var sanitised: Vector3 = RocketEffect.sanitize_launch_direction(Vector3(3.0, 5.0, 4.0))
	assert_almost_eq(sanitised.y, 0.0, 0.0001, "not upward")
	assert_almost_eq(sanitised.length(), 1.0, 0.0001)
	assert_almost_eq(sanitised.x, 0.6, 0.0001)
	var downward: Vector3 = RocketEffect.sanitize_launch_direction(Vector3(0.0, -3.0, -4.0))
	assert_almost_eq(downward.y, -0.6, 0.0001, "a downward pitch is kept")


# --- safety fuel: exactly fuel_duration_s after the launch, frame-rate independent

func test_fuel_fires_at_fuel_duration_after_the_launch() -> void:
	var effect: RocketEffect = RocketEffect.new()
	effect.fuel_duration_s = 1.0
	var block: Block = _make_stub_block()
	var behavior: SpecialBehavior = _make_behavior(block, _make_def(effect, 0.25))

	for _i: int in range(4):
		behavior.advance(0.25)  # launches at age 0.25, reaches age 1.0
	assert_false(behavior.is_triggered(), "not before the fuel is spent")

	behavior.advance(0.25)  # age 1.25 == launch + fuel_duration_s
	assert_true(behavior.is_triggered(), "the safety fuel explodes it")


func test_fuel_is_frame_rate_independent_at_two_fixed_deltas() -> void:
	var coarse: float = 0.05
	var fine: float = 0.01
	# Far apart so neither blast chains into the other.
	var effect_a: RocketEffect = RocketEffect.new()
	effect_a.fuel_duration_s = 1.0
	var behavior_a: SpecialBehavior = _make_behavior(_make_stub_block(Vector3(-100.0, 0.0, 0.0)), _make_def(effect_a))
	var effect_b: RocketEffect = RocketEffect.new()
	effect_b.fuel_duration_s = 1.0
	var behavior_b: SpecialBehavior = _make_behavior(_make_stub_block(Vector3(100.0, 0.0, 0.0)), _make_def(effect_b))

	var time_a: float = 0.0
	while not behavior_a.is_triggered() and time_a < 5.0:
		behavior_a.advance(coarse)
		time_a += coarse
	var time_b: float = 0.0
	while not behavior_b.is_triggered() and time_b < 5.0:
		behavior_b.advance(fine)
		time_b += fine

	assert_true(behavior_a.is_triggered() and behavior_b.is_triggered())
	assert_almost_eq(time_a, time_b, coarse + fine, "trigger time follows simulated time, not tick count")


func test_two_blocks_sharing_the_effect_keep_independent_state() -> void:
	var effect: RocketEffect = RocketEffect.new()
	effect.fuel_duration_s = 1.0
	var shared_def: SpecialDef = _make_def(effect, 0.25)
	var block_a: Block = _make_stub_block(Vector3(-100.0, 0.0, 0.0))
	var block_b: Block = _make_stub_block(Vector3(100.0, 0.0, 0.0))
	RocketEffect.set_launch_direction(block_a, Vector3(1.0, 0.0, 0.0))
	RocketEffect.set_launch_direction(block_b, Vector3(0.0, 0.0, 1.0))
	var behavior_a: SpecialBehavior = _make_behavior(block_a, shared_def)
	var behavior_b: SpecialBehavior = _make_behavior(block_b, shared_def)

	for _i: int in range(4):
		behavior_a.advance(0.25)
	assert_false(behavior_a.is_triggered())
	assert_false(behavior_b.is_triggered(), "block_b's own timer never advanced")
	assert_gt(block_a.linear_velocity.x, 0.0, "each block flies its own direction")
	assert_eq(block_b.linear_velocity, Vector3.ZERO, "block_b has not launched")

	behavior_a.advance(0.25)
	assert_true(behavior_a.is_triggered())
	assert_false(behavior_b.is_triggered(), "block_a's fuel does not trigger block_b")
	behavior_b.advance(0.25)
	assert_almost_eq(block_b.linear_velocity.z, effect.thrust_speed_mps, SPEED_TOLERANCE_MPS)
	assert_almost_eq(block_b.linear_velocity.x, 0.0, SPEED_TOLERANCE_MPS)


# --- hooks and the impact filter --------------------------------------------

func test_lifecycle_hooks() -> void:
	var effect: RocketEffect = RocketEffect.new()
	assert_false(effect.triggers_on_impact(), "its own contact probe detects impacts")
	assert_true(effect.detaches(), "the spent carrier goes at the explosion")
	assert_false(effect.needs_landing(), "launches on arming, no landing wait")
	assert_eq(effect.effect_lifetime_s(), effect.fuel_duration_s)


func test_impact_filter_ignores_the_carrier_and_own_blocks_only_during_the_grace() -> void:
	var effect: RocketEffect = RocketEffect.new()
	var rocket: Block = _make_stub_block(Vector3.ZERO, 0)
	var own: Block = _make_stub_block(Vector3(5.0, 0.0, 0.0), 0)
	var enemy: Block = _make_stub_block(Vector3(10.0, 0.0, 0.0), 1)
	var wall: StaticBody3D = StaticBody3D.new()
	add_child_autofree(wall)
	var behavior: SpecialBehavior = _make_behavior(rocket, _make_def(effect, 0.4))

	behavior.advance(0.1)  # age 0.1, window started at 0.0
	assert_false(behavior.impact_filter(rocket), "never itself")
	assert_false(behavior.impact_filter(null), "nothing is not an impact")
	assert_false(behavior.impact_filter(own, 0.0), "own block ignored inside the grace")
	assert_true(behavior.impact_filter(enemy, 0.0), "an enemy block always counts")
	assert_true(behavior.impact_filter(wall, 0.0), "the disc / map geometry always counts")

	behavior.advance(0.4)  # age 0.5: grace (0.4) over
	assert_true(behavior.impact_filter(own, 0.0), "own block counts once the grace is over")
	assert_false(behavior.impact_filter(own, 0.3), "the window counts from the effect's own start")


func test_impact_filter_does_not_exempt_an_ownerless_carrier() -> void:
	var effect: RocketEffect = RocketEffect.new()
	var rocket: Block = _make_stub_block(Vector3.ZERO, -1)
	var other: Block = _make_stub_block(Vector3(5.0, 0.0, 0.0), -1)
	var behavior: SpecialBehavior = _make_behavior(rocket, _make_def(effect, 0.4))
	assert_true(behavior.impact_filter(other, 0.0), "slot -1 is no one's own block")


# --- real bodies: explodes on first contact, never mid-air ------------------

## A real Block (sphere collider) with gravity off, ticking its own SpecialBehavior through the
## scene tree. The rocket's effect writes its velocity every armed tick.
func _make_rocket(position: Vector3, direction: Vector3, slot: int, effect: RocketEffect) -> SpecialBehavior:
	var block: Block = _make_physics_block(position, 1.0)
	block.owner_slot = slot
	RocketEffect.set_launch_direction(block, direction)
	var def: SpecialDef = SpecialDef.new()
	def.id = &"rocket"
	def.arm_delay = 0.4
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	def.effect = effect
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	behavior.bind(block, def, SpecialTuning.new())
	behavior.triggered.connect(_on_rocket_triggered)
	return behavior


func _on_rocket_triggered(_def_id: StringName, position: Vector3, _chain_depth: int) -> void:
	_trigger_position = position


func _make_physics_block(position: Vector3, mass: float) -> Block:
	var block: Block = Block.new()
	block.mass = mass
	block.gravity_scale = 0.0
	block.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	block.linear_damp = 0.0
	block.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	block.angular_damp = 0.0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = BODY_RADIUS_M
	collision.shape = shape
	block.add_child(collision)
	add_child(block)
	block.global_position = position
	_bodies.append(block)
	return block


func _make_wall() -> StaticBody3D:
	var wall: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(WALL_HALF_THICKNESS_M * 2.0, 20.0, 20.0)
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	wall.global_position = Vector3(WALL_X_M, 0.0, 0.0)
	_bodies.append(wall)
	return wall


## Runs the scene tree until `behavior` triggers; returns where the rocket exploded.
func _fly_until_triggered(behavior: SpecialBehavior) -> Vector3:
	for _i: int in range(MAX_RUN_FRAMES):
		if behavior.is_triggered():
			break
		await wait_physics_frames(1)
	return _trigger_position


func test_explodes_on_the_first_contact_with_the_map_not_in_mid_air() -> void:
	_make_wall()
	var effect: RocketEffect = RocketEffect.new()
	var behavior: SpecialBehavior = _make_rocket(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 0, effect)
	await wait_physics_frames(1)

	var at: Vector3 = await _fly_until_triggered(behavior)

	assert_true(behavior.is_triggered(), "exploded")
	var wall_face_x: float = WALL_X_M - WALL_HALF_THICKNESS_M
	assert_gt(at.x, wall_face_x - BODY_RADIUS_M - 0.6, "right at the wall (x=%.2f), not part-way along its flight" % at.x)
	assert_lt(at.x, wall_face_x, "never through it")
	assert_lt(behavior.age(), effect.fuel_duration_s, "an impact, not the safety fuel")


func test_explodes_on_the_first_contact_with_a_block_and_blows_it_away() -> void:
	var target: Block = _make_physics_block(Vector3(WALL_X_M, 0.0, 0.0), 1.0)
	target.owner_slot = 1
	var effect: RocketEffect = RocketEffect.new()
	var behavior: SpecialBehavior = _make_rocket(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 0, effect)
	await wait_physics_frames(1)

	var at: Vector3 = await _fly_until_triggered(behavior)
	await wait_physics_frames(2)

	assert_true(behavior.is_triggered(), "exploded")
	assert_gt(at.x, WALL_X_M - 2.0 * BODY_RADIUS_M - 0.6, "at the target (x=%.2f), not mid-air" % at.x)
	assert_lt(behavior.age(), effect.fuel_duration_s, "an impact, not the safety fuel")
	assert_gt(target.linear_velocity.x, MIN_PUSH_MPS, "the target is blown away from the rocket")


func test_own_blocks_are_ignored_during_the_grace_but_an_enemys_are_not() -> void:
	var ages: Array[float] = []
	for slot: int in [0, 1]:  # 0 = the rocket's own slot, 1 = an enemy
		var obstacle: Block = _make_physics_block(Vector3(OWN_BLOCK_AHEAD_M, 0.0, 0.0), HEAVY_MASS_KG)
		obstacle.owner_slot = slot
		var effect: RocketEffect = RocketEffect.new()
		var behavior: SpecialBehavior = _make_rocket(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 0, effect)
		await wait_physics_frames(1)
		await _fly_until_triggered(behavior)
		assert_true(behavior.is_triggered(), "slot %d: exploded" % slot)
		ages.append(behavior.age())
		for body: Node3D in _bodies:
			body.free()
		_bodies.clear()
	var arm_delay: float = 0.4
	# Launch happens on the first armed tick (age arm_delay); the grace runs arm_delay after it.
	assert_lt(ages[1], arm_delay + arm_delay, "an enemy block: explodes at once")
	assert_gte(ages[0], arm_delay + arm_delay - TICK, "its own block: ignored until the grace is over")
	assert_lt(ages[0], arm_delay + arm_delay + 0.3, "and then it explodes there")


func test_the_safety_fuel_fires_on_a_straight_line_when_nothing_is_in_the_way() -> void:
	var effect: RocketEffect = RocketEffect.new()
	effect.fuel_duration_s = SHORT_FUEL_S
	var start: Vector3 = Vector3(0.0, 4.0, 0.0)
	var behavior: SpecialBehavior = _make_rocket(start, Vector3(1.0, 0.0, 0.0), 0, effect)
	await wait_physics_frames(1)

	var at: Vector3 = await _fly_until_triggered(behavior)

	assert_true(behavior.is_triggered(), "the fuel explodes it")
	assert_almost_eq(behavior.age(), 0.4 + SHORT_FUEL_S, 2.0 * TICK, "fuel_duration_s after the launch")
	assert_almost_eq(at.y, start.y, 0.05, "a straight line: never climbs")
	assert_almost_eq(at.x, effect.thrust_speed_mps * SHORT_FUEL_S, 0.6, "flew its fuel at thrust speed along x")


# --- the disc ----------------------------------------------------------------

func test_explodes_on_the_first_contact_with_the_disc() -> void:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_rocket_disc"
	map_def.field_radius = 14.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	var field: Field = Field.new()
	field.map_def = map_def
	add_child_autofree(field)
	await wait_physics_frames(SETTLE_FRAMES)
	var surface: float = field.surface_y()
	var effect: RocketEffect = RocketEffect.new()
	var behavior: SpecialBehavior = _make_rocket(
		Vector3(0.0, surface + DISC_DROP_HEIGHT_M, 0.0), Vector3(1.0, -1.0, 0.0), 0, effect
	)
	await wait_physics_frames(1)

	var at: Vector3 = await _fly_until_triggered(behavior)

	assert_true(behavior.is_triggered(), "exploded")
	assert_lt(at.y - surface, DISC_CONTACT_SLACK_M, "on the disc (%.2f above it), not in mid-air" % (at.y - surface))
	assert_lt(behavior.age(), effect.fuel_duration_s, "an impact, not the safety fuel")


# --- config/specials/rocket.tres ---------------------------------------------

func test_rocket_tres_loads_with_the_plan_numbers() -> void:
	var found: SpecialDef = null
	for def: SpecialDef in SpecialDef.load_all_specials():
		if def.id == &"rocket":
			found = def
			break
	assert_not_null(found, "config/specials/rocket.tres is found by load_all_specials()")
	assert_true(found.effect is RocketEffect, "rocket.tres's effect is a RocketEffect")
	var effect: RocketEffect = found.effect as RocketEffect
	assert_eq(effect.thrust_speed_mps, 14.0)
	assert_eq(effect.fuel_duration_s, 4.0)
	assert_eq(effect.default_pitch_down_deg, 20.0)
	assert_eq(effect.blast.radius_m, 4.5)
	assert_eq(effect.blast.peak_speed_mps, 10.0)
	assert_eq(effect.blast.falloff_exponent, 1.5)
	assert_eq(effect.blast.upward_bias, 0.35)
	assert_eq(effect.blast.max_delta_v_mps, 16.0)
