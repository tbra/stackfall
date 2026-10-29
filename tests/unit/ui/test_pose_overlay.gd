extends GutTest
## F2 pose overlay (ui/debug/PoseOverlay.gd): key and pad chord (both work with debug off), and the
## visible text following the held block (from the injected match context), the camera and the disc tilt.

const OVERLAY_SCENE: PackedScene = preload("res://ui/debug/PoseOverlay.tscn")

var _overlay: PoseOverlay = null
var _camera: Camera3D = null
var _field: Node3D = null
var _context: FakeMatchContext = null


func before_each() -> void:
	DebugMode.set_override_for_test(true)
	_camera = Camera3D.new()
	add_child_autofree(_camera)
	_field = Field.new()
	add_child_autofree(_field)
	_context = FakeMatchContext.new()
	_overlay = OVERLAY_SCENE.instantiate() as PoseOverlay
	# set() so a missing property fails the behaviour tests, not the parse of this file
	_overlay.set(&"match_context", _context)
	_overlay.camera = _camera
	_overlay.field = _field as Field
	add_child_autofree(_overlay)


func after_each() -> void:
	Input.action_release(&"camera_snap_home")
	DebugMode.clear_override_for_test()


## Every Label text under the overlay; queried by content, not by node name.
func _texts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for node: Node in _overlay.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	return out


func _has_text_containing(fragment: String) -> bool:
	for text: String in _texts():
		if text.contains(fragment):
			return true
	return false


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


func test_f2_toggles_with_debug_off() -> void:
	DebugMode.set_override_for_test(false)
	_press(_f2())
	assert_true(_overlay.is_shown(), "debug off: F2 still opens the panel")
	_press(_f2())
	assert_false(_overlay.is_shown())


func test_f2_toggles_with_debug_on() -> void:
	_press(_f2())
	assert_true(_overlay.is_shown())
	_press(_f2())
	assert_false(_overlay.is_shown())


func test_pad_chord_toggles_with_debug_off() -> void:
	DebugMode.set_override_for_test(false)
	Input.action_press(&"camera_snap_home")
	_press(_pad())
	assert_true(_overlay.is_shown())
	_press(_pad())
	assert_false(_overlay.is_shown())


func test_pad_press_needs_back_held() -> void:
	_press(_pad())
	assert_false(_overlay.is_shown(), "a bare D-pad press is ignored")
	Input.action_press(&"camera_snap_home")
	_press(_pad())
	assert_true(_overlay.is_shown())


func test_nothing_held_shows_no_held_pose() -> void:
	_overlay.set_shown(true)
	assert_false(_has_text_containing("held   pos"), "no held block: no pose line for it")
	assert_true(_texts().has(PoseOverlay.NO_VALUE))


func test_text_follows_held_block_from_injected_context_camera_and_disc() -> void:
	_overlay.set_shown(true)
	var held: LocalHeldView = _context.local_held()
	held.publish(0, BlockShape.new(), Vector3(1.0, 2.0, 3.0), 0, Quaternion.IDENTITY, true, 0.0)
	_camera.global_position = Vector3(4.0, 5.0, 6.0)
	_field.global_basis = Basis(Vector3.RIGHT, deg_to_rad(10.0))
	_overlay.refresh()
	assert_true(_has_text_containing("(1.00, 2.00, 3.00)"), "held position from the injected context")
	assert_true(_has_text_containing("(4.00, 5.00, 6.00)"), "camera position")
	assert_true(_has_text_containing("10.00 deg about (1.00, 0.00, 0.00)"), "disc tilt")
	held.publish(0, BlockShape.new(), Vector3(7.0, 2.0, 3.0), 0, Quaternion(Vector3.UP, deg_to_rad(90.0)), true, 0.0)
	_overlay.refresh()
	assert_true(_has_text_containing("(7.00, 2.00, 3.00)"))
	assert_false(_has_text_containing("(1.00, 2.00, 3.00)"), "the old held position is gone")
	assert_true(_has_text_containing("(0.00, 90.00, 0.00)"))


func test_untilted_disc_reads_zero_about_up() -> void:
	assert_eq(PoseOverlay.tilt_text(Basis.IDENTITY, 2), "disc tilt 0.00 deg about (0.00, 1.00, 0.00)")
