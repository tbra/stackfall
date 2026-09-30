extends Node
## Bontago-470.5: ambience evidence. Boots the sandbox match (Main.tscn) and,
## through SubViewports that share its world (so it works with the tiny agent
## window), either shoots the sky/cloud views or measures the GPU cost of the
## cloud puffs at several density scales.
##   godot --path . tools/shoot_ambience_470.tscn -- --mode=shots --theme=sunset --tag=before
##   godot --path . tools/shoot_ambience_470.tscn -- --mode=bench --theme=sunset --scales=1,2,4,8 --sizes=1280x720,1920x1080
## Shots go to user://ambience_470/<tag>_<theme>_<view>.png. Bench prints AMB_BENCH lines.
const OUT_DIR: String = "user://ambience_470/"
const SHOT_SIZE: Vector2i = Vector2i(1280, 720)
const SETTLE_FRAMES: int = 40
const WARMUP_FRAMES: int = 20
const BLOCK_FRAMES: int = 40
const BLOCKS: int = 3
const OVERVIEW_DISTANCE_M: float = 62.0
const OVERVIEW_PITCH_DEG: float = -48.0
const HORIZON_OFFSET_M: float = 4.0
const HORIZON_HEIGHT_M: float = 2.0
const SUN_HEIGHT_M: float = 14.0
const SUN_PITCH_DEG: float = 6.0
const VIEW_FOV_DEG: float = 60.0
const BENCH_VIEWS: PackedStringArray = ["player", "overview", "horizon"]
const SHOT_VIEWS: PackedStringArray = ["player", "overview", "horizon", "sun", "sky_up"]

var _main: Node = null
var _skybox: Skybox = null
var _real_camera: Camera3D = null
var _disc_radius: float = 30.0


func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args: Dictionary = _parse_args()
	Settings.set_graphics_preset(StringName(str(args.get("preset", "high"))))
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	for _i: int in range(90):
		await get_tree().physics_frame
	_skybox = _main.get_node("Skybox") as Skybox
	var theme_id: String = str(args.get("theme", "sunset"))
	if theme_id != "sunset":
		_skybox.set_theme_by_id(theme_id)
	for _i: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	_real_camera = get_viewport().get_camera_3d()
	var field: Field = _main.get_node("Field") as Field
	_disc_radius = field.map_definition().field_radius
	if str(args.get("mode", "shots")) == "bench":
		await _bench(args, theme_id)
	elif str(args.get("mode", "shots")) == "birds":
		await _birds(str(args.get("tag", "birds")), int(str(args.get("frames", "6"))), float(str(args.get("fov", "22"))))
	else:
		await _shots(str(args.get("tag", "shot")), theme_id, float(str(args.get("wait", "0"))))
	get_tree().quit()


func _parse_args() -> Dictionary:
	var result: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts: PackedStringArray = arg.substr(2).split("=", true, 1)
			result[parts[0]] = parts[1]
	return result


func _view_transform(view: String) -> Transform3D:
	match view:
		"player":
			return _real_camera.global_transform
		"overview":
			var pitch: float = deg_to_rad(-OVERVIEW_PITCH_DEG)
			var offset: Vector3 = Vector3(0.0, sin(pitch), cos(pitch)) * OVERVIEW_DISTANCE_M
			return Transform3D(Basis.IDENTITY, offset).looking_at(Vector3.ZERO, Vector3.UP)
		"horizon":
			var from: Vector3 = Vector3(_disc_radius + HORIZON_OFFSET_M, HORIZON_HEIGHT_M, 0.0)
			return Transform3D(Basis.IDENTITY, from).looking_at(from + Vector3(1.0, -0.12, 0.0), Vector3.UP)
		"sun":
			var dir: Vector3 = _sun_direction()
			var from: Vector3 = Vector3(0.0, SUN_HEIGHT_M, 0.0)
			var flat: Vector3 = Vector3(dir.x, 0.0, dir.z).normalized()
			var target: Vector3 = from + flat * 100.0 + Vector3.UP * (tan(deg_to_rad(SUN_PITCH_DEG)) * 100.0)
			return Transform3D(Basis.IDENTITY, from).looking_at(target, Vector3.UP)
		_:
			var up_from: Vector3 = Vector3(0.0, SUN_HEIGHT_M, 0.0)
			return Transform3D(Basis.IDENTITY, up_from).looking_at(up_from + Vector3(0.3, 0.6, -1.0), Vector3.UP)


func _sun_direction() -> Vector3:
	var sea: CloudSea = _skybox.get_cloud_sea()
	var material: ShaderMaterial = sea.puff_material()
	if material != null:
		var value: Variant = material.get_shader_parameter(&"light_direction")
		if value is Vector3:
			return value as Vector3
	return Vector3(0.96, 0.07, -0.26)


func _make_sub(size: Vector2i) -> Array:
	var sub: SubViewport = SubViewport.new()
	sub.size = size
	sub.world_3d = get_viewport().world_3d
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera: Camera3D = Camera3D.new()
	camera.fov = VIEW_FOV_DEG
	camera.near = _real_camera.near
	camera.far = _real_camera.far
	camera.environment = _real_camera.environment
	sub.add_child(camera)
	add_child(sub)
	camera.current = true
	return [sub, camera]


