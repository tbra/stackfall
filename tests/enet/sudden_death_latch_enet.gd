extends Node
## Sudden death over real ENet: host + one lagged client, Classic with two goal flags. The host
## enters sudden death, then claims goals through the real objective step: slot 0 latches goal 0,
## slot 1 latches goal 1 (split: nobody wins, slot 0 keeps its latch though its territory is gone),
## then slot 1 takes goal 0 as well and wins. The client must see the sudden-death clock count
## down, no stale capture ring, each later claim, the flip and the win. The host also checks the
## snapshot a late joiner would receive. Run via tools/run_sudden_death_latch_enet.ps1.

const CONNECT_TIMEOUT: float = 20.0
const JOIN_SETTLE_S: float = 2.0
const PHASE_S: float = 2.0
const OBSERVE_S: float = 25.0
const SD_SECONDS: int = 60
const ENTER_SD_AFTER_S: float = 2.0
const CHAIN_RADIUS: float = 5.0
const CHAIN_SPACING: float = 3.0
const PAINT_DELTA: float = 0.05
const NO_TEAM: int = -1
const GOALS: int = 2

var _match_net: Node
## Client timeline: (latch of goal 0, latch of goal 1, round_left) per mode-state message.
var _timeline: Array[Vector3] = []
var _won: int = NO_TEAM
var _ring_after_sd: float = 0.0
var _next_circle_id: int = 1000


func _ready() -> void:
	if not Net.apply_command_line():
		get_tree().quit(2)
		return
	_match_net = get_node(^"/root/MatchNet")
	Events.mode_state_changed.connect(_on_mode_state)
	Events.goal_capture_progress.connect(_on_progress)
	Events.match_won.connect(_on_won)
	if Net.mode() == Net.Mode.HOST:
		await _run_host()
	else:
		await _run_client()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _on_mode_state(state: Dictionary) -> void:
	_timeline.append(Vector3(
		float(BeaconTimerText.latched_in_state(state, 0)),
		float(BeaconTimerText.latched_in_state(state, 1)),
		float(state.get("round_left", -1.0))))


func _on_progress(_team: int, progress: float) -> void:
	if Match.sudden_death_active():
		_ring_after_sd = maxf(_ring_after_sd, progress)


func _on_won(team: int) -> void:
	_won = team


# --- host ---------------------------------------------------------------------

func _run_host() -> void:
	var deadline: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT * 1000.0)
	while Net.peer_ids().size() < 1 and Time.get_ticks_msec() < deadline:
		await _wait(0.1)
	await _wait(JOIN_SETTLE_S)
	var config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.player_count = 2
	config.ai_count = 0
	config.game_mode = MatchConfig.GameMode.CLASSIC
	config.hole_mode = MatchConfig.HoleMode.TEMPORARY
	config.goal_flag_count = GOALS
	config.match_timer_minutes = 1
	config.sudden_death = true
	config.sudden_death_seconds = SD_SECONDS
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
	await _wait(ENTER_SD_AFTER_S)
	Match._lifecycle._match_timer_left = ENTER_SD_AFTER_S
	while Match.state() != Match.State.SUDDEN_DEATH:
		await _wait(0.1)
	print("SDLATCH host sudden_death clock=%.1f" % Match.match_timer_left())
	await _wait(PHASE_S)

	var goals: PackedVector2Array = PlayerSlot.goal_positions_for(GOALS, Match.config.map_def())
	# Phase A: slot 0 holds goal 0 only.
	_paint([_chain(0, [goals[0]]), _chain(1, [])])
	await _wait(PHASE_S)
	# Phase B: slot 1 holds goal 1 only; slot 0's territory is gone but its latch stays.
	_paint([_chain(0, []), _chain(1, [goals[1]])])
	var split_state: int = Match.state()
	var snapshot: Dictionary = Match.mode_state_snapshot()
	var snap_ok: bool = BeaconTimerText.latched_in_state(snapshot, 0) == Match.slot(0).team_id \
		and BeaconTimerText.latched_in_state(snapshot, 1) == Match.slot(1).team_id
	await _wait(PHASE_S)
	# Phase C: slot 1 connects through both goals: it re-claims goal 0 and holds every latch.
	_paint([_chain(1, [goals[1], goals[0]])])
	await _wait(PHASE_S)
	var ended: bool = Match.state() == Match.State.END
	var ok: bool = split_state == Match.State.SUDDEN_DEATH and snap_ok and ended and _won == Match.slot(1).team_id
	print("SDLATCH host split_state=%d snapshot_has_latches=%s end=%s won=%d" % [split_state, snap_ok, ended, _won])
	print("SDLATCH host result=%s" % ["PASS" if ok else "FAIL"])
	await _wait(PHASE_S)
	get_tree().quit(0)


