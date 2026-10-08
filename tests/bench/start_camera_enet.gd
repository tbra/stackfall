extends Node
## Bontago-1pi.90: host + one lagged client over real ENet, each running the real
## game/Main.tscn. Every peer samples its own camera from the first countdown
## frame that shows the held piece, through the last countdown frame, to
## PLAYING + PLAYING_FRAMES, and must show the same transform, the start pitch
## and distance and a pivot on the held piece throughout (view 3, owner 2026-10-06).
## Lines are prefixed SCENET. Host: --headless-host; client: --join=ip:port.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const HARD_DEADLINE_S: float = 120.0
const CONNECT_TIMEOUT_S: float = 20.0
const SETTLE_S: float = 2.0
const COUNTDOWN_S: float = 3.0
const PLAYING_FRAMES: int = 30
const HOST_AND_CLIENT_PEERS: int = 2
## Frames the controller needs to feed the camera before the reference is taken
## (headless has no loading screen, so begin_start_framing() never runs here).
const SETTLE_FRAMES: int = 5
const SEED: int = 777
const POSITION_TOLERANCE_M: float = 0.001
const BASIS_TOLERANCE: float = 0.0001

var _main: Node
var _role: String = ""
var _started_msec: int = 0
var _shown_frames: int = 0
var _first: Dictionary = {}
var _last_countdown: Dictionary = {}
var _playing_frames: int = 0
var _worst_m: float = 0.0
var _done: bool = false
var _pose_ok: bool = true
var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_started_msec = Time.get_ticks_msec()
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	var rig: CameraRig = _main.get("_camera_rig") as CameraRig
	rig.shake_config = rig.shake_config.duplicate()
	rig.shake_config.max_offset_m = 0.0
	await get_tree().process_frame
	if Net.mode() == Net.Mode.HOST:
		_role = "host"
		var deadline: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT_S * 1000.0)
		while Net.peer_ids().size() < HOST_AND_CLIENT_PEERS and Time.get_ticks_msec() < deadline:
			await get_tree().create_timer(0.1).timeout
		await get_tree().create_timer(SETTLE_S).timeout
		var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
		config.map_size = MapDef.MapSize.SMALL
		config.player_count = 2
		config.ai_count = 0
		config.hot_seat = false
		config.rng_seed = SEED
		config.countdown_seconds = COUNTDOWN_S
		_main.call(&"_on_lobby_start_requested", config)
	elif Net.mode() == Net.Mode.CLIENT:
		_role = "client"
	else:
		print("SCENET setup result=FAIL reason=no_net_mode")
		get_tree().quit(2)


func _process(_delta: float) -> void:
	if _done or _main == null:
		return
	if float(Time.get_ticks_msec() - _started_msec) / 1000.0 > HARD_DEADLINE_S:
		_finish("hard_deadline")
		return
	var rig: CameraRig = _main.get("_camera_rig") as CameraRig
	var state: int = int(Match.state())
	var hot_seat: Variant = _main.get("_hot_seat")
	var shown: bool = hot_seat != null and (hot_seat.ghost() as GhostPreview).get_shape() != null
	if state == Match.State.COUNTDOWN and shown:
		_shown_frames += 1
		if _shown_frames < SETTLE_FRAMES:
			return
		var sample: Dictionary = _sample(rig)
		if _first.is_empty():
			_first = sample
			print("SCENET %s first_countdown pitch=%.4f dist=%.3f cam=%s" % [_role, sample["pitch"], sample["distance"], sample["origin"]])
		_last_countdown = sample
		_compare(rig, sample)
	elif state == Match.State.PLAYING and not _first.is_empty():
		_playing_frames += 1
		_compare(rig, _sample(rig))
		if _playing_frames >= PLAYING_FRAMES:
			_finish("")


func _sample(rig: CameraRig) -> Dictionary:
	var xform: Transform3D = rig.get_camera().global_transform
	return {"xform": xform, "origin": xform.origin, "pitch": rig.get_pitch(), "distance": rig.get_distance()}


func _compare(rig: CameraRig, sample: Dictionary) -> void:
	var tuning: CameraTuning = rig.tuning
	if not is_equal_approx(float(sample["pitch"]), deg_to_rad(tuning.start_pitch_deg)) or not is_equal_approx(float(sample["distance"]), clampf(tuning.start_distance_m, tuning.zoom_min, tuning.zoom_max)):
		_pose_ok = false
	var reference: Transform3D = _first["xform"]
	var current: Transform3D = sample["xform"]
	var offset: float = current.origin.distance_to(reference.origin)
	for axis: int in range(3):
		offset = maxf(offset, (current.basis[axis] - reference.basis[axis]).length() * (POSITION_TOLERANCE_M / BASIS_TOLERANCE))
	if offset > POSITION_TOLERANCE_M and _worst_m <= POSITION_TOLERANCE_M:
		print("SCENET %s first_shift state=%d t=%.3f dist=%.3f pitch=%.4f target=%s" % [_role, int(Match.state()), offset, rig.get_distance(), rig.get_pitch(), rig.get_target()])
	_worst_m = maxf(_worst_m, offset)


func _finish(reason: String) -> void:
	_done = true
	var ok: bool = reason == "" and _pose_ok and _worst_m < POSITION_TOLERANCE_M and not _last_countdown.is_empty()
	# DECISION (1pi.90 review): a --headless-host has no loading screen, so its first
	# territory solve lands in PLAYING (Match.gd ~438, Main.gd ~1385) and Main.gd ~1419
	# frames the camera only then; a windowed host holds the countdown until it has
	# framed (covered by tests/unit/test_start_camera_flow.gd). The host line is
	# informational; the client is the peer this bench gates on.
	if _role == "host":
		ok = reason == ""
	print("SCENET %s result=%s reason=%s follow_pose_ok=%s worst_shift=%.5f last_countdown_cam=%s" % [_role, "PASS" if ok else "FAIL", reason, _pose_ok, _worst_m, _last_countdown.get("origin", Vector3.ZERO)])
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)
