extends Node
## Bontago-mp0.128 capture: rain / storm / snow skies at one locked cycle phase.
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/probe_weather_skies.tscn -- --agent-probe phase=0.25 tag=day
const WEATHERS: Array[StringName] = [&"rain", &"storm", &"snow"]
const WAIT_FRAMES: int = 600
const SETTLE_SECONDS: float = 1.5
const CAMERA_DISTANCE_M: float = 35.0
const CAMERA_HEIGHT_M: float = 15.0
const OUTPUT_DIR: String = "res://scratch"
var _shot_viewport: SubViewport = null


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var phase: float = 0.25
	var tag: String = "day"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("phase="):
			phase = arg.trim_prefix("phase=").to_float()
		elif arg.begins_with("tag="):
			tag = arg.trim_prefix("tag=")
	_shot_viewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_shot_viewport.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var config: MatchConfig = main.get("match_config") as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	main.call("start_sandbox_from_menu")
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var skybox: Skybox = main.get_node("Skybox") as Skybox
	var rig: Node = main.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	skybox.configure_match_sky(config)
	skybox.set_process(false)
	skybox.set_locked_phase(phase)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for weather_id: StringName in WEATHERS:
		print("WSKY started %s=%s" % [weather_id, Match.weather().start_event(weather_id)])
		for _i: int in range(WAIT_FRAMES):
			await get_tree().physics_frame
		var material: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
		var sun: Vector3 = material.get_shader_parameter(&"sun_direction") as Vector3
		var flat: Vector3 = Vector3(sun.x, 0.0, sun.z).normalized()
		camera.global_position = -flat * CAMERA_DISTANCE_M + Vector3.UP * CAMERA_HEIGHT_M
		var aim: Vector3 = Vector3(sun.x, maxf(sun.y, 0.15), sun.z).normalized()
		camera.look_at(camera.global_position + aim * CAMERA_DISTANCE_M, Vector3.UP)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path: String = "%s/wsky_%s_%s.png" % [OUTPUT_DIR, weather_id, tag]
		_shot_viewport.get_texture().get_image().save_png(path)
		print("WSKY saved %s storm=%s bright=%s" % [path, skybox.storm_sky_amount(), skybox.snow_brighten_amount()])
	get_tree().quit()
