extends Node
## Bontago-mp0.29: sea + upper puff layer together under one lighting model.
## Bontago-mp0.93: `poses=underside` also frames the layer from gameplay heights
## (the underside artifacts), with the upper layer toggled off in one pose to name
## the source. User args:
##   shot=day|start|night|snow_night|rain|storm[,more]  shots run in order in one process
##   poses=up|underside                `up` = the original pitched-up view (default)
##   out=<dir>                         save PNGs here instead of user://
##   old_shader=<abs path>             also capture every pose with that earlier
##                                     cloud_puffs source (A/B in one process; files
##                                     get a _new / _old suffix)
##   ab=pass1                          also capture every pose with the pass-1 upper layer
##                                     (flat-bottomed puffs, no sink/belly/clearance fade:
##                                     the ceiling tuning is overridden in memory and the
##                                     sky rebuilt, same shader); files get _new / _pass1
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_clouds_unify.tscn -- --agent-probe --render-size=1280x720 shot=start poses=underside
const SETTLE_SECONDS: float = 1.5
const WEATHER_FRAMES: int = 720
const DRAW_FRAMES: int = 6
## Frames to let a swapped puff shader compile before the next capture.
const SHADER_SWAP_FRAMES: int = 24
const CAMERA_POSITION: Vector3 = Vector3(0.0, 14.0, 70.0)
const LOOK_PITCH_DEG: float = 35.0
const FOV_DEG: float = 85.0
## shot -> [cycle phase, weather id, intensity]. `start` is the default match's
## opening phase (SkyThemeDef.cycle_start_phase); `day`, `night`, `rain` are the
## original mp0.29 shots.
const SHOTS: Dictionary = {
	"day": [0.25, &"", 0.0],
	"start": [0.10, &"", 0.0],
	"dusk": [0.44, &"", 0.0],
	"night": [0.75, &"snow", 1.0],
	"night_clear": [0.75, &"", 0.0],
	"rain": [0.47, &"rain", 1.0],
	"storm": [0.47, &"storm", 1.0],
}
## `underside` poses: [label, camera position, pitch deg, yaw from the sun (deg), upper layer visible].
## "horizon70" is the plan's pose (~70 m, looking at the horizon); "play" a typical gameplay height.
const UNDERSIDE_POSES: Array = [
	["horizon70_on", Vector3(0.0, 70.0, 0.0), 0.0, 0.0, true],
	["horizon70_off", Vector3(0.0, 70.0, 0.0), 0.0, 0.0, false],
	["play_on", Vector3(0.0, 40.0, 30.0), 3.0, 0.0, true],
	["away_on", Vector3(0.0, 55.0, 0.0), 6.0, 180.0, true],
	["graze_on", Vector3(0.0, 88.0, 0.0), 8.0, 0.0, true],
]
const UP_POSES: Array = [
	["up", CAMERA_POSITION, LOOK_PITCH_DEG, 0.0, true],
]

var _out_dir: String = "user://"
var _old_shader: Shader = null
var _ab_pass1: bool = false
## The ceiling tuning's pass-1 values for ab=pass1: property -> value.
const PASS1_UPPER: Dictionary = {
	&"upper_flat_base": 0.15,
	&"upper_puff_squash": 1.0,
	&"upper_base_sink_m": 0.0,
	# detail puffs sat on the upper half only (up >= DETAIL_MIN_UP = 0.25), i.e. depth -0.25.
	&"upper_belly_depth": -0.25,
	&"upper_clear_fade_end_m": 0.0,
}


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var shots: PackedStringArray = PackedStringArray(["day"])
	var poses: Array = UP_POSES
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("shot="):
			shots = arg.trim_prefix("shot=").split(",", false)
		elif arg == "poses=underside":
			poses = UNDERSIDE_POSES
		elif arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=").trim_suffix("/") + "/"
		elif arg == "ab=pass1":
			_ab_pass1 = true
		elif arg.begins_with("old_shader="):
			_old_shader = Shader.new()
			_old_shader.code = FileAccess.get_file_as_string(arg.trim_prefix("old_shader="))
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
	var rig: Node = main.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	camera.fov = FOV_DEG
	for shot: String in shots:
		await _shoot(shot, poses, viewport, skybox, camera)
	get_tree().quit()


