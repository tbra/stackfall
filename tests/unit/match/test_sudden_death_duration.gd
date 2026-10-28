extends "res://tests/unit/match/match_world_test.gd"
## Sudden death length: the lobby's sudden_death_seconds is the clock of sudden
## death; goals latch at once; at 0 the largest territory wins (ties to the lowest team id); a latch
## win or an elimination ends the match earlier. Driven through the real Match flow
## (Match._process frames, the objective's own raster step); no hook added for the tests.

const TUNING: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
const FRAME: float = 1.0
const SD_SECONDS: int = 60
## Tiny-map goal (the map centre) reachable by one team: a circle on the centre connected to its home.
const CENTRE_CIRCLE_RADIUS: float = 12.0
const HOME_BONUS: float = 6.0
const MAX_FRAMES: int = 400

var _won: Array[int] = []
var _published: Array[Dictionary] = []


func before_each() -> void:
	super.before_each()
	_won.clear()
	_published.clear()
	Events.match_won.connect(_on_won)
	Events.mode_state_changed.connect(_on_mode_state)


func after_each() -> void:
	Events.match_won.disconnect(_on_won)
	Events.mode_state_changed.disconnect(_on_mode_state)
	super.after_each()


func _on_won(team: int) -> void:
	_won.append(team)


func _on_mode_state(state: Dictionary) -> void:
	_published.append(state)


func _start(duration: int = SD_SECONDS) -> void:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = 2
	config.block_timer = 6.0
	config.rng_seed = 777
	config.game_mode = MatchConfig.GameMode.CLASSIC
	config.hole_mode = MatchConfig.HoleMode.TEMPORARY
	config.goal_flag_count = 1
	config.match_timer_minutes = 1
	config.sudden_death = true
	config.sudden_death_seconds = duration
	Match.start_match(config)
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the match is running")


## Plays 1 s frames until the match timer has at most `left` seconds.
func _play_until_timer_left(left: float) -> void:
	var frames: int = 0
	while Match.match_timer_left() > left and Match.state() == Match.State.PLAYING and frames < MAX_FRAMES:
		Match._process(FRAME)
		frames += 1


## Plays through the end of the match timer: the frame that crosses 0 starts sudden death.
func _enter_sudden_death() -> void:
	_play_until_timer_left(0.0)
	assert_eq(Match.state(), Match.State.SUDDEN_DEATH, "fixture: sudden death has started")


func _home_circle(slot_id: int) -> InfluenceCircle:
	var seat: PlayerSlot = Match.slot(slot_id)
	return InfluenceCircle.for_home(seat.home_position, seat.team_id, slot_id, TUNING)


## Nobody owns anything: every share is exactly equal.
func _paint_nothing() -> void:
	var none: Array[InfluenceCircle] = []
	var raster: TerritoryRaster = Match.raster()
	raster.fill_ownership(none, TerritorySolver.new(TUNING).solve(none), false)
	raster.adopt_fill(raster, 1.0 / TUNING.solve_hz, false, false)


## Repaints the live raster; `centre_team` >= 0 also owns the goal (connected to its home), and
## `bonus_team` >= 0 has a wider home circle (a larger share without reaching the goal).
func _paint(centre_team: int, bonus_team: int = -1) -> void:
	var circles: Array[InfluenceCircle] = []
	for slot_id: int in range(Match.slot_count()):
		circles.append(_home_circle(slot_id))
		if slot_id == bonus_team:
			var seat: PlayerSlot = Match.slot(slot_id)
			circles.append(InfluenceCircle.new(seat.home_position, TUNING.home_radius + HOME_BONUS, seat.team_id, slot_id, false, 900 + slot_id))
	if centre_team >= 0:
		circles.append(InfluenceCircle.new(Vector2.ZERO, CENTRE_CIRCLE_RADIUS, centre_team, centre_team, false, 950))
	var raster: TerritoryRaster = Match.raster()
	raster.fill_ownership(circles, TerritorySolver.new(TUNING).solve(circles), false)
	raster.adopt_fill(raster, 1.0 / TUNING.solve_hz, false, false)


# --- the clock ---------------------------------------------------------------

func test_sudden_death_starts_with_the_configured_duration() -> void:
	_start(90)
	_enter_sudden_death()
	assert_almost_eq(Match.match_timer_left(), 90.0, 0.0001)


func test_the_shortest_duration_is_used_as_configured() -> void:
	_start(MatchConfig.SUDDEN_DEATH_MIN_SECONDS)
	_enter_sudden_death()
	assert_almost_eq(Match.match_timer_left(), float(MatchConfig.SUDDEN_DEATH_MIN_SECONDS), 0.0001)


func test_the_clock_runs_down_in_sudden_death() -> void:
	_start()
	_enter_sudden_death()
	for _i: int in range(10):
		Match._process(FRAME)
	assert_eq(Match.state(), Match.State.SUDDEN_DEATH)
	assert_almost_eq(Match.match_timer_left(), float(SD_SECONDS) - 10.0, 0.001)


func test_the_clock_is_published_once_per_second() -> void:
	_start()
	_enter_sudden_death()
	_published.clear()
	for _i: int in range(20):
		Match._process(0.25)
	var seconds: Array[int] = []
	for state: Dictionary in _published:
		assert_true(state.has("round_left"), "every published state carries the clock")
		seconds.append(int(ceil(float(state.get("round_left", 0.0)))))
	assert_between(seconds.size(), 4, 6, "5 s of sudden death publish about one state per second")
	for i: int in range(1, seconds.size()):
		assert_lt(seconds[i], seconds[i - 1], "each publish shows a new whole second, counting down")
	assert_almost_eq(float(Match.mode_state_snapshot().get("round_left", -1.0)), Match.match_timer_left(), 0.0001, "a late joiner's snapshot carries the same clock")


