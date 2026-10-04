extends Node
## Bontago-1pi.69: host + client over real ENet. The host records a height for
## slot 1; the client's live scoreboard payload (MatchNet EVENT_LIVE_SCORES) must
## show the same stats. Run via tools/run_live_scores_enet.ps1. Host: --headless-host --expect-peers=2.

## Net.peer_ids() counts the host too: one host + one client (Bontago-1pi.18.8).
const HOST_AND_CLIENT_PEERS: int = 2
const CONNECT_TIMEOUT: float = 20.0
const SAMPLE_HEIGHT: float = 4.0

var _match_net: Node


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


func _until(condition: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _wait(0.1)
	return condition.call()


func _run_host() -> void:
	await _until(func() -> bool: return Net.peer_ids().size() >= HOST_AND_CLIENT_PEERS, CONNECT_TIMEOUT)
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
	await _until(func() -> bool: return Match.state() == Match.State.PLAYING, 15.0)
	await _wait(1.0)
	Match.stats().record_height(1, SAMPLE_HEIGHT)
	await _wait(3.0)
	print("LSENET host rows=%d" % (Match.stats().live_payload()["rows"] as Array).size())
	get_tree().quit(0)


func _run_client() -> void:
	var playing: bool = await _until(func() -> bool: return Match.state() == Match.State.PLAYING, CONNECT_TIMEOUT + 10.0)
	var matched: bool = await _until(func() -> bool: return _client_sees_height(), 15.0)
	var live: Dictionary = Match.stats().live_payload()
	print("LSENET client playing=%s rows=%d live=%s height_matches=%s" % [
		playing, (live.get("rows", []) as Array).size(), live.get("live", false), matched])
	print("LSENET result=%s" % ("PASS" if playing and matched else "FAIL"))
	await _wait(1.0)
	get_tree().quit(0)


func _client_sees_height() -> bool:
	for row: Variant in Match.stats().live_payload().get("rows", []) as Array:
		if int((row as Dictionary)["slot_id"]) == 1:
			return absf(float((row as Dictionary)["height"]) - SAMPLE_HEIGHT) < 0.01
	return false
