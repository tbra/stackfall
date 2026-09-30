extends Node
## Bontago-59o.16 P2 evidence: captures the sky from one camera pose with the
## procedural look off (painted) and on. Off-screen run:
##   godot --path . --windowed --position 10000,10000 res://tools/screenshot_sky_procedural.tscn

const SETTLE_S: float = 1.5


func _ready() -> void:
	call_deferred("_capture")


func _shot(name: String) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var path: String = "res://feedback/sky-proc-%s.png" % name
	get_viewport().get_texture().get_image().save_png(path)
	print("SCREENSHOT ", ProjectSettings.globalize_path(path))


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
	var direction: Vector3 = flare.config.sun_direction.normalized()
	camera.global_position = -direction * 45.0 + Vector3.UP * 6.0
	camera.look_at(camera.global_position + direction + Vector3.UP * 0.15, Vector3.UP)
	var skybox: Skybox = main.get_node("Skybox") as Skybox
	await _shot("painted")
	skybox.theme.sky_look_procedural = true
	skybox.apply_theme(skybox.theme)
	await get_tree().create_timer(0.5).timeout
	await _shot("procedural")
	get_tree().quit()
