extends Node
## Bontago-mp0.130: before/after fog retune captures + indicative GPU/frame time.
## Off-screen SubViewport capture of the wide (whole disc + far rim) view per
## theme, then one short perf sample. Run:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_fog_retune.tscn -- --agent-probe --tag=before
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const THEMES: Array[String] = ["dawn", "sunset"]
const WIDE_VIEW: Vector3 = Vector3(0.0, 30.0, 45.0)
const PERF_FRAMES: int = 90
const WARMUP_FRAMES: int = 30
var _tag: String = "after"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
	Settings.set_graphics_preset(&"high")
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(60)
	for theme_id: String in THEMES:
		_set_theme(theme_id)
		await _wait(10)
		await _shoot("%s_%s.png" % [_tag, theme_id])
	_set_theme("sunset")
	print("FOG started=%s" % Match.weather().start_event(&"fog"))
	await _wait(500)
	await _shoot("%s_sunset_fogweather.png" % _tag)
	Match.weather().reset()
	await _wait(30)
	_set_theme("sunset")
	await _wait(10)
	await _perf_variants()
	Match.weather().reset()
	get_tree().quit()


func _set_theme(theme_id: String) -> void:
	for node: Node in get_tree().get_nodes_in_group(Skybox.TUNING_GROUP):
		(node as Skybox).set_theme_by_id(theme_id)


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame


func _make_sub() -> Array:
	var source: Camera3D = get_viewport().get_camera_3d()
	var sub: SubViewport = SubViewport.new()
	sub.size = CAPTURE_SIZE
	sub.world_3d = get_viewport().world_3d
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera: Camera3D = Camera3D.new()
	camera.fov = source.fov
	camera.near = source.near
	camera.far = source.far
	camera.environment = source.environment
	sub.add_child(camera)
	add_child(sub)
	camera.global_transform = Transform3D(Basis.IDENTITY, WIDE_VIEW).looking_at(Vector3.ZERO, Vector3.UP)
	camera.current = true
	return [sub, camera]


func _shoot(file_name: String) -> void:
	var parts: Array = _make_sub()
	var sub: SubViewport = parts[0]
	for _i: int in range(4):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	sub.queue_free()
	var path: String = "user://" + file_name
	image.save_png(path)
	print("SCREENSHOT %s" % ProjectSettings.globalize_path(path))


func _perf() -> void:
	var parts: Array = _make_sub()
	var sub: SubViewport = parts[0]
	var rid: RID = sub.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for _i: int in range(WARMUP_FRAMES):
		await RenderingServer.frame_post_draw
	var gpu: float = 0.0
	var cpu: float = 0.0
	var start: int = Time.get_ticks_usec()
	for _i: int in range(PERF_FRAMES):
		await RenderingServer.frame_post_draw
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	var wall: float = float(Time.get_ticks_usec() - start) / 1000.0 / float(PERF_FRAMES)
	print("PERF %s gpu_ms=%.3f cpu_ms=%.3f wall_ms=%.3f" % [_tag, gpu / PERF_FRAMES, cpu / PERF_FRAMES, wall])
	sub.queue_free()


func _env() -> Environment:
	return get_viewport().get_camera_3d().environment if get_viewport().get_camera_3d().environment != null else (get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment).environment


func _volume() -> FogVolume:
	return get_tree().root.find_children("*", "FogVolume", true, false)[0] as FogVolume


## A/B variants of the sunset fog, 3 reps each, median GPU ms (indicative).
func _perf_variants() -> void:
	var environment: Environment = _env()
	var volume: FogVolume = _volume()
	var fog_material: FogMaterial = volume.material as FogMaterial
	var base_density: float = environment.fog_density
	var base: Dictionary = {"aerial": environment.fog_aerial_perspective, "scatter": environment.fog_sun_scatter,
		"height": environment.fog_height_density, "affect": environment.fog_sky_affect,
		"vol": fog_material.density, "haze": WeatherFogShader.ambient_strength}
	var variants: Array[String] = ["current", "legacy", "no_height", "no_aerial", "no_scatter", "volume_legacy", "no_haze"]
	for variant: String in variants:
		environment.fog_aerial_perspective = base["aerial"]
		environment.fog_sun_scatter = base["scatter"]
		environment.fog_height_density = base["height"]
		environment.fog_sky_affect = base["affect"]
		fog_material.density = base["vol"]
		WeatherFogShader.set_ambient(base["haze"], 90.0, 480.0, environment.fog_light_color, get_tree())
		match variant:
			"legacy":
				environment.fog_density = 0.0003
				environment.fog_aerial_perspective = 0.0
				environment.fog_sun_scatter = 0.0
				environment.fog_height_density = 0.0
				environment.fog_sky_affect = 0.0
				fog_material.density = 0.0003
				WeatherFogShader.set_ambient(0.0, 90.0, 480.0, Color.WHITE, get_tree())
			"no_height":
				environment.fog_height_density = 0.0
			"no_aerial":
				environment.fog_aerial_perspective = 0.0
			"no_scatter":
				environment.fog_sun_scatter = 0.0
			"volume_legacy":
				fog_material.density = 0.0003
			"no_haze":
				WeatherFogShader.set_ambient(0.0, 90.0, 480.0, Color.WHITE, get_tree())
		var samples: Array[float] = []
		for _rep: int in range(3):
			samples.append(await _gpu_sample())
		samples.sort()
		print("PERFV %s median_gpu_ms=%.3f all=%s" % [variant, samples[1], samples])
	environment.fog_density = base_density


func _gpu_sample() -> float:
	var parts: Array = _make_sub()
	var sub: SubViewport = parts[0]
	var rid: RID = sub.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for _i: int in range(WARMUP_FRAMES):
		await RenderingServer.frame_post_draw
	var gpu: float = 0.0
	for _i: int in range(PERF_FRAMES):
		await RenderingServer.frame_post_draw
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	sub.queue_free()
	return gpu / PERF_FRAMES
