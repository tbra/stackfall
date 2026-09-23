extends Node
## Repro/QA shot for Bontago-xtq.15 (owner playtest 2026-09-23, "the same
## white projection that shows up on the disk should show up on the blocks
## as well, just a bit fainter"): places a real block, holds a ghost cube
## directly above it, and shoots a screenshot plus runtime diagnostics --
## compare against docs/original_hover-preview.png (a placed block inside the
## light shaft reads pale/whitish).
##
## Run windowed (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_xtq15_block_projection.tscn
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game), following the shape of tools/screenshot_xtq9_ghost_prism.gd.

const OUTPUT_DIR: String = "user://"
const SETTLE_FRAMES: int = 90
const SHOT_NAME: String = "xtq15_block_projection"


func _ready() -> void:
	print("SCREENSHOT stage=boot_start")
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	print("SCREENSHOT stage=main_added")

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	print("SCREENSHOT stage=match_started")
	await _wait(int(3.5 * Engine.physics_ticks_per_second))
	print("SCREENSHOT stage=settled")

	var sandbox: Sandbox = main._sandbox
	var ghost: GhostPreview = sandbox.ghost()
	var controller: PlayerController = sandbox.controller()
	var home: Vector3 = Match.default_ghost_origin(0)

	# 1. Drop a single cube at home so there is a real placed block for the
	# decal to paint onto (the exact repro pose: a placed block *inside* the
	# hovering ghost's own light shaft).
	Match._held_shapes[0] = load("res://config/blocks/cube.tres")
	var reason: StringName = Match.request_place(0, home + Vector3.UP * 3.0, 0, Quaternion.IDENTITY, false)
	print("SCREENSHOT place cube reason=%s" % [reason])
	await _wait(SETTLE_FRAMES)

	# 2. Hold another cube directly above it, identity rotation (a single
	# silhouette column, matching docs/original_hover-preview.png exactly).
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	ghost.apply_validity(PlacementRules.Result.VALID)
	controller._cursor = home
	controller._update_ghost_transform()
	await _wait(10)

	print("SCREENSHOT ghost_shape=%s has_projection_mesh=%s projection_span_y=%s" % [
		ghost.get_shape().id if ghost.get_shape() != null else "null",
		ghost.has_projection_mesh(), ghost.projection_span_y()
	])
	print("SCREENSHOT decal visible=%s size=%s position=%s color=%s" % [
		ghost.block_projection_decal_visible(), ghost.block_projection_decal_size(),
		ghost.block_projection_decal_position(), ghost.block_projection_decal_color()
	])

	var rig: CameraRig = main._camera_rig
	rig._target = ghost.global_position
	rig._yaw = deg_to_rad(20.0)
	rig._pitch = deg_to_rad(-25.0)
	rig._distance = 4.0
	await get_tree().process_frame
	await get_tree().process_frame

	# Re-assert the held shape right before the shot -- the sandbox's own
	# feed cadence can re-issue a piece to this slot at any point during the
	# waits above (Events.feed_block_issued -> PlayerController._on_feed_
	# block_issued() -> _ghost.set_shape()), silently overriding this probe's
	# own manual override again. Pinning it here (no more awaits afterward)
	# guarantees the screenshot shows exactly what this probe asked for.
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	controller._update_ghost_transform()
	print("SCREENSHOT re-asserted ghost_shape=%s" % [ghost.get_shape().id if ghost.get_shape() != null else "null"])
	print("SCREENSHOT rig yaw=%.3f pitch=%.3f distance=%.3f target=%s camera_global=%s" % [
		rig._yaw, rig._pitch, rig._distance, rig._target, rig.get_node("Camera3D").global_position
	])
	await _shoot(SHOT_NAME)

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
