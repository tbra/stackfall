extends GutTest
## Bontago-sen.5: the minimap must follow the rendered camera every frame.


func _make_minimap() -> Minimap:
	var minimap: Minimap = Minimap.new()
	add_child_autofree(minimap)
	minimap.set_map_def(MapDef.new())
	return minimap


func test_process_runs_after_camera_rig() -> void:
	var minimap: Minimap = _make_minimap()
	var rig: CameraRig = load("res://game/CameraRig.tscn").instantiate()
	add_child_autofree(rig)
	assert_gt(minimap.process_priority, rig.process_priority)


func test_process_step_matches_current_camera_yaw() -> void:
	var minimap: Minimap = _make_minimap()
	var camera: Camera3D = Camera3D.new()
	add_child_autofree(camera)
	camera.current = true
	camera.rotation.y = 0.7
	minimap._process(0.016)
	var forward: Vector3 = -camera.global_transform.basis.z
	assert_almost_eq(minimap._camera_forward.x, Vector2(forward.x, forward.z).normalized().x, 0.0001)
	assert_almost_eq(minimap._camera_forward.y, Vector2(forward.x, forward.z).normalized().y, 0.0001)


func test_cached_image_is_rotated_to_current_basis_between_rebuilds() -> void:
	var minimap: Minimap = _make_minimap()
	var center: Vector2 = Vector2(80.0, 80.0)
	assert_true(minimap.image_to_current_transform(center).is_equal_approx(Transform2D.IDENTITY))
	# Quarter turn: forward (0,1) -> (1,0), right (1,0) -> (0,-1); no image rebuild.
	minimap.set_camera_basis(Vector2(0.0, -1.0), Vector2(1.0, 0.0))
	var xf: Transform2D = minimap.image_to_current_transform(center)
	assert_false(xf.is_equal_approx(Transform2D.IDENTITY))
	assert_almost_eq(xf * center, center, Vector2(0.001, 0.001))
	# Old "ahead" is now to the camera's left after turning toward +x.
	var up: Vector2 = xf * (center + Vector2(0.0, -50.0))
	assert_almost_eq(up.x, center.x - 50.0, 0.001)
	assert_almost_eq(up.y, center.y, 0.001)
	minimap.render_now()
	assert_true(minimap.image_to_current_transform(center).is_equal_approx(Transform2D.IDENTITY))
