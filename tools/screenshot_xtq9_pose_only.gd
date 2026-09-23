extends Node
## Minimal before/after pose capture for Bontago-xtq.9/xtq.10 -- unlike
## tools/screenshot_xtq9_ghost_prism.gd (this package's own diagnostics
## script), this one calls no GhostPreview/GhostTuning API newer than
## Bontago-xtq.7, so the *same* script can be run against a stashed
## pre-package checkout (git checkout -- game/GhostPreview.gd
## config/GhostTuning.gd config/ghost_tuning.tres) to produce a true "before"
## screenshot, then again after `git stash pop` for the "after" one. Not a
## permanent regression fixture -- a one-off manual-QA aid for this package's
## own before/after evidence; safe to delete once reviewed.
##
## Run windowed:
##   godot --path . --scene res://tools/screenshot_xtq9_pose_only.tscn

const OUTPUT_DIR: String = "user://"
const SETTLE_FRAMES: int = 90
const SHOT_NAME: String = "xtq9_pose_only"


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(3.5 * Engine.physics_ticks_per_second))

	var sandbox: Sandbox = main._sandbox
	var ghost: GhostPreview = sandbox.ghost()
	var controller: PlayerController = sandbox.controller()
	var home: Vector3 = Match.default_ghost_origin(0)

	Match._held_shapes[0] = load("res://config/blocks/pillar.tres")
	Match.request_place(0, home + Vector3.UP * 3.0, 0, Quaternion.IDENTITY, false)
	await _wait(SETTLE_FRAMES)

	ghost.set_shape(load("res://config/blocks/bar3.tres"))
	ghost.apply_free_rotation_delta(0.0, deg_to_rad(25.0), Vector3.RIGHT)
	ghost.apply_validity(PlacementRules.Result.VALID)
	controller._cursor = home
	controller._update_ghost_transform()
	await _wait(10)

	var rig: CameraRig = main._camera_rig
	rig._yaw = deg_to_rad(35.0)
	rig._pitch = deg_to_rad(-30.0)
	rig._distance = 7.0
	await get_tree().process_frame
	await get_tree().process_frame
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
