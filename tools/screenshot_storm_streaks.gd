extends Node
## Bontago-mp0.35: storm streak look probe in REAL gameplay (Main sandbox) with a
## tall tower in view. Saves user://storm_streaks.png:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_storm_streaks.tscn -- --agent-probe
const OUTPUT_DIR: String = "user://"
const CAPTURE_SIZE: Vector2i = Vector2i(3440, 1440)
const SETTLE_TICKS: int = 60
const TOWER_CUBES: int = 40
const TOWER_OFFSET: Vector3 = Vector3(0.0, 0.02, -3.0)
const GUST_HEIGHT_M: float = 24.0
const GUST_RADIUS_M: float = 10.0
const GUST_ANGLE_RAD: float = 1.1
const GUST_WAIT_S: float = 1.4
const CAMERA_DISTANCE_M: float = 75.0
const CAMERA_PITCH_DEG: float = -8.0
const CAMERA_TARGET_HEIGHT_M: float = 27.0
const STORM_SEED: int = 11
const STORM_WAIT_S: float = 3.0


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(90)
	var field: Field = main.get_node("Field") as Field
	var base: Vector3 = field.home_flags()[0].global_position + TOWER_OFFSET
	_spawn_tower(main, base)
	await _wait(SETTLE_TICKS)
	rig._target = base + Vector3(0.0, CAMERA_TARGET_HEIGHT_M, 0.0)
	rig._yaw = 0.0
	rig.tuning.follow_distance = CAMERA_DISTANCE_M
	rig.tuning.follow_pitch_deg = CAMERA_PITCH_DEG
	rig.apply_follow_tuning()
	rig.reset_physics_interpolation()
	rig.get_camera().reset_physics_interpolation()
	await _wait(30)
	var storm: StormPresentation = StormPresentation.new()
	main.add_child(storm)
	storm.configure(STORM_SEED)
	storm.set_intensity(1.0)
	await get_tree().create_timer(STORM_WAIT_S).timeout
	await _shoot("storm_streaks.png")
	get_tree().quit()


func _spawn_tower(main: Node, base: Vector3) -> void:
	var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var colors: PackedColorArray = MatchConfig.default_player_colors()
	var container: Node3D = main.get_node("BlocksContainer") as Node3D
	var edge: float = tuning.cube_size - tuning.cube_margin
	for i: int in range(TOWER_CUBES):
		var block: Block = BlockFactory.build(shapes[0], tuning, i % 2, colors[i % 2])
		container.add_child(block)
		block.global_position = base + Vector3(0.0, edge * (float(i) + 0.5), 0.0)
		block.freeze = true


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = await _render_large_shot()
	var path: String = OUTPUT_DIR + file_name
	image.save_png(path)
	print("SCREENSHOT arena saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])


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
