extends Node
## /.186: host + one lagged client over real ENet. Elimination, 3
## seats (host, client, one bot). The host opens a hole under the client's home
## flag; the client must see the claim progress rise (goal_capture_progress),
## survive until the claim time, then be eliminated: the held/next block are
## cleared and the HUD shows the red banner. Run via tools/run_elim_claim_enet.ps1.

const CONNECT_TIMEOUT: float = 20.0
const JOIN_SETTLE_S: float = 2.0
const CLIENT_SLOT: int = 1
## Short claim time so the run stays quick (the real default is TerritoryTuning.capture_hold).
const TEST_CLAIM_S: float = 4.0
const OBSERVE_S: float = 14.0

var _match_net: Node
var _max_progress: float = 0.0
var _progress_before_out: float = 0.0
var _out_seen: bool = false
var _hud: HUD = null


func _ready() -> void:
	if not Net.apply_command_line():
		get_tree().quit(2)
		return
	_match_net = get_node(^"/root/MatchNet")
	# Both peers: the client's ring extrapolation reads the same hold time.
	Match._territory_tuning.capture_hold = TEST_CLAIM_S
	Events.goal_capture_progress.connect(_on_progress)
	Events.player_eliminated.connect(_on_out)
	if Net.mode() == Net.Mode.HOST:
		await _run_host()
	else:
		await _run_client()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _role() -> String:
	return "host" if Net.mode() == Net.Mode.HOST else "client"


func _on_progress(_team_id: int, progress: float) -> void:
	if not _out_seen:
		_max_progress = maxf(_max_progress, progress)


func _on_out(slot_id: int, _team_id: int) -> void:
	if slot_id == CLIENT_SLOT:
		_out_seen = true
		_progress_before_out = _max_progress
		print("ELIMENET %s eliminated slot=%d by=%d progress_seen=%.2f" % [_role(), slot_id, Match.eliminated_by(slot_id), _max_progress])


func _run_host() -> void:
	var deadline: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT * 1000.0)
	while Net.peer_ids().size() < 1 and Time.get_ticks_msec() < deadline:
		await _wait(0.1)
	await _wait(JOIN_SETTLE_S)
	var config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.disc_size_step = 1
	config.player_count = 3
	config.ai_count = 1
	config.game_mode = MatchConfig.GameMode.ELIMINATION
	config.hole_mode = MatchConfig.HoleMode.PERMANENT
	config.sudden_death = false
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
	while Match.state() != Match.State.PLAYING:
		await _wait(0.1)
	await _wait(1.0)
	var grid: CellGrid = Match.cell_grid()
	var coords: Vector2i = grid.world_to_cell(Match.slot(CLIENT_SLOT).home_position)
	Match._territory._raster.force_hole_cell(coords.x, coords.y, 1.0, true)
	print("ELIMENET host hole_opened")
	# A live board keeps changing (territory packets only go out on a raster change,
	# and carry the claim progress): punch an unrelated hole every half second.
	for i: int in range(int(TEST_CLAIM_S)):
		await _wait(0.5)
		Match._territory._raster.force_hole_cell(coords.x + 6 + i, coords.y + 6, 1.0, true)
		if i == 1:
			print("ELIMENET host mid_claim_probe progress=%.2f" % Match._territory._objective.capture_progress())
	print("ELIMENET host mid_claim alive=%s progress=%.2f" % [Match.slot(CLIENT_SLOT).home_flag_alive, Match._territory._objective.capture_progress()])
	await _wait(OBSERVE_S - TEST_CLAIM_S * 0.5 - 2.0)
	print("ELIMENET host final alive=%s held_null=%s state=%d" % [Match.slot(CLIENT_SLOT).home_flag_alive, Match.held_shape(CLIENT_SLOT) == null, Match.state()])
	get_tree().quit(0)


func _run_client() -> void:
	var deadline: int = Time.get_ticks_msec() + int((CONNECT_TIMEOUT + 10.0) * 1000.0)
	while Match.state() != Match.State.PLAYING and Time.get_ticks_msec() < deadline:
		await _wait(0.05)
	if Match.state() != Match.State.PLAYING:
		print("ELIMENET client result=FAIL reason=never_playing")
		get_tree().quit(2)
		return
	_hud = (load("res://ui/hud/HUD.tscn") as PackedScene).instantiate() as HUD
	add_child(_hud)
	_hud.match_provider = Match
	_hud.set_local_slot(CLIENT_SLOT)
	print("ELIMENET client playing held=%s" % [Match.held_shape(CLIENT_SLOT) != null])
	var end_at: int = Time.get_ticks_msec() + int(OBSERVE_S * 1000.0)
	var ring_max: float = 0.0
	while Time.get_ticks_msec() < end_at and not _out_seen:
		await _wait(0.05)
		ring_max = maxf(ring_max, _hud._capture_progress)
	_progress_before_out = maxf(_progress_before_out, ring_max)
	await _wait(0.5)
	var text: String = _hud._eliminated_label.text if _hud._eliminated_label.visible else ""
	print("ELIMENET client ring_max=%.2f event_max=%.2f" % [ring_max, _max_progress])
	print("ELIMENET client out=%s progress_before_out=%.2f held_null=%s next_null=%s banner='%s'" % [_out_seen, _progress_before_out, Match.held_shape(CLIENT_SLOT) == null, Match.next_shape(CLIENT_SLOT) == null, text])
	var ok: bool = _out_seen and _progress_before_out > 0.3 and Match.held_shape(CLIENT_SLOT) == null and text.begins_with("Eliminated")
	print("ELIMENET client result=%s" % ["PASS" if ok else "FAIL"])
	get_tree().quit(0)
