extends Node
## Bontago-mp0.140: wet-disc before/after at full rain. Off-screen SubViewport:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_rain_wet.tscn -- --agent-probe out=<dir>
const CAPTURE_SIZE: Vector2i = Vector2i(1920, 1080)
const RAMP_FRAMES: int = 420
const SETTLE_FRAMES: int = 10
var _out: String = "user://"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.trim_prefix("out=") + "/"
	Settings.set_graphics_preset(&"high")
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(60)
	Match.weather().start_event(&"rain")
	await _wait(RAMP_FRAMES)
	var rain: RainTuning = load("res://config/weather/rain.tres") as RainTuning
	var overlay: TerritoryOverlay = get_tree().get_first_node_in_group(TerritoryOverlay.WET_GROUP) as TerritoryOverlay
	var view: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 30.0, 45.0)).looking_at(Vector3.ZERO, Vector3.UP)
	overlay.set_wet(1.0, 0.0, rain.wet_roughness_scale, 0.0)
	await _shoot("rain_wet_before.png", view)
	overlay.set_wet(1.0, rain.wet_sheen_add, rain.wet_roughness_scale, rain.wet_darken)
	await _shoot("rain_wet_after.png", view)
	get_tree().quit()


func _shoot(file_name: String, view: Transform3D) -> void:
	await _wait(SETTLE_FRAMES)
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
	camera.global_transform = view
	camera.current = true
	for _i: int in range(3):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	sub.queue_free()
	image.save_png(_out + file_name)
	print("SCREENSHOT saved=%s%s size=%s" % [_out, file_name, image.get_size()])


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
