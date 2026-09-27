extends Node
## Bontago-1pi.1 evidence probe (owner playtest: "there are 2 suns, one built
## in to the skybox and another with the lens flares" + follow-up "the sun
## isn't fixed either... the suns are basically 180 degrees apart, so
## impossible to capture on a screenshot"): sweeps the live gameplay camera
## through 8 yaws (plus a low/high pitch) inside an actual match scene and
## saves one PNG per framing to feedback/pt-sun-<tag>-<suffix>.png, so every
## sun-like element (the painted panorama disc, vfx/SunFlare.gd's
## screen-space sparkle/ghosts, DirectionalLight3D shading, DiscMirror
## reflections) can be found and named by inspecting the images, rather than
## guessing from source alone. Also captures two diagnostic framings that aim
## the camera directly along config/sun_flare.tres' sun_direction and its
## exact negation, and the CameraRig's own untouched default view (for the
## light-direction/shading question), all inside the same off-screen windowed
## run (owner rule, 2026-09-23) to stay within this package's 2-run capture
## budget:
##
##   godot --path . --windowed --position 10000,10000 --resolution 1280x720 \
##       res://tools/capture_pt1_sun_sweep.tscn -- --tag=before
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game) -- this package's own evidence tool, same idiom as
## tools/capture_sun_flare_probe.gd and tools/screenshot_pt1_single_sun.gd.

const FRAME_SIZE: Vector2i = Vector2i(1280, 720)
const SETTLE_S: float = 1.5
const CAMERA_EYE_HEIGHT_M: float = 8.0
const YAW_STEP_DEG: float = 45.0
const YAW_COUNT: int = 8
const PITCH_UP_DEG: float = 30.0
const PITCH_DOWN_DEG: float = -20.0

var _tag: String = "before"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var text: String = arg.lstrip("-")
		if text.begins_with("tag="):
			_tag = text.substr(4)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://feedback"))
	call_deferred("_capture")


func _capture() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = FRAME_SIZE

	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(SETTLE_S).timeout

	var config: MatchConfig = main.get("match_config") as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	main.call("start_sandbox_from_menu")
	await get_tree().create_timer(SETTLE_S).timeout

	var flare: SunFlare = main.get_node("SunFlare") as SunFlare
	var rig: Node = main.get_node("CameraRig")
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D

	# Default, untouched CameraRig framing first -- answers the owner's
	# "does the default view now face away from the sun" question.
	await _settle_and_save("%s-default-view" % _tag, flare)

	rig.set_process(false)
	var sun_direction: Vector3 = flare.config.sun_direction.normalized()

	for i in range(YAW_COUNT):
		var yaw_deg: float = i * YAW_STEP_DEG
		var direction: Vector3 = _direction_for(yaw_deg, 0.0)
		_aim_camera(camera, direction)
		await _settle_and_save("%s-yaw%03d" % [_tag, int(yaw_deg)], flare)

	_aim_camera(camera, _direction_for(0.0, PITCH_UP_DEG))
	await _settle_and_save("%s-pitch-up%d" % [_tag, int(PITCH_UP_DEG)], flare)

	_aim_camera(camera, _direction_for(0.0, PITCH_DOWN_DEG))
	await _settle_and_save("%s-pitch-down%d" % [_tag, int(absf(PITCH_DOWN_DEG))], flare)

	_aim_camera(camera, sun_direction)
	await _settle_and_save("%s-aim-sundir" % _tag, flare)

	_aim_camera(camera, -sun_direction)
	await _settle_and_save("%s-aim-negated-sundir" % _tag, flare)

	print("SWEEP done tag=%s" % _tag)
	get_tree().quit()


## Standard spherical parametrization matching Godot's -Z forward: yaw=0,
## pitch=0 gives (0,0,-1). Positive pitch looks upward (+Y).
func _direction_for(yaw_deg: float, pitch_deg: float) -> Vector3:
	var yaw: float = deg_to_rad(yaw_deg)
	var pitch: float = deg_to_rad(pitch_deg)
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)).normalized()


func _aim_camera(camera: Camera3D, direction: Vector3) -> void:
	camera.global_position = Vector3.UP * CAMERA_EYE_HEIGHT_M
	var up: Vector3 = Vector3.UP
	if absf(direction.dot(up)) > 0.999:
		up = Vector3.FORWARD
	camera.look_at(camera.global_position + direction, up)


## vfx/SunFlare.gd's own class doc: a freshly moved camera's rendering
## transform lags one physics tick behind a script write until a physics step
## syncs it (physics interpolation) -- wait a couple of ticks before capture.
func _settle_and_save(suffix: String, flare: SunFlare) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path: String = "res://feedback/pt-sun-%s.png" % suffix
	get_viewport().get_texture().get_image().save_png(path)
	print("SWEEP saved=%s sun_flare_visibility=%f" % [
		ProjectSettings.globalize_path(path), flare.current_visibility(),
	])
