extends Node
## Bontago-6fc.3: social perching birds. Boots the sandbox on the sunset theme,
## forces one flock of five, waits for it to perch, then shoots the flock, a
## chase flight and the group takeoff. Off-screen SubViewport capture only:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_ambient_flock.tscn -- --agent-probe --render-size=1280x720
const OUTPUT_DIR: String = "user://"
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const FAST_TIME_SCALE: float = 4.0
const LAND_TIMEOUT_FRAMES: int = 2400
const FLOCK_SIZE: int = 5
var _main: Node = null
var _view: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(90)
	var skybox: Skybox = _main.get_node("Skybox") as Skybox
	var birds: PerchingBirds = skybox.get_perching_birds()
	var life: AmbientLifeConfig = birds.config
	life.flock_size_min = FLOCK_SIZE
	life.flock_size_max = FLOCK_SIZE
	life.flock_count_max = 1
	life.spawn_delay_min_s = 0.5
	life.spawn_delay_max_s = 1.0
	life.approach_circle_time_min_s = 1.0
	life.approach_circle_time_max_s = 2.0
	life.perch_stay_min_s = 400.0
	life.perch_stay_max_s = 500.0
	life.flock_social_interval_min_s = 600.0
	life.flock_social_interval_max_s = 600.0
	life.flee_camera_radius_m = 0.0
	birds.configure(life, true)
	Engine.time_scale = FAST_TIME_SCALE
	var perched: Array[PerchingBird] = []
	for _i: int in range(LAND_TIMEOUT_FRAMES):
		await get_tree().process_frame
		perched = _perched(birds)
		if perched.size() >= FLOCK_SIZE:
			break
	Engine.time_scale = 1.0
	print("FLOCK perched=%d flocks=%d" % [perched.size(), birds.flock_count()])
	if perched.is_empty():
		get_tree().quit()
		return
	var centre: Vector3 = Vector3.ZERO
	for bird: PerchingBird in perched:
		centre += bird.global_position
	centre /= float(perched.size())
	_aim(Vector3.ZERO, 62.0, -48.0, 0.0)
	await _wait(10)
	await _shoot("flock_1_wide.png")
	_aim(centre, 6.0, -20.0, 0.7)
	await _wait(20)
	await _shoot("flock_2_perched_together.png")
	# Chase: two flockmates loop around each other.
	life.flock_chase_chance = 1.0
	life.flock_swap_chance = 0.0
	life.flock_social_interval_min_s = 0.1
	life.flock_social_interval_max_s = 0.1
	var orbiting: bool = false
	for flock: Variant in birds._flocks:
		flock.social_left = 0.1
	for _i: int in range(240):
		await get_tree().physics_frame
		for index: int in range(birds.slot_count()):
			var bird: PerchingBird = birds.bird_at(index)
			orbiting = orbiting or (bird != null and bird.state == PerchingBird.State.ORBIT)
		if orbiting:
			break
	await _wait(55)
	print("FLOCK orbiting=%s" % orbiting)
	await _shoot("flock_3_chase.png")
	life.flock_social_interval_min_s = 600.0
	life.flock_social_interval_max_s = 600.0
	await _wait(240)
	# Group takeoff: one impact right beside a bird.
	var victim: PerchingBird = _perched(birds)[0]
	Events.block_impacted_at.emit(8.0, victim.global_position + Vector3(0.1, 0.0, 0.0))
	await _wait(18)
	_aim(centre + Vector3(0.0, 2.0, 0.0), 9.0, -15.0, 0.7)
	await _shoot("flock_4_group_takeoff.png")
	get_tree().quit()


func _perched(birds: PerchingBirds) -> Array[PerchingBird]:
	var result: Array[PerchingBird] = []
	for index: int in range(birds.slot_count()):
		var bird: PerchingBird = birds.bird_at(index)
		if bird != null and bird.is_perched():
			result.append(bird)
	return result


func _aim(target: Vector3, distance: float, pitch_deg: float, yaw: float) -> void:
	var elevation: float = deg_to_rad(-pitch_deg)
	var offset: Vector3 = Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * distance
	_view = Transform3D(Basis.IDENTITY, target + offset).looking_at(target, Vector3.UP)


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = await _render_large_shot()
	var path: String = OUTPUT_DIR + file_name
	ContactSheet.save_capture(image, path)
	print("SCREENSHOT flock saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])


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
