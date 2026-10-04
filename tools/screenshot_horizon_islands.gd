extends Node
## Bontago-mp0.123: horizon island capture + draw-call / primitive count with
## and without the ring. Off-screen:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy tools/screenshot_horizon_islands.tscn --quit-after 600 -- --agent-probe
const SETTLE_FRAMES: int = 90
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const CAMERA_HEIGHT_M: float = 6.0
const THEMES: Dictionary = {"day": 0.25, "dusk": 0.47}


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(90)
	var ring: HorizonIslands = main.get_node("HorizonIslands") as HorizonIslands
	var target: Vector3 = (ring.get_child(0) as Node3D).global_position
	var panels: Array[Node] = main.find_children("*", "TuningPanel", true, false)
	var panel: TuningPanel = panels[0] as TuningPanel
	panel.apply_sky_theme_id("cycle")
	var sky: Skybox = main.get_node("Skybox") as Skybox
	for theme_id: String in THEMES:
		await _wait(SETTLE_FRAMES)
		sky.set_locked_phase(float(THEMES[theme_id]))
		await _wait(SETTLE_FRAMES)
		ring.visible = true
		await _shoot("islands_%s.png" % theme_id, target, true)
		ring.visible = false
		await _shoot("islands_%s_off.png" % theme_id, target, false)
	get_tree().quit()


func _shoot(file_name: String, target: Vector3, report: bool) -> void:
	var sub: SubViewport = SubViewport.new()
	sub.size = CAPTURE_SIZE
	sub.world_3d = get_viewport().world_3d
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var source: Camera3D = get_viewport().get_camera_3d()
	var camera: Camera3D = Camera3D.new()
	camera.fov = source.fov
	camera.near = source.near
	camera.far = source.far
	camera.environment = source.environment
	sub.add_child(camera)
	add_child(sub)
	camera.global_position = Vector3(0.0, CAMERA_HEIGHT_M, 0.0)
	camera.look_at(target)
	camera.reset_physics_interpolation()
	camera.current = true
	for _i: int in range(4):
		await RenderingServer.frame_post_draw
	print("ISLANDDIAG target=%s cam_fwd=%s in_frustum=%s" % [target, -camera.global_transform.basis.z, camera.is_position_in_frustum(target)])
	var rid: RID = sub.get_viewport_rid()
	var calls: int = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var prims: int = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	print("ISLANDPERF %s draw_calls=%d primitives=%d" % [file_name, calls, prims])
	var image: Image = sub.get_texture().get_image()
	image.save_png("user://" + file_name)
	print("SCREENSHOT saved=%s" % ProjectSettings.globalize_path("user://" + file_name))
	sub.queue_free()


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
