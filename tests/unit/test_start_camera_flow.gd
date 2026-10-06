extends GutTest
## Bontago-1pi.90 (owner feedback 2026-10-06, "START CAMERA STILL NOT FIXED";
## feedback/051026/3.png countdown vs 4.png play): the camera must show the final
## in-play view -- behind and above the held piece at the local home -- from the
## moment the ready gate opens, through the countdown and into play, with no
## shift at PLAYING. Unlike tests/unit/test_start_framing.gd this drives the real
## start sequence: the real Main scene hosts, the lobby's start path
## (Main._on_lobby_start_pressed) starts a vs-bots match, Match runs its own
## countdown on real frames, and Main's own loading hand-off
## (_finish_loading_when_ready -> CameraRig.begin_start_framing -> fade-out ->
## countdown release) runs untouched. The camera pose is traced every frame from
## the gate opening until PLAYING_FRAMES frames into play.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const MAP_PATH: String = "res://config/maps/round_small.tres"
const LOCAL_SLOT: int = 0
## A short countdown keeps the test fast; its length does not change the code path.
const COUNTDOWN_S: float = 1.0
const PLAYING_FRAMES: int = 30
const FRAME_LIMIT: int = 2400
const POSITION_TOLERANCE_M: float = 0.001
const BASIS_TOLERANCE: float = 0.0001
## Camera shake is a reaction to block impacts (bots may drop early); it is
## disabled for this trace so only the framing itself is compared.
const NO_SHAKE_THRESHOLD: float = 1.0e9

var _main: Variant = null
var _trace: Array[Dictionary] = []


func before_each() -> void:
	Match.abort_match()
	SnapshotSync.end_match()
	_trace.clear()


func after_each() -> void:
	if Events.match_state_changed.is_connected(_hold_countdown_like_a_windowed_build):
		Events.match_state_changed.disconnect(_hold_countdown_like_a_windowed_build)
	Net.leave()
	Match.abort_match()
	Match.set_countdown_held(false)
	SnapshotSync.end_match()
	await get_tree().process_frame
	await get_tree().process_frame


## Main only holds the countdown behind the loading screen in a windowed run
## (DisplayServer is headless here); the hold is applied at the same moment
## Main's own LOBBY -> LOADING branch would, and Main's own hand-off releases it.
func _hold_countdown_like_a_windowed_build(from_state: int, to_state: int) -> void:
	if from_state == Match.State.LOBBY and to_state == Match.State.LOADING:
		Match.set_countdown_held(true)


func _start_vs_bots_match_from_the_lobby() -> void:
	var map: MapDef = (load(MAP_PATH) as MapDef).duplicate(true)
	_main = MAIN_SCENE.instantiate()
	(_main.get_node("Field") as Field).map_def = map
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.rng_seed = 777
	config.player_count = 2
	config.ai_count = 1
	config.countdown_seconds = COUNTDOWN_S
	_main.match_config = config
	add_child_autofree(_main)
	var rig: CameraRig = _main._camera_rig
	rig.shake_config = rig.shake_config.duplicate()
	rig.shake_config.impact_speed_threshold = NO_SHAKE_THRESHOLD
	Events.match_state_changed.connect(_hold_countdown_like_a_windowed_build)
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	await get_tree().process_frame
	# The lobby's Start button (ui/Lobby.gd start_requested) lands here.
	_main._on_lobby_start_pressed(config)


func _sample(frame: int) -> Dictionary:
	var rig: CameraRig = _main._camera_rig
	var sample: Dictionary = {
		"frame": frame,
		"state": Match.state(),
		"held": Match._lifecycle.is_countdown_held(),
		"fading": bool(_main._loading_screen._is_fading),
		"camera": rig.get_camera().global_transform,
		"target": rig.get_target(),
		"pitch": rig.get_pitch(),
		"distance": rig.get_distance(),
		"yaw": rig.get_yaw(),
		"has_piece": false,
		"anchor": Vector3.ZERO,
	}
	if _main._hot_seat != null:
		var ghost: GhostPreview = _main._hot_seat.ghost()
		sample["has_piece"] = ghost.get_shape() != null and ghost.is_visible_in_tree()
		sample["anchor"] = _main._hot_seat.controller()._camera_follow_anchor()
	print("CAMTRACE f=%d state=%d held=%s fading=%s cam=%s target=%s pitch=%.4f dist=%.3f piece=%s anchor=%s" % [
		frame, sample["state"], sample["held"], sample["fading"], (sample["camera"] as Transform3D).origin,
		sample["target"], sample["pitch"], sample["distance"], sample["has_piece"], sample["anchor"],
	])
	return sample