# --- the end of the clock ----------------------------------------------------

func test_at_zero_the_larger_territory_wins() -> void:
	_start(MatchConfig.SUDDEN_DEATH_MIN_SECONDS)
	_paint(-1, 1)
	assert_gt(Match.territory_share(1), Match.territory_share(0), "fixture: team 1 is larger")
	_enter_sudden_death()
	for _i: int in range(MatchConfig.SUDDEN_DEATH_MIN_SECONDS - 1):
		Match._process(FRAME)
	assert_eq(Match.state(), Match.State.SUDDEN_DEATH, "still running a second before the end")
	assert_true(_won.is_empty())

	Match._process(FRAME * 2.0)

	assert_eq(Match.state(), Match.State.END)
	assert_eq(_won, [1] as Array[int])


func test_at_zero_the_larger_territory_wins_for_the_lower_team_too() -> void:
	_start(MatchConfig.SUDDEN_DEATH_MIN_SECONDS)
	_paint(-1, 0)
	assert_gt(Match.territory_share(0), Match.territory_share(1), "fixture: team 0 is larger")
	_enter_sudden_death()
	for _i: int in range(MatchConfig.SUDDEN_DEATH_MIN_SECONDS + 1):
		Match._process(FRAME)
	assert_eq(_won, [0] as Array[int])


func test_a_tie_at_zero_goes_to_the_lowest_team_id() -> void:
	_start(MatchConfig.SUDDEN_DEATH_MIN_SECONDS)
	_paint_nothing()
	assert_eq(Match.territory_share(0), Match.territory_share(1), "fixture: an exact tie")
	_enter_sudden_death()
	for _i: int in range(MatchConfig.SUDDEN_DEATH_MIN_SECONDS + 1):
		Match._process(FRAME)
	assert_eq(_won, [0] as Array[int])


func test_the_match_ends_exactly_once_at_zero() -> void:
	_start(MatchConfig.SUDDEN_DEATH_MIN_SECONDS)
	_paint(-1, 1)
	_enter_sudden_death()
	for _i: int in range(MatchConfig.SUDDEN_DEATH_MIN_SECONDS + 5):
		Match._process(FRAME)
	assert_eq(_won.size(), 1)


# --- latch and elimination end it early --------------------------------------

func test_a_goal_held_when_sudden_death_starts_wins_at_once() -> void:
	_start()
	_play_until_timer_left(1.5)
	_paint(1, 0)
	assert_eq(Match.state(), Match.State.PLAYING)
	_enter_sudden_death()
	Match._process(0.1)
	Match._process(0.1)

	assert_eq(Match.state(), Match.State.END, "no capture_hold wait: the holder wins at the start")
	assert_eq(_won, [1] as Array[int])
	assert_gt(Match.match_timer_left(), float(SD_SECONDS) - 1.0, "the clock had barely started")


func test_a_goal_claimed_during_sudden_death_wins_before_the_clock_ends() -> void:
	_start()
	_paint(-1, 1)
	assert_gt(Match.territory_share(1), Match.territory_share(0), "fixture: the timer would pick team 1")
	_enter_sudden_death()
	assert_eq(Match.state(), Match.State.SUDDEN_DEATH, "nobody holds the goal at the start")
	Match._process(FRAME)
	assert_eq(Match.state(), Match.State.SUDDEN_DEATH)

	_paint(0)
	Match._process(0.1)
	Match._process(0.1)

	assert_eq(Match.state(), Match.State.END)
	assert_eq(_won, [0] as Array[int], "the flag holder wins, not the larger territory")
	assert_gt(Match.match_timer_left(), 0.0, "the clock had not run out")


func test_an_elimination_in_sudden_death_still_ends_the_match() -> void:
	_start()
	_enter_sudden_death()
	Match._process(FRAME)
	Match._lifecycle.eliminate_slots(PackedInt32Array([0]))
	assert_eq(Match.state(), Match.State.END)
	assert_eq(_won, [1] as Array[int])


# --- unchanged ---------------------------------------------------------------

func test_the_gift_ramp_starts_with_sudden_death_and_climbs() -> void:
	_start()
	assert_almost_eq(_ramp(TUNING.sudden_death_ramp_s), 0.0, 0.0001, "none before sudden death")
	_enter_sudden_death()
	assert_almost_eq(_ramp(TUNING.sudden_death_ramp_s), 0.0, 0.0001, "starts at 0")
	for _i: int in range(10):
		Match._process(FRAME)
	assert_almost_eq(_ramp(TUNING.sudden_death_ramp_s), 10.0 / TUNING.sudden_death_ramp_s, 0.001, "climbs with sudden-death time, not with the new clock")


func test_without_sudden_death_the_timer_running_out_changes_nothing() -> void:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = 2
	config.block_timer = 6.0
	config.game_mode = MatchConfig.GameMode.CLASSIC
	config.hole_mode = MatchConfig.HoleMode.TEMPORARY
	config.match_timer_minutes = 1
	config.sudden_death = false
	Match.start_match(config)
	_run_countdown()
	_play_until_timer_left(0.0)
	Match._process(FRAME)
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_almost_eq(Match.match_timer_left(), 0.0, 0.0001)


func _ramp(ramp_s: float) -> float:
	return (Match.lifecycle() as MatchLifecycle).sudden_death_ramp(ramp_s)
