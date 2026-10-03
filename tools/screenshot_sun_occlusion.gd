extends Node
## Bontago-mp0.95: before/after sheet for "sun is visible through the clouds and arena".
## Pose A: camera under the disc looking up at the sun through it (the owner's screenshot);
## before = SunFlare.config.reverse_ray_enabled false (the old single forward ray), after = on.
## Pose B: camera under the upper cloud layer with a puff on the sun ray; before = cloud
## occlusion strength 0, after = 1. One process, four captures, one 2x2 sheet:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_sun_occlusion.tscn -- --agent-probe --render-size=1280x720 out=<dir>
## User args: out=<dir> (default user://).
const SETTLE_SECONDS: float = 1.5
## Real seconds the flare needs to converge after a toggle (visibility_lerp_speed 6/s).
const FLARE_SETTLE_SECONDS: float = 2.0
const DRAW_FRAMES: int = 6
const FOV_DEG: float = 85.0
const POSE_A_PHASE: float = 0.10
const POSE_B_PHASE: float = 0.25
const POSE_A_DEPTH_M: float = 40.0
const POSE_B_HEIGHT_M: float = 40.0
const SEARCH_EXTENT_M: float = 400.0
const SEARCH_STEP_M: float = 20.0
const SOLID_OCCLUSION: float = 0.98
const SHEET_COLUMNS: int = 2

var _out_dir: String = "user://"


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=").trim_suffix("/") + "/"
	Settings.set_graphics_preset(&"high")
	var viewport: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
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
	var flare: SunFlare = get_tree().get_first_node_in_group(SunFlare.GROUP) as SunFlare
	var images: Array[Image] = []

	# Pose A: under the disc, the sun behind it.
	skybox.set_cycle_phase(POSE_A_PHASE)
	await _frames()
	var sun: Vector3 = flare.config.sun_direction.normalized()
	var position: Vector3 = -sun * (POSE_A_DEPTH_M / maxf(sun.y, 0.05))
	_aim(camera, position, sun)
	flare.config.reverse_ray_enabled = false
	flare.config.cloud_occlusion_strength = 1.0
	images.append(await _grab(viewport, flare, "a_before"))
	flare.config.reverse_ray_enabled = true
	images.append(await _grab(viewport, flare, "a_after"))
	print("SUNOCC A sun=%s camera=%s" % [sun, position])

	# Pose B: under the upper layer with a puff on the sun ray.
	skybox.set_cycle_phase(POSE_B_PHASE)
	await _frames()
	sun = flare.config.sun_direction.normalized()
	var sea: CloudSea = skybox.get_cloud_sea()
	var found: Vector3 = _find_blocked_position(sea, sun, flare.config)
	print("SUNOCC B sun=%s camera=%s occlusion=%.3f" % [sun, found, sea.sun_ray_cloud_occlusion(found, sun, flare.config)])
	_aim(camera, found, sun)
	flare.config.cloud_occlusion_strength = 0.0
	images.append(await _grab(viewport, flare, "b_before"))
	flare.config.cloud_occlusion_strength = 1.0
	images.append(await _grab(viewport, flare, "b_after"))

	var size: Vector2i = images[0].get_size()
	var sheet: Image = Image.create(size.x * SHEET_COLUMNS, size.y * 2, false, images[0].get_format())
	for i: int in range(images.size()):
		sheet.blit_rect(images[i], Rect2i(Vector2i.ZERO, size), Vector2i((i % SHEET_COLUMNS) * size.x, (i / SHEET_COLUMNS) * size.y))
	var path: String = _out_dir + "sun_occlusion_sheet.png"
	sheet.save_png(path)
	print("SUNOCC sheet=%s size=%s (rows: disc A before/after, cloud B before/after)" % [ProjectSettings.globalize_path(path), sheet.get_size()])
	get_tree().quit()


func _frames() -> void:
	for _i: int in range(DRAW_FRAMES):
		await get_tree().process_frame


func _aim(camera: Camera3D, position: Vector3, direction: Vector3) -> void:
	camera.global_position = position
	camera.look_at(position + direction * 100.0, Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)


## The grid position closest to the origin whose sun ray the puffs hide almost completely.
func _find_blocked_position(sea: CloudSea, sun: Vector3, tuning: SunFlareConfig) -> Vector3:
	var best: Vector3 = Vector3(0.0, POSE_B_HEIGHT_M, 0.0)
	var best_distance: float = INF
	var time_s: float = CloudSea.shader_time_s()
	var steps: int = int(SEARCH_EXTENT_M / SEARCH_STEP_M)
	for ix: int in range(-steps, steps + 1):
		for iz: int in range(-steps, steps + 1):
			var at: Vector3 = Vector3(float(ix) * SEARCH_STEP_M, POSE_B_HEIGHT_M, float(iz) * SEARCH_STEP_M)
			var distance: float = at.length()
			if distance < best_distance and sea.sun_ray_cloud_occlusion(at, sun, tuning, time_s) >= SOLID_OCCLUSION:
				best = at
				best_distance = distance
	return best


func _grab(viewport: SubViewport, flare: SunFlare, label: String) -> Image:
	await get_tree().create_timer(FLARE_SETTLE_SECONDS).timeout
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	print("SUNOCC %s flare_visibility=%.3f" % [label, flare.current_visibility()])
	return image
