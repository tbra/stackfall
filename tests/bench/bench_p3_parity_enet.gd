extends Node
## P3 parity throw pair over real loopback ENet: the held-gift preview arc against the host flight, for the
## host seat (controller preview, click release) and for a client seat (submit_throw over the wire). Two
## processes; only the host writes the canonical JSON, keyed by ticks since each throw's own spawn so ENet
## arrival time cannot shift a key. Input, Events, Match and MatchNet.submit_* only, except the client seat's gift,
## which is put in its hand on the host (see _hand_client_gift).
##
## Host (records, writes --out):
##   godot --headless --fixed-fps 60 --path . res://tests/bench/bench_p3_parity_enet.tscn -- --headless-host --port=47851 --expect-peers=2 --out=run.json
## Client (join once the host is up, about 12 s later; give godot --log-file, stdout is block-buffered):
##   godot --headless --fixed-fps 60 --path . res://tests/bench/bench_p3_parity_enet.tscn -- --join=127.0.0.1:47851
## Compare two recordings with the same convention as bench_p3_parity (exit 1 above --tol, default 0):
##   godot --headless --path . res://tests/bench/bench_p3_parity_enet.tscn -- --compare=res://tests/bench/fixtures/p3_parity_enet_reference.json,run.json [--tol=0.0001]

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const PARITY: GDScript = preload("res://tests/bench/bench_p3_parity.gd")
const CUBE_PATH: String = "res://config/blocks/cube.tres"
const MAP_PATH: String = "res://config/match/maps/round.tres"
const DEFAULTS_PATH: String = "res://config/match/match_defaults.tres"
const OUT_ARG: String = "--out="
const COMPARE_ARG: String = "--compare="
const TOL_ARG: String = "--tol="
const SEED_ARG: String = "--rng-seed="
const TAG: String = "P3ENET"
const DEFAULT_SEED: int = 20261025
const HOST_SLOT: int = 0
const CLIENT_SLOT: int = 1
const PLAYER_COUNT: int = 2
const FIELD_RADIUS_M: float = 20.0
const GIFT_ID: StringName = &"bomb"
const ROUND_STEP: float = 0.0001
const CONNECT_TIMEOUT_S: float = 90.0
const PROGRESS_TICKS: int = 60
const WAIT_POLL_S: float = 0.1
const PLAYING_TIMEOUT_S: float = 40.0
const CLIENT_PLACE_DELAY_S: float = 6.0
const CLIENT_WAIT_S: float = 40.0
const QUIT_DELAY_S: float = 1.5
## Host-seat timeline in ticks since PLAYING.
const QUEUE_TICK: int = 60
const FEED_TICK: int = 120
const ARC_TICKS: int = 10
const THROW_TICK: int = 190
const FLIGHT_TICKS: int = 90
const THROW_COUNT: int = 2
## The client throw: pose above its home and a fixed camera forward (the host derives the launch from it).
const CLIENT_POSE_HEIGHT_M: float = 5.0
const CLIENT_THROW_AIM: Vector3 = Vector3(0.3, 0.2, -0.9)

var _out_path: String = ""
var _record: Dictionary = {}
var _events: Array = []
var _tick: int = -1
var _main: Node = null
var _controller: PlayerController = null
var _watched: Array[RigidBody3D] = []
var _spawn_tick: Array[int] = []


func _ready() -> void:
	var compare: String = ""
	var tol: float = 0.0
	var rng_seed: int = DEFAULT_SEED
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_ARG):
			_out_path = arg.substr(OUT_ARG.length())
		elif arg.begins_with(COMPARE_ARG):
			compare = arg.substr(COMPARE_ARG.length())
		elif arg.begins_with(TOL_ARG):
			tol = arg.substr(TOL_ARG.length()).to_float()
		elif arg.begins_with(SEED_ARG):
			rng_seed = arg.substr(SEED_ARG.length()).to_int()
	set_physics_process(false)
	if not compare.is_empty():
		var judge: Node = PARITY.new() as Node
		var code: int = int(judge.call(&"_compare", compare, tol))
		judge.free()
		get_tree().quit(code)
		return
	if not UserPaths.is_isolated_run():
		push_error("bench_p3_parity_enet: not an isolated run, Settings would read the user settings file")
		get_tree().quit(1)
		return
	# DECISION: Main owns the session: its _ready() runs Net.apply_command_line() (host or join) and, on a
	# client, builds the world and sends the loading-ready ack when the host replicates the match start.
	_main = MAIN_SCENE.instantiate()
	if _is_host_run():
		var map: MapDef = (load(MAP_PATH) as MapDef).duplicate(true)
		map.field_radius = FIELD_RADIUS_M
		(_main.get_node("Field") as Field).map_def = map
	add_child(_main)
	print("%s main added mode=%d" % [TAG, Net.mode()])
	if _is_host_run():
		await _run_host(rng_seed)
	else:
		await _run_client()


