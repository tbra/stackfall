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

func test_armed_tick_launches_along_the_given_direction() -> void:
	var directions: Array[Vector3] = [
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),  # straight up (1pi.85.34 Q3)
		Vector3(0.3, 0.8, -0.5),
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


func test_own_blocks_near_the_launch_are_passed_through_but_an_enemy_is_not() -> void:
	# Bontago-1pi.85.37: own blocks within the clear radius are collision exceptions (not an impact,
	# not shoved); an enemy block at the same spot is hit at once.
	var ages: Array[float] = []
	var own_speed: float = 0.0
	for slot: int in [0, 1]:  # 0 = the rocket's own slot, 1 = an enemy
		var obstacle: Block = _make_physics_block(Vector3(OWN_BLOCK_AHEAD_M, 0.0, 0.0), HEAVY_MASS_KG)
		obstacle.owner_slot = slot
		var effect: RocketEffect = RocketEffect.new()
		var behavior: SpecialBehavior = _make_rocket(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 0, effect)
		await wait_physics_frames(1)
		await _fly_until_triggered(behavior)
		assert_true(behavior.is_triggered(), "slot %d: exploded" % slot)
		ages.append(behavior.age())
		if slot == 0:
			own_speed = obstacle.linear_velocity.length()
		for body: Node3D in _bodies:
			body.free()
		_bodies.clear()
	var arm_delay: float = 0.4
	assert_lt(ages[1], arm_delay + 0.2, "an enemy block: explodes at once")
	assert_gt(ages[0], ages[1] + 0.5, "its own block: passed through, the fuel ends it later")
	assert_lt(own_speed, 0.5, "and the own block was not shoved")


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


## Bontago-1pi.85.16 (reviewer hypothesis from package C): a horizontal launch from rest on a
## floor, the carrier touching the surface, must not report the resting contact as an impact; it
## flies on to the wall ahead.
func test_a_horizontal_launch_from_rest_on_a_floor_does_not_explode_on_the_resting_contact() -> void:
	_make_wall()
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_collision: CollisionShape3D = CollisionShape3D.new()
	var floor_shape: BoxShape3D = BoxShape3D.new()
	floor_shape.size = Vector3(40.0, 1.0, 40.0)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	add_child(floor_body)
	floor_body.global_position = Vector3(0.0, -0.5 - BODY_RADIUS_M, 0.0)
	_bodies.append(floor_body)
	var effect: RocketEffect = RocketEffect.new()
	var behavior: SpecialBehavior = _make_rocket(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 0, effect)
	(behavior.get_parent() as Block).gravity_scale = 1.0
	await wait_physics_frames(SETTLE_FRAMES)

	var at: Vector3 = await _fly_until_triggered(behavior)

	assert_true(behavior.is_triggered(), "exploded")
	var wall_face_x: float = WALL_X_M - WALL_HALF_THICKNESS_M
	assert_gt(at.x, wall_face_x - BODY_RADIUS_M - 0.6, "at the wall (x=%.2f), not on the floor contact at the start" % at.x)


# --- config/gifts/specials/rocket.tres ---------------------------------------------
