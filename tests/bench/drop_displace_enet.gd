extends Node
## Bontago-1pi.14 round 3: owner scenario over real ENet with simulated lag.
## The client releases block A, then releases the next piece at the SAME cursor
## spot one beat after the interval unlocks it -- before A's replicated pose
## could have reached the client's ghost. The host prints how far A moved
## after B spawned. Run via tools/run_drop_displace_enet.ps1 (3 min deadline).
## Host: --headless-host --expect-peers=2 ; client: --join=127.0.0.1:PORT --sim-lag=N

const PLACE_HEIGHT: float = 0.5
const FIRST_RELEASE_DELAY: float = 0.5
const SECOND_RELEASE_DELAY: float = 3.4
const WATCH_SECONDS: float = 3.0
const CONNECT_TIMEOUT: float = 20.0
const CLIENT_SLOT: int = 1

var _match_net: Node
var _blocks: Array[Block] = []
var _before: Transform3D
var _worst: float = 0.0
var _worst_rot: float = 0.0


func _ready() -> void:
	if not Net.apply_command_line():
		get_tree().quit(2)
		return
	_match_net = get_node(^"/root/MatchNet")
	if Net.mode() == Net.Mode.HOST:
		await _run_host()
	else:
		await _run_client()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run_host() -> void:
	var deadline: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT * 1000.0)
	while Net.peer_ids().size() < 1 and Time.get_ticks_msec() < deadline:
		await _wait(0.1)
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = MatchConfig.BLOCK_TIMER_MIN
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
	_match_net.call(&"replicate_match_start", Match.config)
	field.place_flags(Match.config.player_count, Match.config.player_colors, Match.config.goal_flag_count)
	Events.block_placed.connect(_on_block_placed)
	await _wait(Match.COUNTDOWN_SECONDS + FIRST_RELEASE_DELAY + SECOND_RELEASE_DELAY + 1.0 + WATCH_SECONDS)
	if _blocks.size() < 2:
		print("DROPDISP result=FAIL reason=second_block_not_spawned blocks=%d" % _blocks.size())
		get_tree().quit(1)
		return
	var worst: float = _worst
	var worst_rot: float = _worst_rot
	print("DROPDISP A_drift_m=%.4f A_drift_rad=%.4f blocks=%d (B spawn lift_y=%.3f)" % [
		worst, worst_rot, _blocks.size(), _blocks[1].global_position.y - _blocks[0].global_position.y
	])
	print("DROPDISP result=%s" % ("PASS" if worst < 0.05 else "DRIFT"))
	await _wait(1.0)
	get_tree().quit(0)


func _physics_process(_delta: float) -> void:
	if _blocks.size() < 2 or not is_instance_valid(_blocks[0]):
		return
	var now: Transform3D = _blocks[0].global_transform
	_worst = maxf(_worst, _before.origin.distance_to(now.origin))
	_worst_rot = maxf(_worst_rot, _before.basis.get_rotation_quaternion().angle_to(now.basis.get_rotation_quaternion()))


func _on_block_placed(block: RigidBody3D, _shape_id: StringName) -> void:
	var typed: Block = block as Block
	if typed != null and typed.owner_slot == CLIENT_SLOT:
		_blocks.append(typed)
		if _blocks.size() == 2:
			_before = _blocks[0].global_transform
		print("DROPDISP spawn #%d at y=%.3f" % [_blocks.size(), typed.global_position.y])


func _run_client() -> void:
	var deadline: int = Time.get_ticks_msec() + int((CONNECT_TIMEOUT + 10.0) * 1000.0)
	while Match.state() != Match.State.PLAYING and Time.get_ticks_msec() < deadline:
		await _wait(0.1)
	if Match.state() != Match.State.PLAYING:
		get_tree().quit(2)
		return
	var home: Vector2 = Match.slot(CLIENT_SLOT).home_position
	var origin: Vector3 = Vector3(home.x, PLACE_HEIGHT, home.y)
	await _wait(FIRST_RELEASE_DELAY)
	_match_net.call(&"submit_place", CLIENT_SLOT, origin, 0, Quaternion.IDENTITY, false, Match.feed_seq(CLIENT_SLOT))
	await _wait(SECOND_RELEASE_DELAY)
	# The client's view of A is stale (replication lag), so its ghost sits where A
	# came to rest: the second pose is A's resting pose (--b-pose=x,y,z, measured
	# from a dry run), i.e. the pose interpenetrates A.
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--b-pose="):
			var parts: PackedStringArray = arg.substr(9).split(",")
			origin = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	_match_net.call(&"submit_place", CLIENT_SLOT, origin, 0, Quaternion.IDENTITY, false, Match.feed_seq(CLIENT_SLOT))
	await _wait(WATCH_SECONDS + 3.0)
	get_tree().quit(0)
