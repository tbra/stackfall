extends Node
## Bontago-1pi.85.30: one off-screen capture of an erupting Volcano structure
## (volcano_v1 model, ember particles) on the disc, at the follow camera's framing. Derived from
## screenshot_beacon_collision.gd. Run windowed off-screen, quits after saving.

const OUTPUT_DIR: String = "user://"
const OUTPUT_NAME: String = "volcano_eruption_particles.png"
const SETTLE_FRAMES: int = 20
const CAPTURE_SIZE: Vector2i = Vector2i(1920, 1080)
const TARGET_HEIGHT_M: float = 2.0
const FOLLOW_DISTANCE_M: float = 16.0
const SETTLE_TICKS: int = 60
const ERUPT_S: float = 0.5
const RISE_STEP_S: float = 1.0 / 60.0


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(1.5 * Engine.physics_ticks_per_second))
	var field: Field = main.get_node("Field") as Field
	var flag: HomeFlag = field.home_flags()[0]
	var def: SpecialDef = load("res://config/specials/volcano.tres") as SpecialDef
	var effect: VolcanoEffect = def.effect as VolcanoEffect
	var volcano: VolcanoStructure = VolcanoStructure.new()
	volcano.configure(effect, 0, false)
	field.add_child(volcano)
	volcano.global_position = flag.global_position + Vector3(0.0, 0.0, -4.0)
	volcano.set_physics_process(false)
	for _i: int in range(int(ceil((effect.rise_s + ERUPT_S) / RISE_STEP_S))):
		volcano.tick(RISE_STEP_S)
	volcano.set_physics_process(true)
	rig.tuning.follow_distance = FOLLOW_DISTANCE_M
	rig._target = volcano.global_position + Vector3(0.0, TARGET_HEIGHT_M, 0.0)
	rig._yaw = 0.0
	rig.apply_follow_tuning()
	rig.reset_physics_interpolation()
	rig.get_camera().reset_physics_interpolation()
	await _wait(SETTLE_FRAMES)
	await _shoot(OUTPUT_NAME)
	get_tree().quit()


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = await _render_large_shot()
	var path: String = OUTPUT_DIR + file_name
	ContactSheet.save_capture(image, path)
	print("SCREENSHOT volcano saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])


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
	camera.global_transform = source.global_transform
	camera.current = true
	for _i: int in range(3):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	sub.queue_free()
	return image


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
