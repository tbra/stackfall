extends Node
## Glue fusion WP5 (Bontago-1pi.85.74.6): host + client (+ late joiner) over real ENet. The host stacks three
## blocks (the upper two glue-charged) so they fuse into one FusedBody, kicks it, then dissolves one member
## (hole path) and finally removes the rest (kill-plane path). Clients check: coat on every member, members
## rigid (pair-distance spread < MOVING_TOL_M while moving, < REST_TOL_M at rest), the dissolve despawns only
## the touched member, the kill removes all, no stray body. Run via tools/run_glue_fuse_enet.ps1.
## Host: --headless-host --expect-peers=2. Late joiner: pass `--late` after `--`.

const CONNECT_TIMEOUT: float = 25.0
const POLL_S: float = 0.02
const MEMBERS: int = 3
const SETTLE_TIMEOUT_S: float = 12.0
const KICK_IMPULSE: Vector3 = Vector3(6.0, 2.0, 1.5)
const KICK_TORQUE: Vector3 = Vector3(2.0, 1.0, 3.0)
const MOVING_S: float = 3.0
const REST_S: float = 4.0
const MOVING_TOL_M: float = 0.01
const REST_TOL_M: float = 0.005
const MOVE_EPS_M: float = 0.002
const LATE_WAIT_S: float = 45.0
const LATE_SAMPLE_S: float = 2.0
const LATE_SETTLE_S: float = 12.0
const DISSOLVE_WAIT_S: float = 4.0
const FINAL_WAIT_S: float = 4.0
const MIN_SAMPLES: int = 4

var _late: bool = false


func _ready() -> void:
	_late = OS.get_cmdline_user_args().has("--late")
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
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _wait(POLL_S)
	return condition.call()


func _build_world() -> Array:
	var field: Field = (load("res://game/Field.tscn") as PackedScene).instantiate() as Field
	field.map_def = MapDef.for_size(MapDef.MapSize.SMALL)
	add_child(field)
	var blocks: Node3D = Node3D.new()
	add_child(blocks)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child(registry)
	Match.register_world(field, registry, blocks)
	return [field, blocks]


func _blocks(root: Node3D) -> Array[Block]:
	var found: Array[Block] = []
	for child: Node in root.get_children():
		var block: Block = child as Block
		if block != null and not block.is_queued_for_deletion() and not (block is FusedBody):
			found.append(block)
	return found


func _drop(blocks: Node3D, expected: int) -> bool:
	var reason: StringName = &""
	for _attempt: int in range(40):
		reason = Match.request_place(1, Match.default_ghost_origin(1), 0, Quaternion.IDENTITY, true, Match.feed_seq(1))
		if reason == &"" or _blocks(blocks).size() >= expected:
			break
		await _wait(0.5)
	print("GFUSE host drop expected=%d reason=[%s] blocks=%d" % [expected, reason, _blocks(blocks).size()])
	return await _until(func() -> bool:
		var list: Array[Block] = _blocks(blocks)
		return list.size() >= expected and list[list.size() - 1].net_sleeping(), SETTLE_TIMEOUT_S)


func _run_host() -> void:
	await _until(func() -> bool: return Net.peer_ids().size() >= 2, CONNECT_TIMEOUT)
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = MatchConfig.BLOCK_TIMER_MAX
	var world: Array = _build_world()
	var field: Field = world[0] as Field
	var blocks: Node3D = world[1] as Node3D
	Match._lifecycle.set_loading_gate_forced(true)
	Match.start_match(config)
	get_node(^"/root/MatchNet").call(&"replicate_match_start", Match.config)
	field.place_flags(Match.config.player_count, Match.config.player_colors, Match.config.goal_flag_count)
	SnapshotSync.set_disk(field)
	SnapshotSync.begin_match(Match.registry(), Match.config.map_def())
	Net.request_loading_ready()
	await _until(func() -> bool: return Match.state() == Match.State.PLAYING, 15.0)
	await _wait(1.0)
	await _drop(blocks, 1)
	for step: int in range(1, MEMBERS):
		Match.grant_glue_drops(1, 1)
		await _drop(blocks, step + 1)
		await _wait(0.5)
	var list: Array[Block] = _blocks(blocks)
	var carrier: FusedBody = list[0].fused_carrier() as FusedBody
	var fused: int = 0
	for block: Block in list:
		if carrier != null and block.fused_carrier() == carrier:
			fused += 1
	print("GFUSE host fused=%d of %d carrier=%s" % [fused, list.size(), carrier != null])
	if carrier == null:
		await _wait(LATE_WAIT_S)
		get_tree().quit(0)
		return
	carrier.apply_central_impulse(KICK_IMPULSE * carrier.mass)
	carrier.apply_torque_impulse(KICK_TORQUE * carrier.mass)
	for _tick: int in range(int((MOVING_S + REST_S) * 2.0)):
		await _wait(0.5)
		print("GFUSE host d01=%.4f d02=%.4f p0=%s" % [list[0].global_position.distance_to(list[1].global_position), list[0].global_position.distance_to(list[2].global_position), list[0].global_position])
	print("GFUSE host at_rest_waiting_for_late_peer")
	await _until(func() -> bool: return Net.peer_ids().size() >= 3, LATE_WAIT_S)
	await _wait(LATE_SAMPLE_S + LATE_SETTLE_S)
	var victim: Block = carrier.members[carrier.members.size() - 1]
	print("GFUSE host dissolve net_id=%d" % victim.net_id)
	carrier.remove_member(victim, &"hole")
	await _wait(DISSOLVE_WAIT_S)
	print("GFUSE host kill valid=%s members=%d" % [is_instance_valid(carrier), carrier.members.size() if is_instance_valid(carrier) else -1])
	if is_instance_valid(carrier):
		carrier.remove_all_members(&"kill_plane")
	print("GFUSE host after_kill carrier_valid=%s" % is_instance_valid(carrier))
	await _wait(FINAL_WAIT_S)
	for stray: Block in _blocks(blocks):
		print("GFUSE host stray net_id=%d fused=%s queued=%s" % [stray.net_id, stray.is_fused_member(), stray.is_queued_for_deletion()])
	print("GFUSE host strays=%d" % _blocks(blocks).size())
	get_tree().quit(0)


