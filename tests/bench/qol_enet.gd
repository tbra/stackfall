extends Node
## Bontago-1pi.18.1: host + client over real ENet. The host starts a match with
## the QoL backlog and goal-radius toggles on; the client prints the values it
## received and its mirrored backlog count after one timer expiry.
## Run via tools/run_qol_enet.ps1. Host: --headless-host --expect-peers=2.

const CONNECT_TIMEOUT: float = 20.0
const WATCH_EXTRA_S: float = 1.5

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


func _run_host() -> void:
	var deadline: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT * 1000.0)
	while Net.peer_ids().size() < 1 and Time.get_ticks_msec() < deadline:
		await _wait(0.1)
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = MatchConfig.BLOCK_TIMER_MIN
	config.qol = QolExperiments.new()
	config.qol.backlog_enabled = true
	config.qol.backlog_max = 3
	config.qol.goal_radius_enabled = true
	config.qol.goal_radius_multiplier = 2.5
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
	await _wait(Match.COUNTDOWN_SECONDS + MatchConfig.BLOCK_TIMER_MIN + WATCH_EXTRA_S + 1.0)
	print("QOLENET host backlog0=%d backlog1=%d" % [Match.qol_backlog_count(0), Match.qol_backlog_count(1)])
	get_tree().quit(0)


func _run_client() -> void:
	var deadline: int = Time.get_ticks_msec() + int((CONNECT_TIMEOUT + 10.0) * 1000.0)
	while Match.state() != Match.State.PLAYING and Time.get_ticks_msec() < deadline:
		await _wait(0.1)
	if Match.state() != Match.State.PLAYING or Match.config.qol == null:
		print("QOLENET result=FAIL reason=no_playing_or_no_qol")
		get_tree().quit(2)
		return
	var qol: QolExperiments = Match.config.qol
	await _wait(MatchConfig.BLOCK_TIMER_MIN + WATCH_EXTRA_S)
	var ok: bool = qol.backlog_enabled and qol.backlog_max == 3 and qol.goal_radius_enabled \
		and is_equal_approx(qol.goal_radius_multiplier, 2.5) and not qol.timer_pause_enabled \
		and Match.qol_backlog_count(0) == 1 and Match.qol_backlog_count(1) == 1
	print("QOLENET client backlog_enabled=%s max=%d goal_x=%.2f pause=%s mirror0=%d mirror1=%d" % [
		qol.backlog_enabled, qol.backlog_max, qol.goal_radius_multiplier, qol.timer_pause_enabled,
		Match.qol_backlog_count(0), Match.qol_backlog_count(1)])
	print("QOLENET result=%s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0)
