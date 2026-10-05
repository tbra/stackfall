extends Node
## Bontago-mp0.123: horizon island capture + draw-call / primitive count with
## and without the ring. Off-screen:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy tools/screenshot_horizon_islands.tscn --quit-after 600 -- --agent-probe
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
## Owner start framing (feedback/ref_camera_start.png): camera just outside the
## rim behind the home beacon, raised to see the whole disc, looking outward.
const START_PITCH_DEG: float = -14.0
const START_DISTANCE_M: float = 34.0
const HOME_OFFSET_M: float = 30.0
const SETTLE_FRAMES: int = 90
const CAMERA_HEIGHT_M: float = 6.0
## Close-up diagnosis framing (pass --closeup after --).
const CLOSEUP_DISTANCE_M: float = 320.0
const CLOSEUP_DROP_M: float = 60.0
const THEMES: Dictionary = {"day": 0.25, "dusk": 0.47}


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(90)
	var ring: HorizonIslands = main.get_node("HorizonIslands") as HorizonIslands
	var target: Vector3 = (ring.get_child(0) as Node3D).global_position
	var panels: Array[Node] = main.find_children("*", "TuningPanel", true, false)
	var panel: TuningPanel = panels[0] as TuningPanel
	panel.apply_sky_theme_id("cycle")
	var sky: Skybox = main.get_node("Skybox") as Skybox
	var first: bool = true
	for theme_id: String in THEMES:
		await _wait(SETTLE_FRAMES)
		sky.set_locked_phase(float(THEMES[theme_id]))
		await _wait(SETTLE_FRAMES)
		ring.visible = true
		if first and OS.get_cmdline_user_args().has("--closeup"):
			await _closeup(ring.get_child(0) as Node3D)
		first = false
		await _shoot("islands_%s.png" % theme_id, target, true, START_PITCH_DEG)
	get_tree().quit()


## Close-up of one island in the real shader and sky (diagnosis only): camera
## CLOSEUP_DISTANCE_M from the island toward the arena, at CLOSEUP_DROP_M below the cap.
func _closeup(island: Node3D) -> void:
	var sub: SubViewport = SubViewport.new()
	sub.size = CAPTURE_SIZE
	sub.world_3d = get_viewport().world_3d
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera: Camera3D = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.far = CLOSEUP_DISTANCE_M * 4.0
	sub.add_child(camera)
	add_child(sub)
	var p: Vector3 = island.global_position
	var toward: Vector3 = Vector3(-p.x, 0.0, -p.z).normalized()
	var eye: Vector3 = p + toward * CLOSEUP_DISTANCE_M + Vector3.DOWN * CLOSEUP_DROP_M
	var aim: Vector3 = p + Vector3.DOWN * CLOSEUP_DROP_M * 0.5
	camera.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(aim, Vector3.UP)
	camera.current = true
	for _i: int in range(6):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	image.save_png("user://islands_closeup.png")
	print("SCREENSHOT saved=%s" % ProjectSettings.globalize_path("user://islands_closeup.png"))
	sub.queue_free()


func _shoot(file_name: String, target: Vector3, report: bool, pitch_deg: float) -> void:
	# The real gameplay camera (CameraRig) is aimed at the island through its
	# own set_home_view(); a bare sub-camera ignored look_at under physics
	# interpolation, so this probe never moves a second camera.
	var main: Node = get_tree().root.get_node("Main")
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig
	var outward: Vector3 = Vector3(target.x, 0.0, target.z).normalized()
	rig.set_home_view(-outward * HOME_OFFSET_M, outward)
	rig.set("_distance", START_DISTANCE_M)
	if not is_nan(pitch_deg):
		# The player orbiting down to a low angle: still the real rig, just a
		# flatter pitch so the horizon band fills the frame.
		rig.set("_pitch", deg_to_rad(pitch_deg))
		rig.call("_update_transform")
	await _wait(30)
	for _i: int in range(3):
		await RenderingServer.frame_post_draw
	var source: Camera3D = rig.get_camera()
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
	# Copy the rig camera's transform (the real gameplay view) and stop physics
	# interpolation from blending it with the origin.
	camera.global_transform = source.global_transform
	camera.reset_physics_interpolation()
	camera.current = true
	for _i: int in range(4):
		await RenderingServer.frame_post_draw
	print("ISLANDDIAG target=%s in_frustum=%s fov=%s" % [target, camera.is_position_in_frustum(target), camera.fov])
	var rid: RID = sub.get_viewport_rid()
	var calls: int = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var prims: int = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	print("ISLANDPERF %s draw_calls=%d primitives=%d" % [file_name, calls, prims])
	var image: Image = sub.get_texture().get_image()
	image.save_png("user://" + file_name)
	print("SCREENSHOT saved=%s size=%s" % [ProjectSettings.globalize_path("user://" + file_name), image.get_size()])
	sub.queue_free()


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
