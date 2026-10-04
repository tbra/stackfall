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
##
## `-- --strip=blend` (Bontago-59o.18 C1b, for the owner's sign-off of the day
## palette blend): the running cycle at the strip phases below (locked at each, so
## the radiance map is built as in a locked match) followed by the OLD static
## Dawn (dawn.tres) and Sunset (sunset.tres) themes for comparison, one run, one
## contact sheet in capture order. `--seed=<n>` (C1b variation) sets the match seed
## the sky variation draws from (default -1 = SkyVariation.DEFAULT_SEED).

const SETTLE_SECONDS: float = 1.5
const SHOT_SETTLE_SECONDS: float = 0.4
const OUTPUT_DIR: String = "user://captures"
const CAMERA_DISTANCE_M: float = 35.0
const CAMERA_HEIGHT_M: float = 15.0
const PHASES: Array[float] = [0.0, 0.25, 0.5, 0.75]
const NAMES: PackedStringArray = ["dawn", "day", "dusk", "night"]
const LOCK_ARG: String = "--lock="
const LOCK_ALL: String = "all"
const STRIP_ARG: String = "--strip="
const STRIP_BLEND: String = "blend"
const SEED_ARG: String = "--seed="
## Palette strip (--strip=blend): file name, cycle phase. 0.03 / 0.47 / 0.75 are the
## Dawn / Sunset / Night lock phases, 0.10 the opening phase of a Cycle match, 0.25
## noon and 0.38 the middle of the dusk blend window (SkyThemeDef.cycle_dusk_weight_phases).
const STRIP_SHOTS: Array[Dictionary] = [
	{"name": "dawn", "phase": 0.03},
	{"name": "morning", "phase": 0.10},
	{"name": "noon", "phase": 0.25},
	{"name": "blend_mid", "phase": 0.38},
	{"name": "sunset", "phase": 0.47},
	{"name": "midnight", "phase": 0.75},
]
## Old static themes shot after the strip: theme id -> file name.
const STRIP_STATIC: Array[Dictionary] = [
	{"name": "old_static_dawn", "theme": "dawn"},
	{"name": "old_static_sunset", "theme": "sunset"},
]
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
	if _strip_requested(OS.get_cmdline_user_args()):
		await _shoot_strip(skybox, camera, config)
	elif lock.is_empty():
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


func _strip_requested(user_args: PackedStringArray) -> bool:
	return user_args.has(STRIP_ARG + STRIP_BLEND)


## --strip=blend: the cycle at each strip phase (locked there), then the old static themes.
func _shoot_strip(skybox: Skybox, camera: Camera3D, config: MatchConfig) -> void:
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	config.rng_seed = _seed_option(OS.get_cmdline_user_args())
	skybox.configure_match_sky(config)
	skybox.set_process(false)
	print("daynight strip: match seed %s" % config.rng_seed)
	for shot: Dictionary in STRIP_SHOTS:
		skybox.set_locked_phase(float(shot["phase"]))
		print("daynight strip: %s phase=%s" % [shot["name"], skybox.current_cycle_phase()])
		await _shoot(skybox, camera, "daynight_strip_%s.png" % shot["name"])
	for shot: Dictionary in STRIP_STATIC:
		skybox.set_theme_by_id(str(shot["theme"]))
		print("daynight strip: %s (static %s, cycle active=%s)" % [shot["name"], shot["theme"], skybox.is_cycle_active()])
		await _shoot(skybox, camera, "daynight_strip_%s.png" % shot["name"])


## The match seed named by `--seed=`, -1 (the sky's default curve) when absent.
func _seed_option(user_args: PackedStringArray) -> int:
	for arg: String in user_args:
		if arg.begins_with(SEED_ARG):
			return arg.trim_prefix(SEED_ARG).to_int()
	return -1


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
	if OS.get_cmdline_user_args().has("--aim=moon"):
		# Bontago-mp0.122: frame the moon (opposite the sun) instead of the sun.
		aim = (material.get_shader_parameter(&"moon_direction") as Vector3).normalized()
		camera.global_position = Vector3.UP * CAMERA_HEIGHT_M
	camera.look_at(camera.global_position + aim * CAMERA_DISTANCE_M, Vector3.UP)
	await get_tree().create_timer(SHOT_SETTLE_SECONDS).timeout
	await RenderingServer.frame_post_draw
	ContactSheet.save_capture(_shot_viewport.get_texture().get_image(), OUTPUT_DIR.path_join(file_name))
