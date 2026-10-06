extends GutTest
## Bontago-1pi.85.25 / .27 (docs/GIFT_PLAYTEST2_PLAN.md PA1): Rocket and Paintball fly a dead-straight,
## fast line from the release tick (no free-fall arm delay, no gravity), the Rocket's nose follows
## its velocity every tick, and the Rocket blast is ~10x. Real bodies with NORMAL gravity: the old
## code dropped them during the 0.4 s arm delay and let gravity bend the flight.

const TICK: float = 1.0 / 60.0
const START: Vector3 = Vector3(0.0, 40.0, 0.0)
const FLIGHT_FRAMES: int = 36
const MIN_DISTANCE_M: float = 30.0
const MAX_Y_DEVIATION_M: float = 0.05
const SPEED_TOLERANCE_MPS: float = 0.5
const MAX_NOSE_ERROR_DEG: float = 1.0
const BODY_RADIUS_M: float = 0.3
const OWN_SLOT: int = 0
const ENEMY_SLOT: int = 1
const OWN_BLOCK_AHEAD_M: float = 1.0
const ENEMY_BEHIND_OWN_M: float = 4.0
const THIN_WALL_AHEAD_M: float = 12.0
const THIN_WALL_HALF_M: float = 0.025
const BIG_HALF_M: float = 5.0
const HEAVY_MASS_KG: float = 1000.0
const OWN_SHOVE_LIMIT_MPS: float = 0.5
const MAX_WAIT_FRAMES: int = 60

var _bodies: Array[Node3D] = []
var _triggered_at: Array[Vector3] = []


func after_each() -> void:
	for body: Node3D in _bodies:
		if is_instance_valid(body):
			body.free()
	_bodies.clear()
	_triggered_at.clear()


func _def(id: StringName) -> SpecialDef:
	for def: SpecialDef in SpecialDef.load_all_specials():
		if def.id == id:
			return def
	return null


## A real Block (sphere collider) under normal gravity, with the shipped def's behaviour bound.
func _launch(id: StringName, direction: Vector3, slot: int = -1) -> Block:
	var def: SpecialDef = _def(id)
	var block: Block = Block.new()
	block.mass = 1.0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = BODY_RADIUS_M
	collision.shape = shape
	block.add_child(collision)
	add_child(block)
	_bodies.append(block)
	block.global_position = START
	block.owner_slot = slot
	if id == &"rocket":
		RocketEffect.set_launch_direction(block, direction)
	else:
		PaintballEffect.set_launch_direction(block, direction)
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	behavior.bind(block, def, SpecialTuning.new())
	behavior.triggered.connect(
		func(_id: StringName, at: Vector3, _depth: int) -> void: _triggered_at.append(at)
	)
	return block


## A weightless heavy box Block of `slot` at `offset` from START, `half` = half extents.
func _obstacle(offset: Vector3, slot: int, half: Vector3) -> Block:
	var block: Block = Block.new()
	block.mass = HEAVY_MASS_KG
	block.gravity_scale = 0.0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = half * 2.0
	collision.shape = shape
	block.add_child(collision)
	add_child(block)
	_bodies.append(block)
	block.global_position = START + offset
	block.owner_slot = slot
	return block


func _fly_until_triggered() -> void:
	for _i: int in range(MAX_WAIT_FRAMES):
		if not _triggered_at.is_empty():
			return
		await wait_physics_frames(1)


func _speed_of(id: StringName) -> float:
	if id == &"rocket":
		return (_def(id).effect as RocketEffect).thrust_speed_mps
	return (_def(id).effect as PaintballEffect).flight_speed_mps


