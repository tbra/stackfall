extends Node
## Bontago-1pi.32: host + one lagged client over real ENet, loading-screen ready
## gate armed (MatchLifecycle.set_loading_gate_forced -- headless has no overlay
## to arm it). Per-peer log lines (LRENET): the host holds the countdown until
## both humans pressed ready; the client presses ready
## over the lagged link, receives the host's open message, then sees the 3-2-1
## run down and PLAYING. Run via tools/run_loading_ready_enet.ps1.
## Host: --headless-host --expect-peers=2.
##
## Late-join step (Bontago-1pi.42, runner -Late): the host runs a 3-seat match with
## the production seat policy, holds its own ready press until a third peer
## (--late-joiner) has joined mid-gate, and that joiner must hold the host's
## current ready/required sets after its replay (the lifecycle's roster broadcast
## reaches it BEFORE net_match_start, whose start_match() resets the mirror), press
## ready as a required seat and see the gate open and PLAYING with the others.

const CONNECT_TIMEOUT: float = 20.0
const JOIN_SETTLE_S: float = 2.0
const HOST_READY_AFTER_S: float = 1.0
const CLIENT_READY_AFTER_S: float = 2.0
const TOLERANCE_S: float = 0.3
const LATE_SETTLE_S: float = 1.5
const LATE_SEATS: int = 3

var _match_net: Node
var _t0_msec: int = 0
var _open_t: float = -1.0
var _playing_t: float = -1.0
var _first_tick_after_open_t: float = -1.0
var _tick_t: Dictionary = {}
var _late_step: bool = false
var _late_joiner: bool = false
var _late_mirror_ok: bool = false
var _late_replay_mirror_ok: bool = false


func _ready() -> void:
	if not Net.apply_command_line():
		get_tree().quit(2)
		return
	_match_net = get_node(^"/root/MatchNet")
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	_late_step = user_args.has("--late-step")
	_late_joiner = user_args.has("--late-joiner")
	# Both ends arm the gate themselves: headless has no LoadingScreen to do it.
	Match._lifecycle.set_loading_gate_forced(true)
	Events.loading_gate_opened.connect(_on_opened)
	Events.loading_ready_changed.connect(_on_ready_changed)
	Events.countdown_tick.connect(_on_tick)
	Events.match_state_changed.connect(_on_state)
	if Net.mode() == Net.Mode.HOST:
		await _run_host()
	elif _late_joiner:
		await _run_late_joiner()
	else:
		await _run_client()


func _role() -> String:
	if Net.mode() == Net.Mode.HOST:
		return "host"
	return "late" if _late_joiner else "client"


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _now_s() -> float:
	return float(Time.get_ticks_msec() - _t0_msec) / 1000.0


func _on_ready_changed(ready_ids: PackedInt32Array, required_ids: PackedInt32Array) -> void:
	print("LRENET %s ready=%s required=%s t=%.2f" % [_role(), str(ready_ids), str(required_ids), _now_s()])


func _on_opened() -> void:
	_open_t = _now_s()
	print("LRENET %s gate_open t=%.2f" % [_role(), _open_t])


func _on_tick(seconds_left: int) -> void:
	if _t0_msec == 0:
		_t0_msec = Time.get_ticks_msec()
	_tick_t[seconds_left] = _now_s()
	print("LRENET %s tick=%d t=%.2f" % [_role(), seconds_left, _now_s()])


func _on_state(_from: int, to_state: int) -> void:
	if to_state == Match.State.PLAYING:
		_playing_t = _now_s()
		print("LRENET %s playing t=%.2f" % [_role(), _playing_t])


func _verdict(role: String) -> void:
	var ok: bool = _open_t >= 0.0 and _playing_t >= _open_t + Match.config.effective_countdown_seconds() - TOLERANCE_S
	print("LRENET %s result=%s open_t=%.2f playing_t=%.2f" % [role, "PASS" if ok else "FAIL", _open_t, _playing_t])


func _run_host() -> void:
	var deadline: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT * 1000.0)
	while Net.peer_ids().size() < 2 and Time.get_ticks_msec() < deadline:
		await _wait(0.1)
	await _wait(JOIN_SETTLE_S)
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = LATE_SEATS if _late_step else 2
	config.hot_seat = false
	if _late_step:
		# Production admission: Main keeps the match "in progress" and installs the
		# seat policy, so a mid-gate joiner takes the open third seat.
		Net.set_match_in_progress(true)
		Net.set_seat_policy(Callable(_match_net, &"pick_open_seat"), Callable(_match_net, &"seat_reclaimable"))
	var field: Field = (load("res://game/Field.tscn") as PackedScene).instantiate() as Field
	field.map_def = MapDef.for_size(config.map_size)
	add_child(field)
	var blocks: Node3D = Node3D.new()
	add_child(blocks)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child(registry)
	Match.register_world(field, registry, blocks)
	Match.start_match(config)
	_match_net.call(&"replicate_match_start", Match.config)
	field.place_flags(Match.config.player_count, Match.config.player_colors, Match.config.goal_flag_count)
	print("LRENET host started required=%s armed=%s" % [str(Match._lifecycle.loading_required_peers()), str(Match._lifecycle.is_loading_gate_armed())])
	await _wait(HOST_READY_AFTER_S)
	if _late_step:
		await _host_wait_for_late_joiner()
		Net.request_loading_ready()
		var play_deadline: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT * 1000.0)
		while Match.state() != Match.State.PLAYING and Time.get_ticks_msec() < play_deadline:
			await _wait(0.05)
		await _wait(0.5)
	else:
		Net.request_loading_ready()
		await _wait(Match.COUNTDOWN_SECONDS + 3.0)
	_verdict("host")
	get_tree().quit(0)


