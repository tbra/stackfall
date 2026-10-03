extends Node
## Bontago-mp0.97: active-snowfall capture (flake visibility). Boots the
## sandbox with a few towers, starts snow with fast growth and shoots the
## player view (the rig camera's own transform, so the camera-following flakes
## are in frame) and the same view turned 25 degrees. Off-screen SubViewport capture only:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy \
##     tools/screenshot_snow_flakes.tscn -- --agent-probe --render-size=1280x720
const OUTPUT_DIR: String = "user://"
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const FAST_SECONDS_PER_LEVEL: float = 1.5
const RAMP_IN_S: float = 0.5
const SNOW_FRAMES: int = 420
const TOWERS: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(3.0, 0.0, 1.0), Vector3(-2.5, 0.0, 2.5)]
## The second shot is the player view turned this far about the world up axis
## (the flakes follow the rig camera, so a free-standing camera would not see
## them where a player does).
const SIDE_YAW_DEG: float = 25.0
var _main: Node = null
var _view: Transform3D = Transform3D.IDENTITY
var _frame_max_ms: float = 0.0
var _frame_count: int = 0
var _tracking: bool = false


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(90)
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var parent: Node3D = Match.blocks_parent()
	var index: int = 0
	for base: Vector3 in TOWERS:
		for level: int in range(3):
			var shape: BlockShape = shapes[(index * 3 + level) % shapes.size()]
			var block: Block = BlockFactory.build(shape, tuning, index % 2, Color(0.9, 0.25, 0.2) if index % 2 == 0 else Color(0.2, 0.45, 0.95))
			parent.add_child(block)
			block.global_position = base + Vector3(0.0, 0.2 + float(level) * 2.2, 0.0)
			Events.block_placed.emit(block, shape.id)
			await _wait(45)
		index += 1
	await _wait(150)
	var snow: SnowTuning = load("res://config/weather/snow.tres") as SnowTuning
	snow.seconds_per_level = FAST_SECONDS_PER_LEVEL
	snow.ramp_in_s = RAMP_IN_S
	_tracking = true
	print("SNOWFLAKES start_event=%s" % Match.weather().start_event(&"snow"))
	await _wait(SNOW_FRAMES)
	_tracking = false
	print("SNOWFLAKES frames=%d max_frame_ms=%.1f" % [_frame_count, _frame_max_ms])
	var field: Field = Match.field()
	var cover: SnowDiscCover = SnowCaps.disc_cover(field)
	var material: ShaderMaterial = field.overlay().material()
	print("SNOWFLAKES cover_level=%d shown=%.2f strength=%s threshold=%s" % [cover.level() if cover != null else -1, cover.shown_level() if cover != null else -1.0, material.get_shader_parameter(&"snow_strength"), material.get_shader_parameter(&"snow_threshold")])
	var presenter: Node = get_tree().root.find_child("WeatherPresenter", true, false)
	var presentation: SnowPresentation = null
	if presenter != null:
		presentation = (presenter as WeatherPresenter).presentation_for(&"snow") as SnowPresentation
	if presentation != null:
		var particles: GPUParticles3D = presentation.particles()
		print("SNOWFLAKES amount=%d ratio=%.2f lifetime=%.1f emitting=%s intensity=%.2f" % [particles.amount, particles.amount_ratio, particles.lifetime, particles.emitting, presentation.intensity])
	else:
		print("SNOWFLAKES presentation=none")
	if DisplayServer.get_name() != "headless":
		await _capture_pair("snowflakes")
	Match.weather().reset()
	get_tree().quit()


func _process(delta: float) -> void:
	if _tracking:
		_frame_count += 1
		_frame_max_ms = maxf(_frame_max_ms, delta * 1000.0)


func _capture_pair(tag: String) -> void:
	_view = get_viewport().get_camera_3d().global_transform
	await _shoot(tag + "_player.png")
	_view = Transform3D(Basis(Vector3.UP, deg_to_rad(SIDE_YAW_DEG)) * _view.basis, _view.origin)
	await _shoot(tag + "_side.png")


func _shoot(file_name: String) -> void:
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
	var path: String = OUTPUT_DIR + file_name
	ContactSheet.save_capture(image, path)
	print("SCREENSHOT snowflakes saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