## Runs real frames from the lobby start until PLAYING_FRAMES frames of play,
## recording the camera every frame.
func _trace_until_playing() -> void:
	var playing_frames: int = 0
	for frame: int in range(FRAME_LIMIT):
		await get_tree().process_frame
		var sample: Dictionary = _sample(frame)
		_trace.append(sample)
		if int(sample["state"]) == Match.State.PLAYING:
			playing_frames += 1
			if playing_frames > PLAYING_FRAMES:
				return


func _first_index(predicate: Callable) -> int:
	for index: int in range(_trace.size()):
		if predicate.call(_trace[index]):
			return index
	return -1


func _assert_same_pose(expected: Transform3D, actual: Transform3D, label: String) -> void:
	assert_lt(actual.origin.distance_to(expected.origin), POSITION_TOLERANCE_M, "%s: camera position %s vs gate-open %s" % [label, actual.origin, expected.origin])
	for axis: int in range(3):
		assert_lt((actual.basis[axis] - expected.basis[axis]).length(), BASIS_TOLERANCE, "%s: camera orientation axis %d" % [label, axis])


func test_gate_open_countdown_and_play_share_one_camera_pose() -> void:
	await _start_vs_bots_match_from_the_lobby()
	await _trace_until_playing()
	var gate_open: int = _first_index(func(s: Dictionary) -> bool: return bool(s["fading"]))
	var countdown_end: int = _first_index(func(s: Dictionary) -> bool: return int(s["state"]) == Match.State.PLAYING) - 1
	var play_30: int = _trace.size() - 1
	assert_gt(gate_open, -1, "the loading screen's ready gate opened (fade-out started)")
	assert_gt(countdown_end, gate_open, "the countdown ran after the gate opened")
	if gate_open < 0 or countdown_end <= gate_open:
		return
	assert_eq(int(_trace[countdown_end]["state"]), Match.State.COUNTDOWN)
	assert_eq(int(_trace[play_30]["state"]), Match.State.PLAYING)
	var reference: Transform3D = _trace[gate_open]["camera"]
	_assert_same_pose(reference, _trace[countdown_end]["camera"], "countdown end")
	_assert_same_pose(reference, _trace[play_30]["camera"], "PLAYING + %d frames" % PLAYING_FRAMES)
	# No intermediate countdown-only view and no ease anywhere in between.
	var worst_m: float = 0.0
	var worst_frame: int = -1
	for index: int in range(gate_open, _trace.size()):
		var offset: float = (_trace[index]["camera"] as Transform3D).origin.distance_to(reference.origin)
		if offset > worst_m:
			worst_m = offset
			worst_frame = int(_trace[index]["frame"])
	assert_lt(worst_m, POSITION_TOLERANCE_M, "largest camera shift after the gate opened: %.4f m at frame %d" % [worst_m, worst_frame])


func test_the_start_view_is_the_follow_view_of_the_held_piece() -> void:
	await _start_vs_bots_match_from_the_lobby()
	await _trace_until_playing()
	var gate_open: int = _first_index(func(s: Dictionary) -> bool: return bool(s["fading"]))
	assert_gt(gate_open, -1, "the loading screen's ready gate opened (fade-out started)")
	if gate_open < 0:
		return
	var tuning: CameraTuning = (_main._camera_rig as CameraRig).tuning
	for index: int in [gate_open, _trace.size() - 1]:
		var sample: Dictionary = _trace[index]
		assert_true(bool(sample["has_piece"]), "frame %d: the held piece is shown" % int(sample["frame"]))
		assert_lt((sample["target"] as Vector3).distance_to(sample["anchor"] as Vector3), POSITION_TOLERANCE_M, "frame %d: the camera pivots on the held piece, not the bare beacon" % int(sample["frame"]))
		assert_almost_eq(float(sample["pitch"]), deg_to_rad(tuning.start_pitch_deg), 0.0001, "frame %d: start pitch" % int(sample["frame"]))
		assert_almost_eq(float(sample["distance"]), clampf(tuning.start_distance_m, tuning.zoom_min, tuning.zoom_max), 0.0001, "frame %d: start distance" % int(sample["frame"]))
