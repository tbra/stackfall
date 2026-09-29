extends Node
## Bontago-adt.3: ambient-life capture. Boots the real Main.tscn sandbox on the
## sunset theme, fast-forwards until a bird has landed, shoots a wide view and a
## close-up, triggers a takeoff and shoots mid-flee, then switches to night
## (through the F4 panel path) and shoots fireflies from a few views.
## Off-screen SubViewport capture only:
##   godot --path . --windowed --position 10000,10000 tools/screenshot_ambient_life.tscn --quit-after 3000
const OUTPUT_DIR: String = "user://"
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const FAST_TIME_SCALE: float = 4.0
const LAND_TIMEOUT_FRAMES: int = 2400
var _rig: CameraRig = null
var _main: Node = null
var _view: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_rig = _main.get_node("CameraRig") as CameraRig
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(90)
	var skybox: Skybox = _main.get_node("Skybox") as Skybox
	var birds: PerchingBirds = skybox.get_perching_birds()
	print("AMBIENT enabled=%s slots=%d" % [birds.is_enabled(), birds.slot_count()])
	var life: AmbientLifeConfig = birds.config
	life.spawn_delay_min_s = 0.5
	life.spawn_delay_max_s = 2.0
	life.approach_circle_time_min_s = 1.0
	life.approach_circle_time_max_s = 3.0
	life.perch_stay_min_s = 400.0
	life.perch_stay_max_s = 500.0
	life.idle_hop_chance = 0.3
	birds.configure(life, true)
	Engine.time_scale = FAST_TIME_SCALE
	var perched: Array[PerchingBird] = []
	for _i: int in range(LAND_TIMEOUT_FRAMES):
		await get_tree().process_frame
		perched = _perched(birds)
		if perched.size() >= 3:
			break
	Engine.time_scale = 1.0
	print("AMBIENT perched=%d towers=%s" % [perched.size(), _tower_flags(birds)])
	if perched.is_empty():
		get_tree().quit()
		return
	var bird: PerchingBird = perched[0]
	# Wide: the whole disc from the default gameplay-ish angle.
	_aim(Vector3.ZERO, 62.0, -48.0, 0.0)
	await _wait(20)
	await _shoot("ambient_1_sunset_wide_birds.png")
	# Medium: camera outside the flee radius.
	_aim(bird.global_position, 16.0, -22.0, 0.6)
	await _wait(20)
	await _shoot("ambient_2_sunset_perched_medium.png")
	# Close-up with the camera flee radius switched off so it stays put.
	life.flee_camera_radius_m = 0.0
	_aim(bird.global_position + Vector3(0.0, 0.25, 0.0), 3.4, -12.0, 0.9)
	await _wait(45)
	await _shoot("ambient_3_sunset_closeup_idle.png")
	await _wait(50)
	await _shoot("ambient_3b_sunset_closeup_idle_later.png")
	# Takeoff: a block impact right beside it.
	Events.block_impacted_at.emit(8.0, bird.global_position + Vector3(2.0, 0.0, 1.0))
	await _wait(14)
	await _shoot("ambient_4_sunset_flee_early.png")
	await _wait(22)
	await _shoot("ambient_5_sunset_flee_mid.png")
	life.flee_camera_radius_m = 9.0
	# Night: fireflies.
	var panels: Array[Node] = _main.find_children("*", "TuningPanel", true, false)
	var panel: TuningPanel = panels[0] as TuningPanel if not panels.is_empty() else null
	print("AMBIENT panel_found=%s" % (panel != null))
	if panel != null:
		panel.apply_sky_theme_id("night")
	await _wait(60)
	print("AMBIENT night birds_enabled=%s motes=%s" % [birds.is_enabled(), skybox.get_fireflies().mote_instance() != null])
	_aim(Vector3.ZERO, 62.0, -48.0, 0.0)
	await _wait(20)
	await _shoot("ambient_6_night_wide.png")
	var field: Field = _main.get_node("Field") as Field
	var radius: float = field.map_definition().field_radius
	_aim(Vector3(radius * 0.8, -3.0, 0.0), 26.0, -8.0, PI * 0.5)
	await _wait(20)
	await _shoot("ambient_7_night_rim_low.png")
	_aim(Vector3(0.0, 0.0, radius * 0.7), 34.0, -18.0, PI)
	await _wait(20)
	await _shoot("ambient_8_night_rim_view.png")
	if panel != null:
		panel.apply_sky_theme_id("sunset")
	await _wait(30)
	print("AMBIENT back-to-sunset birds_enabled=%s motes=%s children=%d" % [birds.is_enabled(), skybox.get_fireflies().mote_instance() != null, skybox.get_child_count()])
	get_tree().quit()


func _perched(birds: PerchingBirds) -> Array[PerchingBird]:
	var result: Array[PerchingBird] = []
	for index: int in range(birds.slot_count()):
		var bird: PerchingBird = birds.bird_at(index)
		if bird != null and bird.is_perched():
			result.append(bird)
	return result


func _tower_flags(birds: PerchingBirds) -> String:
	var flags: Array[String] = []
	for index: int in range(birds.slot_count()):
		flags.append(str(birds.perched_on_tower(index)))
	return ",".join(flags)


## The capture uses its own camera (the gameplay rig keeps following the local
## ghost), placed `distance` from `target`, elevated by -pitch_deg, around `yaw`.
func _aim(target: Vector3, distance: float, pitch_deg: float, yaw: float) -> void:
	var elevation: float = deg_to_rad(-pitch_deg)
	var offset: Vector3 = Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * distance
	_view = Transform3D(Basis.IDENTITY, target + offset).looking_at(target, Vector3.UP)


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = await _render_large_shot()
	var path: String = OUTPUT_DIR + file_name
	image.save_png(path)
	print("SCREENSHOT arena saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])


## Same SubViewport idiom as screenshot_xtq35_haze.gd's own
## _render_large_shot(): a fresh Camera3D matching the real rig camera's
## transform/fov/near/far/environment, sharing the live World3D via
## `sub.world_3d` (own_world_3d stays false), so the capture is CAPTURE_SIZE
## regardless of the actual (OS-clamped) window size.
func _render_large_shot() -> Image:
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
	camera.global_transform = _view
	camera.current = true
	for _i: int in range(3):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	sub.queue_free()
	return image


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
