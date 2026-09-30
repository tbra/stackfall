extends Node
## Bontago-470.3/470.2: fog (both themes) and one Breeze gust capture. Boots the sandbox, starts rain on the host
## schedule seam, waits for the hold, shoots the player view (the rig camera's
## own transform) and a wide view, prints friction values and the cost of one
## wet-friction rewrite. Off-screen SubViewport capture only:
##   godot --path . --windowed --position 10000,10000 tools/screenshot_fog.tscn --quit-after 900
const OUTPUT_DIR: String = "user://"
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const RAMP_FRAMES: int = 420
const HALF_FRAMES: int = 120
var _rig: CameraRig = null
var _main: Node = null
var _view: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_rig = _main.get_node("CameraRig") as CameraRig
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(60)
	print("FOG started=%s" % Match.weather().start_event(&"fog"))
	await _wait(500)
	print("FOG intensity=%s" % Match.weather().active_intensity())
	await _capture_pair("fog_r3_sunset")
	for node: Node in get_tree().get_nodes_in_group(Skybox.TUNING_GROUP):
		(node as Skybox).set_theme_by_id("night")
	await _wait(10)
	await _capture_pair("fog_r3_night")
	Match.weather().end_event()
	await _wait(420)
	print("FOG ended active=%s" % Match.weather().active_id())
	# One Breeze gust visual.
	var gust: Dictionary = {"id": 1, "x": 0.0, "y": 3.0, "z": 0.0, "a": 0.6, "r": 5.0, "d": 6.0, "s": 1.0}
	Events.breeze_gust_started.emit(gust)
	await _wait(150)
	await _capture_pair("breeze_gust")
	Match.weather().reset()
	get_tree().quit()


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = await _render_large_shot()
	var path: String = OUTPUT_DIR + file_name
	image.save_png(path)
	print("SCREENSHOT fog saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])


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


func _capture_pair(tag: String) -> void:
	_view = get_viewport().get_camera_3d().global_transform
	await _shoot(tag + "_player.png")
	_view = Transform3D(Basis.IDENTITY, Vector3(0.0, 30.0, 45.0)).looking_at(Vector3.ZERO, Vector3.UP)
	await _shoot(tag + "_wide.png")