func _spread(values: Array[float]) -> float:
	if values.is_empty():
		return INF
	return values.max() - values.min()


func _run_client() -> void:
	var world: Array = _build_world()
	var blocks: Node3D = world[1] as Node3D
	Match._lifecycle.set_loading_gate_forced(true)
	await _until(func() -> bool: return Match.state() != Match.State.LOBBY, CONNECT_TIMEOUT + 20.0)
	SnapshotSync.set_disk(world[0] as Field)
	SnapshotSync.begin_match(Match.registry(), Match.config.map_def())
	Net.request_loading_ready()
	var playing: bool = await _until(func() -> bool: return Match.state() == Match.State.PLAYING, CONNECT_TIMEOUT + 20.0)
	if not playing:
		print("GFUSE result=FAIL reason=not_playing")
		get_tree().quit(2)
		return
	var tag: String = "late" if _late else "client"
	var all_coated: Callable = func() -> bool:
		var members: Array[Block] = _blocks(blocks)
		if members.size() < MEMBERS:
			return false
		for block: Block in members:
			if not HoneyCoat.is_coated(block):
				return false
		return true
	var coated: bool = await _until(all_coated, 80.0)
	print("GFUSE %s coated_all=%s" % [tag, coated])
	var failed: PackedStringArray = PackedStringArray()
	if not coated:
		failed.append("coat")
	var list: Array[Block] = _blocks(blocks)
	var moving: Array[float] = []
	var rest: Array[float] = []
	var moving2: Array[float] = []
	var rest2: Array[float] = []
	if list.size() >= MEMBERS:
		var window_s: float = LATE_SAMPLE_S if _late else MOVING_S + REST_S
		var sample_until: int = Time.get_ticks_msec() + int(window_s * 1000.0)
		var rest_start: int = Time.get_ticks_msec() + int(MOVING_S * 1000.0)
		var last: Array[Vector3] = []
		for block: Block in list:
			last.append(block.global_position)
		while Time.get_ticks_msec() < sample_until:
			await _wait(POLL_S)
			var moved: bool = false
			for index: int in range(list.size()):
				var pos: Vector3 = list[index].global_position
				if pos.distance_to(last[index]) > MOVE_EPS_M:
					moved = true
				last[index] = pos
			if Engine.get_physics_frames() % 30 == 0:
				print("GFUSE %s d01=%.4f d02=%.4f p0=%s" % [tag, list[0].global_position.distance_to(list[1].global_position), list[0].global_position.distance_to(list[2].global_position), list[0].global_position])
			var d01: float = list[0].global_position.distance_to(list[1].global_position)
			var d02: float = list[0].global_position.distance_to(list[2].global_position)
			if _late or Time.get_ticks_msec() >= rest_start:
				rest.append(d01)
				rest2.append(d02)
			elif moved:
				moving.append(d01)
				moving2.append(d02)
		print("GFUSE %s moving_n=%d moving_spread=%.4f rest_n=%d rest_spread=%.4f" % [tag, moving.size(), maxf(_spread(moving), _spread(moving2)), rest.size(), maxf(_spread(rest), _spread(rest2))])
		if not _late and (moving.size() < MIN_SAMPLES or maxf(_spread(moving), _spread(moving2)) >= MOVING_TOL_M):
			failed.append("moving_rigidity")
		if rest.size() < MIN_SAMPLES or maxf(_spread(rest), _spread(rest2)) >= REST_TOL_M:
			failed.append("rest_rigidity")
	else:
		failed.append("members_missing")
	# Hole dissolve: exactly one member gone, the rest still present.
	var before: int = _blocks(blocks).size()
	var dissolved: bool = await _until(func() -> bool: return _blocks(blocks).size() == before - 1, 60.0)
	var after: int = _blocks(blocks).size()
	print("GFUSE %s dissolve before=%d after=%d ok=%s" % [tag, before, after, dissolved])
	if not dissolved or after != MEMBERS - 1:
		failed.append("dissolve")
	var cleared: bool = await _until(func() -> bool: return _blocks(blocks).is_empty(), 30.0)
	await _wait(1.0)
	var strays: int = blocks.get_child_count()
	print("GFUSE %s kill cleared=%s strays=%d" % [tag, cleared, strays])
	if not cleared or strays != 0:
		failed.append("kill")
	print("GFUSE result=%s %s" % ["PASS" if failed.is_empty() else "FAIL", ",".join(failed)])
	await _wait(0.5)
	get_tree().quit(0)
