extends GutTest
## game/CameraRig.gd's own coverage (previously only exercised indirectly
## through test_playercontroller_mouse.gd's follow-block tests).
##
## Bontago-mv0.17 item 4 (owner feel report: "on match start the follow
## camera's yaw must look from the player's home flag toward the disk
## centre"): CameraRig.set_home_view() is what PlayerController.
## set_home_position() calls once a controller binds to a real slot
## (game/HotSeat.gd's bind_local_slot(), game/Sandbox.gd's own turn-changed
## handler) — see those files' own DECISION comments for who calls this and
## why.


func _make_rig() -> CameraRig:
	var rig: CameraRig = load("res://game/CameraRig.tscn").instantiate()
	add_child_autofree(rig)
	return rig


func test_set_home_view_points_the_rig_from_home_toward_the_center() -> void:
	var rig: CameraRig = _make_rig()

	var home: Vector3 = Vector3(0.0, 0.0, 20.0)
	rig.set_home_view(home)

	var expected_yaw: float = atan2(home.x, home.z)
	assert_almost_eq(rig.get_yaw(), expected_yaw, 0.001)
	assert_almost_eq(rig.get_target().x, home.x, 0.001)
	assert_almost_eq(rig.get_target().z, home.z, 0.001)


func test_set_home_view_camera_looks_toward_the_center_not_away_from_it() -> void:
	var rig: CameraRig = _make_rig()

	# A home flag out on the +X rim; the centre (the default look_at_position)
	# is the world origin.
	rig.set_home_view(Vector3(20.0, 0.0, 0.0))

	var camera: Camera3D = rig.get_camera()
	var facing: Vector3 = -camera.global_transform.basis.z  # Camera3D looks down its own -Z.
	assert_lt(facing.x, 0.0, "from a home flag on the +X rim, the camera should face back toward the centre (-X), not out toward the rim.")


func test_set_home_view_seeds_the_follow_position_so_there_is_no_snap_back() -> void:
	var rig: CameraRig = _make_rig()
	assert_true(rig.tuning.follow_block, "fixture: follow_block defaults to true.")

	var home: Vector3 = Vector3(-8.0, 0.0, 3.0)
	rig.set_home_view(home)
	# Bontago-mv0.17: set_home_view() also seeds _follow_position, so a single
	# _process() tick right after binding does not visibly pull the target
	# away from home_position before PlayerController's own
	# set_follow_position() call this same frame arrives.
	rig._process(1.0 / 60.0)

	assert_almost_eq(rig.get_target().x, home.x, 0.01)
	assert_almost_eq(rig.get_target().z, home.z, 0.01)


func test_set_home_view_with_a_home_position_already_at_the_center_keeps_the_previous_yaw() -> void:
	var rig: CameraRig = _make_rig()
	rig.set_home_view(Vector3(15.0, 0.0, 0.0))
	var yaw_before: float = rig.get_yaw()

	# A degenerate "home == centre" input must not divide by a zero-length
	# direction; the yaw should simply stay put.
	rig.set_home_view(Vector3.ZERO)

	assert_almost_eq(rig.get_yaw(), yaw_before, 0.001)
