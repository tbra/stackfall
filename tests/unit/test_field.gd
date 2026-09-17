extends GutTest
## Field builds its disk from MapDef/PhysicsTuning and frees anything that
## reaches the kill plane (spec 2.1).
##
## M2 replaced the single cylinder collision with the cell grid spec 3.3 asks
## for; the grid itself is covered by test_field_cells.gd, so what is left here
## is the disk's size, its material and the kill plane.


func test_disk_mesh_radius_matches_map_def() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = load("res://config/maps/round_medium.tres")
	field.tuning = load("res://config/physics_tuning.tres")
	add_child_autofree(field)

	var overlay: TerritoryOverlay = field.overlay()
	assert_not_null(overlay, "Field should build the disk's visible surface.")
	var cylinder: CylinderMesh = overlay.mesh as CylinderMesh
	assert_not_null(cylinder, "The disk is drawn as a cylinder.")
	assert_almost_eq(cylinder.top_radius, field.map_def.field_radius, 0.001)
	assert_almost_eq(cylinder.height, field.map_def.disk_height, 0.001)


func test_disk_collision_covers_the_disk() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = load("res://config/maps/round_small.tres")
	add_child_autofree(field)

	# One BoxShape3D per in-disk cell, so the count is the disk's area in
	# cells; a 30 m disk at cell_size 1 is a few thousand of them.
	assert_gt(field.cell_count(), 0, "The disk collides as a grid of cells.")
	assert_eq(field.get_shape_owners().size(), field.cell_count())


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
