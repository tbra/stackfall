extends GutTest
## BombEffect (spec 2.6 "large explosion on activation"; docs/M4_SPECIALS_
## PACKAGES.md's P3-BOMB package). Bomb has no physics_tick()/
## wants_early_trigger() override -- activation is entirely the base
## impact/fuse detection SpecialBehavior.advance() already runs -- so every
## test here exercises detonate() directly, either standalone or via a real
## SpecialBehavior.trigger() call (which is what the production path
## actually calls). Real RigidBody3D/Block bodies added directly to the
## test's own tree -- a physics smoke test, same shape as
## tests/unit/test_special_physics.gd -- proving push/exclude/radius-cutoff
## and the trigger_others_in_range() chain call.

const RADIUS: float = 3.5
const IMPULSE: float = 18.0

var _bodies: Array[Node3D] = []


## Synchronous free() -- not queue_free() -- so no stale collider lingers in
## the physics world for even one frame into the next test, mirroring
## tests/unit/test_special_physics.gd's own after_each().
func after_each() -> void:
	for body: Node3D in _bodies:
		if is_instance_valid(body):
			body.free()
	_bodies.clear()


func _space_state() -> PhysicsDirectSpaceState3D:
	return get_viewport().world_3d.direct_space_state


## A real Block (not a bare RigidBody3D) with a small sphere collider, so
## detonate() can call block.get_world_3d()/block.get_rid() exactly like the
## production path does. Gravity and damping are turned off so a one-frame
## velocity read reflects only the explosion's impulse.
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
	# DECISION (tests/unit/test_bomb_effect.gd, matches
	# tests/unit/test_special_physics.gd's own DECISION): add_child() before
	# setting global_position -- Node3D.global_position needs is_inside_tree()
	# to resolve a global transform.
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


func _make_behavior(block: Block, effect: BombEffect) -> SpecialBehavior:
	var def: SpecialDef = SpecialDef.new()
	def.id = &"bomb"
	def.arm_delay = 0.0
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	def.effect = effect
	var tuning: SpecialTuning = SpecialTuning.new()
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	behavior.bind(block, def, tuning)
	return behavior


# --- detonate() pushes a nearby real body, outward, falls off with distance -

func test_detonate_pushes_a_nearby_real_body_outward() -> void:
	var bomb_block: Block = _make_block(Vector3.ZERO)
	var nearby: RigidBody3D = _make_rigid_body(Vector3(RADIUS * 0.5, 0.0, 0.0))
	var effect: BombEffect = BombEffect.new()
	effect.explosion_radius = RADIUS
	effect.explosion_impulse = IMPULSE
	var behavior: SpecialBehavior = _make_behavior(bomb_block, effect)
	await wait_physics_frames(1)

	behavior.trigger(0)
	await wait_physics_frames(1)

	assert_gt(
		nearby.linear_velocity.length(), 0.0, "a nearby real body must gain velocity from the blast"
	)
	assert_gt(
		nearby.linear_velocity.dot(Vector3(1.0, 0.0, 0.0)),
		0.0,
		"the push must point outward, away from the bomb"
	)


# --- the bomb's own body is excluded -----------------------------------------

func test_detonate_does_not_push_the_bomb_itself() -> void:
	var bomb_block: Block = _make_block(Vector3.ZERO)
	var effect: BombEffect = BombEffect.new()
	effect.explosion_radius = RADIUS
	effect.explosion_impulse = IMPULSE
	var behavior: SpecialBehavior = _make_behavior(bomb_block, effect)
	await wait_physics_frames(1)

	behavior.trigger(0)
	await wait_physics_frames(1)

	assert_eq(
		bomb_block.linear_velocity, Vector3.ZERO, "the bomb's own body must be excluded from its blast"
	)


# --- nothing beyond radius moves ---------------------------------------------

func test_body_beyond_radius_is_untouched() -> void:
	var bomb_block: Block = _make_block(Vector3.ZERO)
	var far_body: RigidBody3D = _make_rigid_body(Vector3(RADIUS * 1.5, 0.0, 0.0))
	var effect: BombEffect = BombEffect.new()
	effect.explosion_radius = RADIUS
	effect.explosion_impulse = IMPULSE
	var behavior: SpecialBehavior = _make_behavior(bomb_block, effect)
	await wait_physics_frames(1)

	behavior.trigger(0)
	await wait_physics_frames(1)

	assert_eq(
		far_body.linear_velocity, Vector3.ZERO, "a body beyond explosion_radius must be untouched"
	)


# --- trigger_others_in_range() chains into a nearby armed special -----------

func test_trigger_chains_into_a_nearby_special_one_depth_deeper() -> void:
	var bomb_block: Block = _make_block(Vector3.ZERO)
	var neighbor_block: Block = _make_block(Vector3(RADIUS * 0.5, 0.0, 0.0))

	var bomb_effect: BombEffect = BombEffect.new()
	bomb_effect.explosion_radius = RADIUS
	bomb_effect.explosion_impulse = IMPULSE
	var bomb_behavior: SpecialBehavior = _make_behavior(bomb_block, bomb_effect)

	var neighbor_effect: BombEffect = BombEffect.new()
	var neighbor_behavior: SpecialBehavior = _make_behavior(neighbor_block, neighbor_effect)
	await wait_physics_frames(1)

	bomb_behavior.trigger(0)
	await wait_physics_frames(1)

	assert_true(
		neighbor_behavior.is_triggered(),
		"trigger_others_in_range() must reach a special within explosion_radius"
	)
	assert_eq(
		neighbor_behavior.chain_depth(), 1, "a chained trigger must be exactly one depth deeper"
	)


func test_trigger_does_not_chain_into_a_special_beyond_radius() -> void:
	var bomb_block: Block = _make_block(Vector3.ZERO)
	var far_block: Block = _make_block(Vector3(RADIUS * 1.5, 0.0, 0.0))

	var bomb_effect: BombEffect = BombEffect.new()
	bomb_effect.explosion_radius = RADIUS
	bomb_effect.explosion_impulse = IMPULSE
	var bomb_behavior: SpecialBehavior = _make_behavior(bomb_block, bomb_effect)

	var far_effect: BombEffect = BombEffect.new()
	var far_behavior: SpecialBehavior = _make_behavior(far_block, far_effect)
	await wait_physics_frames(1)

	bomb_behavior.trigger(0)
	await wait_physics_frames(1)

	assert_false(
		far_behavior.is_triggered(), "a special beyond explosion_radius must not be chained into"
	)


# --- config/specials/bomb.tres loads with the contract defaults -------------

func test_bomb_tres_loads_with_expected_id_and_effect_defaults() -> void:
	var defs: Array[SpecialDef] = SpecialDef.load_all_specials()
	var found: SpecialDef = null
	for def: SpecialDef in defs:
		if def.id == &"bomb":
			found = def
			break
	assert_not_null(found, "config/specials/bomb.tres must be found by load_all_specials()")
	assert_true(found.effect is BombEffect, "bomb.tres's effect sub-resource must be a BombEffect")
	var effect: BombEffect = found.effect as BombEffect
	assert_eq(effect.explosion_radius, 3.5)
	assert_eq(effect.explosion_impulse, 18.0)
	assert_not_null(effect.tuning, "tuning must fall back to the preloaded config/special_tuning.tres")
	assert_eq(effect.tuning.max_explosion_impulse, 30.0)
