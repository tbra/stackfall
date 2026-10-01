extends Node
## Bontago-t8x.2/.3 evidence: procedural sky from a low/side pose (sun off-axis,
## flare ghosts visible) and an overhead pose (puff layer near the disc rim).
## Off-screen: godot --path . --windowed --position 10000,10000 --resolution 320x180
##   --audio-driver Dummy res://tools/screenshot_t8x_sky.tscn -- --agent-probe --render-size=1920x1080

const SETTLE_S: float = 1.5
const SIDE_YAW_DEG: float = 35.0
const SIDE_DISTANCE_M: float = 45.0
const SIDE_HEIGHT_M: float = 6.0
const OVERHEAD_HEIGHT_M: float = 70.0
const OVERHEAD_BACK_M: float = 55.0


func _ready() -> void:
	call_deferred("_capture")


func _shot(name: String) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var path: String = "res://feedback/t8x-sky-%s.png" % name
	ContactSheet.save_capture(get_viewport().get_texture().get_image(), path)


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://feedback"))
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(SETTLE_S).timeout
	var config: MatchConfig = main.get("match_config") as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	main.call("start_sandbox_from_menu")
	await get_tree().create_timer(SETTLE_S).timeout
	var flare: SunFlare = main.get_node("SunFlare") as SunFlare
	var rig: Node = main.get_node("CameraRig")
	rig.set_process(false)
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	var skybox: Skybox = main.get_node("Skybox") as Skybox
	skybox.theme.sky_look_procedural = true
	skybox.apply_theme(skybox.theme)
	var direction: Vector3 = flare.config.sun_direction.normalized()
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z).normalized()
	var side: Vector3 = flat.rotated(Vector3.UP, deg_to_rad(SIDE_YAW_DEG))
	camera.global_position = -flat * SIDE_DISTANCE_M + Vector3.UP * SIDE_HEIGHT_M
	camera.look_at(camera.global_position + side + Vector3.UP * direction.y, Vector3.UP)
	await _shot("side")
	camera.global_position = -flat * OVERHEAD_BACK_M + Vector3.UP * OVERHEAD_HEIGHT_M
	camera.look_at(Vector3.ZERO, Vector3.UP)
	await _shot("overhead")
	camera.global_position = Vector3(0.0, SIDE_HEIGHT_M, 0.0) - flat * 5.0
	camera.look_at(camera.global_position + flat + Vector3.UP * 0.6, Vector3.UP)
	await _shot("upward")
	get_tree().quit()
