extends Node
## Bontago-adt.3 (round 2): perching-bird review capture. Sandbox on sunset:
## natural disc landings (with the local cursor logged), medium/close shots, a
## flee sequence, a gameplay-distance view, a STAGED tower (a fake block stack
## is added so a bird can perch on it), and cost timing (bird script CPU, fireflies GPU).
##   godot --path . --windowed --position 10000,10000 tools/screenshot_ambient_r2.tscn --quit-after 6000
const OUTPUT_DIR: String = "user://"
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const FAST_TIME_SCALE: float = 6.0
const LAND_TIMEOUT_FRAMES: int = 2400
const TIMING_FRAMES: int = 300
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
	life.spawn_delay_min_s = 0.5
	life.spawn_delay_max_s = 2.0
	life.approach_circle_time_min_s = 1.0
	life.approach_circle_time_max_s = 3.0
	life.perch_stay_min_s = 900.0
	life.perch_stay_max_s = 1000.0
	life.perch_tower_fraction = 0.0
	birds.configure(life, true)
	var perched: Array[PerchingBird] = await _fast_until(birds, 3)
	print("R2 perched=%d" % perched.size())
	var ghost: Node3D = get_tree().get_first_node_in_group(GhostPreview.LOCAL_HELD_GROUP) as Node3D
	var field: Field = _main.get_node("Field") as Field
	for bird: PerchingBird in perched:
		var surface: Vector3 = bird.perch_surface
		var to_ghost: float = Vector2(surface.x - ghost.global_position.x, surface.z - ghost.global_position.z).length()
		var to_home: float = 999.0
		for flag: HomeFlag in field.home_flags():
			to_home = minf(to_home, Vector2(surface.x - flag.global_position.x, surface.z - flag.global_position.z).length())
		print("R2 bird surface=%s dist_to_cursor=%.1f dist_to_home=%.1f" % [surface, to_ghost, to_home])
	print("R2 ghost=%s visible=%s" % [ghost.global_position, ghost.is_visible_in_tree()])
	if perched.is_empty():
		get_tree().quit()
		return
	var bird: PerchingBird = perched[0]
	# Natural landings with the cursor in view: camera near the ghost looking at the disc.
	_aim(ghost.global_position, 30.0, -30.0, PI * 0.5)
	await _wait(10)
	await _shoot("ambient_r2_natural_cursor_view.png")
	# Medium and close on a disc bird.
	_aim(bird.global_position, 5.0, -25.0, 0.7, 1.2)
	await _wait(10)
	await _shoot("ambient_r2_disc_medium.png")
	life.flee_camera_radius_m = 0.0
	_aim(bird.global_position + Vector3(0.0, 0.05, 0.0), 1.5, -8.0, 1.0, 0.35)
	await _wait(30)
	await _shoot("ambient_r2_disc_close_a.png")
	await _wait(40)
	await _shoot("ambient_r2_disc_close_b.png")
	# Gameplay distance (typical follow distance) on another bird.
	var other: PerchingBird = perched[1] if perched.size() > 1 else bird
	_aim(other.global_position, 22.0, -35.0, 0.3)
	await _wait(10)
	await _shoot("ambient_r2_gameplay_distance.png")
	_view = get_viewport().get_camera_3d().global_transform
	await _shoot("ambient_r2_gameplay_real_camera.png")
	# Flee sequence on the first bird.
	_aim(bird.global_position + Vector3(0.0, 0.6, 0.0), 3.0, -12.0, 1.0, 0.7)
	await _wait(5)
	Events.block_impacted_at.emit(8.0, bird.global_position + Vector3(2.0, 0.0, 1.0))
	var elapsed: Array[int] = [2, 8, 16, 30]
	var previous: int = 0
	for index: int in range(elapsed.size()):
		await _wait(elapsed[index] - previous)
		previous = elapsed[index]
		await _shoot("ambient_r2_flee_%d.png" % index)
	life.flee_camera_radius_m = 9.0
	# Cost: bird script CPU per frame with 4 birds active.
	birds.configure(life, true)
	await _fast_until(birds, 3)
	var total_usec: int = 0
	var frames: int = 0
	for _i: int in range(TIMING_FRAMES):
		await get_tree().process_frame
		var started: int = Time.get_ticks_usec()
		birds._process(0.0)
		total_usec += Time.get_ticks_usec() - started
		frames += 1
	print("R2 COST birds_process_only_avg_ms=%.4f (extra manual call, 4 birds, %d frames)" % [float(total_usec) / 1000.0 / float(frames), frames])
	# STAGED tower: add a stack of boxes and prefer towers.
	var tower: RigidBody3D = RigidBody3D.new()
	tower.freeze = true
	tower.name = "StagedTower"
	for level: int in range(3):
		var collision: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3.ONE
		collision.shape = box
		collision.position = Vector3(0.0, 0.5 + float(level), 0.0)
		tower.add_child(collision)
	var visual: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(1.0, 3.0, 1.0)
	visual.mesh = mesh
	visual.position = Vector3(0.0, 1.5, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.3, 0.25)
	visual.material_override = mat
	tower.add_child(visual)
	_main.add_child(tower)
	tower.global_position = Vector3(-6.0, 0.0, 24.0)
	birds.bind_scene(field, null)
	birds.blocks = [tower]
	life.perch_tower_fraction = 1.0
	life.perch_tower_min_settle_s = 0.5
	life.perch_bird_count = 2
	birds.configure(life, true)
	var on_tower: PerchingBird = null
	Engine.time_scale = FAST_TIME_SCALE
	for _i: int in range(LAND_TIMEOUT_FRAMES):
		await get_tree().process_frame
		for slot: int in range(birds.slot_count()):
			var candidate: PerchingBird = birds.bird_at(slot)
			if candidate != null and candidate.is_perched() and birds.perched_on_tower(slot):
				on_tower = candidate
		if on_tower != null:
			break
	Engine.time_scale = 1.0
	print("R2 tower_bird=%s" % (on_tower != null))
	if on_tower != null:
		life.flee_camera_radius_m = 0.0
		_aim(on_tower.global_position, 5.0, -20.0, 0.6, 1.2)
		await _wait(10)
		await _shoot("ambient_r2_tower_medium.png")
		_aim(on_tower.global_position + Vector3(0.0, 0.05, 0.0), 1.5, -8.0, 0.9, 0.35)
		await _wait(30)
		await _shoot("ambient_r2_tower_close.png")
		life.flee_camera_radius_m = 9.0
	# Fireflies GPU cost at night, 1280x720 sub-viewport.
	var panels: Array[Node] = _main.find_children("*", "TuningPanel", true, false)
	var panel: TuningPanel = panels[0] as TuningPanel
	panel.apply_sky_theme_id("night")
	await _wait(30)
	var sub: SubViewport = SubViewport.new()
	sub.size = CAPTURE_SIZE
	sub.world_3d = get_viewport().world_3d
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera: Camera3D = Camera3D.new()
	sub.add_child(camera)
	add_child(sub)
	_aim(Vector3.ZERO, 62.0, -48.0, 0.0)
	camera.global_transform = _view
	camera.current = true
	RenderingServer.viewport_set_measure_render_time(sub.get_viewport_rid(), true)
	var fireflies: Fireflies = skybox.get_fireflies()
	var results: Dictionary = {}
	for enabled: bool in [true, false, true, false]:
		fireflies.visible = enabled
		await _wait(20)
		var gpu_total: float = 0.0
		var cpu_total: float = 0.0
		for _i: int in range(TIMING_FRAMES):
			await get_tree().process_frame
			gpu_total += RenderingServer.viewport_get_measured_render_time_gpu(sub.get_viewport_rid())
			cpu_total += RenderingServer.viewport_get_measured_render_time_cpu(sub.get_viewport_rid())
		print("R2 COST fireflies_visible=%s gpu_ms=%.3f cpu_ms=%.3f (1280x720 subviewport, avg of %d)" % [enabled, gpu_total / float(TIMING_FRAMES), cpu_total / float(TIMING_FRAMES), TIMING_FRAMES])
	get_tree().quit()


func _fast_until(birds: PerchingBirds, wanted: int) -> Array[PerchingBird]:
	Engine.time_scale = FAST_TIME_SCALE
	var result: Array[PerchingBird] = []
	for _i: int in range(LAND_TIMEOUT_FRAMES):
		await get_tree().process_frame
		result = _perched(birds)
		if result.size() >= wanted:
			break
	Engine.time_scale = 1.0
	return result


func _perched(birds: PerchingBirds) -> Array[PerchingBird]:
	var result: Array[PerchingBird] = []
	for index: int in range(birds.slot_count()):
		var bird: PerchingBird = birds.bird_at(index)
		if bird != null and bird.is_perched():
			result.append(bird)
	return result


## The capture uses its own camera, `distance` from `target`, elevated by -pitch_deg, around `yaw`.
func _aim(target: Vector3, distance: float, pitch_deg: float, yaw: float, lateral: float = 0.0) -> void:
	var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
	target += right * lateral
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
