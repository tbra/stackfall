extends Node
## Windowed smoke-shot for Bontago-xtq.40 (owner playtest: "ghost block
## renders without any lines"): verifies the held placement ghost's own
## translucent shape body now draws the same thin dark cell-grid lines a real
## placed block does (shaders/ghost_cell_grid.gdshader, game/GhostPreview.gd),
## at the real follow-camera distance -- CameraTuning's shipped defaults
## (follow_distance/follow_pitch_deg, game/CameraRig.gd's
## apply_follow_tuning()) -- same idiom as tools/screenshot_xtq35_haze.gd.
##
## Boots the real Main.tscn/sandbox so this exercises the actual
## GhostPreview/BlockFactory wiring, not a hand-built substitute. A real
## GhostPreview node is built directly (GhostPreview.new() + set_shape() +
## update_placement()), mirroring tests/unit/test_ghost_preview.gd's own
## _make_ghost() convention -- the simplest way to get one on screen without
## wiring a full PlayerController input path for a screenshot probe.
##
## Fix round precedent (xtq28/xtq35): an off-screen (--position 10000,10000)
## window is clamped by Windows to a tiny size, so capture goes through a
## fixed CAPTURE_SIZE SubViewport sharing the live World3D (own_world_3d stays
## false), not the real window's own clamped texture.
##
## Run windowed, off-screen (a real render is required):
##   godot --path . --position 10000,10000 tools/screenshot_xtq40_ghost.tscn --quit-after 90
## Never --always-on-top/--maximized; quits right after saving.
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game).

const OUTPUT_DIR: String = "user://"
const OUTPUT_NAME: String = "m7p40_ghost.png"
const SETTLE_FRAMES: int = 90
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)

## Same "just above the disk centre" convention as screenshot_xtq35_haze.gd's
## own HELD_BLOCK_TARGET -- the ghost is placed here too, so the camera's
## follow target and the held shape line up without wiring a real
## PlayerController.
const HELD_TARGET: Vector3 = Vector3(0.0, 1.0, 0.0)

## A couple of real settled blocks nearby (same BLOCK_OFFSETS idiom as
## screenshot_xtq35_haze.gd) so the shot shows a real placed block's grid
## lines right next to the ghost's own, for a direct side-by-side comparison.
const BLOCK_OFFSETS: Array[Vector3] = [
	Vector3(-1.5, 0.02, 0.0),
	Vector3(1.2, 0.02, 0.6),
]
const SETTLE_TICKS: int = 60


func _ready() -> void:
	Settings.set_graphics_preset(&"high")

	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig

	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(1.5 * Engine.physics_ticks_per_second))

	_spawn_settled_blocks(main)
	for _i: int in range(SETTLE_TICKS):
		await get_tree().physics_frame

	var ghost: GhostPreview = _spawn_ghost(main)

	print(
		"SCREENSHOT xtq40 ghost_material=%s ghost_shader=%s use_hatch=%s grid_line_width_px=%s" % [
			ghost._material,
			ghost._material.shader if ghost._material != null else null,
			ghost._material.get_shader_parameter(&"use_hatch") if ghost._material != null else null,
			ghost._material.get_shader_parameter(&"grid_line_width_px") if ghost._material != null else null,
		]
	)

	_point_camera(rig)
	await _wait(SETTLE_FRAMES)
	await _shoot(OUTPUT_NAME)

	get_tree().quit()


## Places the camera exactly where CameraRig's own apply_follow_tuning() would
## for a block held at HELD_TARGET, using whatever CameraTuning this rig
## already carries -- config/camera_tuning.tres' shipped defaults, never
## overridden by this file.
func _point_camera(rig: CameraRig) -> void:
	rig._target = HELD_TARGET
	rig._yaw = 0.0
	rig.apply_follow_tuning()
	var cam3d: Camera3D = rig.get_camera()
	rig.reset_physics_interpolation()
	cam3d.reset_physics_interpolation()


func _spawn_settled_blocks(main: Node) -> void:
	var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var colors: PackedColorArray = MatchConfig.default_player_colors()
	var blocks_container: Node3D = main.get_node("BlocksContainer") as Node3D
	for i: int in range(BLOCK_OFFSETS.size()):
		var shape: BlockShape = shapes[i % shapes.size()]
		var owner_slot: int = i % 2
		var color: Color = colors[owner_slot]
		var block: Block = BlockFactory.build(shape, tuning, owner_slot, color)
		blocks_container.add_child(block)
		block.global_position = BLOCK_OFFSETS[i]


## Direct GhostPreview.new()/set_shape()/update_placement() construction,
## mirroring tests/unit/test_ghost_preview.gd's own _make_ghost() helper --
## the simplest way to get a real, on-screen held ghost for this probe.
func _spawn_ghost(main: Node) -> GhostPreview:
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var colors: PackedColorArray = MatchConfig.default_player_colors()
	var ghost: GhostPreview = GhostPreview.new()
	main.add_child(ghost)
	ghost.set_shape(shapes[0])
	ghost.set_player_color(colors[0])
	ghost.update_placement(HELD_TARGET, Vector3.UP)
	ghost.apply_validity(PlacementRules.Result.VALID)
	return ghost


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = await _render_large_shot()
	var path: String = OUTPUT_DIR + file_name
	image.save_png(path)
	print("SCREENSHOT xtq40 saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])


## Same SubViewport idiom as screenshot_xtq35_haze.gd's own
## _render_large_shot(): a fresh Camera3D matching the real rig camera's
## transform/fov/near/far/environment, sharing the live World3D via
## `sub.world_3d` (own_world_3d stays false), so the capture is CAPTURE_SIZE
## regardless of the actual (OS-clamped) window size.
func _render_large_shot() -> Image:
	var source: Camera3D = get_viewport().get_camera_3d()
	var sub: SubViewport = SubViewport.new()
	sub.size = CAPTURE_SIZE
	sub.world_3d = get_viewport().world_3d
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera: Camera3D = Camera3D.new()
	camera.fov = source.fov
	camera.near = source.near
	camera.far = source.far
	camera.environment = source.environment
	sub.add_child(camera)
	add_child(sub)
	camera.global_transform = source.global_transform
	camera.current = true
	for _i: int in range(3):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	sub.queue_free()
	return image


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
