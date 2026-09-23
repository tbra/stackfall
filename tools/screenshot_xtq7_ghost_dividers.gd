extends Node
## Repro/QA shot for Bontago-xtq.7 (owner report, docs/solid-blocks2-issue.png,
## 2026-09-23): "the ghost blocks are still clearly made up of smaller
## blocks ... I can see the internal dividers inside the ghost blocks and the
## preview is also clearly the smaller blocks footprints ... in the original
## the ghost block projects its whole shape downwards to the disc." Holds a
## tilted bar3 above an already-placed pillar (the owner's own repro pose:
## "the middle section of the ghost block shows up on top of the dropped
## block and the other sections land on the disc") and shoots a screenshot
## plus runtime mesh/footprint/projection diagnostics.
##
## docs/ghost-dividers-before.png / docs/ghost-projection-after.png are this
## script's own before/after captures (the "before" one from the pre-fix
## CULL_DISABLED material and per-cell footprint; re-running this script
## against the current, fixed checkout reproduces the "after" one, not the
## "before" -- those two filenames are historical evidence, not something
## this script re-derives from a flag). Compare against docs/original_in-
## game.png for the reference original behaviour.
##
## Run windowed (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_xtq7_ghost_dividers.tscn
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game), following the shape of tools/screenshot_xtq3_solid_blocks.gd
## and tools/screenshot_mv017.gd.

const OUTPUT_DIR: String = "user://"
const SETTLE_FRAMES: int = 90
const SHOT_NAME: String = "xtq7_pitched_bar3_over_placed_block"


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
	# placed block to hover the pitched bar3 over -- the owner's screenshot
	# shows the ghost's middle section landing on top of a dropped block.
	Match._held_shapes[0] = load("res://config/blocks/pillar.tres")
	var reason: StringName = Match.request_place(0, home + Vector3.UP * 3.0, 0, Quaternion.IDENTITY, false)
	print("SCREENSHOT place pillar reason=%s" % [reason])
	await _wait(SETTLE_FRAMES)

	# 2. Hold bar3, tilted (partial free-rotation pitch, the owner's own
	# rotate-drag gesture -- not a 90-degree step, which for an X-extending
	# bar pitched about X is a geometric no-op), hovering with its middle
	# cell over the placed pillar and its two end cells over open disc --
	# the owner's screenshot pose ("the middle section ... shows up on top
	# of the dropped block and the other sections land on the disc").
	ghost.set_shape(load("res://config/blocks/bar3.tres"))
	ghost.apply_free_rotation_delta(0.0, deg_to_rad(25.0), Vector3.RIGHT)
	controller._cursor = home
	controller._update_ghost_transform()
	await _wait(10)

	# --- Runtime diagnostics: why do dividers render? ---------------------
	var visual: Node3D = null
	for child: Node in ghost.get_children():
		if child.name == "ShapeVisual":
			visual = child as Node3D
			break
	var mesh_child_count: int = visual.get_child_count() if visual != null else -1
	print("SCREENSHOT ghost shape_visual child_count=%d" % mesh_child_count)
	if visual != null:
		for mesh_child: Node in visual.get_children():
			var mesh_instance: MeshInstance3D = mesh_child as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			var mesh: Mesh = mesh_instance.mesh
			var surface_count: int = mesh.get_surface_count()
			for surface_index: int in range(surface_count):
				var arrays: Array = mesh.surface_get_arrays(surface_index)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
				print("SCREENSHOT mesh surface=%d vertex_count=%d triangle_count=%d" % [
					surface_index, verts.size(), indices.size() / 3
				])
	print("SCREENSHOT ghost material cull_mode=%d transparency=%d depth_draw_mode=%d" % [
		ghost._material.cull_mode, ghost._material.transparency, ghost._material.depth_draw_mode
	])
	print("SCREENSHOT footprint_quad_count=%d" % ghost.footprint_quad_count())
	for i: int in range(ghost.footprint_quad_count()):
		print("SCREENSHOT footprint[%d] position=%s polygon=%s" % [
			i, ghost.footprint_quad_position(i), ghost.footprint_polygon_world(i)
		])
	print("SCREENSHOT has_projection_mesh=%s projection_span_y=%s" % [
		ghost.has_projection_mesh(), ghost.projection_span_y()
	])

	# 3. Frame the camera like the owner's screenshot: behind/above, looking
	# down at the pillar with the pitched bar3 hovering over it.
	# The sandbox camera follows the held block every _process() (game/
	# CameraRig.gd), which would silently undo a direct Camera3D.global_position
	# assignment on the next frame -- drive the rig's own yaw/pitch/distance
	# fields instead, same as an owner's manual orbit input would, then let
	# one process frame apply them.
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
