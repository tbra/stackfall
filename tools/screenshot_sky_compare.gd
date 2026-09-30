extends Node
## Bontago-59o.16 P5: owner comparison of the painted sky against the procedural
## look. Renders both from three identical camera poses (default, low orbit,
## looking at the sun), stitches one side-by-side PNG (left painted, right
## procedural) to docs/sky_compare_sunset.png and prints an indicative perf
## sample (average GPU and frame ms over PERF_FRAMES, toggle off vs on).
## Off-screen run, quits after the capture:
##   godot --path . --windowed --position 10000,10000 res://tools/screenshot_sky_compare.tscn -- --sandbox

const SETTLE_S: float = 1.5
const PERF_FRAMES: int = 120
const PERF_WARMUP_FRAMES: int = 30
const PANEL_WIDTH: int = 800
const OUTPUT_PATH: String = "res://docs/sky_compare_sunset.png"
const POSE_NAMES: Array[String] = ["default", "low orbit", "sun"]
const ORBIT_RADIUS_M: float = 45.0
const DEFAULT_HEIGHT_M: float = 6.0
const LOW_ORBIT_HEIGHT_M: float = 1.0
const LOW_ORBIT_YAW_DEG: float = 100.0
const SUN_PITCH: float = 0.15
const LOW_PITCH: float = -0.05


func _ready() -> void:
	call_deferred("_capture")


func _grab() -> Image:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var scale: float = float(PANEL_WIDTH) / float(image.get_width())
	image.resize(PANEL_WIDTH, int(round(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	return image


func _pose(camera: Camera3D, index: int, direction: Vector3) -> void:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z).normalized()
	match index:
		0:
			camera.global_position = -flat * ORBIT_RADIUS_M + Vector3.UP * DEFAULT_HEIGHT_M
			camera.look_at(camera.global_position + flat.rotated(Vector3.UP, deg_to_rad(40.0)) + Vector3.UP * LOW_PITCH, Vector3.UP)
		1:
			var side: Vector3 = flat.rotated(Vector3.UP, deg_to_rad(LOW_ORBIT_YAW_DEG))
			camera.global_position = -side * ORBIT_RADIUS_M + Vector3.UP * LOW_ORBIT_HEIGHT_M
			camera.look_at(camera.global_position + side + Vector3.UP * LOW_PITCH, Vector3.UP)
		_:
			camera.global_position = -flat * ORBIT_RADIUS_M + Vector3.UP * DEFAULT_HEIGHT_M
			camera.look_at(camera.global_position + direction + Vector3.UP * SUN_PITCH, Vector3.UP)


func _set_procedural(skybox: Skybox, on: bool) -> void:
	skybox.theme.sky_look_procedural = on
	skybox.apply_theme(skybox.theme)
	await get_tree().create_timer(0.5).timeout


func _perf() -> Dictionary:
	var viewport_rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	for _i: int in range(PERF_WARMUP_FRAMES):
		await get_tree().process_frame
	var gpu_ms: float = 0.0
	var cpu_ms: float = 0.0
	var start: int = Time.get_ticks_usec()
	for _i: int in range(PERF_FRAMES):
		await RenderingServer.frame_post_draw
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
		cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
	var wall_ms: float = float(Time.get_ticks_usec() - start) / 1000.0 / float(PERF_FRAMES)
	return {"gpu": gpu_ms / PERF_FRAMES, "cpu": cpu_ms / PERF_FRAMES, "wall": wall_ms}


func _capture() -> void:
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
	var direction: Vector3 = flare.config.sun_direction.normalized()
	var painted: Array[Image] = []
	var procedural: Array[Image] = []
	for index: int in range(POSE_NAMES.size()):
		_pose(camera, index, direction)
		await _set_procedural(skybox, false)
		painted.append(await _grab())
		await _set_procedural(skybox, true)
		procedural.append(await _grab())
	# Perf sample at the default pose (indicative: windowed dev GPU, vsync may cap wall time).
	_pose(camera, 0, direction)
	await _set_procedural(skybox, false)
	var off: Dictionary = await _perf()
	await _set_procedural(skybox, true)
	var on: Dictionary = await _perf()
	print("PERF off gpu=%.3f cpu=%.3f wall=%.3f ms | on gpu=%.3f cpu=%.3f wall=%.3f ms | delta gpu=%.3f ms" % [
		off["gpu"], off["cpu"], off["wall"], on["gpu"], on["cpu"], on["wall"], float(on["gpu"]) - float(off["gpu"])])
	var panel_h: int = painted[0].get_height()
	var sheet: Image = Image.create(PANEL_WIDTH * 2, panel_h * POSE_NAMES.size(), false, Image.FORMAT_RGB8)
	for index: int in range(POSE_NAMES.size()):
		sheet.blit_rect(painted[index], Rect2i(0, 0, PANEL_WIDTH, panel_h), Vector2i(0, index * panel_h))
		sheet.blit_rect(procedural[index], Rect2i(0, 0, PANEL_WIDTH, panel_h), Vector2i(PANEL_WIDTH, index * panel_h))
	var out: String = ProjectSettings.globalize_path(OUTPUT_PATH)
	sheet.save_png(out)
	print("SCREENSHOT ", out)
	get_tree().quit()
