extends Node
## Off-screen capture of the day/night cycle (Bontago-mp0.13, Bontago-59o.18).
##
## No argument: four deterministic running-cycle phases (dawn, day, dusk, night).
## `-- --lock=<option>`: the lobby option as a match would start it, through
## Skybox.configure_match_sky(): `cycle` (the default, running from its start
## phase), `sunset`, `dawn`, `night` (the cycle locked at that option's phase) or
## `all` (all four in one run, one contact-sheet strip). Windowed runs follow
## docs/AGENT_WORKFLOW.md (--windowed --position 10000,10000 --resolution 320x180
## --audio-driver Dummy ... -- --agent-probe --render-size=1280x720).

const SETTLE_SECONDS: float = 1.5
const SHOT_SETTLE_SECONDS: float = 0.4
const OUTPUT_DIR: String = "user://captures"
const CAMERA_DISTANCE_M: float = 35.0
const CAMERA_HEIGHT_M: float = 15.0
const PHASES: Array[float] = [0.0, 0.25, 0.5, 0.75]
const NAMES: PackedStringArray = ["dawn", "day", "dusk", "night"]
const LOCK_ARG: String = "--lock="
const LOCK_ALL: String = "all"
## Lobby option id -> the sky mode it selects (RANDOM rolls one of the locked three).
const OPTION_MODES: Dictionary = {
	"cycle": MatchConfig.SkyThemeMode.CYCLE,
	"sunset": MatchConfig.SkyThemeMode.DAY,
	"dawn": MatchConfig.SkyThemeMode.DAWN,
	"night": MatchConfig.SkyThemeMode.NIGHT,
}
var _shot_viewport: SubViewport = null


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
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
	var lock: String = _lock_option(OS.get_cmdline_user_args())
	if lock.is_empty():
		skybox.configure_match_sky(config)
		skybox.set_process(false)
		for index: int in range(PHASES.size()):
			skybox.set_cycle_phase(PHASES[index])
			await _shoot(skybox, camera, "daynight_%s.png" % NAMES[index])
	else:
		var options: PackedStringArray = PackedStringArray(OPTION_MODES.keys()) if lock == LOCK_ALL else PackedStringArray([lock])
		for option: String in options:
			config.sky_theme_mode = OPTION_MODES[option] as MatchConfig.SkyThemeMode
			config.resolve_sky_theme(0)
			skybox.configure_match_sky(config)
			skybox.set_process(false)
			print("daynight: option=%s locked_phase=%s phase=%s" % [option, skybox.locked_phase(), skybox.current_cycle_phase()])
			await _shoot(skybox, camera, "daynight_lock_%s.png" % option)
	get_tree().quit()


## The option named by `--lock=`, "" when the argument is absent or unknown.
func _lock_option(user_args: PackedStringArray) -> String:
	for arg: String in user_args:
		if not arg.begins_with(LOCK_ARG):
			continue
		var value: String = arg.trim_prefix(LOCK_ARG)
		if value == LOCK_ALL or OPTION_MODES.has(value):
			return value
		push_warning("screenshot_daynight: unknown %s%s (cycle|sunset|dawn|night|all); using the phase sweep" % [LOCK_ARG, value])
	return ""


func _shoot(skybox: Skybox, camera: Camera3D, file_name: String) -> void:
	var material: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
	var sun_direction: Vector3 = material.get_shader_parameter(&"sun_direction") as Vector3
	var flat: Vector3 = Vector3(sun_direction.x, 0.0, sun_direction.z).normalized()
	camera.global_position = -flat * CAMERA_DISTANCE_M + Vector3.UP * CAMERA_HEIGHT_M
	var aim: Vector3 = Vector3(sun_direction.x, maxf(sun_direction.y, 0.15), sun_direction.z).normalized()
	camera.look_at(camera.global_position + aim * CAMERA_DISTANCE_M, Vector3.UP)
	await get_tree().create_timer(SHOT_SETTLE_SECONDS).timeout
	await RenderingServer.frame_post_draw
	ContactSheet.save_capture(_shot_viewport.get_texture().get_image(), OUTPUT_DIR.path_join(file_name))
