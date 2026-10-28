extends "res://tests/unit/match/match_world_test.gd"
## Sudden death no longer crumbles the disc: time alone opens no hole and knocks out no home flag.
## The match ends only by a goal latch win, an elimination or the sudden-death clock (largest
## territory at 0). Driven through the real Match flow; observed through the raster, the slots and
## the Events bus a client view also listens to.

const TUNING: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
const FRAME: float = 1.0
const SD_SECONDS: int = 120
const HOME_BONUS: float = 6.0
const CENTRE_CIRCLE_RADIUS: float = 12.0
const MAX_FRAMES: int = 400

var _won: Array[int] = []
var _hole_events: int = 0


func before_each() -> void:
	super.before_each()
	_won.clear()
	_hole_events = 0
	Events.match_won.connect(_on_won)
	Events.hole_cells_changed.connect(_on_holes)


func after_each() -> void:
	Events.match_won.disconnect(_on_won)
	Events.hole_cells_changed.disconnect(_on_holes)
	super.after_each()


func _on_won(team: int) -> void:
	_won.append(team)


func _on_holes(_opened: PackedInt32Array, _closed: PackedInt32Array) -> void:
	_hole_events += 1


func _start_sudden_death(player_count: int = 2) -> void:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = player_count
	config.block_timer = 6.0
	config.rng_seed = 777
	config.game_mode = MatchConfig.GameMode.CLASSIC
	config.hole_mode = MatchConfig.HoleMode.TEMPORARY
	config.goal_flag_count = 1
	config.match_timer_minutes = 1
	config.sudden_death = true
	config.sudden_death_seconds = SD_SECONDS
	Match.start_match(config)
	_run_countdown()
	var frames: int = 0
	while Match.state() == Match.State.PLAYING and frames < MAX_FRAMES:
		Match._process(FRAME)
		frames += 1
	assert_eq(Match.state(), Match.State.SUDDEN_DEATH, "fixture: sudden death has started")


func _hole_count() -> int:
	var grid: CellGrid = Match.cell_grid()
	var count: int = 0
	for index: int in grid.in_disk_cells():
		var coords: Vector2i = grid.cell_coords(index)
		if Match.raster().is_hole(coords.x, coords.y):
			count += 1
	return count


func _alive_homes() -> int:
	var count: int = 0
	for slot_id: int in range(Match.slot_count()):
		if Match.slot(slot_id).home_flag_alive:
			count += 1
	return count


## Repaints the live raster; `centre_team` >= 0 owns the goal, `bonus_team` >= 0 has the larger share.
func _paint(centre_team: int, bonus_team: int = -1) -> void:
	var circles: Array[InfluenceCircle] = []
	for slot_id: int in range(Match.slot_count()):
		var seat: PlayerSlot = Match.slot(slot_id)
		circles.append(InfluenceCircle.for_home(seat.home_position, seat.team_id, slot_id, TUNING))
		if slot_id == bonus_team:
			circles.append(InfluenceCircle.new(seat.home_position, TUNING.home_radius + HOME_BONUS, seat.team_id, slot_id, false, 900 + slot_id))
	if centre_team >= 0:
		circles.append(InfluenceCircle.new(Vector2.ZERO, CENTRE_CIRCLE_RADIUS, centre_team, centre_team, false, 950))
	var raster: TerritoryRaster = Match.raster()
	raster.fill_ownership(circles, TerritorySolver.new(TUNING).solve(circles), false)
	raster.adopt_fill(raster, 1.0 / TUNING.solve_hz, false, false)


func test_no_cell_becomes_a_hole_over_the_whole_duration() -> void:
	_start_sudden_death()
	var before: int = _hole_count()
	_hole_events = 0
	for _i: int in range(SD_SECONDS - 1):
		Match._process(FRAME)
	assert_eq(Match.state(), Match.State.SUDDEN_DEATH, "a second before the end it is still running")
	assert_eq(_hole_count(), before, "time alone opens no hole")
	assert_eq(_hole_events, 0, "no hole_cells_changed reaches a view without a contest")


func test_no_hole_opens_at_any_point_of_the_countdown() -> void:
	_start_sudden_death()
	var before: int = _hole_count()
	for _i: int in range(SD_SECONDS - 1):
		Match._process(FRAME)
		assert_eq(_hole_count(), before, "hole count unchanged at every second")
		if _hole_count() != before:
			return


func test_home_flags_are_not_eliminated_by_time_alone() -> void:
	_start_sudden_death(3)
	var homes: int = _alive_homes()
	assert_eq(homes, 3, "fixture: all home flags alive")
	for _i: int in range(SD_SECONDS - 1):
		Match._process(FRAME)
	assert_eq(Match.state(), Match.State.SUDDEN_DEATH, "nobody was knocked out, so the match runs on")
	assert_eq(_alive_homes(), homes)
	assert_true(_won.is_empty())


func test_the_clock_ends_it_with_the_largest_territory_and_still_no_holes() -> void:
	_start_sudden_death()
	_paint(-1, 1)
	assert_gt(Match.territory_share(1), Match.territory_share(0), "fixture: team 1 is larger")
	var before: int = _hole_count()
	for _i: int in range(SD_SECONDS + 2):
		Match._process(FRAME)
	assert_eq(Match.state(), Match.State.END)
	assert_eq(_won, [1] as Array[int], "the match ended by the clock, not by a crumbling disc")
	assert_eq(_hole_count(), before)


func test_a_latch_win_ends_it_without_a_hole() -> void:
	_start_sudden_death()
	var before: int = _hole_count()
	for _i: int in range(10):
		Match._process(FRAME)
	_paint(0)
	Match._process(0.1)
	Match._process(0.1)
	assert_eq(Match.state(), Match.State.END)
	assert_eq(_won, [0] as Array[int])
	assert_eq(_hole_count(), before)


func test_an_elimination_still_ends_it() -> void:
	_start_sudden_death()
	for _i: int in range(10):
		Match._process(FRAME)
	Match._lifecycle.eliminate_slots(PackedInt32Array([0]))
	assert_eq(Match.state(), Match.State.END)
	assert_eq(_won, [1] as Array[int])
