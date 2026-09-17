extends GutTest
## Field builds its disk from MapDef/PhysicsTuning and frees anything that
## reaches the kill plane (spec 2.1).


func test_disk_radius_matches_map_def() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = load("res://config/maps/round_medium.tres")
	field.tuning = load("res://config/physics_tuning.tres")
	add_child_autofree(field)

	var collision: CollisionShape3D = null
	for child: Node in field.get_children():
		if child is CollisionShape3D:
			collision = child
			break
	assert_not_null(collision, "Field should build a disk CollisionShape3D.")
	var cylinder: CylinderShape3D = collision.shape as CylinderShape3D
	assert_not_null(cylinder, "The disk collides as a cylinder.")
	assert_almost_eq(cylinder.radius, field.map_def.field_radius, 0.001)


func test_disk_friction_matches_tuning() -> void:
	var field: Field = autofree(Field.new())
	add_child_autofree(field)
	assert_almost_eq(
		field.physics_material_override.friction,
		field.tuning.disk_friction,
		0.0001
	)


func test_kill_plane_frees_the_body_and_emits_event() -> void:
	var field: Field = autofree(Field.new())
	add_child_autofree(field)
	watch_signals(Events)

	var body: RigidBody3D = autofree(RigidBody3D.new())
	add_child_autofree(body)
	field._on_kill_plane_body_entered(body)

	assert_signal_emitted(Events, "block_removed")
	assert_true(body.is_queued_for_deletion(), "The body should be freed once it hits the kill plane.")