func _is_host_run() -> bool:
	return OS.get_cmdline_user_args().has("--headless-host")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(condition: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline:
		await _wait(WAIT_POLL_S)
	return bool(condition.call())


# --- host -----------------------------------------------------------------------------------

func _run_host(rng_seed: int) -> void:
	if not await _until(func() -> bool: return Net.peer_ids().size() >= PLAYER_COUNT, CONNECT_TIMEOUT_S):
		print("%s host result=FAIL reason=not_connected" % TAG)
		get_tree().quit(1)
		return
	print("%s host peers connected" % TAG)
	Input.use_accumulated_input = false
	seed(rng_seed)
	_record["header.mouse_move_speed_scale"] = _r(Settings.mouse_move_speed_scale())
	var map: MapDef = (_main.get_node("Field") as Field).map_def
	var config: MatchConfig = (load(DEFAULTS_PATH) as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.rng_seed = rng_seed
	config.ai_count = 0
	config.player_count = PLAYER_COUNT
	config.sandbox = false
	config.scripted_gifts = true
	config.countdown_seconds = 0.0
	var pinned: BlockFeedConfig = Match._block_feed_config.duplicate() as BlockFeedConfig
	pinned.shapes = [load(CUBE_PATH) as BlockShape]
	pinned.weight_overrides = PackedFloat32Array()
	Match._block_feed_config = pinned
	Match.register_world(_main.get_node("Field"), _main.get_node("BlockRegistry"), _main.get_node("BlocksContainer"))
	Match.start_match(config)
	Match.set_feed_timer_enabled(false)
	get_node(^"/root/MatchNet").call(&"replicate_match_start", Match.config)
	Events.block_placed.connect(_on_block_placed)
	Events.placement_rejected.connect(_on_placement_rejected)
	if not await _until(_find_world, PLAYING_TIMEOUT_S):
		print("%s host result=FAIL reason=never_playing" % TAG)
		get_tree().quit(1)
		return
	print("%s host playing" % TAG)
	set_physics_process(true)


func _find_world() -> bool:
	if Match.state() != Match.State.PLAYING:
		return false
	_controller = _find(_main, "PlayerController") as PlayerController
	return _controller != null


func _find(node: Node, class_label: String) -> Node:
	if node.get_script() != null and (node.get_script() as Script).get_global_name() == class_label:
		return node
	for child: Node in node.get_children():
		var hit: Node = _find(child, class_label)
		if hit != null:
			return hit
	return null


func _physics_process(_delta: float) -> void:
	_tick += 1
	if _tick % PROGRESS_TICKS == 0:
		print("%s host tick=%d throws=%d state=%d seq1=%d held1=%s" % [TAG, _tick, _watched.size(), Match.state(), Match.feed_seq(CLIENT_SLOT), Match.held_shape(CLIENT_SLOT)])
	match _tick:
		QUEUE_TICK:
			_events.append("gift_queued|%s" % Match.debug_queue_special(HOST_SLOT, GIFT_ID))
			_hand_client_gift()
		FEED_TICK:
			_click()
		THROW_TICK:
			_record["host.throw.held"] = String(Match.held_special(HOST_SLOT))
			_click()
	if _tick >= THROW_TICK - ARC_TICKS and _tick < THROW_TICK:
		_sample_arc("host.arc.%02d." % (_tick - (THROW_TICK - ARC_TICKS)))
	_sample_flights()
	Input.flush_buffered_events()
	if _watched.size() >= THROW_COUNT and _tick - _spawn_tick[THROW_COUNT - 1] > FLIGHT_TICKS:
		set_physics_process(false)
		_finish_host()


## DECISION: the debug gift seam is host-only (the wire drops its sentinel claim), so the client seat's gift is
## put straight into its held slot on the host, the way tests/enet/muzzle_spawn_enet.gd does; the host is
## the authority submit_throw is judged against, so the client needs no mirror of it.
func _hand_client_gift() -> void:
	Match._gifts._ensure_capacity(CLIENT_SLOT)
	Match._gifts._held_specials[CLIENT_SLOT] = GIFT_ID
	Match._feed._held_is_gift[CLIENT_SLOT] = true
	_events.append("client_gift_held|%s" % Match.held_special(CLIENT_SLOT))


func _click() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)


## The two throws: the host seat's first block at or after THROW_TICK, then the client's first block.
func _on_block_placed(block: RigidBody3D, shape_id: StringName) -> void:
	var body: Block = block as Block
	var owner_slot: int = body.owner_slot if body != null else -1
	_events.append("block_placed|%s|%d" % [shape_id, owner_slot])
	print("%s host block_placed shape=%s owner=%d tick=%d" % [TAG, shape_id, owner_slot, _tick])
	var host_throw: bool = owner_slot == HOST_SLOT and _tick >= THROW_TICK and _watched.is_empty()
	var client_throw: bool = owner_slot == CLIENT_SLOT and _watched.size() == 1
	if host_throw or client_throw:
		var index: int = _watched.size()
		_watched.append(block)
		_spawn_tick.append(_tick)
		_put_vector("throw%d.spawn" % index, block.global_position)
		_record["throw%d.shape" % index] = String(shape_id)
		_record["throw%d.owner" % index] = owner_slot


func _on_placement_rejected(slot_id: int, reason: StringName) -> void:
	_events.append("placement_rejected|%d|%s" % [slot_id, reason])
	print("%s host placement_rejected slot=%d reason=%s tick=%d" % [TAG, slot_id, reason, _tick])


func _sample_flights() -> void:
	for i: int in range(_watched.size()):
		var age: int = _tick - _spawn_tick[i]
		if age <= FLIGHT_TICKS and is_instance_valid(_watched[i]):
			_put_vector("throw%d.flight.%03d" % [i, age], _watched[i].global_position)


func _sample_arc(prefix: String) -> void:
	var launch: Dictionary = _controller.gift_launch_preview()
	_record[prefix + "present"] = int(not launch.is_empty())
	if launch.is_empty():
		return
	_put_vector(prefix + "origin", launch["origin"] as Vector3)
	_put_vector(prefix + "velocity", launch["velocity"] as Vector3)
	_record[prefix + "gravity"] = _r(float(launch["gravity_scale"]))


func _finish_host() -> void:
	_record["events"] = _events
	var text: String = JSON.stringify(_record, "\t", true)
	if not _out_path.is_empty():
		var file: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
		if file == null:
			push_error("bench_p3_parity_enet: cannot write %s" % _out_path)
			get_tree().quit(1)
			return
		file.store_string(text)
		file.close()
	var armed: bool = int(_record.get("host.arc.00.present", 0)) == 1
	var owners_ok: bool = int(_record.get("throw0.owner", -1)) == HOST_SLOT and int(_record.get("throw1.owner", -1)) == CLIENT_SLOT
	var pass_all: bool = armed and owners_ok
	print("%s host sha256=%s keys=%d events=%d arc_present=%s owners_ok=%s" % [TAG, text.sha256_text(), _record.size(), _events.size(), armed, owners_ok])
	print("%s host result=%s" % [TAG, "PASS" if pass_all else "FAIL"])
	await _wait(QUIT_DELAY_S)
	get_tree().quit(0 if pass_all else 1)


func _r(value: float) -> float:
	return snappedf(value, ROUND_STEP) + 0.0


func _put_vector(key: String, v: Vector3) -> void:
	_record[key + ".x"] = _r(v.x)
	_record[key + ".y"] = _r(v.y)
	_record[key + ".z"] = _r(v.z)


# --- client ---------------------------------------------------------------------------------

## Waits for the host to put a gift in its seat's hand, then throws it.
func _run_client() -> void:
	await _until(func() -> bool: return Match.state() != Match.State.LOBBY, CONNECT_TIMEOUT_S + PLAYING_TIMEOUT_S)
	if not await _until(func() -> bool: return Match.state() == Match.State.PLAYING, CONNECT_TIMEOUT_S + PLAYING_TIMEOUT_S):
		print("%s client result=FAIL reason=never_playing" % TAG)
		get_tree().quit(2)
		return
	var slot_id: int = Net.local_slot()
	Events.placement_rejected.connect(func(rejected_slot: int, why: StringName) -> void:
		print("%s client placement_rejected slot=%d reason=%s" % [TAG, rejected_slot, why]))
	var match_net: Node = get_node(^"/root/MatchNet")
	# DECISION: the host's tiny map rides a test-only MatchConfig subclass the wire does not carry, so the
	# client derives its home from the same map definition instead of its replicated (default-map) slot.
	var map: MapDef = (load(MAP_PATH) as MapDef).duplicate(true)
	map.field_radius = FIELD_RADIUS_M
	var home: Vector2 = PlayerSlot.home_position_for(slot_id, PLAYER_COUNT, map)
	var origin: Vector3 = Vector3(home.x, CLIENT_POSE_HEIGHT_M, home.y)
	# The host hands this seat its gift at QUEUE_TICK and throws its own at THROW_TICK; the client goes after.
	await _wait(CLIENT_PLACE_DELAY_S)
	var reason: Variant = match_net.call(
		&"submit_throw", slot_id, origin, 0, Quaternion.IDENTITY, CLIENT_THROW_AIM.normalized(), Match.feed_seq(slot_id)
	)
	print("%s client slot=%d throw_sent=%s seq=%d" % [TAG, slot_id, reason, Match.feed_seq(slot_id)])
	await _wait(QUIT_DELAY_S)
	await _until(func() -> bool: return not Net.is_client(), CLIENT_WAIT_S)
	get_tree().quit(0)
