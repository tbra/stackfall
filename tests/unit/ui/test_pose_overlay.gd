extends GutTest
## F2 pose overlay (ui/debug/PoseOverlay.gd): debug gate, key and pad chord, and the visible
## labels following the held block, the camera and the disc tilt.

const OVERLAY_SCENE: PackedScene = preload("res://ui/debug/PoseOverlay.tscn")

var _overlay: PoseOverlay = null
var _camera: Camera3D = null
var _field: Node3D = null


func before_each() -> void:
	DebugMode.set_override_for_test(true)
	_camera = Camera3D.new()
	add_child_autofree(_camera)
	_field = Field.new()
	add_child_autofree(_field)
	_overlay = OVERLAY_SCENE.instantiate() as PoseOverlay
	_overlay.camera = _camera
	_overlay.field = _field as Field
	add_child_autofree(_overlay)


func after_each() -> void:
	Input.action_release(&"camera_snap_home")
	MatchContext.current().local_held().clear()
	DebugMode.clear_override_for_test()


func _label(label_name: String) -> Label:
	return _overlay.find_child(label_name, true, false) as Label


func _press(event: InputEvent) -> void:
	_overlay._unhandled_input(event)


func _f2() -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_F2
	event.pressed = true
	return event


func _pad() -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_DPAD_LEFT
	event.pressed = true
	return event


func test_f2_toggles_only_in_debug_mode() -> void:
	_press(_f2())
	assert_true(_overlay.is_shown())
	_press(_f2())
	assert_false(_overlay.is_shown())
	DebugMode.set_override_for_test(false)
	_press(_f2())
	assert_false(_overlay.is_shown(), "debug off: F2 does nothing")


func test_pad_press_needs_back_held() -> void:
	_press(_pad())
	assert_false(_overlay.is_shown(), "a bare D-pad press is ignored")
	Input.action_press(&"camera_snap_home")
	_press(_pad())
	assert_true(_overlay.is_shown())


func test_labels_follow_held_block_camera_and_disc() -> void:
	_overlay.set_shown(true)
	assert_eq(_label("HeldLabel").text, PoseOverlay.NO_VALUE, "nothing held")
	var held: LocalHeldView = MatchContext.current().local_held()
	held.publish(0, BlockShape.new(), Vector3(1.0, 2.0, 3.0), 0, Quaternion.IDENTITY, true, 0.0)
	_camera.global_position = Vector3(4.0, 5.0, 6.0)
	_field.global_basis = Basis(Vector3.RIGHT, deg_to_rad(10.0))
	_overlay.refresh()
	var first_held: String = _label("HeldLabel").text
	assert_string_contains(first_held, "(1.00, 2.00, 3.00)")
	assert_string_contains(_label("CameraLabel").text, "(4.00, 5.00, 6.00)")
	assert_string_contains(_label("TiltLabel").text, "10.00 deg about (1.00, 0.00, 0.00)")
	held.publish(0, BlockShape.new(), Vector3(7.0, 2.0, 3.0), 0, Quaternion(Vector3.UP, deg_to_rad(90.0)), true, 0.0)
	_overlay.refresh()
	assert_ne(_label("HeldLabel").text, first_held)
	assert_string_contains(_label("HeldLabel").text, "(0.00, 90.00, 0.00)")


func test_untilted_disc_reads_zero_about_up() -> void:
	assert_eq(PoseOverlay.tilt_text(Basis.IDENTITY, 2), "disc tilt 0.00 deg about (0.00, 1.00, 0.00)")
