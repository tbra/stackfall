extends Node
## Bontago-1pi.18.2: host + client over real ENet with the QoL gift slot on.
## The host slots a gift for the client's seat; the client sees it replicate,
## sends the use_gift_slot intent, and the host validates it. Run via
## tools/run_gift_slot_enet.ps1. Host: --headless-host --expect-peers=2.

## Net.peer_ids() counts the host too: one host + one client (Bontago-1pi.18.8).
const HOST_AND_CLIENT_PEERS: int = 2
const CONNECT_TIMEOUT: float = 20.0
const GIFT_ID: StringName = &"anvil"

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
	config.qol = QolExperiments.new()
	config.qol.gift_slot_enabled = true
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
	Match._gifts._queue_claimed_special(1, GIFT_ID)
	var used: bool = await _until(func() -> bool: return Match.held_special(1) == GIFT_ID, 15.0)
	print("GSENET host slotted_then_used=%s held=%s slot_left=%d next_queue=%s" % [
		used, Match.held_special(1), Match.gift_slot_count(1), Match.next_special(1)])
	await _wait(1.0)
	get_tree().quit(0)


func _run_client() -> void:
	var playing: bool = await _until(func() -> bool: return Match.state() == Match.State.PLAYING, CONNECT_TIMEOUT + 10.0)
	if not playing or Match.config.qol == null or not Match.config.qol.gift_slot_enabled:
		print("GSENET result=FAIL reason=no_playing_or_toggle_missing")
		get_tree().quit(2)
		return
	var slot_id: int = Net.local_slot()
	var seen: bool = await _until(func() -> bool: return Match.gift_slot_head(slot_id) == GIFT_ID, 15.0)
	var queue_untouched: bool = Match.next_special(slot_id) == &"" and Match.held_special(slot_id) == &""
	var sent: bool = bool(_match_net.call(&"submit_use_gift_slot", slot_id))
	var held: bool = await _until(func() -> bool: return Match.held_special(slot_id) == GIFT_ID, 15.0)
	var emptied: bool = Match.gift_slot_head(slot_id) == &""
	var ok: bool = seen and queue_untouched and sent and held and emptied
	print("GSENET client slot=%d replicated=%s queue_untouched=%s sent=%s held_after_use=%s slot_emptied=%s" % [
		slot_id, seen, queue_untouched, sent, held, emptied])
	print("GSENET result=%s" % ("PASS" if ok else "FAIL"))
	await _wait(1.0)
	get_tree().quit(0)
