extends Node
## One off-screen run captures four deterministic phases of Bontago-mp0.13.

const SETTLE_SECONDS: float = 1.5
const SHOT_SETTLE_SECONDS: float = 0.4
const OUTPUT_DIR: String = "user://captures"
const CAMERA_DISTANCE_M: float = 35.0
const CAMERA_HEIGHT_M: float = 15.0
const PHASES: Array[float] = [0.0, 0.25, 0.5, 0.75]
const NAMES: PackedStringArray = ["dawn", "day", "dusk", "night"]
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
	skybox.configure_match_sky(config)
	skybox.set_process(false)
	var rig: Node = main.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	for index: int in range(PHASES.size()):
		skybox.set_cycle_phase(PHASES[index])
		var material: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
		var sun_direction: Vector3 = material.get_shader_parameter(&"sun_direction") as Vector3
		var flat: Vector3 = Vector3(sun_direction.x, 0.0, sun_direction.z).normalized()
		camera.global_position = -flat * CAMERA_DISTANCE_M + Vector3.UP * CAMERA_HEIGHT_M
		var aim: Vector3 = Vector3(sun_direction.x, maxf(sun_direction.y, 0.15), sun_direction.z).normalized()
		camera.look_at(camera.global_position + aim * CAMERA_DISTANCE_M, Vector3.UP)
		await get_tree().create_timer(SHOT_SETTLE_SECONDS).timeout
		await RenderingServer.frame_post_draw
		var path: String = OUTPUT_DIR.path_join("daynight_%s.png" % NAMES[index])
		ContactSheet.save_capture(_shot_viewport.get_texture().get_image(), path)
	get_tree().quit()
