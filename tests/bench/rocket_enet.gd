extends Node
## Bontago-1pi.85.25 (PA1): host + one lagged client over real ENet. The host launches a Rocket
## carrier (real SpecialBehavior, normal gravity) steeply down onto the disc; the client samples
## the REPLICATED body each frame and checks its nose axis follows the travel direction and that
## it ends up where the host says the rocket exploded (no desync). Run: tools/run_rocket_enet.ps1.

const TAG: String = "RKTENET"
const PEERS: int = 2
const CONNECT_TIMEOUT: float = 25.0
const GATE_TIMEOUT: float = 40.0
const POLL_S: float = 0.05
const SEED: int = 20261007
const START_LOCAL: Vector3 = Vector3(-10.0, 35.0, 0.0)
## Aimed steeply UPWARD (Bontago-1pi.85.43): the host must detonate it before it leaves the
## replicable volume, so the client never sees a body pinned at the quantization clamp.
const AIM: Vector3 = Vector3(0.2, 1.0, 0.0)
const MAX_NOSE_ERROR_DEG: float = 8.0
const MIN_SAMPLES: int = 5
const MIN_MOVE_M: float = 0.05
const WATCH_TIMEOUT: float = 15.0
const ARM_WAIT_S: float = 0.3
const QUIT_DELAY_S: float = 1.5
const PRE_FIRE_WAIT_S: float = 1.0
const MAX_END_ERROR_M: float = 12.0
const CLAMP_EPSILON_M: float = 0.05
## Samples ignored at the start: the spawn message carries the resting pose before the first snapshot.
const SKIP_SAMPLES: int = 5
const UNSET_DEG: float = 999.0

var _explosion: Vector3 = Vector3.ZERO
var _exploded: bool = false
var _client_report: Dictionary = {}
var _client_done: bool = false


func _ready() -> void:
	if not Net.apply_command_line():
		get_tree().quit(2)
		return
	Events.special_triggered.connect(_on_trigger)
	if Net.mode() == Net.Mode.HOST:
		await _run_host()
	else:
		await _run_client()


func _physics_process(delta: float) -> void:
	SnapshotSync.host_tick(delta)
	SnapshotSync.client_tick(delta)


