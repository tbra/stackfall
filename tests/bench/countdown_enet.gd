extends Node
## Bontago-mp0.27: host + one lagged client over real ENet. Both sides log the
## 3-2-1 countdown ticks with a local timestamp; the client submits a placement
## intent mid-countdown, which the host must reject (no block spawned).
## Run via tools/run_countdown_enet.ps1. Host: --headless-host --expect-peers=2.

const CONNECT_TIMEOUT: float = 20.0
## Let the client finish its handshake so it sees the whole countdown (without
## this it joins mid-countdown, which is the late-join path).
const JOIN_SETTLE_S: float = 2.0
const CLIENT_SLOT: int = 1
const INTENT_DELAY_S: float = 1.2
const PLACE_HEIGHT: float = 3.0

var _match_net: Node
var _t0_msec: int = 0
var _block_count: Callable = Callable()
var _blocks: Node3D = null
var _rejects: int = 0


func _ready() -> void:
	if not Net.apply_command_line():
		get_tree().quit(2)
		return
	_match_net = get_node(^"/root/MatchNet")
	Events.countdown_tick.connect(_on_tick)
	Events.placement_rejected.connect(func(_s: int, _r: StringName) -> void: _rejects += 1)
	if Net.mode() == Net.Mode.HOST:
		await _run_host()
	else:
		await _run_client()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _now_s() -> float:
	return float(Time.get_ticks_msec() - _t0_msec) / 1000.0


func _on_tick(seconds_left: int) -> void:
	if _t0_msec == 0:
		_t0_msec = Time.get_ticks_msec()
	var role: String = "host" if Net.mode() == Net.Mode.HOST else "client"
	print("CDENET %s tick=%d t=%.2f" % [role, seconds_left, _now_s()])


func _run_host() -> void:
	var deadline: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT * 1000.0)
	while Net.peer_ids().size() < 1 and Time.get_ticks_msec() < deadline:
		await _wait(0.1)
	await _wait(JOIN_SETTLE_S)
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = 2
	config.hot_seat = false
	var field: Field = (load("res://game/Field.tscn") as PackedScene).instantiate() as Field
	field.map_def = MapDef.for_size(config.map_size)
	add_child(field)
	_blocks = Node3D.new()
	add_child(_blocks)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child(registry)
	Match.register_world(field, registry, _blocks)
	Match.start_match(config)
	_match_net.call(&"replicate_match_start", Match.config)
	field.place_flags(Match.config.player_count, Match.config.player_colors, Match.config.goal_flag_count)
	await _wait(INTENT_DELAY_S + 1.0)
	# Bontago-1pi.79: every slot already holds its first block during the countdown.
	print("CDENET host held_in_countdown=%s" % [Match.held_shape(0) != null and Match.held_shape(CLIENT_SLOT) != null])
	print("CDENET host state=%d blocks_during_countdown=%d rejects=%d" % [Match.state(), _blocks.get_child_count(), _rejects])
	await _wait(Match.COUNTDOWN_SECONDS + 1.5)
	print("CDENET host final_state=%d" % Match.state())
	get_tree().quit(0)


func _run_client() -> void:
	var deadline: int = Time.get_ticks_msec() + int((CONNECT_TIMEOUT + 10.0) * 1000.0)
	while Match.state() != Match.State.COUNTDOWN and Time.get_ticks_msec() < deadline:
		await _wait(0.02)
		if Engine.get_process_frames() % 25 == 0:
			print("CDENET client waiting state=%d" % Match.state())
	if Match.state() != Match.State.COUNTDOWN:
		print("CDENET result=FAIL reason=no_countdown")
		get_tree().quit(2)
		return
	print("CDENET client saw_countdown remaining=%.2f" % Match.countdown_remaining())
	print("CDENET client held_in_countdown=%s next=%s" % [Match.held_shape(CLIENT_SLOT) != null, Match.next_shape(CLIENT_SLOT) != null])
	await _wait(INTENT_DELAY_S)
	var home: Vector2 = Match.slot(CLIENT_SLOT).home_position
	_match_net.call(&"submit_place", CLIENT_SLOT, Vector3(home.x, PLACE_HEIGHT, home.y), 0, Quaternion.IDENTITY, false, Match.feed_seq(CLIENT_SLOT))
	while Match.state() != Match.State.PLAYING and Time.get_ticks_msec() < deadline:
		await _wait(0.02)
	print("CDENET client playing_at=%.2f state=%d result=%s" % [_now_s(), Match.state(), "PASS" if Match.state() == Match.State.PLAYING else "FAIL"])
	await _wait(0.5)
	get_tree().quit(0)
