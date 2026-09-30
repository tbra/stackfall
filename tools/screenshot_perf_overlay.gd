extends Node
## Bontago-470.8 evidence: BASIC and DETAILED F1 perf overlay in a live
## (sandbox) match, captured through a SubViewport that shares the live World3D
## and hosts its own PerfOverlay (a CanvasLayer in the root window would not
## appear in a SubViewport texture).
##   godot --path . --windowed --position 10000,10000 tools/screenshot_perf_overlay.tscn --quit-after 900
## Writes user://perf_overlay_basic.png and user://perf_overlay_detailed.png.

const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const BLOCK_COLUMNS: int = 8
const BLOCK_ROWS: int = 6
const BLOCK_SPACING: float = 1.6
const DROP_HEIGHT_STEP: float = 0.9
## Longer than the match countdown, so the state is PLAYING and the follow camera is live.
## Longer than DebugConfig.stats_window_s so a fresh 1 s snapshot is on screen.
const SAMPLE_WAIT_FRAMES: int = 150
const COUNTDOWN_WAIT_FRAMES: int = 300


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(COUNTDOWN_WAIT_FRAMES)
	var field: Field = main.get_node("Field") as Field
	var flag: HomeFlag = field.home_flags()[0]
	_spawn_blocks(main, flag.global_position)
	rig._target = flag.global_position + Vector3(-4.0, 1.5, 0.0)
	rig._yaw = 0.0
	rig.tuning.follow_distance = 18.0
	rig.tuning.follow_pitch_deg = -35.0
	rig.apply_follow_tuning()
	rig.reset_physics_interpolation()
	rig.get_camera().reset_physics_interpolation()
	await _wait(SAMPLE_WAIT_FRAMES)
	var sampler: PerfSampler = null
	for child: Node in main.get_children():
		if child is PerfSampler:
			sampler = child as PerfSampler
	print("PROBE debug_mode=%s sampler=%s" % [DebugMode.is_enabled(), sampler != null])
	await _shoot(sampler, PerfOverlay.Mode.BASIC, "perf_overlay_basic.png")
	await _shoot(sampler, PerfOverlay.Mode.DETAILED, "perf_overlay_detailed.png")
	get_tree().quit()


func _spawn_blocks(main: Node, origin: Vector3) -> void:
	var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var colors: PackedColorArray = MatchConfig.default_player_colors()
	var container: Node3D = main.get_node("BlocksContainer") as Node3D
	var index: int = 0
	for row: int in range(BLOCK_ROWS):
		for col: int in range(BLOCK_COLUMNS):
			var owner_slot: int = index % 2
			var block: Block = BlockFactory.build(shapes[index % shapes.size()], tuning, owner_slot, colors[owner_slot])
			container.add_child(block)
			Match.registry()._on_block_placed(block, shapes[index % shapes.size()].id)
			block.global_position = origin + Vector3(
				-3.0 - float(row) * BLOCK_SPACING,
				2.0 + float(index % 5) * DROP_HEIGHT_STEP,
				(float(col) - float(BLOCK_COLUMNS) * 0.5) * BLOCK_SPACING)
			index += 1


func _shoot(sampler: PerfSampler, mode: PerfOverlay.Mode, file_name: String) -> void:
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
	var overlay: PerfOverlay = PerfOverlay.new()
	overlay.config = DebugMode.config()
	overlay.sampler = sampler
	sub.add_child(overlay)
	add_child(sub)
	camera.global_transform = source.global_transform
	camera.current = true
	while overlay.mode() != mode:
		overlay.cycle_mode()
	# Let the sampler feed a few snapshots (and the graph) before the capture.
	await _wait(SAMPLE_WAIT_FRAMES)
	for _i: int in range(3):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	var path: String = "user://" + file_name
	image.save_png(path)
	print("SCREENSHOT saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])
	sub.queue_free()


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
