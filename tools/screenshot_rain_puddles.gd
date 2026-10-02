extends Node
## Bontago-mp0.21: puddle capture (fast-forwards the wetness). User arg `weather=rain|storm|snow`
## (after --): starts it, waits for the fades, shoots one wide up-tilted view.
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_weather_ceiling.tscn -- --agent-probe --render-size=1280x720 weather=rain
const CAPTURE_SIZE: Vector2i = Vector2i(3440, 1440)
const WAIT_FRAMES: int = 720
## Gameplay camera framing, tipped up so the disc stays low in frame with the
## ceiling above it.
const PITCH_UP_DEG: float = 0.0
const FOV_DEG: float = 80.0


func _ready() -> void:
	var weather_id: StringName = &"rain"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("weather="):
			weather_id = StringName(arg.trim_prefix("weather="))
	Settings.set_graphics_preset(&"high")
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	for _i: int in range(60):
		await get_tree().physics_frame
	print("PUDL started=%s" % Match.weather().start_event(weather_id))
	for _i: int in range(WAIT_FRAMES):
		await get_tree().physics_frame
	var puddles: RainPuddles = Match.field().get_node_or_null(RainPuddles.NODE_NAME) as RainPuddles
	print("PUDL puddles=%s" % puddles)
	if puddles != null:
		puddles.advance(200.0)
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
	camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(PITCH_UP_DEG))
	print("PUDL cam=%s rot=%s" % [camera.global_position, camera.rotation_degrees])
	camera.current = true
	for _i: int in range(6):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	var path: String = "user://rain_puddles_%s.png" % weather_id
	image.save_png(path)
	print("PUDL saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])
	get_tree().quit()