func _on_trigger(net_id: int, def_id: StringName, position: Vector3, _depth: int) -> void:
	if def_id != &"rocket" or Net.mode() != Net.Mode.HOST:
		return
	_exploded = true
	_explosion = position
	# What a held gift gets from MatchPlacement._on_gift_completed(): despawn the spent carrier.
	var carrier: Block = Match.registry().block_for_net_id(net_id)
	if carrier != null:
		Events.block_removed.emit(carrier, String(Events.REASON_GIFT_DESPAWN))
		carrier.queue_free()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(condition: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline:
		await _wait(POLL_S)
	return bool(condition.call())


func _build_world() -> Field:
	var field: Field = (load("res://game/Field.tscn") as PackedScene).instantiate() as Field
	field.map_def = MapDef.for_size(MapDef.MapSize.SMALL)
	add_child(field)
	var blocks: Node3D = Node3D.new()
	add_child(blocks)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child(registry)
	Match.register_world(field, registry, blocks)
	return field


@rpc("authority", "call_remote", "reliable")
func net_fire(direction: Vector3) -> void:
	_watch_rocket(direction)


@rpc("any_peer", "call_remote", "reliable")
func net_report(worst_deg: float, samples: int, gone: bool, last_pos: Vector3) -> void:
	_client_report = {"worst_deg": worst_deg, "samples": samples, "gone": gone, "last": last_pos}
	_client_done = true


func _run_host() -> void:
	var connected: bool = await _until(func() -> bool: return Net.peer_ids().size() >= PEERS, CONNECT_TIMEOUT)
	if not connected:
		print("%s host result=FAIL reason=not_connected" % TAG)
		get_tree().quit(1)
		return
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = PEERS
	config.hot_seat = false
	config.rng_seed = SEED
	config.gifts_enabled = false
	config.weather_mode = MatchConfig.WeatherMode.OFF
	Match._lifecycle.set_loading_gate_forced(true)
	var field: Field = _build_world()
	Match.start_match(config)
	get_node(^"/root/MatchNet").call(&"replicate_match_start", Match.config)
	field.place_flags(Match.config.player_count, Match.config.player_colors, Match.config.goal_flag_count)
	SnapshotSync.set_disk(field)
	SnapshotSync.begin_match(Match.registry(), Match.config.map_def())
	Net.request_loading_ready()
	var playing: bool = await _until(func() -> bool: return Match.state() == Match.State.PLAYING, GATE_TIMEOUT)
	await _wait(PRE_FIRE_WAIT_S)
	var def: SpecialDef = SpecialDef.find_by_id(&"rocket")
	var cube: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var start: Vector3 = field.to_global(START_LOCAL)
	rpc(&"net_fire", field.global_basis * AIM.normalized())
	await _wait(ARM_WAIT_S)
	var rocket: Block = Match.spawn_special_projectile(cube, start, Basis.IDENTITY, 0, Vector3.ZERO, def, null)
	var direction: Vector3 = field.global_basis * AIM.normalized()
	var ok: bool = playing and rocket != null and RocketEffect.set_launch_direction(rocket, direction)
	print("%s host fired ok=%s start=%s dir=%s" % [TAG, ok, start, direction])
	await _until(func() -> bool: return _exploded, WATCH_TIMEOUT)
	await _until(func() -> bool: return _client_done, WATCH_TIMEOUT)
	var worst: float = float(_client_report.get("worst_deg", UNSET_DEG))
	var samples: int = int(_client_report.get("samples", 0))
	var last: Vector3 = _client_report.get("last", Vector3(INF, INF, INF)) as Vector3
	var end_err: float = last.distance_to(_explosion)
	var gone: bool = bool(_client_report.get("gone", false))
	var clamped: bool = last.y >= RocketEffect.replicable_bounds().end.y - CLAMP_EPSILON_M
	var pass_all: bool = ok and _exploded and _client_done and worst < MAX_NOSE_ERROR_DEG \
		and samples >= MIN_SAMPLES and gone and end_err < MAX_END_ERROR_M and not clamped
	print("%s host exploded=%s at=%s client_samples=%d worst_nose_deg=%.2f carrier_gone=%s end_err_m=%.2f" % [
		TAG, _exploded, _explosion, samples, worst, gone, end_err])
	print("%s host result=%s" % [TAG, "PASS" if pass_all else "FAIL"])
	await _wait(QUIT_DELAY_S)
	get_tree().quit(0 if pass_all else 1)


func _run_client() -> void:
	var field: Field = _build_world()
	Match._lifecycle.set_loading_gate_forced(true)
	var started: bool = await _until(func() -> bool: return Match.state() != Match.State.LOBBY, CONNECT_TIMEOUT + GATE_TIMEOUT)
	if not started:
		print("%s client result=FAIL reason=no_match_start" % TAG)
		get_tree().quit(2)
		return
	SnapshotSync.set_disk(field)
	SnapshotSync.begin_match(Match.registry(), Match.config.map_def())
	Net.request_loading_ready()
	await _until(func() -> bool: return Match.state() == Match.State.PLAYING, GATE_TIMEOUT)
	await _until(func() -> bool: return not Net.is_client(), WATCH_TIMEOUT * 4.0)
	get_tree().quit(0)


func _new_block(before: Dictionary) -> Block:
	for block: Block in Match.registry().all_blocks():
		if not before.has(block.net_id):
			return block
	return null


## Client: the only block in this world is the rocket (no placements, gifts off).
func _watch_rocket(direction: Vector3) -> void:
	var before: Dictionary = {}
	var found: bool = await _until(func() -> bool: return _new_block(before) != null, WATCH_TIMEOUT)
	var body: Block = _new_block(before)
	found = found and body != null
	var worst: float = 0.0
	var count: int = 0
	var last: Vector3 = Vector3.ZERO
	var prev: Vector3 = body.global_position if found else Vector3.ZERO
	var net_id: int = body.net_id if found else -1
	while found and is_instance_valid(body) and Match.registry().block_for_net_id(net_id) == body:
		await get_tree().process_frame
		if not is_instance_valid(body):
			break
		if (body.global_position - prev).length() > MIN_MOVE_M:
			var nose: Vector3 = body.global_basis * Vector3.UP
			# A straight line, so the nose must follow the aimed direction.
			var error_deg: float = rad_to_deg(nose.angle_to(direction))
			if count < MIN_SAMPLES * 2 or error_deg > MAX_NOSE_ERROR_DEG:
				print("%s client sample=%d nose_err_deg=%.2f pos=%s" % [TAG, count, error_deg, body.global_position])
			if count >= SKIP_SAMPLES:
				worst = maxf(worst, error_deg)
			count += 1
			prev = body.global_position
		last = body.global_position
	var gone: bool = found and (not is_instance_valid(body) or Match.registry().block_for_net_id(net_id) != body)
	print("%s client slot=%d samples=%d worst_nose_deg=%.2f gone=%s last=%s" % [TAG, Net.local_slot(), count, worst, gone, last])
	rpc_id(Net.HOST_PEER_ID, &"net_report", worst, count, gone, last)
