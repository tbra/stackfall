extends GutTest
## GlueEffect (spec 2.6 "[NEW] joins touching blocks of yours within 4 m with
## breakable joints, break force 40"; docs/M8_PLAN.md's P3-GLUE package).
## detonate() has no physics_tick()/wants_early_trigger() override -- every
## pairing test below calls it directly against real Block bodies added to
## the test's own tree, the same physics-smoke-test shape
## tests/unit/test_bomb_effect.gd and tests/unit/test_special_physics.gd use.
## GlueJoint's stress-break tests drive apply_stress_sample() directly, the
## documented seam that bypasses the velocity-delta computation so a test can
## assert the break/keep decision against a chosen number.

const RADIUS: float = 4.0
const BREAK_FORCE: float = 40.0

var _nodes: Array[Node] = []


## Synchronous free() -- not queue_free() -- so no stale collider lingers in
## the physics world for even one frame into the next test, mirroring
## tests/unit/test_bomb_effect.gd's own after_each(). Tracks both Node3D
## bodies and any bare GlueJoint (a plain Node) a test added directly.
func after_each() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


## A real Block with a small sphere collider and owner_slot set, mirroring
## tests/unit/test_bomb_effect.gd's own _make_block() plus the owner_slot
## this special's own-owner query filter needs.
func _make_block(position: Vector3, owner_slot: int) -> Block:
	var block: Block = Block.new()
	block.owner_slot = owner_slot
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
	# DECISION (tests/unit/test_glue_effect.gd, matches
	# tests/unit/test_bomb_effect.gd's own DECISION): add_child() before
	# setting global_position -- Node3D.global_position needs
	# is_inside_tree() to resolve a global transform.
	add_child(block)
	block.global_position = position
	_nodes.append(block)
	return block


## A plain RigidBody3D for GlueJoint's own stress-sample tests, which never
## query real physics -- only real enough to hand bind() valid Object
## instances for its `is_instance_valid(_body_*)` guard.
func _make_rigid_body(position: Vector3) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.mass = 1.0
	body.gravity_scale = 0.0
	add_child(body)
	body.global_position = position
	_nodes.append(body)
	return body


## Every GlueJoint this special creates is a direct child of the detonating
## block (GlueEffect._glue_pair()'s own build order).
func _find_glue_joints(host: Node) -> Array[GlueJoint]:
	var joints: Array[GlueJoint] = []
	for child: Node in host.get_children():
		if child is GlueJoint:
			joints.append(child as GlueJoint)
	return joints


func _make_effect() -> GlueEffect:
	var effect: GlueEffect = GlueEffect.new()
	effect.glue_radius_m = RADIUS
	effect.break_force = BREAK_FORCE
	return effect


# --- detonate(): a touching own-owner pair forms exactly one joint ----------

func test_detonate_glues_a_touching_own_owner_pair() -> void:
	var host: Block = _make_block(Vector3.ZERO, 3)
	var neighbor: Block = _make_block(Vector3(1.0, 0.0, 0.0), 3)
	var effect: GlueEffect = _make_effect()
	await wait_physics_frames(2)

	effect.detonate(host, null, 0)

	var joints: Array[GlueJoint] = _find_glue_joints(host)
	assert_eq(joints.size(), 1, "a touching own-owner pair must form exactly one GlueJoint")
	if joints.size() == 1:
		var inner: Generic6DOFJoint3D = null
		for child: Node in joints[0].get_children():
			if child is Generic6DOFJoint3D:
				inner = child as Generic6DOFJoint3D
		assert_not_null(inner, "the GlueJoint must own a Generic6DOFJoint3D child")
		if inner != null:
			assert_eq(inner.node_a, host.get_path())
			assert_eq(inner.node_b, neighbor.get_path())


# --- detonate(): a non-touching own-owner pair forms no joint ---------------

func test_detonate_does_not_glue_a_non_touching_own_owner_pair() -> void:
	var host: Block = _make_block(Vector3.ZERO, 3)
	_make_block(Vector3(2.0, 0.0, 0.0), 3)
	var effect: GlueEffect = _make_effect()
	await wait_physics_frames(2)

	effect.detonate(host, null, 0)

	assert_eq(
		_find_glue_joints(host).size(),
		0,
		"a pair further apart than the touching threshold must not be glued"
	)


# --- detonate(): a touching enemy pair forms no joint -----------------------

func test_detonate_does_not_glue_a_touching_enemy_pair() -> void:
	var host: Block = _make_block(Vector3.ZERO, 3)
	_make_block(Vector3(1.0, 0.0, 0.0), 4)
	var effect: GlueEffect = _make_effect()
	await wait_physics_frames(2)

	effect.detonate(host, null, 0)

	assert_eq(
		_find_glue_joints(host).size(),
		0,
		"a touching pair owned by a different player must not be glued"
	)


# --- config/specials/glue.tres loads with the contract defaults -------------

func test_glue_tres_loads_with_expected_id_and_effect_defaults() -> void:
	var defs: Array[SpecialDef] = SpecialDef.load_all_specials()
	var found: SpecialDef = null
	for def: SpecialDef in defs:
		if def.id == &"glue":
			found = def
			break
	assert_not_null(found, "config/specials/glue.tres must be found by load_all_specials()")
	if found == null:
		return
	assert_true(found.effect is GlueEffect, "glue.tres's effect sub-resource must be a GlueEffect")
	var effect: GlueEffect = found.effect as GlueEffect
	assert_eq(effect.glue_radius_m, 4.0)
	assert_eq(effect.break_force, 40.0)


# --- GlueJoint.apply_stress_sample(): above break_force frees the joint -----

func test_glue_joint_frees_itself_and_joint_above_break_force() -> void:
	var body_a: RigidBody3D = _make_rigid_body(Vector3.ZERO)
	var body_b: RigidBody3D = _make_rigid_body(Vector3(1.0, 0.0, 0.0))
	var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	var glue_joint: GlueJoint = GlueJoint.new()
	glue_joint.add_child(joint)
	add_child(glue_joint)
	_nodes.append(glue_joint)
	glue_joint.bind(joint, body_a, body_b, BREAK_FORCE)

	glue_joint.apply_stress_sample(BREAK_FORCE + 1.0)
	# Two frames so a queue_free()d node is actually gone before the
	# assertion, matching tests/unit/test_headless_bot_match.gd's own idiom.
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(is_instance_valid(joint), "a stress sample above break_force must free the joint")
	assert_false(
		is_instance_valid(glue_joint), "a stress sample above break_force must free the GlueJoint too"
	)


# --- GlueJoint.apply_stress_sample(): below break_force keeps the joint -----

func test_glue_joint_keeps_joint_below_break_force() -> void:
	var body_a: RigidBody3D = _make_rigid_body(Vector3.ZERO)
	var body_b: RigidBody3D = _make_rigid_body(Vector3(1.0, 0.0, 0.0))
	var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	var glue_joint: GlueJoint = GlueJoint.new()
	glue_joint.add_child(joint)
	add_child(glue_joint)
	_nodes.append(glue_joint)
	glue_joint.bind(joint, body_a, body_b, BREAK_FORCE)

	glue_joint.apply_stress_sample(BREAK_FORCE - 1.0)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(is_instance_valid(joint), "a stress sample below break_force must keep the joint")
	assert_true(is_instance_valid(glue_joint), "a stress sample below break_force must keep the GlueJoint")
