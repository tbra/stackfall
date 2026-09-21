extends Node
## Windowed smoke-shot of Bontago-mv0.14's original-style block-locked
## controls (spec 1.5/2.5, docs/ORIGINAL_BONTAGO_NOTES.md "Controls"): the
## implementer-R gate asks to "move the block with the mouse and confirm the
## camera follows, wheel changes height, hold rotation mode + mouse snaps
## rotations, hold camera mode orbits" by hand. Synthetic OS-level input
## injection has been unreliable in this environment before, so this instead
## drives the exact same functions a real mouse's events would reach --
## PlayerController._unhandled_input() and CameraRig._unhandled_input(), fed
## hand-built InputEventMouseMotion/InputEventMouseButton objects, the same
## seam tests/unit/test_playercontroller_mouse.gd exercises headlessly -- and
## saves one PNG per step so a human can eyeball the *rendered* result. It is
## not a substitute for an owner actually moving a real mouse.
##
## Boots the real sandbox route the same way tools/screenshot_sandbox.gd does.
## Run windowed (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_controls_mv014.tscn
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts that are not part
## of the running game), alongside tools/screenshot_sandbox.gd.

const OUTPUT_DIR: String = "user://"
const SETTLE_FRAMES: int = 15

var _bar3: BlockShape = preload("res://config/blocks/bar3.tres")


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(3.5 * Engine.physics_ticks_per_second))

	var sandbox: Sandbox = main._sandbox
	var controller: PlayerController = sandbox.controller()
	var ghost: GhostPreview = sandbox.ghost()
	var rig: CameraRig = main._camera_rig

	# An off-centre shape so rotation is visible in a screenshot (a cube looks
	# the same in every orientation).
	ghost.set_shape(_bar3)
	await _wait(SETTLE_FRAMES)
	await _shoot("01_boot", controller, rig, ghost)

	# Step 1: mouse motion moves the ghost; the camera (follow_block, default
	# true) should have visibly moved with it by the time we shoot.
	for _i: int in range(40):
		controller._unhandled_input(_motion(Vector2(15.0, 0.0)))
		await get_tree().process_frame
	await _wait(SETTLE_FRAMES)
	await _shoot("02_mouse_moved_ghost_camera_followed", controller, rig, ghost)

	# Step 2: the wheel raises the block's hover height.
	for _i: int in range(6):
		controller._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	await _wait(SETTLE_FRAMES)
	await _shoot("03_wheel_raised_height", controller, rig, ghost)

	# Step 3: hold rotation_mode + motion snaps the orientation by 90 degrees.
	Input.action_press(&"rotation_mode")
	controller._unhandled_input(_motion(Vector2(260.0, 0.0)))
	Input.action_release(&"rotation_mode")
	await _wait(SETTLE_FRAMES)
	await _shoot("04_rotation_mode_snapped_orientation", controller, rig, ghost)

	# Step 4: hold camera_mode + motion orbits the camera instead of moving
	# the block.
	var cursor_before: Vector3 = controller._cursor
	Input.action_press(&"camera_mode")
	for _i: int in range(30):
		var motion: InputEventMouseMotion = _motion(Vector2(20.0, 0.0))
		rig._unhandled_input(motion)
		controller._unhandled_input(motion)
		await get_tree().process_frame
	Input.action_release(&"camera_mode")
	await _wait(SETTLE_FRAMES)
	await _shoot("05_camera_mode_orbited_camera_not_block", controller, rig, ghost)
	print("SCREENSHOT camera_mode cursor unchanged: %s (before=%s after=%s)" % [
		cursor_before.is_equal_approx(controller._cursor), cursor_before, controller._cursor
	])

	get_tree().quit()


func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.relative = relative
	return event


func _wheel(button: MouseButton) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _shoot(name: String, controller: PlayerController, rig: CameraRig, ghost: GhostPreview) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s%s.png" % [OUTPUT_DIR, name]
	image.save_png(path)
	print("SCREENSHOT %s saved=%s cursor=%s hover_offset=%.2f orientation_index=%d rig_yaw=%.3f rig_target=%s" % [
		name, ProjectSettings.globalize_path(path), controller._cursor,
		ghost.manual_hover_offset, ghost.orientation_index, rig.get_yaw(), rig.get_target()
	])


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
