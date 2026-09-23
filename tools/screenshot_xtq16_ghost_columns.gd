extends Node
## Repro/QA shot for Bontago-xtq.16 (owner playtest 2026-09-23, "the
## projection column visible above the actual cells (S-piece)"): holds S4 at
## identity rotation over bare disc and shoots a screenshot plus runtime
## diagnostics, so the per-silhouette-column prism fix can be compared
## before/after against the old whole-hull cap.
##
## Run windowed (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_xtq16_ghost_columns.tscn
##
## Only reads has_projection_mesh()/projection_span_y() -- both existed
## before this package's own fix too -- so the same probe runs against either
## the pre- or post-fix game/GhostPreview.gd (this file is stash-friendly for
## an owner before/after comparison; the new projection_column_count()/
## projection_column_span_y() test seams are exercised by tests/unit/
## test_ghost_preview.gd instead, not here).
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game), following the shape of tools/screenshot_xtq9_ghost_prism.gd.

const OUTPUT_DIR: String = "user://"
const SETTLE_FRAMES: int = 30
const SHOT_NAME: String = "xtq16_s4_columns"


func _ready() -> void:
	print("SCREENSHOT stage=boot_start")
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	print("SCREENSHOT stage=main_added")

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	print("SCREENSHOT stage=match_started")
	await _wait(int(2.0 * Engine.physics_ticks_per_second))
	print("SCREENSHOT stage=settled")

	var sandbox: Sandbox = main._sandbox
	var ghost: GhostPreview = sandbox.ghost()
	var controller: PlayerController = sandbox.controller()
	var home: Vector3 = Match.default_ghost_origin(0)

	# Hold S4 at identity rotation over the bare disc -- the exact repro pose
	# (config/blocks/S4.tres has a cell at (2, 0, 0) with nothing above it, and
	# a cell at (0, 1, 0) with nothing below it, in the same footprint).
	ghost.set_shape(load("res://config/blocks/S4.tres"))
	ghost.apply_validity(PlacementRules.Result.VALID)
	controller._cursor = home
	controller._update_ghost_transform()
	await _wait(SETTLE_FRAMES)

	print("SCREENSHOT ghost_shape=%s ghost_global_position=%s ghost_visible=%s has_projection_mesh=%s projection_span_y=%s" % [
		ghost.get_shape().id if ghost.get_shape() != null else "null",
		ghost.global_position, ghost.visible,
		ghost.has_projection_mesh(), ghost.projection_span_y()
	])

	var rig: CameraRig = main._camera_rig
	rig._target = ghost.global_position
	rig._yaw = deg_to_rad(20.0)
	rig._pitch = deg_to_rad(-25.0)
	rig._distance = 4.0
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
