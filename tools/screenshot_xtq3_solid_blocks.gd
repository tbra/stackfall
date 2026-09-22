extends Node
## Windowed smoke-shot for Bontago-xtq.3 (owner feel report "our blocks are
## made up of many smaller blocks, is that necessary? the original just has
## solid shapes"): places several multi-cube shapes side by side and shoots a
## screenshot so a human can confirm each one now renders as one seamless
## solid mesh instead of a visible grid of per-cell cubes.
##
## Run windowed (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_xtq3_solid_blocks.tscn
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game), following the shape of tools/screenshot_mv017.gd.

const OUTPUT_DIR: String = "user://"
const SETTLE_FRAMES: int = 90
const SHAPE_IDS: Array[String] = ["bar4", "L4", "slab6", "T4", "cube"]
const ROW_SPACING: float = 2.5


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(3.5 * Engine.physics_ticks_per_second))

	var home: Vector3 = Match.default_ghost_origin(0)
	var index: int = 0
	for shape_id: String in SHAPE_IDS:
		var shape: BlockShape = load("res://config/blocks/%s.tres" % shape_id)
		Match._held_shapes[0] = shape
		var offset: Vector3 = Vector3((index - (SHAPE_IDS.size() - 1) * 0.5) * ROW_SPACING, 2.0, 0.0)
		var reason: StringName = Match.request_place(0, home + offset, 0, Quaternion.IDENTITY, false)
		if reason != &"":
			# Bontago-xtq.3 QA tool only: the very first request right after
			# boot can land while the feed's own release lock hasn't cleared
			# yet -- one retry a few frames later is enough headroom.
			await _wait(30)
			Match._held_shapes[0] = shape
			reason = Match.request_place(0, home + offset, 0, Quaternion.IDENTITY, false)
		print("SCREENSHOT place shape=%s offset=%s reason=%s" % [shape_id, offset, reason])
		await _wait(SETTLE_FRAMES)
		index += 1

	await _wait(SETTLE_FRAMES)

	var rig: CameraRig = main._camera_rig
	var camera: Camera3D = rig.get_node("Camera3D")
	var look_from: Vector3 = home + Vector3(0.0, 6.0, 10.0)
	camera.global_position = look_from
	camera.look_at(home + Vector3.UP, Vector3.UP)

	await get_tree().process_frame
	print("SCREENSHOT xtq3 shapes placed=%s home=%s" % [SHAPE_IDS, home])
	await _shoot("xtq3_solid_blocks")

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
