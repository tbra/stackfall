extends Node
## Off-screen capture of a running local bot match as one contact sheet (Bontago-1t5.29, E7 of
## docs/BOT_AI_REDESIGN.md 2.5). Hosts a loopback bot match the way `--headless-host --bots=<n>`
## does (Main._start_headless_bot_match_with_args, so every flag of game/MainHeadlessBotsFlow.gd
## works), renders Main into the AgentProbe SubViewport and saves one frame per requested match
## time via ContactSheet.save_capture, then quits. Passive seats = human seats nobody drives
## (--players larger than --bots; their pieces auto-drop on the block timer).
##
##   godot --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy \
##     --path <checkout> res://tools/bot_match_sheet.tscn -- --agent-probe --render-size=1280x720 \
##     --out=<abs dir> [--bots=4] [--players=<n>] [--difficulty=easy|normal|hard] \
##     [--brain=legacy|v2] [--seed=<int>] [--times=60,120,180,300] [--cam=yaw,pitch,dist[,tx,ty,tz]]
##
## --out       absolute directory for the frames and <run>_sheet.png (required).
## --bots      bot seats (default 4); --players total seats (default = bots, so no passive seats).
## --times     match-clock seconds (physics frames / 60 after the match starts PLAYING).
## --cam       camera override re-applied every frame (as tools/sandbox_shot.gd); default is a
##             whole-disc overview. Besides the per-frame PNGs and the running
##             bot_match_sheet_sheet.png, one big sheet bot_match_p1.png (<=2600x3000) is written.
## Prints BOT_SHEET_SAVED <dir> and quits 0; BOT_SHEET_FAILED <reason> and quits 1 on error.
## Match time runs in real time, so the default 300 s capture takes about five minutes.

const OUT_ARG: String = "--out="
const BOTS_ARG: String = "--bots="
const PLAYERS_ARG: String = "--players="
const DIFFICULTY_ARG: String = "--difficulty="
const BRAIN_ARG: String = "--brain="
const SEED_ARG: String = "--seed="
const TIMES_ARG: String = "--times="
const CAM_ARG: String = "--cam="
const DEFAULT_BOTS: int = 4
const DEFAULT_TIMES: PackedFloat32Array = [60.0, 120.0, 180.0, 300.0]
const FALLBACK_RENDER_SIZE: Vector2i = Vector2i(1280, 720)
const BOOT_FRAMES: int = 3
const STARTUP_WAIT_S: float = 1.0
const START_TIMEOUT_S: float = 60.0
const CAM_MIN_PARTS: int = 3
const CAM_TARGET_PARTS: int = 6
const FAIL_EXIT_CODE: int = 1
const BIG_SHEET_NAME: String = "bot_match_p%d.png"
## Whole-disc overview (yaw, pitch deg, distance m, target xyz): homes sit on the rim, so the
## default follow/home view hides the towers. Overridden by --cam.
const DEFAULT_CAM: String = "0,-50,80,0,0,0"
const FRAME_NAME: String = "t%03d.png"

var _main: Node
var _vp: SubViewport
var _cam: PackedFloat32Array = PackedFloat32Array()
var _images: Array[Image] = []


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = _arg(args, OUT_ARG)
	if out.is_empty():
		_fail("missing --out=<dir>")
		return
	var bots: int = int(_arg(args, BOTS_ARG)) if _arg(args, BOTS_ARG).is_valid_int() else DEFAULT_BOTS
	var players: int = int(_arg(args, PLAYERS_ARG)) if _arg(args, PLAYERS_ARG).is_valid_int() else bots
	var times: PackedFloat32Array = _parse_times(_arg(args, TIMES_ARG))
	if times.is_empty():
		_fail("bad --times, want comma-separated seconds")
		return
	var cam_text: String = _arg(args, CAM_ARG)
	if cam_text.is_empty():
		cam_text = DEFAULT_CAM
	if not cam_text.is_empty():
		_cam = _parse_cam(cam_text)
		if _cam.is_empty():
			_fail("bad --cam, want yaw,pitch,distance[,tx,ty,tz]")
			return
	DirAccess.make_dir_recursive_absolute(out)

	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_vp = AgentProbe.make_render_viewport(self, FALLBACK_RENDER_SIZE)
	_vp.add_child(_main)
	for _i: int in range(BOOT_FRAMES):
		await get_tree().process_frame
	await get_tree().create_timer(STARTUP_WAIT_S).timeout

	# Same entry as --headless-host --bots=<n> (Main._ready): loopback host, then the flow.
	var net: Node = get_node("/root/Net")
	if int(net.call("host_game", 0, "", false, false)) != OK:
		_fail("Net.host_game failed")
		return
	var flow_args: PackedStringArray = PackedStringArray(["--bots=%d" % bots, "--players=%d" % players])
	for pair: Array in [[DIFFICULTY_ARG, "--bot-difficulty="], [BRAIN_ARG, "--bot-brain="], [SEED_ARG, "--match-seed="]]:
		var value: String = _arg(args, pair[0] as String)
		if not value.is_empty():
			flow_args.append((pair[1] as String) + value)
	_main.call("_start_headless_bot_match_with_args", flow_args)

	var waited_s: float = 0.0
	var match_node: Node = get_node("/root/Match")
	while int(match_node.call("state")) != MatchAutoload.State.PLAYING:
		await get_tree().physics_frame
		waited_s += 1.0 / float(Engine.physics_ticks_per_second)
		if waited_s > START_TIMEOUT_S:
			_fail("match never reached PLAYING")
			return
	var start_frame: int = Engine.get_physics_frames()
	var tick_hz: float = float(Engine.physics_ticks_per_second)
	for t: float in times:
		while float(Engine.get_physics_frames() - start_frame) / tick_hz < t:
			_apply_cam()
			if int(match_node.call("state")) != MatchAutoload.State.PLAYING:
				break
			await get_tree().physics_frame
		if not await _capture(out.path_join(FRAME_NAME % int(t))):
			return
		if int(match_node.call("state")) != MatchAutoload.State.PLAYING:
			print("BOT_SHEET_NOTE match ended at ", t, " s; later frames skipped")
			break
	var pages: Array[Image] = ContactSheet.build_pages(_images, ContactSheet.MAX_SHEET_PX_W)
	for i: int in pages.size():
		var sheet_path: String = out.path_join(BIG_SHEET_NAME % (i + 1))
		pages[i].save_png(sheet_path)
		print("BOT_SHEET_BIG ", sheet_path, " ", pages[i].get_size())
	print("BOT_SHEET_SAVED ", out)
	get_tree().quit()


func _capture(path: String) -> bool:
	_apply_cam()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _vp.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("empty viewport image")
		return false
	if ContactSheet.save_capture(image, path) != OK:
		_fail("could not save %s" % path)
		return false
	_images.append(image)
	return true


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


func _parse_times(text: String) -> PackedFloat32Array:
	if text.is_empty():
		return DEFAULT_TIMES
	var out: PackedFloat32Array = PackedFloat32Array()
	for p: String in text.split(",", false):
		if not p.is_valid_float():
			return PackedFloat32Array()
		out.append(float(p))
	return out


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


func _fail(reason: String) -> void:
	print("BOT_SHEET_FAILED ", reason)
	get_tree().quit(FAIL_EXIT_CODE)
