extends Node
## Repro/QA shot for Bontago-xtq.9/xtq.10 (owner reports, M:/Bontago-worktrees/
## play/feedback/screenshot_20260923_11*.png, 2026-09-23): "the ghost block
## should be a bit more opaque. the preview starts from the bottom of the
## ghost block which looks a bit weird when it's angled." followed by "the
## projection colour is right but any surface that falls within the
## projection should be a lot brighter (maybe emissive?), and the footprint
## on the disc should be almost white." Holds a tilted bar3 above an
## already-placed pillar (the same repro pose tools/
## screenshot_xtq7_ghost_dividers.gd uses) and shoots a screenshot plus
## runtime tint/material diagnostics.
##
## Run windowed (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_xtq9_ghost_prism.tscn
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game), following the shape of tools/screenshot_xtq7_ghost_dividers.gd.

const OUTPUT_DIR: String = "user://"
const SETTLE_FRAMES: int = 90
const SHOT_NAME: String = "xtq9_pitched_bar3_over_placed_block"


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

	# 1. Drop a pillar (upright, 3 cells tall) at home so there is a real
	# placed block to hover the pitched bar3 over -- same repro pose as the
	# owner's own screenshots.
	Match._held_shapes[0] = load("res://config/blocks/pillar.tres")
	var reason: StringName = Match.request_place(0, home + Vector3.UP * 3.0, 0, Quaternion.IDENTITY, false)
	print("SCREENSHOT place pillar reason=%s" % [reason])
	await _wait(SETTLE_FRAMES)

	# 2. Hold bar3, tilted (partial free-rotation pitch, the owner's own
	# rotate-drag gesture), so the prism's own new top-of-column cap
	# (Bontago-xtq.9) is visibly above the shape rather than cutting through
	# it.
	ghost.set_shape(load("res://config/blocks/bar3.tres"))
	ghost.apply_free_rotation_delta(0.0, deg_to_rad(25.0), Vector3.RIGHT)
	ghost.apply_validity(PlacementRules.Result.VALID)
	controller._cursor = home
	controller._update_ghost_transform()
	await _wait(10)

	# --- Runtime diagnostics -------------------------------------------------
	print("SCREENSHOT ghost body tint=%s" % [ghost.current_tint_color()])
	print("SCREENSHOT ghost footprint tint=%s" % [ghost.current_footprint_tint_color()])
	print("SCREENSHOT ghost_tuning footprint_base_color=%s footprint_hue_strength=%.3f footprint_alpha=%.3f" % [
		ghost.ghost_tuning.footprint_base_color, ghost.ghost_tuning.footprint_hue_strength, ghost.ghost_tuning.footprint_alpha
	])
	print("SCREENSHOT projection tint=%s emission=%s additive_blend=%s emission_enabled=%s energy=%.3f" % [
		ghost.current_projection_tint_color(), ghost.current_projection_emission_color(),
		ghost.projection_uses_additive_blend(), ghost.projection_emission_enabled(),
		ghost.ghost_tuning.projection_emission_energy
	])
	print("SCREENSHOT has_projection_mesh=%s projection_span_y=%s" % [
		ghost.has_projection_mesh(), ghost.projection_span_y()
	])

	# 3. Frame the camera like the owner's screenshot: behind/above, looking
	# down at the pillar with the pitched bar3 hovering over it. The sandbox
	# camera follows the held block every _process() (game/CameraRig.gd),
	# which would silently undo a direct Camera3D.global_position assignment
	# on the next frame -- drive the rig's own yaw/pitch/distance fields
	# instead, then let one process frame apply them.
	var rig: CameraRig = main._camera_rig
	rig._yaw = deg_to_rad(35.0)
	rig._pitch = deg_to_rad(-30.0)
	rig._distance = 7.0
	await get_tree().process_frame
	await get_tree().process_frame
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
