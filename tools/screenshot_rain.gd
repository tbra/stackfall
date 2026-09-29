extends Node
## Bontago-22y.5: rain capture. Boots the sandbox, starts rain on the host
## schedule seam, waits for the hold, shoots the player view (the rig camera's
## own transform) and a wide view, prints friction values and the cost of one
## wet-friction rewrite. Off-screen SubViewport capture only:
##   godot --path . --windowed --position 10000,10000 tools/screenshot_rain.tscn --quit-after 900
const OUTPUT_DIR: String = "user://"
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const RAMP_FRAMES: int = 420
const HALF_FRAMES: int = 120
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
	await _wait(60)
	var disc: Field = Match.field()
	var before: float = disc.physics_material_override.friction
	print("RAIN start disc_friction=%s host=%s" % [before, Match.weather()._is_host()])
	await _capture_pair("rain_r3_off")
	print("RAIN started=%s" % Match.weather().start_event(&"rain"))
	# Half intensity: freeze the ramp part-way (ramp_in 4 s = 240 physics frames).
	await _wait(HALF_FRAMES)
	print("RAIN half intensity=%s" % Match.weather().active_intensity())
	await _capture_pair("rain_r3_half")
	await _wait(RAMP_FRAMES)
	print("RAIN full intensity=%s disc_friction=%s" % [Match.weather().active_intensity(), disc.physics_material_override.friction])
	await _capture_pair("rain_r3_full")
	# Cost of one wet-friction rewrite over 300 materials.
	var effect: RainEffect = RainEffect.new()
	effect.tuning = load("res://config/weather/rain.tres") as RainTuning
	var bodies: Array = []
	for _i: int in range(300):
		var body: RigidBody3D = RigidBody3D.new()
		body.physics_material_override = PhysicsMaterial.new()
		bodies.append(body)
	effect.set_providers(func() -> Array: return bodies, func() -> Variant: return null)
	effect.apply(0.1)
	var start: int = Time.get_ticks_usec()
	for step: int in range(100):
		effect.apply(0.1 + 0.005 * float(step % 100 + 1) * 2.0)
	print("RAIN write_300_materials_us=%.1f" % (float(Time.get_ticks_usec() - start) / 100.0))
	effect.restore()
	Match.weather().reset()
	print("RAIN restored disc_friction=%s" % disc.physics_material_override.friction)
	get_tree().quit()


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = await _render_large_shot()
	var path: String = OUTPUT_DIR + file_name
	image.save_png(path)
	print("SCREENSHOT rain saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])


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


func _capture_pair(tag: String) -> void:
	_view = get_viewport().get_camera_3d().global_transform
	await _shoot(tag + "_player.png")
	_view = Transform3D(Basis.IDENTITY, Vector3(0.0, 30.0, 45.0)).looking_at(Vector3.ZERO, Vector3.UP)
	await _shoot(tag + "_wide.png")