func _shots(tag: String, theme_id: String, wait_s: float) -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	if wait_s > 0.0:
		await get_tree().create_timer(wait_s).timeout
	var made: Array = _make_sub(SHOT_SIZE)
	var sub: SubViewport = made[0] as SubViewport
	var camera: Camera3D = made[1] as Camera3D
	for view: String in SHOT_VIEWS:
		camera.global_transform = _view_transform(view)
		for _i: int in range(6):
			await RenderingServer.frame_post_draw
		var path: String = "%s%s_%s_%s.png" % [OUT_DIR, tag, theme_id, view]
		sub.get_texture().get_image().save_png(path)
		print("AMB_SHOT %s" % ProjectSettings.globalize_path(path))


func _bench(args: Dictionary, theme_id: String) -> void:
	var scales: PackedStringArray = str(args.get("scales", "1")).split(",")
	var sizes: PackedStringArray = str(args.get("sizes", "1280x720")).split(",")
	var base_theme: SkyThemeDef = Skybox.load_theme(theme_id)
	var sea: CloudSea = _skybox.get_cloud_sea()
	for size_text: String in sizes:
		var parts: PackedStringArray = size_text.split("x")
		var made: Array = _make_sub(Vector2i(int(parts[0]), int(parts[1])))
		var sub: SubViewport = made[0] as SubViewport
		var camera: Camera3D = made[1] as Camera3D
		var rid: RID = sub.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(rid, true)
		for scale_text: String in scales:
			var factor: float = float(scale_text)
			var theme: SkyThemeDef = base_theme.duplicate() as SkyThemeDef
			theme.cloud_clump_count = int(round(float(base_theme.cloud_clump_count) * factor))
			theme.cloud_bank_count = int(round(float(base_theme.cloud_bank_count) * factor * float(str(args.get("bankmult", "1")))))
			theme.cloud_clump_count = int(round(float(theme.cloud_clump_count) * float(str(args.get("seamult", "1")))))
			sea.configure(theme, 1.0, theme.sky_material)
			var instance: MultiMeshInstance3D = sea.puff_instance()
			for view: String in BENCH_VIEWS:
				camera.global_transform = _view_transform(view)
				var with_ms: float = 0.0
				var without_ms: float = 0.0
				for block: int in range(BLOCKS * 2):
					var shown: bool = block % 2 == 0
					instance.visible = shown
					for _i: int in range(WARMUP_FRAMES):
						await RenderingServer.frame_post_draw
					var total: float = 0.0
					for _i: int in range(BLOCK_FRAMES):
						await RenderingServer.frame_post_draw
						total += RenderingServer.viewport_get_measured_render_time_gpu(rid)
					if shown:
						with_ms += total / float(BLOCK_FRAMES * BLOCKS)
					else:
						without_ms += total / float(BLOCK_FRAMES * BLOCKS)
				instance.visible = true
				await RenderingServer.frame_post_draw
				var draws: int = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
				var prims: int = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
				print("AMB_BENCH theme=%s size=%s scale=%s view=%s clumps=%d puffs=%d gpu_with=%.3f gpu_without=%.3f puffs_ms=%.3f draws=%d prims=%d" % [
					theme_id, size_text, scale_text, view, theme.cloud_clump_count, sea.puff_count(), with_ms, without_ms, with_ms - without_ms, draws, prims,
				])
		sub.queue_free()


## Launches every distant-bird slot, jumps to mid-crossing and shoots a wide
## and a telephoto sequence of the first flock (one shot per `frames` real frames).
func _birds(tag: String, shots: int, tele_fov: float) -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var birds: DistantBirds = _skybox.get_birds()
	var forced: SkyThemeDef = Skybox.load_theme("sunset").duplicate() as SkyThemeDef
	forced.bird_single_chance = 0.0
	forced.bird_flock_size_min = 5
	forced.bird_flock_size_max = 7
	forced.bird_seed = 4
	birds.configure(forced, true)
	for slot: int in range(birds.slot_count()):
		birds.launch_now(slot)
	var flight: FlockPlanner.Flight = birds.flight_of(0)
	if flight == null:
		print("AMB_BIRDS none (theme has no flocks)")
		return
	birds.advance(flight.duration_s * 0.5)
	print("AMB_BIRDS slots=%d flock0=%d closest=%.0f duration=%.0f v=%s" % [
		birds.slot_count(), birds.birds_in_slot(0), flight.closest_distance_m, flight.duration_s, flight.is_v])
	var made: Array = _make_sub(SHOT_SIZE)
	var sub: SubViewport = made[0] as SubViewport
	var camera: Camera3D = made[1] as Camera3D
	var origin: Vector3 = Vector3(0.0, SUN_HEIGHT_M, 0.0)
	var launched_at: float = birds.flight_clock() - flight.duration_s * 0.5
	for shot: int in range(shots):
		if shot > 0:
			birds.advance(1.5)
		var leader: Vector3 = flight.position_at(birds.flight_clock() - launched_at)
		camera.fov = VIEW_FOV_DEG if shot == 0 else tele_fov
		camera.global_transform = Transform3D(Basis.IDENTITY, origin).looking_at(leader, Vector3.UP)
		for _i: int in range(6):
			await RenderingServer.frame_post_draw
		var path: String = "%s%s_birds_%d.png" % [OUT_DIR, tag, shot]
		sub.get_texture().get_image().save_png(path)
		print("AMB_SHOT %s" % ProjectSettings.globalize_path(path))
