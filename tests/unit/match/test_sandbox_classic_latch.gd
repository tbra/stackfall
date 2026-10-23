extends "res://tests/unit/match/match_world_test.gd"
## A sandbox Classic match never ends on the goal hold, so a capture it latched earlier must not
## decide a later step's wipe-out: that wipe-out is judged by territory share like any other.

const TUNING: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")

var _won: Array[int] = []


func before_each() -> void:
	super.before_each()
	_won.clear()
	Events.match_won.connect(_on_won)


func after_each() -> void:
	Events.match_won.disconnect(_on_won)
	super.after_each()


func _on_won(team: int) -> void:
	_won.append(team)


func test_an_earlier_sandbox_capture_does_not_decide_a_later_wipe_out() -> void:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = 2
	config.team_mode = MatchConfig.TeamMode.OFF
	config.game_mode = MatchConfig.GameMode.CLASSIC
	config.hole_mode = MatchConfig.HoleMode.TEMPORARY
	config.sandbox = true
	config.rng_seed = 4242
	config.sudden_death = false
	config.match_timer_minutes = 0
	config.round_timer_minutes = 0
	Match.start_match(config)
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the sandbox is running")

	# Team 1 alone owns the goal, so a real update latches its capture; the sandbox keeps playing.
	var goal: Vector2 = Match.slot(1).home_position
	var objective: ClassicObjective = Match._territory._objective as ClassicObjective
	objective.set_checker(WinChecker.new(PackedVector2Array([goal]), 0.0))
	var only_team_1: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(goal, Match.slot(1).team_id, 1, TUNING)
	]
	_paint(only_team_1)
	objective.update(Match.raster(), 1.0 / TUNING.solve_hz)
	assert_eq(objective.winner(), 1, "fixture: team 1 latched the capture")
	Match._territory._finish_objective_step()
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: a sandbox does not end on the hold")

	# Later, team 0 holds the larger share and both homes are lost in one step.
	var circles: Array[InfluenceCircle] = []
	for slot_id: int in range(Match.slot_count()):
		var seat: PlayerSlot = Match.slot(slot_id)
		circles.append(InfluenceCircle.for_home(seat.home_position, seat.team_id, slot_id, TUNING))
		if seat.team_id == 0:
			circles.append(InfluenceCircle.new(seat.home_position, TUNING.home_radius + 6.0, 0, slot_id, false, 900 + slot_id))
	_paint(circles)
	assert_gt(Match.territory_share(0), Match.territory_share(1), "fixture: team 0 holds more")

	Match._lifecycle.eliminate_slots(PackedInt32Array([0, 1]))

	assert_eq(_won, [0] as Array[int], "the larger share wins, not the stale capturer")


func _paint(circles: Array[InfluenceCircle]) -> void:
	var raster: TerritoryRaster = Match.raster()
	raster.fill_ownership(circles, TerritorySolver.new(TUNING).solve(circles), false)
	raster.adopt_fill(raster, 1.0 / TUNING.solve_hz, false, false)
