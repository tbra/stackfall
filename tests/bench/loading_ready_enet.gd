extends Node
## Bontago-1pi.32: host + one lagged client over real ENet, loading-screen ready
## gate armed (MatchLifecycle.set_loading_gate_forced -- headless has no overlay
## to arm it). Per-peer log lines (LRENET): the host holds the countdown until
## min_display_s elapsed AND both humans pressed ready; the client presses ready
## over the lagged link, receives the host's open message, then sees the 3-2-1
## run down and PLAYING. Run via tools/run_loading_ready_enet.ps1.
## Host: --headless-host --expect-peers=2.

const CONNECT_TIMEOUT: float = 20.0
const JOIN_SETTLE_S: float = 2.0
const HOST_READY_AFTER_S: float = 1.0
const CLIENT_READY_AFTER_S: float = 2.0
const TOLERANCE_S: float = 0.3

var _match_net: Node
var _t0_msec: int = 0
var _open_t: float = -1.0
var _playing_t: float = -1.0
var _first_tick_after_open_t: float = -1.0
var _tick_t: Dictionary = {}


func _ready() -> void:
	if not Net.apply_command_line():
		get_tree().quit(2)
		return
	_match_net = get_node(^"/root/MatchNet")
	# Both ends arm the gate themselves: headless has no LoadingScreen to do it.
	Match._lifecycle.set_loading_gate_forced(true)
	Events.loading_gate_opened.connect(_on_opened)
	Events.loading_ready_changed.connect(_on_ready_changed)
	Events.countdown_tick.connect(_on_tick)
	Events.match_state_changed.connect(_on_state)
	if Net.mode() == Net.Mode.HOST:
		await _run_host()
	else:
		await _run_client()


func _role() -> String:
	return "host" if Net.mode() == Net.Mode.HOST else "client"


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
	var ok: bool = _open_t >= Match._lifecycle._loading_tuning.min_display_s - TOLERANCE_S and _playing_t >= _open_t + Match.config.effective_countdown_seconds() - TOLERANCE_S
	print("LRENET %s result=%s open_t=%.2f playing_t=%.2f min_display_s=%.1f" % [role, "PASS" if ok else "FAIL", _open_t, _playing_t, Match._lifecycle._loading_tuning.min_display_s])


func _run_host() -> void:
	var deadline: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT * 1000.0)
	while Net.peer_ids().size() < 2 and Time.get_ticks_msec() < deadline:
		await _wait(0.1)
	await _wait(JOIN_SETTLE_S)
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = 2
	config.hot_seat = false
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
	Net.request_loading_ready()
	await _wait(Match._lifecycle._loading_tuning.min_display_s + Match.COUNTDOWN_SECONDS + 3.0)
	_verdict("host")
	get_tree().quit(0)


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
