extends Node
## Windowed smoke-shot for the Bontago-mv0.17 owner feel pass (six items:
## lower follow lag, remove the wedge block, bottom-centre pivot, camera
## starts at home looking toward the centre, wheel-only height, footprint
## projection). Boots the real sandbox route the same way
## tools/screenshot_sandbox.gd does, then:
##   1. Shoots right after boot -- the camera should already be behind the
##      held block, looking from the home flag toward the disk centre (item
##      4), with the block sitting at hover height above the disk and its
##      footprint projected below it (items 3, 5, 6).
##   2. Places several blocks in a row, printing each held shape's id, so a
##      human (or this log) can confirm none of them is ever "wedge" (item 2
##      -- config/blocks/wedge.tres no longer exists, so the bag cannot deal
##      it; this is the visual half of that check, the unit tests are the
##      other half).
##   3. Raises the ghost with the wheel and shoots again, to show the wheel
##      is what changes height (item 5) and the footprint follows it down.
##
## Run windowed (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_mv017.tscn
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts that are not part
## of the running game), alongside tools/screenshot_sandbox.gd and
## tools/screenshot_controls_mv014.gd, which this follows the shape of.

const OUTPUT_DIR: String = "user://"
const SETTLE_FRAMES: int = 20
const PLACEMENTS_TO_CYCLE: int = 8


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(3.5 * Engine.physics_ticks_per_second))

	var sandbox: Sandbox = main._sandbox
	var ghost: GhostPreview = sandbox.ghost()
	var rig: CameraRig = main._camera_rig

	await _wait(SETTLE_FRAMES)
	print("SCREENSHOT boot home_position=%s ghost_pos=%s rig_yaw=%.3f rig_target=%s footprint_quads=%d" % [
		Match.slot(0).home_position, ghost.global_position, rig.get_yaw(), rig.get_target(),
		ghost.footprint_quad_count()
	])
	await _shoot("01_boot_home_view_and_footprint")

	# Cycle several placements at the home flag (always valid: it is inside
	# the player's own territory) and print every held shape's id -- item 2's
	# visual confirmation that the wedge never comes up.
	var seen_ids: Array[String] = []
	for i: int in range(PLACEMENTS_TO_CYCLE):
		var shape: BlockShape = Match.held_shape(0)
		var shape_id: String = String(shape.id) if shape != null else "<none>"
		seen_ids.append(shape_id)
		var spot: Vector3 = Match.default_ghost_origin(0) + Vector3.UP * 3.0
		Match.request_place(0, spot, 0, Quaternion.IDENTITY, false)
		await _wait(SETTLE_FRAMES)
		if i == PLACEMENTS_TO_CYCLE - 1:
			await _shoot("02_after_%d_placements" % PLACEMENTS_TO_CYCLE)
	print("SCREENSHOT shapes dealt over %d placements: %s (wedge present: %s)" % [
		PLACEMENTS_TO_CYCLE, seen_ids, seen_ids.has("wedge")
	])

	# Raise with the wheel only -- item 5. The footprint should follow the
	# ghost's new XZ (unchanged here) but the ghost's own height is now
	# purely this manual offset on top of the disk surface.
	for _i: int in range(6):
		sandbox.controller()._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	await _wait(SETTLE_FRAMES)
	print("SCREENSHOT after wheel-raise manual_hover_offset=%.2f ghost_pos=%s footprint_quads=%d" % [
		ghost.manual_hover_offset, ghost.global_position, ghost.footprint_quad_count()
	])
	await _shoot("03_wheel_raised_only")

	get_tree().quit()


func _wheel(button: MouseButton) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s%s.png" % [OUTPUT_DIR, name]
	image.save_png(path)
	print("SCREENSHOT %s saved=%s" % [name, ProjectSettings.globalize_path(path)])


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
