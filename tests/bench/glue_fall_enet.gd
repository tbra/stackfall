extends Node
## Bontago-1pi.85.72: host + client over real ENet. The host drops a glue-charged block; the client must
## see the honey coat on it (replicated EVENT_BLOCK_GLUED at spawn, not at first bond). Both processes print
## unix timestamps so the coat-vs-first-bond order can be read from the logs. Run via
## tools/run_glue_fall_enet.ps1. Host: --headless-host --expect-peers=2.

const HOST_AND_CLIENT_PEERS: int = 2
const CONNECT_TIMEOUT: float = 20.0
const OBSERVE_S: float = 8.0
const POLL_S: float = 0.02
const GLUE_CHARGES: int = 1

var _first_bond_time: float = 0.0


func _ready() -> void:
	if not Net.apply_command_line():
		get_tree().quit(2)
		return
	if Net.mode() == Net.Mode.HOST:
		await _run_host()
	else:
		await _run_client()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(condition: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _wait(POLL_S)
	return condition.call()


func _on_bond(_a: Node, _b: Node, formed: bool) -> void:
	if formed and _first_bond_time == 0.0:
		_first_bond_time = Time.get_unix_time_from_system()


func _run_host() -> void:
	await _until(func() -> bool: return Net.peer_ids().size() >= HOST_AND_CLIENT_PEERS, CONNECT_TIMEOUT)
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = MatchConfig.BLOCK_TIMER_MAX
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
	await _until(func() -> bool: return Match.state() == Match.State.PLAYING, 15.0)
	await _wait(1.0)
	Events.glue_bond_changed.connect(_on_bond)
	Match.grant_glue_drops(1, GLUE_CHARGES)
	var spawn_time: float = Time.get_unix_time_from_system()
	var reason: StringName = Match.request_place(1, Match.default_ghost_origin(1), 0, Quaternion.IDENTITY, true, Match.feed_seq(1))
	var host_block: Block = null
	for child: Node in blocks.get_children():
		host_block = child as Block
	var coated: bool = host_block != null and HoneyCoat.is_coated(host_block)
	print("GFENET host reason=[%s] coated_at_spawn=%s bonded_at_spawn=%s" % [reason, coated, _first_bond_time != 0.0])
	await _wait(OBSERVE_S)
	print("GFENET host spawn_t=%.3f first_bond_dt=%.3f" % [spawn_time, _first_bond_time - spawn_time])
	get_tree().quit(0)


func _run_client() -> void:
	# The client needs its own world so replicated spawns have a parent to land under.
	var field: Field = (load("res://game/Field.tscn") as PackedScene).instantiate() as Field
	field.map_def = MapDef.for_size(MapDef.MapSize.SMALL)
	add_child(field)
	var blocks: Node3D = Node3D.new()
	add_child(blocks)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child(registry)
	Match.register_world(field, registry, blocks)
	var playing: bool = await _until(func() -> bool: return Match.state() == Match.State.PLAYING, CONNECT_TIMEOUT + 10.0)
	if not playing:
		print("GFENET result=FAIL reason=not_playing")
		get_tree().quit(2)
		return
	var seen: Array[float] = [0.0]
	var found: bool = await _until(func() -> bool:
		var root: Node3D = Match.blocks_parent()
		if root == null:
			return false
		for child: Node in root.get_children():
			if child is Block and HoneyCoat.is_coated(child as Block):
				seen[0] = Time.get_unix_time_from_system()
				return true
		return false, CONNECT_TIMEOUT + OBSERVE_S)
	print("GFENET client coat_seen=%s t=%.3f" % [found, seen[0]])
	print("GFENET result=%s" % ("PASS" if found else "FAIL"))
	await _wait(1.0)
	get_tree().quit(0)
