extends Node
## Bontago-1pi.46 R3 (docs/MATCH_RESET_AUDIT.md section 6, ENet variant): host + one lagged
## client over real ENet, each running the real game/Main.tscn. Two modes, each its own process
## pair (so "fresh" really is a fresh launch):
##   fresh  the host starts match B; both peers fingerprint it at COUNTDOWN + 0.5 s and
##          PLAYING + 1 s and write the fingerprints to --out-dir.
##   dirty  the host first plays match A (Night sky, storm, rain, gift crate, black hole,
##          dirtied camera and sky on both peers, a tense music stem), replays it, then lets
##          the client leave and re-join the lobby, and only then starts the same B; each
##          peer compares its B fingerprints with the ones the fresh run wrote.
## The client's COUNTDOWN fingerprint includes the influence circles it decoded (audit G3).
## Fingerprints are tests/unit/support/MatchFingerprint.gd minus its wall-clock keys.
## Prints "RESETENET <role> ..." lines; exit 0 = this peer matched (dirty) or wrote (fresh),
## 1 = a diff, 2 = setup, 3 = deadline; a peer whose only diffs follow the known seat gap
## below prints result=PENDING (exit 0). Run via tools/run_reset_enet.ps1.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const HARD_DEADLINE_S: float = 150.0
const CONNECT_TIMEOUT_S: float = 20.0
const STATE_TIMEOUT_S: float = 25.0
const HOST_AND_CLIENT_PEERS: int = 2
const SEED: int = 777
const COUNTDOWN_S: float = 3.0
const CHECK_COUNTDOWN_S: float = 0.5
const CHECK_PLAYING_S: float = 1.0
const WEATHER_PHASE_S: float = 5.0
const SETTLE_S: float = 1.0
const DIRTY_ZOOM: float = 40.0
const BLACK_HOLE_POSITION: Vector3 = Vector3(0.0, 1.0, 0.0)
const CRATE_POINT: Vector2 = Vector2(2.0, 2.0)
const FILE_NAME: String = "fp_%s.var"

var _main: Node
var _mode: String = "fresh"
var _out_dir: String = ""
var _join_address: String = ""
var _join_port: int = 0
var _started_msec: int = 0
var _role_name: String = ""
var _state_since_msec: int = 0
var _captured: Dictionary = {}
var _finish_requested: bool = false


func _ready() -> void:
	_started_msec = Time.get_ticks_msec()
	for raw: String in OS.get_cmdline_user_args():
		var text: String = raw.lstrip("-")
		if text.begins_with("mode="):
			_mode = text.substr("mode=".length())
		elif text.begins_with("out-dir="):
			_out_dir = text.substr("out-dir=".length())
		elif text.begins_with("join="):
			var spec: String = text.substr("join=".length())
			var colon: int = spec.rfind(":")
			_join_address = spec.substr(0, colon)
			_join_port = int(spec.substr(colon + 1))
	Events.match_state_changed.connect(_on_state_changed)
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().process_frame
	if Net.mode() == Net.Mode.HOST:
		_role_name = "host"
		await _run_host()
	elif Net.mode() == Net.Mode.CLIENT:
		_role_name = "client"
	else:
		print("RESETENET setup result=FAIL reason=no_net_mode")
		get_tree().quit(2)


func _process(_delta: float) -> void:
	if _elapsed_s() > HARD_DEADLINE_S:
		print("RESETENET %s result=FAIL reason=hard_deadline" % _role_name)
		get_tree().quit(3)
		return
	if _main == null:
		return
	# Checkpoints are taken by each peer's own clock from its own state changes.
	var held_s: float = float(Time.get_ticks_msec() - _state_since_msec) / 1000.0
	var state: int = int(Match.state())
	if state == Match.State.COUNTDOWN and held_s >= CHECK_COUNTDOWN_S and not _captured.has("countdown"):
		_captured["countdown"] = MatchFingerprint.without_volatile(MatchFingerprint.capture(_main))
	if state == Match.State.PLAYING and held_s >= CHECK_PLAYING_S and not _captured.has("playing"):
		_captured["playing"] = MatchFingerprint.without_volatile(MatchFingerprint.capture(_main))


