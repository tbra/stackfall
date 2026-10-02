extends Node
## Bontago-mp0.32 probe: real sandbox match, two touching cubes plus a few
## towers, fast snow, one wide and one close capture (off-screen SubViewport).
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/snow_merge_probe.tscn -- --agent-probe
const CAPTURE_SIZE: Vector2i = Vector2i(3440, 1440)
const FAST_SECONDS_PER_LEVEL: float = 1.2
const OUT_WIDE: String = "user://snow_merge_candidate.png"
const OUT_CLOSE: String = "user://snow_merge_candidate_close.png"
var _view: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(90)
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var cube: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var slab: BlockShape = load("res://config/blocks/slab6.tres") as BlockShape
	var parent: Node3D = Match.blocks_parent()
	var spots: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(tuning.cube_size, 0.0, 0.0), Vector3(2.0 * tuning.cube_size, 0.0, 0.0), Vector3(-4.0, 0.0, 3.0), Vector3(4.0, 0.0, -3.0)]
	var index: int = 0
	for spot: Vector3 in spots:
		var block: Block = BlockFactory.build(slab if index == 4 else cube, tuning, index % 2, Color(0.9, 0.25, 0.2) if index % 2 == 0 else Color(0.2, 0.45, 0.95))
		parent.add_child(block)
		block.global_position = spot + Vector3(0.0, 0.3, 0.0)
		Events.block_placed.emit(block, cube.id)
		index += 1
		await _wait(50)
	await _wait(150)
	var snow: SnowTuning = load("res://config/weather/snow.tres") as SnowTuning
	snow.seconds_per_level = FAST_SECONDS_PER_LEVEL
	snow.ramp_in_s = 0.5
	print("SNOWPROBE start=%s" % Match.weather().start_event(&"snow"))
	await _wait(int(FAST_SECONDS_PER_LEVEL * 60.0 * 8.0))
	_aim(Vector3(tuning.cube_size, 1.0, 0.0), 9.0, -35.0, 0.35)
	await _shoot(OUT_CLOSE)
	_aim(Vector3(0.0, 0.5, 0.0), 26.0, -38.0, 0.25)
	await _shoot(OUT_WIDE)
	get_tree().quit()


func _aim(target: Vector3, distance: float, pitch_deg: float, yaw: float) -> void:
	var elevation: float = deg_to_rad(-pitch_deg)
	var offset: Vector3 = Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * distance
	_view = Transform3D(Basis.IDENTITY, target + offset).looking_at(target, Vector3.UP)


func _shoot(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
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
	camera.global_transform = _view
	camera.current = true
	for _i: int in range(3):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	sub.queue_free()
	image.save_png(path)
	print("SNOWPROBE saved=%s" % ProjectSettings.globalize_path(path))


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
