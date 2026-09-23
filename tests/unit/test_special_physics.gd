extends GutTest
## SpecialPhysics.explode() (spec 3.5 "Explosions"; docs/M4_SPECIALS_PACKAGES.md
## P3-SH). Real RigidBody3D/StaticBody3D bodies added directly to the test's
## own tree -- a physics smoke test, not a stubbed unit test -- proving the
## sphere-query falloff, radius cutoff, impulse clamp, exclude list and
## StaticBody3D skip this package's contract describes.
##
## DECISION (tests/unit/test_special_physics.gd): builds bare RigidBody3D/
## StaticBody3D fixtures directly rather than a real Field + BlockFactory
## Block -- explode()'s own contract returns Array[RigidBody3D] and is
## agnostic to Block; it only needs "a real rigid body" and "a real static
## body" to prove every acceptance case, and a full Field's disk mesh is
## unrelated cost this package doesn't own (test_tower_placement.gd notes a
## tiny map already costs real seconds to build).

const RADIUS: float = 5.0
const IMPULSE: float = 20.0
const HUGE_IMPULSE: float = 1_000_000.0
const DEFAULT_MASS: float = 1.0
## Loose enough to absorb one physics step's float error, tight enough that a
## clamp bug (e.g. forgetting to divide by mass) would still fail this.
const SPEED_TOLERANCE: float = 0.1

var _bodies: Array[Node3D] = []


## Synchronous free() -- not queue_free() -- so no stale collider lingers in
## the physics world for even one frame into the next test (brief: "free
## bodies synchronously in after_each").
func after_each() -> void:
	for body: Node3D in _bodies:
		if is_instance_valid(body):
			body.free()
	_bodies.clear()


func _space_state() -> PhysicsDirectSpaceState3D:
	return get_viewport().world_3d.direct_space_state


## A real RigidBody3D with a small sphere collider. Gravity and damping are
## turned off so a one-frame velocity read reflects only the explosion's
## impulse, not gravity or damping accrued over that same frame.
func _make_rigid_body(position: Vector3, mass: float = DEFAULT_MASS) -> RigidBody3D:
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
	# DECISION (tests/unit/test_special_physics.gd): add_child() before
	# setting global_position -- Node3D.global_position needs is_inside_tree()
	# to resolve a global transform; setting it beforehand silently no-ops
	# (Godot logs "!is_inside_tree()" and returns Transform3D()), leaving
	# every fixture body sitting at the world origin.
	add_child(body)
	body.global_position = position
	_bodies.append(body)
	return body


## A single RigidBody3D with `shape_count` separate CollisionShape3D children,
## all spanning the query sphere -- exactly what BlockFactory.build() produces
## for a multi-cell shape (one CollisionShape3D per cell; domino has 2, slab6
## has 6 -- game/BlockFactory.gd lines ~86-93). Each child collider is offset
## from the body's own origin so intersect_shape() returns one Dictionary
## entry per shape, all sharing the same `collider`/RID.
func _make_multi_shape_rigid_body(
	position: Vector3, shape_count: int, mass: float = DEFAULT_MASS
) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.mass = mass
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp = 0.0
	for i: int in range(shape_count):
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: SphereShape3D = SphereShape3D.new()
		shape.radius = 0.3
		collision.shape = shape
		# Small per-cell offsets, same idea as BlockFactory's cube_size-spaced
		# cells: keeps every child shape well inside the query sphere at
		# RADIUS * 0.3 without any one of them landing outside it.
		collision.position = Vector3(float(i) * 0.5, 0.0, 0.0)
		body.add_child(collision)
	add_child(body)
	body.global_position = position
	_bodies.append(body)
	return body