## Influence circles for `slot_id`: its home, then circles along the path home -> targets.
func _chain(slot_id: int, targets: Array) -> Array[InfluenceCircle]:
	var seat: PlayerSlot = Match.slot(slot_id)
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(seat.home_position, seat.team_id, slot_id, Match._territory_tuning)]
	var from: Vector2 = seat.home_position
	for target: Vector2 in targets:
		var steps: int = int(ceil(from.distance_to(target) / CHAIN_SPACING))
		for i: int in range(1, steps + 1):
			_next_circle_id += 1
			circles.append(InfluenceCircle.new(from.lerp(target, float(i) / float(steps)), CHAIN_RADIUS, seat.team_id, slot_id, false, _next_circle_id))
		from = target
	return circles


## Paints the live raster from these chains and runs the objective step on it, like a territory step.
func _paint(chains: Array) -> void:
	var circles: Array[InfluenceCircle] = []
	for chain: Array in chains:
		circles.append_array(chain)
	var raster: TerritoryRaster = Match.raster()
	raster.fill_ownership(circles, TerritorySolver.new(Match._territory_tuning).solve(circles), true)
	raster.adopt_fill(raster, PAINT_DELTA, true, false)
	Match._territory._objective.update(raster, PAINT_DELTA)
	Match._territory._finish_objective_step()


# --- client -------------------------------------------------------------------

func _run_client() -> void:
	var deadline: int = Time.get_ticks_msec() + int((CONNECT_TIMEOUT + 10.0) * 1000.0)
	while Match.state() != Match.State.PLAYING and Time.get_ticks_msec() < deadline:
		await _wait(0.05)
	if Match.state() != Match.State.PLAYING:
		print("SDLATCH client result=FAIL reason=never_playing")
		get_tree().quit(2)
		return
	var end_at: int = Time.get_ticks_msec() + int(OBSERVE_S * 1000.0)
	var clock_first: float = -1.0
	var clock_last: float = -1.0
	var saw_sd: bool = false
	while Time.get_ticks_msec() < end_at and _won == NO_TEAM:
		await _wait(0.05)
		if Match.state() == Match.State.SUDDEN_DEATH:
			if not saw_sd:
				clock_first = Match.match_timer_left()
			saw_sd = true
			clock_last = Match.match_timer_left()
	await _wait(0.5)
	var team0: int = Match.slot(0).team_id
	var team1: int = Match.slot(1).team_id
	var saw_a: bool = _saw(team0, NO_TEAM)
	var saw_split: bool = _saw(team0, team1)
	var saw_win: bool = _saw(team1, team1)
	var clock_ok: bool = saw_sd and clock_first > 0.0 and clock_first <= float(SD_SECONDS) and clock_last < clock_first
	print("SDLATCH client saw_sd=%s clock=%.1f->%.1f ring_after_sd=%.2f a=%s split=%s flip_win=%s won=%d" % [saw_sd, clock_first, clock_last, _ring_after_sd, saw_a, saw_split, saw_win, _won])
	var ok: bool = clock_ok and _ring_after_sd <= 0.001 and saw_a and saw_split and saw_win and _won == team1
	print("SDLATCH client result=%s" % ["PASS" if ok else "FAIL"])
	get_tree().quit(0)


func _saw(latch0: int, latch1: int) -> bool:
	for entry: Vector3 in _timeline:
		if int(entry.x) == latch0 and int(entry.y) == latch1:
			return true
	return false
