extends GutTest
## ("I can still move the camera with
## the joystick while the round end screen shows"). The camera rig ignores
## orbit/zoom input while the results screen or pause menu is open.

const STICK_FULL: float = 1.0
const YAW_EPSILON: float = 0.0001


func _make_rig() -> CameraRig:
	var rig: CameraRig = load("res://game/player/CameraRig.tscn").instantiate()
	add_child_autofree(rig)
	return rig


func _push_right_stick(value: float) -> void:
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_RIGHT_X
	motion.axis_value = value
	Input.parse_input_event(motion)


func after_each() -> void:
	_push_right_stick(0.0)
	Input.flush_buffered_events()


func test_right_stick_orbits_when_nothing_is_open() -> void:
	var rig: CameraRig = _make_rig()
	var yaw_before: float = rig.get_yaw()
	_push_right_stick(STICK_FULL)
	Input.flush_buffered_events()
	await wait_physics_frames(3)
	rig._process(0.1)
	assert_ne(rig.get_yaw(), yaw_before, "fixture: the stick orbits the camera when no UI is open")


func test_right_stick_does_not_move_camera_while_results_are_open() -> void:
	var rig: CameraRig = _make_rig()
	Events.match_results_ready.emit({})
	assert_true(rig.is_input_blocked())
	var yaw_before: float = rig.get_yaw()
	_push_right_stick(STICK_FULL)
	Input.flush_buffered_events()
	await wait_physics_frames(3)
	rig._process(0.1)
	assert_almost_eq(rig.get_yaw(), yaw_before, YAW_EPSILON, "results screen: stick must not orbit")


func test_pause_menu_blocks_and_releases_camera_input() -> void:
	var rig: CameraRig = _make_rig()
	Events.pause_menu_opened.emit()
	assert_true(rig.is_input_blocked())
	Events.pause_menu_closed.emit()
	assert_false(rig.is_input_blocked())

