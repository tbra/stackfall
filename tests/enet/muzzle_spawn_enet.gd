extends Node
## host + one lagged client over real ENet. The host releases a held Rocket and
## then a held Paintball through the real request_throw path; the model's pivot on the spawned body
## must sit at the held model's pivot (ghost pose + gift cell centre) on the host AND on the client,
## read from the client's replicated spawn transform. Run: tools/run_muzzle_spawn_enet.ps1.

const TAG: String = "MUZZLEENET"
const PEERS: int = 2
const CONNECT_TIMEOUT: float = 25.0
const GATE_TIMEOUT: float = 40.0
const POLL_S: float = 0.05
const SEED: int = 20261014
const TOLERANCE_M: float = 0.05
const POSE_HEIGHT_M: float = 5.0
const REPORT_TIMEOUT: float = 15.0
const PRE_FIRE_WAIT_S: float = 1.0
const ARM_WAIT_S: float = 0.3
const QUIT_DELAY_S: float = 1.5
const UNSET_M: float = 999.0
const GIFTS: Array[StringName] = [&"rocket", &"paintball"]
const AIMS: Array[Vector3] = [Vector3(0.3, 0.2, -0.9), Vector3(0.3, -0.2, -0.9)]
const CLIENT_LIFETIME_S: float = 120.0

var _expected: Vector3 = Vector3.ZERO
var _expected_gift: StringName = &""
var _look_reports: Dictionary = {}
var _reports: Dictionary = {}


func _ready() -> void:
	if not Net.apply_command_line():
		get_tree().quit(2)
		return
	if Net.mode() == Net.Mode.HOST:
		await _run_host()
	else:
		await _run_client()


func _physics_process(delta: float) -> void:
	SnapshotSync.host_tick(delta)
	SnapshotSync.client_tick(delta)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(condition: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline:
		await _wait(POLL_S)
	return bool(condition.call())


func _build_world() -> Field:
	var field: Field = (load("res://game/field/Field.tscn") as PackedScene).instantiate() as Field
	field.map_def = MapDef.base().scaled(0.75)
	add_child(field)
	var blocks: Node3D = Node3D.new()
	add_child(blocks)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child(registry)
	Match.register_world(field, registry, blocks)
	return field


func _pivot_of(block: Block) -> Vector3:
	var visual: Node3D = block.get_node_or_null(NodePath(String(BlockFactory.GIFT_VISUAL_NODE))) as Node3D
	if visual == null:
		return Vector3(INF, INF, INF)
	return block.global_transform * visual.position


func _newest_block() -> Block:
	var newest: Block = null
	for candidate: Block in Match.registry().all_blocks():
		if newest == null or candidate.net_id > newest.net_id:
			newest = candidate
	return newest


@rpc("authority", "call_remote", "reliable")
func net_expect(gift: StringName, held_pivot: Vector3) -> void:
	_expected = held_pivot
	_expected_gift = gift
	print("%s client expecting %s pivot=%s" % [TAG, gift, held_pivot])


## Client: the spawn transform at the moment the body is built (before any snapshot).
func _on_client_block_placed(block: RigidBody3D, _shape_id: StringName) -> void:
	var body: Block = block as Block
	if body == null or Net.mode() == Net.Mode.HOST:
		return
	var pivot: Vector3 = _pivot_of(body)
	var distance: float = pivot.distance_to(_expected)
	print("%s client spawn pivot=%s expected=%s dist=%.3f" % [TAG, pivot, _expected, distance])
	rpc_id(Net.HOST_PEER_ID, &"net_report", distance, _glob_only_look_ok(body))


## Paintball: the client body shows only the glob and a slingshot copy was left beside it; any
## other gift has no such requirement.
func _glob_only_look_ok(body: Block) -> bool:
	if _expected_gift != &"paintball":
		return true
	var visual: Node = body.get_node_or_null(NodePath(String(BlockFactory.GIFT_VISUAL_NODE)))
	if visual == null:
		return false
	for mesh: Node in visual.find_children("*", "MeshInstance3D", true, false):
		if (mesh as MeshInstance3D).visible and not mesh.name.begins_with("Blob"):
			return false
	var sling: Node = body.get_parent().get_node_or_null(^"PaintballSling")
	print("%s client glob_only sling=%s" % [TAG, sling != null])
	return sling != null


@rpc("any_peer", "call_remote", "reliable")
func net_report(distance: float, look_ok: bool) -> void:
	_look_reports[_look_reports.size()] = look_ok
	_reports[_reports.size()] = distance


func _run_host() -> void:
	var connected: bool = await _until(func() -> bool: return Net.peer_ids().size() >= PEERS, CONNECT_TIMEOUT)
	if not connected:
		print("%s host result=FAIL reason=not_connected" % TAG)
		get_tree().quit(1)
		return
	var config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.disc_size_step = 1
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
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	var pass_all: bool = playing
	var index: int = 0
	for gift: StringName in GIFTS:
		Match._gifts._ensure_capacity(0)
		Match._gifts._held_specials[0] = gift
		Match._feed._held_is_gift[0] = true
		var shape: BlockShape = Match.held_shape(0)
		var home: Vector2 = Match.slot(0).home_position
		var pose: Vector3 = field.to_global(Vector3(home.x, POSE_HEIGHT_M, home.y))
		var held_pivot: Vector3 = pose + BlockFactory.gift_cell_center(shape, tuning)
		rpc(&"net_expect", gift, held_pivot)
		await _wait(ARM_WAIT_S)
		var reason: StringName = Match.request_throw(0, pose, 0, Quaternion.IDENTITY, AIMS[index].normalized())
		var block: Block = _newest_block() if reason == PlacementRules.REASON_OK else null
		var host_dist: float = _pivot_of(block).distance_to(held_pivot) if block != null else UNSET_M
		var got: bool = await _until(func() -> bool: return _reports.size() > index, REPORT_TIMEOUT)
		var client_dist: float = float(_reports.get(index, UNSET_M))
		var ok: bool = reason == PlacementRules.REASON_OK and got and host_dist < TOLERANCE_M and client_dist < TOLERANCE_M and bool(_look_reports.get(index, false))
		print("%s host gift=%s reason=%s host_dist_m=%.3f client_dist_m=%.3f tolerance_m=%.2f ok=%s" % [
			TAG, gift, reason, host_dist, client_dist, TOLERANCE_M, ok])
		pass_all = pass_all and ok
		index += 1
		await _wait(PRE_FIRE_WAIT_S)
	print("%s host result=%s" % [TAG, "PASS" if pass_all else "FAIL"])
	await _wait(QUIT_DELAY_S)
	get_tree().quit(0 if pass_all else 1)


func _run_client() -> void:
	var field: Field = _build_world()
	Match._lifecycle.set_loading_gate_forced(true)
	Events.block_placed.connect(_on_client_block_placed)
	var started: bool = await _until(func() -> bool: return Match.state() != Match.State.LOBBY, CONNECT_TIMEOUT + GATE_TIMEOUT)
	if not started:
		print("%s client result=FAIL reason=no_match_start" % TAG)
		get_tree().quit(2)
		return
	SnapshotSync.set_disk(field)
	SnapshotSync.begin_match(Match.registry(), Match.config.map_def())
	Net.request_loading_ready()
	await _until(func() -> bool: return Match.state() == Match.State.PLAYING, GATE_TIMEOUT)
	await _until(func() -> bool: return not Net.is_client(), CLIENT_LIFETIME_S)
	get_tree().quit(0)
