extends Node
## Windowed smoke-shot for M7 P3 (Bontago-xtq.28): sunset SkyThemeDef applied
## to the fallback ProceduralSkyMaterial, plus Skybox's cloud-deck FogVolume,
## on the High graphics preset (both the native Environment.volumetric_fog_
## enabled flag and the FogVolume's own visibility gate must be true there).
## Boots the real Main.tscn/sandbox (same pattern as
## tools/screenshot_xtq8_sky_reflection.gd) rather than a standalone rig, so
## the shot exercises the actual Skybox/Settings wiring this package adds,
## not a hand-built substitute.
##
## Run windowed (a real render is required), off-screen per the current
## windowed-run rule:
##   godot --path . --scene res://tools/screenshot_xtq28_sunset_fog.tscn \
##       --position 10000,10000
##
## Fix round 2: an off-screen window is clamped by Windows to a tiny size
## (observed 489x248 at --position 10000,10000), so the previous candidate's
## plain get_viewport().get_texture() capture never showed a usable frame
## regardless of what the scene actually rendered. _shoot()/_render_large_
## shot() below now capture through a fixed CAPTURE_SIZE SubViewport instead
## (the same idiom tools/screenshot_feel8a_footprint.gd's own --seam-check path
## already established), independent of the real window's clamped size.
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game).

const OUTPUT_DIR: String = "user://"
const OUTPUT_NAME: String = "m7p3_sunset_fog.png"
const SETTLE_FRAMES: int = 90
## Bontago-xtq.28 fix round 2: an off-screen (--position 10000,10000) window is
## clamped by Windows to a tiny size (observed 489x248), so the main viewport's
## own get_texture() capture never showed a usable frame. Render through a
## fixed-size SubViewport instead, the same _render_large_shot() idiom
## tools/screenshot_feel8a_footprint.gd's own --seam-check path already
## established: a fresh Camera3D matching the real rig camera's transform/fov,
## sharing the live World3D (not the whole Main scene reparented under it).
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)

## Bontago-xtq.28 fix round: the rejected candidate hardcoded a near-level
## CAMERA_DISTANCE/CAMERA_PITCH_DEG here (copied from a different probe,
## tools/screenshot_xtq8_sky_reflection.gd, whose goal -- a reflected horizon
## band on the disk surface -- is unrelated to this shot), which put the
## camera almost at disk height so the field read as a thin ellipse with the
## disk barely visible edge-on. Distance is no longer set here at all --
## `_point_camera()` below leaves it at whatever game/CameraRig.gd's own
## `_ready()` free-camera branch already computed (`tuning.follow_block ==
## false`, set right below): distance == field_radius * 1.4 clamped to the
## tuning's zoom range.
##
## DECISION (this file, Bontago-xtq.28 fix round): pitch is NOT reused from
## CameraRig's own defaults (tuning.snap_pitch_deg == -35.0, the same value
## both `_ready()`'s free-camera branch and the player's camera_snap_home/
## camera_snap_goal `_snap_to()` use). Whether the horizon sits in frame at
## all depends only on pitch vs. the camera's vertical half-FOV (75 deg fov,
## half == 37.5 deg) -- not on distance -- and top-of-frame ray angle ==
## pitch - half_fov. At snap_pitch_deg (-35 deg downward), that is
## 37.5 - 35 == 2.5 deg of sky above the horizon: technically "in frame" but
## nowhere near enough to read the sunset gradient (orange horizon band, deep
## blue zenith) this shot exists to show, and confirmed by this fix round's
## first capture (attempt 1/2: near-uniform grey/brown, disk reduced to a
## small ellipse near the frame's top edge). CAMERA_PITCH_DEG below is this
## tool's own, shallower choice (top-of-frame ray == 37.5 - 18 == 19.5 deg
## above horizon, a good third of the frame) -- a "similar elevated 3/4 view"
## per the brief, not a literal reuse of the gameplay snap pitch, which is
## tuned for a tight over-the-shoulder stacking view, not an atmosphere shot.
const CAMERA_PITCH_DEG: float = -18.0
const CAMERA_YAW_DEG: float = 35.0


func _ready() -> void:
	Settings.set_graphics_preset(&"high")

	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig
	var skybox: Skybox = main.get_node("Skybox") as Skybox

	var free_tuning: CameraTuning = (rig.tuning as CameraTuning).duplicate(true) as CameraTuning
	free_tuning.follow_block = false
	rig.tuning = free_tuning

	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(int(1.5 * Engine.physics_ticks_per_second))

	var fog_volume: FogVolume = skybox.get_fog_volume()
	print("SCREENSHOT xtq28 fallback_active=%s fog_volume_visible=%s volumetric_fog_enabled=%s" % [
		skybox.fallback_active,
		fog_volume.visible if fog_volume != null else null,
		main.get_world_3d().environment.volumetric_fog_enabled,
	])

	_point_camera(rig)
	await _wait(SETTLE_FRAMES)
	await _shoot(OUTPUT_NAME)

	get_tree().quit()


func _point_camera(rig: CameraRig) -> void:
	# _distance is left untouched: it's already CameraRig._ready()'s own
	# free-camera default (field_radius * 1.4, clamped to the tuning's zoom
	# range). _pitch is overridden to this file's own shallower
	# CAMERA_PITCH_DEG (see its doc above) so the horizon and sunset gradient
	# are actually in frame. _target is re-centred on the disk
	# (PlayerController.set_home_position() -> rig.set_home_view() may have
	# already retargeted it at a player's home flag during sandbox setup,
	# above).
	rig._target = Vector3(0.0, 1.0, 0.0)
	rig._yaw = deg_to_rad(CAMERA_YAW_DEG)
	rig._pitch = deg_to_rad(CAMERA_PITCH_DEG)
	rig._update_transform()
	var cam3d: Camera3D = rig.get_node("Camera3D") as Camera3D
	rig.reset_physics_interpolation()
	cam3d.reset_physics_interpolation()


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = await _render_large_shot()
	var path: String = OUTPUT_DIR + file_name
	image.save_png(path)
	print("SCREENSHOT xtq28 saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])


## Bontago-xtq.28 fix round 2: same SubViewport idiom as tools/screenshot_
## feel8a_footprint.gd's own _render_large_shot() -- a fresh Camera3D matching
## the real rig camera's transform/fov/near/far/environment, sharing the live
## World3D via `sub.world_3d` (own_world_3d stays false, the SubViewport
## default), so the capture is CAPTURE_SIZE regardless of the actual (OS-
## clamped) window size.
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