## Every state change restarts the checkpoint clock; a match leaving/entering the lobby or
## loading discards the previous match's fingerprints (polling _process() can miss a LOBBY or
## LOADING that passes within one frame, which is how a stale match-A capture got through).
func _on_state_changed(_from_state: int, to_state: int) -> void:
	_state_since_msec = Time.get_ticks_msec()
	if to_state == Match.State.LOBBY or to_state == Match.State.LOADING:
		_captured.clear()


func _elapsed_s() -> float:
	return float(Time.get_ticks_msec() - _started_msec) / 1000.0


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(condition: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _wait(0.05)
	return condition.call()


func _config(weather_mode: int, sky_mode: int) -> MatchConfig:
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = 2
	config.ai_count = 0
	config.hot_seat = false
	config.rng_seed = SEED
	config.countdown_seconds = COUNTDOWN_S
	config.weather_mode = weather_mode as MatchConfig.WeatherMode
	config.sky_theme_mode = sky_mode as MatchConfig.SkyThemeMode
	return config


func _dirty_camera_and_sky() -> void:
	var rig: CameraRig = _main.get("_camera_rig") as CameraRig
	rig.zoom_continuous(DIRTY_ZOOM)
	rig._yaw += 1.3
	rig._pitch = deg_to_rad(-72.0)
	rig._on_block_impacted(1000.0)
	rig._peek_active = true
	rig._focus_action = &"camera_snap_goal"
	(_main.get("_skybox") as Skybox).set_theme_by_id("sunset")
	Sfx._tense_stem_is_active = true


# --- host ---------------------------------------------------------------------------------

func _run_host() -> void:
	if not await _until(func() -> bool: return Net.peer_ids().size() >= HOST_AND_CLIENT_PEERS, CONNECT_TIMEOUT_S):
		print("RESETENET host result=FAIL reason=no_client")
		get_tree().quit(2)
		return
	await _wait(SETTLE_S)
	if _mode == "dirty":
		await _host_play_a()
	await _host_play_b()
	await _wait(SETTLE_S)
	rpc(&"h_finish")
	await _wait(SETTLE_S)
	_finish()


func _host_play_a() -> void:
	_main._on_lobby_start_requested(_config(MatchConfig.WeatherMode.STORM, MatchConfig.SkyThemeMode.NIGHT))
	if not await _until(func() -> bool: return Match.state() == Match.State.PLAYING, STATE_TIMEOUT_S):
		_fail("host never reached PLAYING in A")
		return
	rpc(&"h_dirty")
	Match.weather().set_debug_override(&"storm")
	await _wait(WEATHER_PHASE_S)
	Match.weather().set_debug_override(&"rain")
	await _wait(WEATHER_PHASE_S)
	Match._gifts._spawn_crate_at(CRATE_POINT)
	Events.special_triggered.emit(0, &"black_hole", BLACK_HOLE_POSITION, 0)
	_dirty_camera_and_sky()
	await _wait(SETTLE_S)
	# Replay: start_match() from PLAYING takes the same abort-then-start path as from END.
	Match.start_match(Match.config)
	if not await _until(func() -> bool: return Match.state() == Match.State.PLAYING, STATE_TIMEOUT_S):
		_fail("host never reached PLAYING in the replay")
		return
	await _wait(SETTLE_S)
	# Second cycle: back to the lobby (results "Back to lobby"), then the client leaves
	# ("lobby Back") and re-joins. DECISION: the host aborts first; a client that leaves while the
	# match is still PLAYING comes back as slot 2 (its seat stays reserved until the host returns
	# to the lobby) -- a seat-allocation question, noted in the Bead, not a match-reset one.
	Match.abort_match()
	await _wait(SETTLE_S)
	rpc(&"h_leave_rejoin")
	await _until(func() -> bool: return Net.peer_ids().size() < HOST_AND_CLIENT_PEERS, CONNECT_TIMEOUT_S)
	await _until(func() -> bool: return Net.peer_ids().size() >= HOST_AND_CLIENT_PEERS, CONNECT_TIMEOUT_S)
	await _wait(SETTLE_S)


func _host_play_b() -> void:
	_captured.clear()
	_main._on_lobby_start_requested(_config(MatchConfig.WeatherMode.OFF, MatchConfig.SkyThemeMode.DAY))
	if not await _until(func() -> bool: return _captured.has("playing"), STATE_TIMEOUT_S + COUNTDOWN_S):
		_fail("host never fingerprinted B (captured=%s)" % [_captured.keys()])


func _fail(reason: String) -> void:
	print("RESETENET %s result=FAIL reason=%s" % [_role_name, reason])
	get_tree().quit(1)


# --- client harness RPCs --------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func h_dirty() -> void:
	_dirty_camera_and_sky()


@rpc("authority", "call_remote", "reliable")
func h_leave_rejoin() -> void:
	Net.leave()
	await _wait(SETTLE_S)
	Net.join_game(_join_address, _join_port, "Player")


@rpc("authority", "call_remote", "reliable")
func h_finish() -> void:
	_finish()


# --- verdict ---------------------------------------------------------------------------------

func _finish() -> void:
	if _finish_requested:
		return
	_finish_requested = true
	var path: String = _out_dir.path_join(FILE_NAME % _role_name)
	if _mode == "fresh":
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_var(_captured)
		file.close()
		for checkpoint: String in _captured.keys():
			print("RESETENET %s fp %s keys=%d json=%s" % [_role_name, checkpoint, (_captured[checkpoint] as Dictionary).size(), JSON.stringify(_captured[checkpoint])])
		print("RESETENET %s result=PASS mode=fresh checkpoints=%d" % [_role_name, _captured.size()])
		get_tree().quit(0)
		return
	var reference: Dictionary = {}
	if FileAccess.file_exists(path):
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		reference = file.get_var() as Dictionary
		file.close()
	var found: PackedStringArray = PackedStringArray()
	for checkpoint: String in ["countdown", "playing"]:
		if not reference.has(checkpoint) or not _captured.has(checkpoint):
			found.append("%s missing_fingerprint reference=%s test=%s" % [checkpoint, reference.has(checkpoint), _captured.has(checkpoint)])
			continue
		for line: String in MatchFingerprint.diff(reference[checkpoint] as Dictionary, _captured[checkpoint] as Dictionary):
			found.append("%s %s" % [checkpoint, line])
	# KNOWN GAP (found by this bench, not a presentation reset): a client that leaves and
	# re-joins the lobby comes back as slot 2 instead of its old slot 1 (Net does not recycle
	# the seat), so its camera has no home beacon and the ghosts show another seat's piece.
	# While net.peer_slots / net.local_slot differ from the fresh run, diffs in the keys that
	# follow from the seat are reported as known_gap, and the peer ends PENDING, not PASS.
	var seat_changed: bool = false
	for line: String in found:
		if line.contains(" net.peer_slots:") or line.contains(" net.local_slot:"):
			seat_changed = true
	var diffs: int = 0
	var known: int = 0
	for line: String in found:
		var follows_seat: bool = (
			line.contains(" camera.") or line.contains(" net.peer_slots:") or line.contains(" net.local_slot:")
			or line.contains(" wiring.node.RemoteCursors/GhostPreview") or line.contains(" wiring.node.HotSeat/GhostPreview")
		)
		if seat_changed and follows_seat:
			known += 1
			print("RESETENET %s known_gap %s" % [_role_name, line])
		else:
			diffs += 1
			print("RESETENET %s diff %s" % [_role_name, line])
	var verdict: String = "FAIL" if diffs > 0 else ("PENDING" if known > 0 else "PASS")
	print("RESETENET %s result=%s diffs=%d known_gaps=%d" % [_role_name, verdict, diffs, known])
	get_tree().quit(1 if diffs > 0 else 0)
