extends Node
## Bontago-mp0.34 capture: a storm over a CYCLE sky, looking up toward the sun.
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/probe_storm_clouds.tscn -- --agent-probe time=night
const CAPTURE_SIZE: Vector2i = Vector2i(3440, 1440)
const SETTLE_SECONDS: float = 1.5
const STORM_WAIT_FRAMES: int = 720
const CAMERA_DISTANCE_M: float = 35.0
const CAMERA_HEIGHT_M: float = 15.0
const PITCH_UP_DEG: float = 22.0
const FOV_DEG: float = 80.0
const NIGHT_PHASE: float = 0.75
const DAY_PHASE: float = 0.2


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var night: bool = true
	for arg: String in OS.get_cmdline_user_args():
		if arg == "time=day":
			night = false
	var viewport: SubViewport = AgentProbe.make_render_viewport(self, CAPTURE_SIZE)
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
	skybox.set_cycle_phase(NIGHT_PHASE if night else DAY_PHASE)
	print("PROBE storm started=%s" % Match.weather().start_event(&"storm"))
	for _i: int in range(STORM_WAIT_FRAMES):
		await get_tree().physics_frame
	skybox.set_cycle_phase(NIGHT_PHASE if night else DAY_PHASE)
	var rig: Node = main.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	camera.fov = FOV_DEG
	var material: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
	var sun: Vector3 = material.get_shader_parameter(&"sun_direction") as Vector3
	var flat: Vector3 = Vector3(sun.x, 0.0, sun.z).normalized()
	camera.global_position = -flat * CAMERA_DISTANCE_M + Vector3.UP * CAMERA_HEIGHT_M
	camera.look_at(camera.global_position + flat * CAMERA_DISTANCE_M, Vector3.UP)
	camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(PITCH_UP_DEG))
	var lighting: CloudLighting = skybox.cloud_lighting()
	print("PROBE night=%.2f storm=%.2f dim=%.2f sun_scale=%.3f" % [lighting.night_mix, lighting.storm, lighting.dim, lighting.sun_scale])
	await get_tree().create_timer(0.5).timeout
	for _i: int in range(4):
		await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var path: String = "user://storm_clouds_%s.png" % ("night" if night else "day")
	image.save_png(path)
	print("PROBE saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])
	get_tree().quit()
