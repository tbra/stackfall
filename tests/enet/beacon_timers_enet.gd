extends Node
## /189: host + client over real ENet. The host fakes beacon ownership
## (team 0 on both goal cells) plus, per --mode, a Classic capture progress or a CTF
## mode state with two beacons held; the client's own Field beacon labels must follow.
## Run via tools/run_beacon_timers_enet.ps1. Host: --headless-host --expect-peers=2 --mode=classic|ctf.

const HOST_AND_CLIENT_PEERS: int = 2
const CONNECT_TIMEOUT: float = 20.0
const CAPTURE_PROGRESS: float = 0.5
const HOST_FORCE_STEPS: int = 80
const HOST_FORCE_STEP_S: float = 0.1
const MODE_ARG: String = "--mode="

var _match_net: Node
var _field: Field
var _ctf: bool = false


func _ready() -> void:
	if not Net.apply_command_line():
		get_tree().quit(2)
		return
	_match_net = get_node(^"/root/MatchNet")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(MODE_ARG):
			_ctf = arg.trim_prefix(MODE_ARG) == "ctf"
	_field = (load("res://game/field/Field.tscn") as PackedScene).instantiate() as Field
	_field.map_def = MapDef.base().scaled(0.75)
	add_child(_field)
	var blocks: Node3D = Node3D.new()
	add_child(blocks)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child(registry)
	Match.register_world(_field, registry, blocks)
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
	config.hot_seat = false
	config.goal_flag_count = 2
	if _ctf:
		config.game_mode = MatchConfig.GameMode.CAPTURE_THE_FLAG
	Match.start_match(config)
	_match_net.call(&"replicate_match_start", Match.config)
	_field.place_flags(Match.config.player_count, Match.config.player_colors, Match.config.goal_flag_count)
	await _until(func() -> bool: return Match.state() == Match.State.PLAYING, 15.0)
	await _wait(1.0)
	# The host's own solver keeps overwriting the fake state, so re-assert it for a while.
	for _i: int in range(HOST_FORCE_STEPS):
		_force_host_state()
		await _wait(HOST_FORCE_STEP_S)
	print("BTENET host mode=%s timer=%s chip=%s" % [
		"ctf" if _ctf else "classic", _field.goal_flags()[0].timer_text(), _field.goal_flags()[0].multiplier_chip_text()])
	get_tree().quit(0)


func _force_host_state() -> void:
	var raster: TerritoryRaster = Match.raster()
	for flag: GoalFlag in _field.goal_flags():
		var cell: Vector2i = raster.grid().world_to_cell(Vector2(flag.position.x, flag.position.z))
		raster._team_ids[raster.grid().cell_index(cell.x, cell.y)] = 0
	raster._mark_changed()
	if _ctf:
		var objective: CaptureFlagObjective = Match._territory._objective as CaptureFlagObjective
		objective._held_counts[0] = 2
		objective._state_dirty = true
		Match._lifecycle.publish_mode_state_if_changed()
	else:
		Events.goal_capture_progress.emit(0, CAPTURE_PROGRESS)
		_match_net.set(&"_capture_team", 0)
		_match_net.set(&"_capture_progress", CAPTURE_PROGRESS)
	Events.territory_replicated.emit(raster)


func _run_client() -> void:
	var playing: bool = await _until(func() -> bool: return Match.state() == Match.State.PLAYING, CONNECT_TIMEOUT + 10.0)
	_field.place_flags(Match.config.player_count, Match.config.player_colors, Match.config.goal_flag_count)
	var seen: bool = await _until(_labels_follow_host, 20.0)
	var flag: GoalFlag = _field.goal_flags()[0]
	print("BTENET client mode=%s playing=%s timer=%s chip=%s ctrl=%d" % [
		"ctf" if _ctf else "classic", playing, flag.timer_text(), flag.multiplier_chip_text(), flag.control()])
	print("BTENET result=%s" % ("PASS" if playing and seen else "FAIL"))
	await _wait(1.0)
	get_tree().quit(0)


func _labels_follow_host() -> bool:
	var flags: Array[GoalFlag] = _field.goal_flags()
	if flags.is_empty():
		return false
	for flag: GoalFlag in flags:
		if _ctf:
			if flag.timer_text().is_empty() or flag.multiplier_chip_text() != "x2":
				return false
		else:
			# Half of the shared hold left (the client extrapolates a little), never empty.
			if flag.timer_text().is_empty():
				return false
	return true
