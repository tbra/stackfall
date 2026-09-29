extends Node
## Bontago-adt: live sky-theme switch capture. Boots the real Main.tscn sandbox,
## shoots a wide view (sunset), switches to night through the F4 panel's
## apply_sky_theme_id() (same path as the Theme dropdown), shoots again, then
## back to sunset. Off-screen SubViewport capture only:
##   godot --path . --windowed --position 10000,10000 tools/screenshot_sky_theme_switch.tscn --quit-after 400
const OUTPUT_DIR: String = "user://"
const SETTLE_FRAMES: int = 90
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const WIDE_DISTANCE_M: float = 26.0
const WIDE_PITCH_DEG: float = -14.0


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
	rig._target = field.home_flags()[0].global_position + Vector3(0.0, 1.0, 0.0)
	rig._yaw = 0.0
	rig.tuning.follow_distance = WIDE_DISTANCE_M
	rig.tuning.follow_pitch_deg = WIDE_PITCH_DEG
	rig.apply_follow_tuning()
	rig.reset_physics_interpolation()
	rig.get_camera().reset_physics_interpolation()
	var panels: Array[Node] = main.find_children("*", "TuningPanel", true, false)
	var panel: TuningPanel = panels[0] as TuningPanel if not panels.is_empty() else null
	print("SCREENSHOT sky panel_found=%s" % (panel != null))
	await _wait(SETTLE_FRAMES)
	await _shoot("sky_switch_1_sunset.png")
	for theme_id: String in ["night", "sunset", "night"]:
		if panel != null:
			panel.apply_sky_theme_id(theme_id)
		await _wait(SETTLE_FRAMES)
		if theme_id == "night":
			await _shoot("sky_switch_%s_night.png" % ("2" if theme_id == "night" and not FileAccess.file_exists(OUTPUT_DIR + "sky_switch_2_night.png") else "4"))
		else:
			await _shoot("sky_switch_3_sunset_again.png")
	get_tree().quit()


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
