extends Node
## Reusable off-screen sandbox capture (Bontago-fca.68). Starts the sandbox the
## way the menu does (Main.start_sandbox_from_menu), renders it into the
## AgentProbe SubViewport at --render-size (the OS window stays tiny; never
## resize it), saves ONE PNG, prints `SHOT_SAVED <path>` and quits 0. Any
## failure prints `SHOT_FAILED <reason>` and quits 1.
##
##   godot --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy \
##     --path <checkout> res://tools/sandbox_shot.tscn -- --agent-probe \
##     --render-size=1920x1080 --out=<abs png> [--frames=N] [--sky=<theme id>] \
##     [--cam=yaw,pitch,distance[,tx,ty,tz]]
##
## --out     absolute (or user://) PNG path (required).
## --frames  physics frames to settle after the sandbox starts (default 90).
## --sky     Skybox theme id passed to Skybox.set_theme_by_id (e.g. "cycle").
## --cam     camera override re-applied every frame: yaw and pitch in degrees,
##           orbit distance in metres, optional target x,y,z (default: the
##           ghost-free home target the sandbox chose).

const OUT_ARG: String = "--out="
const FRAMES_ARG: String = "--frames="
const SKY_ARG: String = "--sky="
const CAM_ARG: String = "--cam="
const DEFAULT_SETTLE_FRAMES: int = 90
const FALLBACK_RENDER_SIZE: Vector2i = Vector2i(1920, 1080)
const BOOT_FRAMES: int = 3
const STARTUP_WAIT_S: float = 1.5
const CAM_MIN_PARTS: int = 3
const CAM_TARGET_PARTS: int = 6
const FAIL_EXIT_CODE: int = 1

var _main: Node
var _vp: SubViewport
var _cam: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = _arg(args, OUT_ARG)
	if out.is_empty():
		_fail("missing --out=<png>")
		return
	var frames: int = DEFAULT_SETTLE_FRAMES
	var frames_text: String = _arg(args, FRAMES_ARG)
	if not frames_text.is_empty():
		if not frames_text.is_valid_int():
			_fail("bad --frames")
			return
		frames = int(frames_text)
	var cam_text: String = _arg(args, CAM_ARG)
	if not cam_text.is_empty():
		_cam = _parse_cam(cam_text)
		if _cam.is_empty():
			_fail("bad --cam, want yaw,pitch,distance[,tx,ty,tz]")
			return
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())

	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_vp = AgentProbe.make_render_viewport(self, FALLBACK_RENDER_SIZE)
	_vp.add_child(_main)
	for _i: int in range(BOOT_FRAMES):
		await get_tree().process_frame
	await get_tree().create_timer(STARTUP_WAIT_S).timeout
	_main.call("start_sandbox_from_menu")
	await get_tree().create_timer(STARTUP_WAIT_S).timeout

	var sky: String = _arg(args, SKY_ARG)
	if not sky.is_empty():
		var skybox: Skybox = _main.get("_skybox") as Skybox
		if skybox == null or not skybox.set_theme_by_id(sky):
			_fail("unknown --sky '%s'" % sky)
			return
	for _i: int in range(frames):
		_apply_cam()
		await get_tree().physics_frame
	_apply_cam()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _vp.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("empty viewport image")
		return
	if ContactSheet.save_capture(image, out) != OK:
		_fail("could not save %s" % out)
		return
	print("SHOT_SAVED ", out, " ", image.get_size())
	get_tree().quit()


func _apply_cam() -> void:
	if _cam.is_empty():
		return
	var rig: CameraRig = _main.get("_camera_rig") as CameraRig
	if rig == null:
		return
	rig._yaw = deg_to_rad(_cam[0])
	rig._pitch = deg_to_rad(_cam[1])
	rig._distance = _cam[2]
	if _cam.size() >= CAM_TARGET_PARTS:
		rig._target = Vector3(_cam[3], _cam[4], _cam[5])


func _parse_cam(text: String) -> PackedFloat32Array:
	var parts: PackedStringArray = text.split(",")
	var out: PackedFloat32Array = PackedFloat32Array()
	if parts.size() != CAM_MIN_PARTS and parts.size() != CAM_TARGET_PARTS:
		return out
	for p: String in parts:
		if not p.is_valid_float():
			return PackedFloat32Array()
		out.append(float(p))
	return out


func _arg(args: PackedStringArray, prefix: String) -> String:
	for a: String in args:
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


func _fail(message: String) -> void:
	printerr("SHOT_FAILED ", message)
	get_tree().quit(FAIL_EXIT_CODE)
