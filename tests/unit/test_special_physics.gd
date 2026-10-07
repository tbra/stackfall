extends GutTest
## SpecialPhysics.query_bodies_in_range() tests (spec 3.5 "Explosions";
## docs/M8_PLAN.md "Interface stubs" item 1). Real RigidBody3D/StaticBody3D
## bodies added directly to the test's own tree -- a physics smoke test, not
## a stubbed unit test -- proving the sphere-query, radius cutoff, exclude
## list, owner filter and StaticBody3D skip this package's contract describes.
##
## DECISION (tests/unit/test_special_physics.gd): builds bare RigidBody3D/
## StaticBody3D fixtures directly rather than a real Field + BlockFactory
## Block -- query_bodies_in_range()'s own contract returns Array[RigidBody3D]
## and is agnostic to Block; it only needs "a real rigid body" and "a real
## static body" to prove every acceptance case, and a full Field's disk mesh
## is unrelated cost this package doesn't own (test_tower_placement.gd notes
## a tiny map already costs real seconds to build).

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




# --- config/special_tuning.tres --------------------------------------------------

func test_special_tuning_resource_has_a_usable_max_explosion_impulse() -> void:
	var tuning: SpecialTuning = load("res://config/special_tuning.tres") as SpecialTuning
	assert_not_null(tuning)
	assert_gt(tuning.max_explosion_impulse, 0.0, "a clamp of zero or less would disable every blast")


# --- query_bodies_in_range() ---------------------------------------------------
## Query-only sibling of ExplosionFx.blast() (docs/M8_PLAN.md "Interface stubs" item 1):
## same sphere-query + dedupe, no impulse/wake/mark_script_kick.

func test_query_returns_multi_shape_body_exactly_once() -> void:
	var position: Vector3 = Vector3(RADIUS * 0.3, 0.0, 0.0)
	var multi_body: RigidBody3D = _make_multi_shape_rigid_body(position, 6)
	await wait_physics_frames(1)

	var hit: Array[RigidBody3D] = SpecialPhysics.query_bodies_in_range(
		_space_state(), Vector3.ZERO, RADIUS, []
	)

	assert_eq(
		hit.count(multi_body),
		1,
		"a body with 6 CollisionShape3D children must appear exactly once"
	)
	assert_eq(
		multi_body.linear_velocity,
		Vector3.ZERO,
		"query_bodies_in_range() must not apply any impulse"
	)


func test_query_owner_filter_excludes_and_includes_as_expected() -> void:
	var enemy_block: Block = Block.new()
	enemy_block.owner_slot = 1
	var enemy_collision: CollisionShape3D = CollisionShape3D.new()
	var enemy_shape: SphereShape3D = SphereShape3D.new()
	enemy_shape.radius = 0.3
	enemy_collision.shape = enemy_shape
	enemy_block.add_child(enemy_collision)
	add_child(enemy_block)
	enemy_block.global_position = Vector3(RADIUS * 0.5, 0.0, 0.0)
	_bodies.append(enemy_block)

	var own_block: Block = Block.new()
	own_block.owner_slot = 0
	var own_collision: CollisionShape3D = CollisionShape3D.new()
	var own_shape: SphereShape3D = SphereShape3D.new()
	own_shape.radius = 0.3
	own_collision.shape = own_shape
	own_block.add_child(own_collision)
	add_child(own_block)
	own_block.global_position = Vector3(RADIUS * 0.5, 0.0, 1.0)
	_bodies.append(own_block)
	await wait_physics_frames(1)

	var mover_owner_slot: int = 0
	var enemy_only_filter: Callable = func(body: RigidBody3D) -> bool:
		var block: Block = body as Block
		return block != null and block.owner_slot != mover_owner_slot

	var hit: Array[RigidBody3D] = SpecialPhysics.query_bodies_in_range(
		_space_state(), Vector3.ZERO, RADIUS, [], enemy_only_filter
	)

	assert_has(hit, enemy_block, "the filter must include a body it returns true for")
	assert_does_not_have(hit, own_block, "the filter must exclude a body it returns false for")


func test_query_radius_zero_or_negative_returns_empty() -> void:
	_make_rigid_body(Vector3(RADIUS * 0.1, 0.0, 0.0))
	await wait_physics_frames(1)

	var hit_zero: Array[RigidBody3D] = SpecialPhysics.query_bodies_in_range(
		_space_state(), Vector3.ZERO, 0.0, []
	)
	var hit_negative: Array[RigidBody3D] = SpecialPhysics.query_bodies_in_range(
		_space_state(), Vector3.ZERO, -1.0, []
	)

	assert_eq(hit_zero.size(), 0, "radius 0 must return an empty array")
	assert_eq(hit_negative.size(), 0, "a negative radius must return an empty array")


func test_query_excluded_rid_is_not_returned() -> void:
	var excluded_body: RigidBody3D = _make_rigid_body(Vector3(RADIUS * 0.5, 0.0, 0.0))
	var other_body: RigidBody3D = _make_rigid_body(Vector3(RADIUS * 0.5, 0.0, 1.0))
	await wait_physics_frames(1)

	var exclude: Array[RID] = [excluded_body.get_rid()]
	var hit: Array[RigidBody3D] = SpecialPhysics.query_bodies_in_range(
		_space_state(), Vector3.ZERO, RADIUS, exclude
	)

	assert_does_not_have(hit, excluded_body)
	assert_has(hit, other_body, "a non-excluded body in range must still be returned")