## The host's own press is held back until the third peer sits in the open seat, so
## the gate is provably still closed while the joiner arrives.
func _host_wait_for_late_joiner() -> void:
	var deadline: int = Time.get_ticks_msec() + int((CONNECT_TIMEOUT + 15.0) * 1000.0)
	while Net.peer_ids().size() < LATE_SEATS and Time.get_ticks_msec() < deadline:
		await _wait(0.1)
	await _wait(LATE_SETTLE_S)
	print("LRENET host late_seated peers=%s required=%s ready=%s blocking=%s" % [str(Net.peer_ids()), str(Match._lifecycle.loading_required_peers()), str(Match._lifecycle.loading_ready_peers()), str(Match._lifecycle.loading_gate_blocking())])


func _run_client() -> void:
	var deadline: int = Time.get_ticks_msec() + int((CONNECT_TIMEOUT + 10.0) * 1000.0)
	while Match.state() != Match.State.COUNTDOWN and Time.get_ticks_msec() < deadline:
		await _wait(0.02)
	if Match.state() != Match.State.COUNTDOWN:
		print("LRENET client result=FAIL reason=no_match_start")
		get_tree().quit(2)
		return
	print("LRENET client saw_start armed=%s blocking=%s" % [str(Match._lifecycle.is_loading_gate_armed()), str(Match._lifecycle.loading_gate_blocking())])
	await _wait(CLIENT_READY_AFTER_S)
	print("LRENET client pressing_ready t=%.2f blocking=%s" % [_now_s(), str(Match._lifecycle.loading_gate_blocking())])
	Net.request_loading_ready()
	while Match.state() != Match.State.PLAYING and Time.get_ticks_msec() < deadline:
		await _wait(0.02)
	await _wait(0.3)
	print("LRENET client local_ready=%s" % str(Match._lifecycle.loading_ready_peers().has(Net.local_peer_id())))
	_verdict("client")
	get_tree().quit(0)


## Joins while the host's gate is closed. After its replay it must hold the host's
## sets (the other client already pressed, the host has not) and be waited for.
func _run_late_joiner() -> void:
	var deadline: int = Time.get_ticks_msec() + int((CONNECT_TIMEOUT + 25.0) * 1000.0)
	while Match.state() != Match.State.COUNTDOWN and Time.get_ticks_msec() < deadline:
		await _wait(0.02)
	if Match.state() != Match.State.COUNTDOWN:
		print("LRENET late result=FAIL reason=no_match_start")
		get_tree().quit(2)
		return
	# The replay's last message (net_replay_end) lands after every gate message, so
	# the mirror read here is what the replay alone left it with -- before any later
	# ready press or roster change can re-publish the sets and mask a wiped mirror.
	while int(_match_net.get(&"last_replay_acknowledged")) <= 0 and Time.get_ticks_msec() < deadline:
		await _wait(0.005)
	var replay_required: PackedInt32Array = Match._lifecycle.loading_required_peers()
	_late_replay_mirror_ok = replay_required.size() == LATE_SEATS and replay_required.has(Net.local_peer_id()) and replay_required.has(Net.HOST_PEER_ID) and Match._lifecycle.loading_gate_blocking()
	print("LRENET late replay_mirror ready=%s required=%s replay_mirror_ok=%s" % [str(Match._lifecycle.loading_ready_peers()), str(replay_required), str(_late_replay_mirror_ok)])
	await _wait(LATE_SETTLE_S)
	var ready_ids: PackedInt32Array = Match._lifecycle.loading_ready_peers()
	var required_ids: PackedInt32Array = Match._lifecycle.loading_required_peers()
	var local_peer: int = Net.local_peer_id()
	# Who else has pressed by now depends on timing (client 1, then the host); the
	# joiner itself has not, so it must still be waited for and the gate still closed.
	_late_mirror_ok = required_ids.size() == LATE_SEATS and required_ids.has(local_peer) and required_ids.has(Net.HOST_PEER_ID) and not ready_ids.has(local_peer) and Match._lifecycle.loading_gate_blocking()
	print("LRENET late mirror ready=%s required=%s local=%d blocking=%s mirror_ok=%s" % [str(ready_ids), str(required_ids), local_peer, str(Match._lifecycle.loading_gate_blocking()), str(_late_mirror_ok)])
	Net.request_loading_ready()
	while Match.state() != Match.State.PLAYING and Time.get_ticks_msec() < deadline:
		await _wait(0.02)
	await _wait(0.3)
	var ok: bool = _late_replay_mirror_ok and _late_mirror_ok and _open_t >= 0.0 and Match.state() == Match.State.PLAYING and Match._lifecycle.loading_ready_peers().has(local_peer)
	print("LRENET late result=%s replay_mirror_ok=%s mirror_ok=%s open_t=%.2f playing_t=%.2f local_ready=%s" % ["PASS" if ok else "FAIL", str(_late_replay_mirror_ok), str(_late_mirror_ok), _open_t, _playing_t, str(Match._lifecycle.loading_ready_peers().has(local_peer))])
	get_tree().quit(0)