func _make_static_body(position: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3.ONE
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	body.global_position = position
	_bodies.append(body)
	return body


# --- (1) falloff -------------------------------------------------------------

func test_falloff_closer_body_gets_a_larger_impulse() -> void:
	var near_body: RigidBody3D = _make_rigid_body(Vector3(RADIUS * 0.5, 0.0, 0.0))
	var far_body: RigidBody3D = _make_rigid_body(Vector3(RADIUS * 0.9, 0.0, 0.0))
	await wait_physics_frames(1)  # bodies exist in the space

	var hit: Array[RigidBody3D] = SpecialPhysics.explode(
		_space_state(), Vector3.ZERO, RADIUS, IMPULSE, 1000.0
	)
	await wait_physics_frames(1)  # the impulse reaches linear_velocity

	assert_has(hit, near_body)
	assert_has(hit, far_body)
	assert_gt(
		near_body.linear_velocity.length(),
		far_body.linear_velocity.length(),
		"a body at 0.5r must receive a larger impulse than one at 0.9r"
	)


# --- (2) nothing beyond radius ------------------------------------------------

func test_body_beyond_radius_is_untouched_and_not_returned() -> void:
	var far_body: RigidBody3D = _make_rigid_body(Vector3(RADIUS * 1.1, 0.0, 0.0))
	await wait_physics_frames(1)

	var hit: Array[RigidBody3D] = SpecialPhysics.explode(
		_space_state(), Vector3.ZERO, RADIUS, IMPULSE, 1000.0
	)
	await wait_physics_frames(1)

	assert_does_not_have(hit, far_body)
	assert_eq(
		far_body.linear_velocity, Vector3.ZERO, "a body outside radius must receive zero velocity"
	)


# --- (3) clamp -----------------------------------------------------------------

func test_huge_impulse_is_clamped_to_max_impulse() -> void:
	var mass: float = 2.0
	var body: RigidBody3D = _make_rigid_body(Vector3(RADIUS * 0.1, 0.0, 0.0), mass)
	await wait_physics_frames(1)

	var max_impulse: float = 30.0
	var hit: Array[RigidBody3D] = SpecialPhysics.explode(
		_space_state(), Vector3.ZERO, RADIUS, HUGE_IMPULSE, max_impulse
	)
	await wait_physics_frames(1)

	assert_has(hit, body)
	var expected_speed: float = max_impulse / mass
	assert_almost_eq(
		body.linear_velocity.length(),
		expected_speed,
		SPEED_TOLERANCE,
		"clamp must cap the applied impulse at max_impulse, not the raw huge impulse"
	)


# --- (4) exclude ---------------------------------------------------------------

func test_excluded_rid_is_untouched_and_not_returned() -> void:
	var excluded_body: RigidBody3D = _make_rigid_body(Vector3(RADIUS * 0.5, 0.0, 0.0))
	var other_body: RigidBody3D = _make_rigid_body(Vector3(RADIUS * 0.5, 0.0, 1.0))
	await wait_physics_frames(1)

	var exclude: Array[RID] = [excluded_body.get_rid()]
	var hit: Array[RigidBody3D] = SpecialPhysics.explode(
		_space_state(), Vector3.ZERO, RADIUS, IMPULSE, 1000.0, exclude
	)
	await wait_physics_frames(1)

	assert_does_not_have(hit, excluded_body)
	assert_eq(
		excluded_body.linear_velocity, Vector3.ZERO, "an excluded body must receive no impulse"
	)
	assert_has(hit, other_body, "a non-excluded body in range must still be hit")


# --- (5) StaticBody3D is ignored -------------------------------------------------

func test_static_body_in_range_is_ignored() -> void:
	var static_body: StaticBody3D = _make_static_body(Vector3(RADIUS * 0.3, 0.0, 0.0))
	var rigid_body: RigidBody3D = _make_rigid_body(Vector3(RADIUS * 0.3, 0.0, 1.0))
	await wait_physics_frames(1)

	var hit: Array[RigidBody3D] = SpecialPhysics.explode(
		_space_state(), Vector3.ZERO, RADIUS, IMPULSE, 1000.0
	)
	await wait_physics_frames(1)

	assert_eq(
		hit.size(), 1, "only the real RigidBody3D must be returned, never the StaticBody3D"
	)
	assert_has(hit, rigid_body)
	# Not also asserting `assert_does_not_have(hit, static_body)`: `hit` is a
	# typed Array[RigidBody3D], so passing a StaticBody3D to a typed array's
	# has() is itself a type-validation error, not a meaningful check.
	# hit.size() == 1 above, with only rigid_body present, already proves the
	# StaticBody3D was never returned.


# --- (6) direction is outward from centre ----------------------------------------

func test_impulse_direction_points_outward_from_centre() -> void:
	var start_position: Vector3 = Vector3(RADIUS * 0.4, 0.0, RADIUS * 0.3)
	var body: RigidBody3D = _make_rigid_body(start_position)
	await wait_physics_frames(1)

	SpecialPhysics.explode(_space_state(), Vector3.ZERO, RADIUS, IMPULSE, 1000.0)
	await wait_physics_frames(1)

	# The explosion centre is the world origin here, so the outward direction
	# from centre to the body's own (pre-impulse) position is just its
	# starting position vector.
	assert_gt(
		body.linear_velocity.dot(start_position),
		0.0,
		"the applied impulse must point away from the explosion centre"
	)


# --- config/special_tuning.tres --------------------------------------------------


# --- (7) a multi-shape body (one CollisionShape3D per cell, like a placed
# block) is hit once, not once per shape -------------------------------------

func test_multi_shape_body_is_returned_once_and_gets_one_bodys_worth_of_impulse() -> void:
	var mass: float = 1.0
	var position: Vector3 = Vector3(RADIUS * 0.3, 0.0, 0.0)
	var multi_body: RigidBody3D = _make_multi_shape_rigid_body(position, 6, mass)
	# Same distance from the explosion centre (RADIUS * 0.3) as `multi_body`,
	# so both bodies get the same falloff -- just off the x-axis so it can't
	# collide with `multi_body`'s own shapes (which spread along +x from
	# `position`).
	var single_body: RigidBody3D = _make_rigid_body(Vector3(0.0, 0.0, RADIUS * 0.3), mass)
	await wait_physics_frames(1)

	var max_impulse: float = 1000.0
	var hit: Array[RigidBody3D] = SpecialPhysics.explode(
		_space_state(), Vector3.ZERO, RADIUS, IMPULSE, max_impulse
	)
	await wait_physics_frames(1)

	assert_eq(
		hit.count(multi_body),
		1,
		"a body with 6 CollisionShape3D children must appear exactly once in the returned array"
	)

	var ratio: float = clampf(position.length() / RADIUS, 0.0, 1.0)
	var falloff: float = pow(1.0 - ratio, 2.0)
	var expected_speed: float = clampf(IMPULSE * falloff, 0.0, max_impulse) / mass
	assert_almost_eq(
		multi_body.linear_velocity.length(),
		single_body.linear_velocity.length(),
		SPEED_TOLERANCE,
		"a 6-shape body at the same distance/mass as a 1-shape body must end up at the same speed"
	)
	assert_almost_eq(
		multi_body.linear_velocity.length(),
		expected_speed,
		SPEED_TOLERANCE,
		"a multi-shape body must receive exactly one body's worth of impulse, not one per shape"
	)


func test_special_tuning_resource_has_max_explosion_impulse() -> void:
	var tuning: SpecialTuning = load("res://config/special_tuning.tres") as SpecialTuning
	assert_not_null(tuning)
	assert_eq(tuning.max_explosion_impulse, 30.0)
