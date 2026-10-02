extends Node
## Bontago-mp0.29: sea + upper puff layer together under one lighting model.
## User arg `shot=day|night|rain`:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_clouds_unify.tscn -- --agent-probe --render-size=3440x1440 shot=day
const SETTLE_SECONDS: float = 1.5
const WEATHER_FRAMES: int = 720
const CAMERA_POSITION: Vector3 = Vector3(0.0, 14.0, 70.0)
const LOOK_PITCH_DEG: float = 35.0
const FOV_DEG: float = 85.0
## shot -> [cycle phase, weather id, intensity]; all pitched up to see the upper puffs.
const SHOTS: Dictionary = {
	"day": [0.25, &"", 0.0],
	"night": [0.75, &"snow", 1.0],
	"rain": [0.47, &"rain", 1.0],
}


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var shot: String = "day"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("shot="):
			shot = arg.trim_prefix("shot=")
	var spec: Array = SHOTS[shot]
	Settings.set_graphics_preset(&"high")
	var viewport: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(3440, 1440))
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	viewport.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var config: MatchConfig = main.get("match_config") as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	main.call("start_sandbox_from_menu")
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var skybox: Skybox = main.get_node("Skybox") as Skybox
	skybox.configure_match_sky(config)
	skybox.set_process(false)
	skybox.set_cycle_phase(float(spec[0]))
	if StringName(spec[1]) != &"":
		print("CLOUDS start=%s" % Match.weather().start_event(StringName(spec[1])))
	var rig: Node = main.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	camera.fov = FOV_DEG
	for _i: int in range(WEATHER_FRAMES):
		await get_tree().physics_frame
	var sun: Vector3 = (skybox.theme.sky_material as ShaderMaterial).get_shader_parameter(&"sun_direction") as Vector3
	var flat: Vector3 = Vector3(sun.x, 0.0, sun.z).normalized()
	camera.global_position = CAMERA_POSITION
	camera.look_at(CAMERA_POSITION + flat * 100.0, Vector3.UP)
	camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(LOOK_PITCH_DEG))
	var l: CloudLighting = skybox.cloud_lighting()
	print("CLOUDS night=%.2f storm=%.2f overcast=%.2f dim=%.2f desat=%.2f" % [l.night_mix, l.storm, l.overcast, l.dim, l.desaturate])
	for _i: int in range(30):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var path: String = "user://clouds_unify_%s.png" % shot
	image.save_png(path)
	print("CLOUDS saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])
	get_tree().quit()
