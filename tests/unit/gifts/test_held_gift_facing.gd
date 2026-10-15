extends GutTest
## Bontago-1pi.85.61 / 85.62: the held Rocket and Magnet point their nose along the aim (not
## upright), and every throwable's arc preview starts inside the held model's world AABB.

const NOSE_TOLERANCE_DEG: float = 5.0
const AIM: Vector3 = Vector3(0.6, 0.3, -0.74)
const ARC_GIFTS: Array[StringName] = [&"bomb", &"jumping_bean", &"magnet"]


func after_each() -> void:
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


func _ghost_holding(id: StringName) -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	ghost.set_held_gift(id)
	return ghost


func _nose_world(ghost: GhostPreview, id: StringName) -> Vector3:
	var axis: Vector3 = GiftModelTable.shared().entry_for(id).held_nose_axis
	return (ghost.gift_visual().global_basis * axis).normalized()


func test_table_marks_rocket_and_magnet_nose_forward() -> void:
	for id: StringName in [&"rocket", &"magnet"]:
		assert_ne(GiftModelTable.shared().entry_for(id).held_nose_axis, Vector3.ZERO, String(id))
	assert_eq(GiftModelTable.shared().entry_for(&"bomb").held_nose_axis, Vector3.ZERO)


func test_held_rocket_and_magnet_nose_follows_the_aim_and_is_not_vertical() -> void:
	for id: StringName in [&"rocket", &"magnet"]:
		var ghost: GhostPreview = _ghost_holding(id)
		ghost.set_held_aim(AIM)
		var nose: Vector3 = _nose_world(ghost, id)
		assert_lt(rad_to_deg(nose.angle_to(AIM.normalized())), NOSE_TOLERANCE_DEG, "%s nose on aim" % id)
		assert_lt(absf(nose.dot(Vector3.UP)), 0.99, "%s not standing upright" % id)


func test_held_rocket_without_aim_points_horizontally_along_the_camera() -> void:
	var camera: Camera3D = autofree(Camera3D.new())
	add_child_autofree(camera)
	camera.current = true
	camera.rotation_degrees = Vector3(-30.0, 40.0, 0.0)
	var ghost: GhostPreview = _ghost_holding(&"rocket")
	ghost.set_held_aim(Vector3.ZERO)
	var nose: Vector3 = _nose_world(ghost, &"rocket")
	var forward: Vector3 = -camera.global_transform.basis.z
	forward.y = 0.0
	assert_lt(rad_to_deg(nose.angle_to(forward.normalized())), NOSE_TOLERANCE_DEG)
	assert_almost_eq(nose.y, 0.0, 0.01, "tipped 90 degrees from up")


func test_non_nose_gift_stays_upright() -> void:
	var ghost: GhostPreview = _ghost_holding(&"bomb")
	ghost.set_held_aim(AIM)
	assert_true(ghost.gift_visual().basis.is_equal_approx(Basis.IDENTITY))


func test_arc_origin_lies_inside_the_held_model_for_every_throwable() -> void:
	for id: StringName in ARC_GIFTS:
		var fake: FakeMatch = FakeMatch.new()
		fake.held_special_by_slot[0] = id
		var ghost: GhostPreview = _ghost_holding(id)
		var controller: PlayerController = autofree(PlayerController.new())
		add_child_autofree(controller)
		controller._ghost = ghost
		controller._active_slot = 0
		controller._match = fake
		# No field behind the fake match: surface_y is the ghost height, so drop the min-height lift.
		controller.special_tuning = controller.special_tuning.duplicate() as SpecialTuning
		controller.special_tuning.gift_aim_min_height_m = 0.0
		ghost.global_position = Vector3(1.0, 6.0, 2.0)
		var preview: Dictionary = controller.gift_launch_preview()
		assert_false(preview.is_empty(), "%s is previewable" % id)
		var box: AABB = ghost.gift_visual_world_aabb()
		assert_gt(box.size.length(), 0.0, "%s has a model box" % id)
		assert_true(box.grow(0.001).has_point(preview["origin"] as Vector3), "%s arc starts in the model" % id)