func _assert_straight_fast_flight(id: StringName) -> void:
	var direction: Vector3 = Vector3(0.6, 0.0, 0.8)
	var block: Block = _launch(id, direction)
	var max_dy: float = 0.0
	for _i: int in range(FLIGHT_FRAMES):
		await wait_physics_frames(1)
		max_dy = maxf(max_dy, absf(block.global_position.y - START.y))
	var travelled: float = (block.global_position - START).length()
	assert_lt(max_dy, MAX_Y_DEVIATION_M, "%s keeps its launch height (max drop %.3f m)" % [id, max_dy])
	assert_gt(travelled, MIN_DISTANCE_M, "%s covers >30 m in 0.6 s (%.1f m)" % [id, travelled])
	var horizontal: Vector3 = Vector3(block.linear_velocity.x, 0.0, block.linear_velocity.z)
	var expected_speed: float = _speed_of(id)
	assert_almost_eq(block.linear_velocity.length(), expected_speed, SPEED_TOLERANCE_MPS, "%s at the tuned speed" % id)
	assert_almost_eq(block.linear_velocity.y, 0.0, SPEED_TOLERANCE_MPS, "%s has no vertical speed" % id)
	assert_gt(horizontal.normalized().dot(Vector3(0.6, 0.0, 0.8)), 0.999, "%s flies along the aim" % id)
	assert_almost_eq(block.gravity_scale, 0.0, 0.0001, "%s is weightless while flying" % id)


func test_rocket_flies_straight_and_fast_without_gravity() -> void:
	await _assert_straight_fast_flight(&"rocket")


func test_paintball_flies_straight_and_fast_without_gravity() -> void:
	await _assert_straight_fast_flight(&"paintball")


func test_rocket_nose_follows_the_velocity_every_tick() -> void:
	var block: Block = _launch(&"rocket", Vector3(0.6, -0.3, -0.8))
	var effect: RocketEffect = _def(&"rocket").effect as RocketEffect
	for i: int in range(FLIGHT_FRAMES):
		await wait_physics_frames(1)
		var nose: Vector3 = block.global_basis * effect.model_nose_axis.normalized()
		var velocity_dir: Vector3 = block.linear_velocity.normalized()
		var error_deg: float = rad_to_deg(nose.angle_to(velocity_dir))
		assert_lt(error_deg, MAX_NOSE_ERROR_DEG, "tick %d: nose %.2f deg off the velocity" % [i, error_deg])


func test_nose_basis_handles_every_direction() -> void:
	var nose: Vector3 = Vector3.UP
	for direction: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3(0.3, -0.9, 0.1)]:
		var basis: Basis = RocketEffect.nose_basis(nose, direction)
		assert_lt((basis * nose).angle_to(direction.normalized()), 0.001, "nose onto %s" % [direction])
		assert_almost_eq(basis.determinant(), 1.0, 0.001, "a proper rotation for %s" % [direction])


func test_the_rocket_carrier_gravity_is_restored_at_the_explosion() -> void:
	var block: Block = _launch(&"rocket", Vector3(1.0, 0.0, 0.0))
	await wait_physics_frames(2)
	assert_eq(block.gravity_scale, 0.0)
	var effect: RocketEffect = _def(&"rocket").effect as RocketEffect
	effect.detonate(block, block.get_child(block.get_child_count() - 1) as SpecialBehavior, 0)
	assert_eq(block.gravity_scale, 1.0, "back to the carrier's own scale")


func test_shipped_numbers_and_stronger_blast() -> void:
	var rocket: SpecialDef = _def(&"rocket")
	var effect: RocketEffect = rocket.effect as RocketEffect
	assert_eq(rocket.arm_delay, 0.0, "no free-fall arm delay")
	assert_gte(effect.thrust_speed_mps, 60.0, "fast")
	assert_eq(effect.fuel_duration_s, 3.0)
	assert_eq(effect.flight_gravity_scale, 0.0)
	assert_eq(effect.model_nose_axis, Vector3.UP, "rocket_v1.glb nose is +Y")
	assert_eq(effect.blast.radius_m, 7.0)
	assert_eq(effect.blast.peak_speed_mps, 100.0, "10x the old 10 m/s")
	assert_eq(effect.blast.max_delta_v_mps, 160.0)
	var paintball: SpecialDef = _def(&"paintball")
	var glob: PaintballEffect = paintball.effect as PaintballEffect
	assert_eq(paintball.arm_delay, 0.0)
	assert_gte(glob.flight_speed_mps, 60.0, "fast")
	assert_eq(glob.flight_gravity_scale, 0.0)


