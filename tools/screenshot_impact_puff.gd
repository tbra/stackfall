extends Node
## Bontago-mp0.120: impact-puff flipbook evidence. Off-screen SubViewport capture:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_impact_puff.tscn -- --agent-probe --render-size=1280x720
const OUTPUT_DIR: String = "user://"
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const SOFT_SPEED: float = 4.5
const HARD_SPEED: float = 11.0
const SPACING_M: float = 3.0
const CAMERA_DISTANCE_M: float = 9.0
const CAMERA_PITCH_DEG: float = -25.0
const FRAMES_BEFORE_SHOT: int = 8
var _main: Node = null
var _view: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(60)
	Events.block_impacted_at.emit(SOFT_SPEED, Vector3(-SPACING_M * 0.5, 0.0, 0.0))
	Events.block_impacted_at.emit(HARD_SPEED, Vector3(SPACING_M * 0.5, 0.0, 0.0))
	var elevation: float = deg_to_rad(-CAMERA_PITCH_DEG)
	var offset: Vector3 = Vector3(0.0, sin(elevation), cos(elevation)) * CAMERA_DISTANCE_M
	_view = Transform3D(Basis.IDENTITY, offset).looking_at(Vector3.ZERO, Vector3.UP)
	await _wait(FRAMES_BEFORE_SHOT)
	await _shoot("impact_puff.png")
	get_tree().quit()


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = await _render_large_shot()
	var path: String = OUTPUT_DIR + file_name
	ContactSheet.save_capture(image, path)
	print("SCREENSHOT puff saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])


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
	camera.global_transform = _view
	camera.current = true
	for _i: int in range(3):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	sub.queue_free()
	return image


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
