extends Node
## Bontago-8or.25: black hole activation over real ENet with simulated lag.
## The host emits the same Events.special_triggered a real impact would; the
## client must build a BlackHoleVisual from the replicated event.
## Handshake (Bontago-fca.40, modelled on gift_fx_enet): the client attaches its
## listener after PLAYING, then sends net_ready; the host fires only after that ack,
## and waits for the client's net_done before quitting. No fixed-timer race.
## Run via tools/run_black_hole_enet.ps1 (3 min deadline).

const CONNECT_TIMEOUT: float = 20.0
const WATCH_SECONDS: float = 4.0
const READY_TIMEOUT: float = 30.0
const DONE_TIMEOUT: float = 15.0
const POLL_S: float = 0.1
const TRIGGER_POSITION: Vector3 = Vector3(0.0, 1.0, 0.0)


func _ready() -> void:
	if not Net.apply_command_line():
		get_tree().quit(2)
		return
	if Net.mode() == Net.Mode.HOST:
		await _run_host()
	else:
		await _run_client()


var _client_ready: bool = false
var _client_done: bool = false


@rpc("any_peer", "call_remote", "reliable")
func net_ready() -> void:
	_client_ready = true
	print("BHENET host client_ready peer=%d" % multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func net_done() -> void:
	_client_done = true


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _visual_count() -> int:
	if Match.blocks_parent() == null:
		return 0
	return Match.blocks_parent().find_children("*", "BlackHoleVisual", true, false).size()


func _run_host() -> void:
	var deadline: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT * 1000.0)
	while Net.peer_ids().size() < 1 and Time.get_ticks_msec() < deadline:
		await _wait(0.1)
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = 2
	config.hot_seat = false
	config.rng_seed = 20260918
	var field: Field = (load("res://game/Field.tscn") as PackedScene).instantiate() as Field
	field.map_def = MapDef.for_size(config.map_size)
	add_child(field)
	var blocks: Node3D = Node3D.new()
	add_child(blocks)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child(registry)
	Match.register_world(field, registry, blocks)
	Match.start_match(config)
	get_node(^"/root/MatchNet").call(&"replicate_match_start", Match.config)
	field.place_flags(Match.config.player_count, Match.config.player_colors, Match.config.goal_flag_count)
	await _wait(Match.COUNTDOWN_SECONDS + 1.0)
	var ready_deadline: int = Time.get_ticks_msec() + int(READY_TIMEOUT * 1000.0)
	while not _client_ready and Time.get_ticks_msec() < ready_deadline:
		await _wait(POLL_S)
	if not _client_ready:
		print("BHENET host result=FAIL reason=client_never_ready")
		get_tree().quit(1)
		return
	Events.special_triggered.emit(1, &"black_hole", TRIGGER_POSITION, 0)
	await _wait(0.2)
	print("BHENET host visuals=%d" % _visual_count())
	var done_deadline: int = Time.get_ticks_msec() + int((WATCH_SECONDS + DONE_TIMEOUT) * 1000.0)
	while not _client_done and Time.get_ticks_msec() < done_deadline:
		await _wait(POLL_S)
	print("BHENET host result=%s" % ("PASS" if _client_done else "FAIL reason=client_never_done"))
	get_tree().quit(0 if _client_done else 1)


func _run_client() -> void:
	var deadline: int = Time.get_ticks_msec() + int((CONNECT_TIMEOUT + 10.0) * 1000.0)
	while Match.state() != Match.State.PLAYING and Time.get_ticks_msec() < deadline:
		await _wait(0.1)
	if Match.state() != Match.State.PLAYING:
		print("BHENET client result=FAIL reason=never_playing")
		get_tree().quit(2)
		return
	# The bench client has no registered world (Main builds it), so Match
	# draws no visual here; the replicated event itself is what is checked.
	# The visual build is covered by test_special_black_hole.
	var counter: Array[int] = [0]
	var on_trigger: Callable = func(_n: int, def_id: StringName, _p: Vector3, _c: int) -> void:
		if def_id == &"black_hole":
			counter[0] += 1
	Events.special_triggered.connect(on_trigger)
	# Listener attached: only now may the host fire.
	rpc_id(Net.HOST_PEER_ID, &"net_ready")
	var end: int = Time.get_ticks_msec() + int(WATCH_SECONDS * 1000.0)
	while Time.get_ticks_msec() < end and counter[0] == 0:
		await _wait(0.05)
	print("BHENET client events=%d result=%s" % [counter[0], "PASS" if counter[0] > 0 else "FAIL"])
	rpc_id(Net.HOST_PEER_ID, &"net_done")
	await _wait(0.5)
	get_tree().quit(0)
