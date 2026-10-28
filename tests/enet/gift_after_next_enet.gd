extends Node
## host + client over real ENet with the default after-next rule.
## The host claims a gift for the client's seat; the client must see it staged as the block AFTER next
## (the next piece stays ordinary), then next, then held, as the host issues two blocks. Run via
## tools/run_gift_after_next_enet.ps1. Host: --headless-host --expect-peers=2.

## Net.peer_ids() counts the host too: one host + one client.
const HOST_AND_CLIENT_PEERS: int = 2
const CONNECT_TIMEOUT: float = 20.0
const STAGED_SPECIAL: StringName = &"anvil"
const STEP_WAIT_S: float = 2.5

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
	var config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.disc_size_step = 1
	config.player_count = 2
	config.block_timer = MatchConfig.BLOCK_TIMER_MAX
	var field: Field = (load("res://game/field/Field.tscn") as PackedScene).instantiate() as Field
	field.map_def = config.map_def()
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
	var ordinary_next: StringName = Match.next_shape(1).id
	# A real claim (id >= 0): replicated gift events reject the sandbox's negative debug id.
	var gift_id: int = Match._gifts._next_gift_id
	Match._gifts._next_gift_id += 1
	Match._gifts._queue_claimed_special(1, STAGED_SPECIAL)
	Events.gift_claimed.emit(gift_id, 1, STAGED_SPECIAL)
	var drawn: StringName = Match.after_next_special(1)
	var staged_ok: bool = drawn != &"" and Match.next_special(1) == &"" and Match.next_shape(1).id == ordinary_next
	await _wait(STEP_WAIT_S)
	Match._feed._consume_and_refeed(1, true)
	await _wait(STEP_WAIT_S)
	var promoted_ok: bool = Match.next_special(1) == drawn
	Match._feed._consume_and_refeed(1, true)
	await _wait(STEP_WAIT_S)
	print("GANENET host drawn=%s staged_ok=%s promoted_ok=%s held=%s" % [drawn, staged_ok, promoted_ok, Match.held_special(1)])
	get_tree().quit(0)


func _run_client() -> void:
	var playing: bool = await _until(func() -> bool: return Match.state() == Match.State.PLAYING, CONNECT_TIMEOUT + 10.0)
	if not playing or Match.config.qol == null or not Match.config.qol.gift_after_next_in_force():
		print("GANENET result=FAIL reason=no_playing_or_after_next_off")
		get_tree().quit(2)
		return
	var slot_id: int = Net.local_slot()
	var staged: bool = await _until(func() -> bool: return Match.after_next_special(slot_id) != &"", 15.0)
	var gift_id: StringName = Match.after_next_special(slot_id)
	var next_plain: bool = Match.next_special(slot_id) == &"" and Match.held_special(slot_id) == &""
	var next_now: bool = await _until(func() -> bool: return Match.next_special(slot_id) == gift_id, 15.0)
	var staged_cleared: bool = Match.after_next_special(slot_id) == &""
	var held: bool = await _until(func() -> bool: return Match.held_special(slot_id) == gift_id, 15.0)
	var ok: bool = staged and next_plain and next_now and staged_cleared and held
	print("GANENET client slot=%d staged=%s next_plain=%s next_after_issue=%s staged_cleared=%s held_after_two=%s" % [
		slot_id, staged, next_plain, next_now, staged_cleared, held])
	print("GANENET result=%s" % ("PASS" if ok else "FAIL"))
	await _wait(1.0)
	get_tree().quit(0)
