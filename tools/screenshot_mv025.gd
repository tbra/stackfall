extends Node
## Windowed smoke-shot for Bontago-mv0.25 (Feel 4a: 3-DOF rotate drag, the
## rotated footprint fix, the removed shadow blob, and the world-space reject
## kick -- docs/rotation-issue.png, owner test 2026-09-22). Boots the real
## sandbox route the same way tools/screenshot_mv017.gd does, then:
##   1. Holds an L-shaped block, rotates it with a combined yaw + pitch (the
##      same apply_free_rotation_delta() path rotate_drag drives) so it is no
##      longer axis-aligned, and shoots it -- the footprint quads below it
##      should show the block's true rotated silhouette (a hexagon/diamond,
##      not the old fixed axis-aligned squares), and there must be no separate
##      grey shadow blob under it.
##   2. Plays the reject animation at that same rotation and shoots mid-arc --
##      the kick should read as a plain world-space hop, not one dragged
##      sideways/backwards by the block's own rotation.
##
## Run windowed (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_mv025.tscn
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts that are not part
## of the running game), alongside tools/screenshot_mv017.gd, which this
## follows the shape of.

const OUTPUT_DIR: String = "user://"
const SETTLE_FRAMES: int = 20


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(3.5 * Engine.physics_ticks_per_second))

	var sandbox: Sandbox = main._sandbox
	var ghost: GhostPreview = sandbox.ghost()

	ghost.set_shape(load("res://config/blocks/L3.tres"))
	# A combined yaw + pitch, the same apply_free_rotation_delta() path
	# rotate_drag (MMB hold + drag) drives continuously -- deliberately not a
	# 90-degree table entry, so the footprint must be a genuinely rotated
	# polygon, not one of the old fixed axis-aligned squares.
	ghost.apply_free_rotation_delta(deg_to_rad(45.0), deg_to_rad(25.0), Vector3.RIGHT)

	await _wait(SETTLE_FRAMES)
	print("SCREENSHOT rotated_l_block free_quaternion=%s footprint_quads=%d ghost_pos=%s" % [
		ghost.free_quaternion, ghost.footprint_quad_count(), ghost.global_position
	])
	await _shoot("01_rotated_l_block_footprint")

	ghost.play_reject_animation()
	await _wait(int(0.15 * Engine.physics_ticks_per_second))
	print("SCREENSHOT mid_reject reject_offset=%s" % [ghost.reject_offset()])
	await _shoot("02_reject_kick_mid_arc")

	get_tree().quit()


func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s%s.png" % [OUTPUT_DIR, name]
	image.save_png(path)
	print("SCREENSHOT %s saved=%s" % [name, ProjectSettings.globalize_path(path)])


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