func _assert_leaves_own_tower_and_hits_enemy_behind(id: StringName) -> void:
	var half: Vector3 = Vector3.ONE * BODY_RADIUS_M
	var own: Block = _obstacle(Vector3(OWN_BLOCK_AHEAD_M, 0.0, 0.0), OWN_SLOT, half)
	var enemy: Block = _obstacle(Vector3(ENEMY_BEHIND_OWN_M, 0.0, 0.0), ENEMY_SLOT, half)
	await wait_physics_frames(1)  # the obstacles are in the physics space
	_launch(id, Vector3.RIGHT, OWN_SLOT)
	await wait_physics_frames(1)
	assert_lt(own.linear_velocity.length(), OWN_SHOVE_LIMIT_MPS, "%s did not shove the own block" % id)
	await _fly_until_triggered()
	assert_eq(_triggered_at.size(), 1, "%s hit the enemy right behind the own block" % id)
	if not _triggered_at.is_empty():
		assert_gt(_triggered_at[0].x, START.x + OWN_BLOCK_AHEAD_M, "%s passed the own block" % id)
		assert_lt(_triggered_at[0].x, enemy.global_position.x, "%s stopped at the enemy" % id)


func test_rocket_leaves_own_tower_without_shoving_and_hits_enemy_behind_it() -> void:
	await _assert_leaves_own_tower_and_hits_enemy_behind(&"rocket")


func test_paintball_leaves_own_tower_without_shoving_and_hits_enemy_behind_it() -> void:
	await _assert_leaves_own_tower_and_hits_enemy_behind(&"paintball")


func test_own_block_beside_the_launch_does_not_detonate_it() -> void:
	var half: Vector3 = Vector3.ONE * BODY_RADIUS_M
	var own: Block = _obstacle(Vector3(0.0, 0.0, BODY_RADIUS_M * 2.0), OWN_SLOT, half)
	await wait_physics_frames(1)
	_launch(&"rocket", Vector3.RIGHT, OWN_SLOT)
	await wait_physics_frames(FLIGHT_FRAMES)
	assert_true(_triggered_at.is_empty(), "no detonation on the neighbouring own block %s" % [_triggered_at])
	assert_lt(own.linear_velocity.length(), OWN_SHOVE_LIMIT_MPS, "own block not shoved")


func test_an_own_block_outside_the_clear_radius_is_an_ordinary_impact() -> void:
	var half: Vector3 = Vector3.ONE * BODY_RADIUS_M
	var effect: RocketEffect = _def(&"rocket").effect as RocketEffect
	_obstacle(Vector3(effect.own_block_clear_radius_m + 3.0, 0.0, 0.0), OWN_SLOT, half)
	await wait_physics_frames(1)
	_launch(&"rocket", Vector3.RIGHT, OWN_SLOT)
	await _fly_until_triggered()
	assert_eq(_triggered_at.size(), 1, "a farther own block still detonates the rocket")


func _assert_no_tunnelling(id: StringName) -> void:
	var half: Vector3 = Vector3(THIN_WALL_HALF_M, BIG_HALF_M, BIG_HALF_M)
	var wall: Block = _obstacle(Vector3(THIN_WALL_AHEAD_M, 0.0, 0.0), ENEMY_SLOT, half)
	await wait_physics_frames(1)
	var block: Block = _launch(id, Vector3.RIGHT, OWN_SLOT)
	await wait_physics_frames(2)
	assert_true(block.continuous_cd, "%s flies with continuous collision detection" % id)
	await _fly_until_triggered()
	assert_eq(_triggered_at.size(), 1, "%s hit the thin enemy block" % id)
	if not _triggered_at.is_empty():
		assert_lt(_triggered_at[0].x, wall.global_position.x, "%s did not tunnel through it" % id)
	assert_lt(block.global_position.x, wall.global_position.x + 1.0, "%s stayed on this side" % id)


func test_rocket_does_not_tunnel_through_a_thin_enemy_block() -> void:
	await _assert_no_tunnelling(&"rocket")


func test_paintball_does_not_tunnel_through_a_thin_enemy_block() -> void:
	await _assert_no_tunnelling(&"paintball")