func _shoot(shot: String, poses: Array, viewport: SubViewport, skybox: Skybox, camera: Camera3D) -> void:
	var spec: Array = SHOTS[shot]
	skybox.set_cycle_phase(float(spec[0]))
	if StringName(spec[1]) != &"":
		print("CLOUDS start=%s" % Match.weather().start_event(StringName(spec[1])))
		for _i: int in range(WEATHER_FRAMES):
			await get_tree().physics_frame
	else:
		for _i: int in range(DRAW_FRAMES):
			await get_tree().physics_frame
	var sun: Vector3 = (skybox.theme.sky_material as ShaderMaterial).get_shader_parameter(&"sun_direction") as Vector3
	var flat: Vector3 = Vector3(sun.x, 0.0, sun.z).normalized()
	var l: CloudLighting = skybox.cloud_lighting()
	print("CLOUDS %s night=%.2f storm=%.2f overcast=%.2f dim=%.2f desat=%.2f" % [shot, l.night_mix, l.storm, l.overcast, l.dim, l.desaturate])
	var upper: MultiMeshInstance3D = skybox.get_cloud_sea().upper_instance()
	var material: ShaderMaterial = skybox.get_cloud_sea().puff_material()
	var current: Shader = material.shader
	var variants: Array[String] = [""]
	if _old_shader != null:
		variants = ["new", "old"]
	if _ab_pass1:
		variants = ["new", "pass1"]
	var tuning: WeatherCeilingTuning = skybox.get_cloud_sea().upper_tuning
	var saved: Dictionary = {}
	for property: StringName in PASS1_UPPER:
		saved[property] = tuning.get(property)
	for variant: String in variants:
		if variant == "old" or variant == "new":
			material.shader = _old_shader if variant == "old" else current
			for _i: int in range(SHADER_SWAP_FRAMES):
				await get_tree().process_frame
		if _ab_pass1:
			var source: Dictionary = PASS1_UPPER if variant == "pass1" else saved
			for property: StringName in source:
				tuning.set(property, source[property])
			skybox.apply_theme(skybox.theme)
			skybox.set_cycle_phase(float(spec[0]))
			upper = skybox.get_cloud_sea().upper_instance()
			material = skybox.get_cloud_sea().puff_material()
			for _i: int in range(SHADER_SWAP_FRAMES):
				await get_tree().process_frame
		for pose: Array in poses:
			await _grab_pose(shot, variant, pose, flat, viewport, camera, upper)
	if _ab_pass1:
		for property: StringName in saved:
			tuning.set(property, saved[property])
		skybox.apply_theme(skybox.theme)
		skybox.set_cycle_phase(float(spec[0]))
		upper = skybox.get_cloud_sea().upper_instance()
		material = skybox.get_cloud_sea().puff_material()
	material.shader = current
	upper.visible = true


func _grab_pose(shot: String, variant: String, pose: Array, flat: Vector3, viewport: SubViewport, camera: Camera3D,
		upper: MultiMeshInstance3D) -> void:
	var position: Vector3 = pose[1] as Vector3
	var look: Vector3 = flat.rotated(Vector3.UP, deg_to_rad(float(pose[3])))
	camera.global_position = position
	camera.look_at(position + look * 100.0, Vector3.UP)
	camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(float(pose[2])))
	upper.visible = bool(pose[4])
	for _i: int in range(DRAW_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var suffix: String = "" if variant == "" else "_" + variant
	var path: String = "%sclouds_unify_%s_%s%s.png" % [_out_dir, shot, String(pose[0]), suffix]
	image.save_png(path)
	print("CLOUDS saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])
