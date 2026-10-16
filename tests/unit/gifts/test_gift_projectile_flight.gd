extends GutTest
## Bontago-1pi.85.25 / .27 (docs/GIFT_PLAYTEST2_PLAN.md PA1): Rocket and Paintball fly a dead-straight,
## fast line from the release tick (no free-fall arm delay, no gravity), the Rocket's nose follows
## its velocity every tick, and the Rocket blast is ~10x. Real bodies with NORMAL gravity: the old
## code dropped them during the 0.4 s arm delay and let gravity bend the flight.

const START: Vector3 = Vector3(0.0, 40.0, 0.0)
const FLIGHT_FRAMES: int = 36
const MIN_DISTANCE_M: float = 30.0
const MAX_Y_DEVIATION_M: float = 0.05
const SPEED_TOLERANCE_MPS: float = 0.5
const BODY_RADIUS_M: float = 0.3
const OWN_SLOT: int = 0
const ENEMY_SLOT: int = 1
const OWN_BLOCK_AHEAD_M: float = 1.0
const ENEMY_BEHIND_OWN_M: float = 4.0
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


func test_own_block_beside_the_launch_does_not_detonate_it() -> void:
	var half: Vector3 = Vector3.ONE * BODY_RADIUS_M
	var own: Block = _obstacle(Vector3(0.0, 0.0, BODY_RADIUS_M * 2.0), OWN_SLOT, half)
	await wait_physics_frames(1)
	_launch(&"rocket", Vector3.RIGHT, OWN_SLOT)
	await wait_physics_frames(FLIGHT_FRAMES)
	assert_true(_triggered_at.is_empty(), "no detonation on the neighbouring own block %s" % [_triggered_at])
	assert_lt(own.linear_velocity.length(), OWN_SHOVE_LIMIT_MPS, "own block not shoved")


## Bontago-1pi.85.43: a rocket fired straight up is detonated by the host before it leaves the
## volume snapshots quantize into (it used to climb past pos_max_y and render pinned at the clamp).
func test_rocket_fired_straight_up_detonates_inside_the_replicable_bounds() -> void:
	var bounds: AABB = RocketEffect.replicable_bounds()
	var block: Block = _launch(&"rocket", Vector3.UP)
	for _i: int in range(MAX_WAIT_FRAMES * 2):
		if not _triggered_at.is_empty():
			break
		await wait_physics_frames(1)
	assert_false(_triggered_at.is_empty(), "the rocket detonated")
	assert_true(bounds.has_point(_triggered_at[0]), "burst at %s inside %s" % [_triggered_at[0], bounds])
	assert_lt(block.global_position.y, bounds.end.y + 1.0, "no runaway past the ceiling")
