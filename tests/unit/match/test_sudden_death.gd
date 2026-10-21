extends "res://tests/unit/match/match_world_test.gd"
## Spec 1.9 match timer and sudden death (M6 A3).

func _config(player_count: int) -> MatchConfig:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 12345
	config.hole_mode = MatchConfig.HoleMode.TEMPORARY
	return config


func test_match_timer_only_counts_down_in_playing() -> void:
	var config: MatchConfig = _config(2)
	config.match_timer_minutes = 1
	Match.start_match(config)
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	assert_almost_eq(Match.match_timer_left(), 0.0, 0.0001, "not armed until PLAYING")

	Match._process(1.0 / Engine.physics_ticks_per_second)
	assert_almost_eq(Match.match_timer_left(), 0.0, 0.0001, "COUNTDOWN never ticks the match timer")

	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING)
	# _run_countdown() itself runs a couple of frames past the exact countdown
	# ->PLAYING transition (padding shared with test_match_territory_punch.gd's
	# own fixture), so those frames have already ticked the match timer down a
	# hair below the full 60.0 s it was armed with -- assert the armed window
	# rather than an exact value, then diff PLAYING's own further tick against
	# whatever that armed value actually was.
	var armed: float = Match.match_timer_left()
	assert_true(armed <= 60.0 and armed > 59.9, "armed close to match_timer_minutes * 60, minus fixture padding frames")

	Match._process(5.0)
	assert_almost_eq(Match.match_timer_left(), armed - 5.0, 0.0001, "PLAYING ticks the match timer down")


func test_match_timer_at_zero_enters_sudden_death_only_when_configured() -> void:
	var config: MatchConfig = _config(2)
	config.match_timer_minutes = 1
	config.sudden_death = true
	Match.start_match(config)
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING)

	Match._lifecycle._match_timer_left = 0.05
	Match._process(0.1)

	assert_eq(Match.state(), Match.State.SUDDEN_DEATH, "the timer hitting zero with sudden_death on transitions")
	assert_almost_eq(Match.match_timer_left(), 0.0, 0.0001)


# --- Match._process()'s SUDDEN_DEATH branch (regression against the audit --
# named gap: this state used to have no case at all, so everything froze) ---

# --- placement / preview / client feed display stay live ----

# --- shrink_to_radius() (spec 1.9: "crumbles inward by 1 m every 10 s") -----

func test_shrink_to_radius_punches_exactly_the_cells_outside_its_argument() -> void:
	Match.start_match(_config(2))
	_run_countdown()

	var grid: CellGrid = Match.cell_grid()
	var shrink_radius: float = 12.0
	Match._territory.shrink_to_radius(shrink_radius)

	for index: int in grid.in_disk_cells():
		var coords: Vector2i = grid.cell_coords(index)
		var is_hole: bool = Match.raster().is_hole(coords.x, coords.y)
		var outside: bool = grid.index_center(index).length() > shrink_radius
		assert_eq(is_hole, outside,
			"cell %d hole state must match whether it's outside the shrink radius" % index)


# --- Radius-8 tiebreak (spec 1.9, verbatim numbers) -------------------------

func test_sudden_death_tiebreak_picks_the_team_with_strictly_more_territory_share() -> void:
	Match.start_match(_config(2))
	_run_countdown()
	Match._lifecycle._begin_sudden_death()
	watch_signals(Events)

	Match._raster._team_counts = {0: 1, 1: 5}

	Match._lifecycle._resolve_sudden_death_tiebreak()

	assert_eq(Match.state(), Match.State.END)
	assert_signal_emitted_with_parameters(Events, "match_won", [1])


# --- Win checks during SUDDEN_DEATH (stackfall-reviewer F1: an elimination or
# a goal capture must finish the match immediately, not only at the radius-8
# tiebreak) --------------------------------------------------------------

func test_elimination_during_sudden_death_finishes_the_match_immediately() -> void:
	Match.start_match(_config(3))
	_run_countdown()
	Match._lifecycle._begin_sudden_death()
	assert_eq(Match.state(), Match.State.SUDDEN_DEATH)
	watch_signals(Events)

	# Free-for-all (_config()'s default team_mode): three players, three teams.
	# Eliminating the first of the two non-surviving teams must not end the
	# match by itself -- two teams (1 and 2) are still alive.
	Match._lifecycle._eliminate_slot(0)
	assert_eq(Match.state(), Match.State.SUDDEN_DEATH,
		"one team down of three: two are still alive, the match keeps running")

	# Eliminating the second-to-last team leaves exactly one team standing.
	Match._lifecycle._eliminate_slot(1)

	assert_eq(Match.state(), Match.State.END,
		"F1: an elimination during SUDDEN_DEATH must finish the match immediately, not only at the tiebreak")
	assert_signal_emitted_with_parameters(Events, "match_won", [2])


func test_goal_capture_during_sudden_death_finishes_the_match_immediately() -> void:
	Match.start_match(_config(2))
	_run_countdown()
	Match._lifecycle._begin_sudden_death()
	assert_eq(Match.state(), Match.State.SUDDEN_DEATH)
	watch_signals(Events)

	# Force WinChecker's latched winner directly (same direct-private-field
	# convention this file's own header doc describes, and
	# test_match_territory_punch.gd's Match._raster._team_counts already
	# uses) rather than staging real blocks to hold every goal for
	# capture_hold seconds -- _run_territory_step() below is what reads it.
	Match._territory._win_checker._winner = 1

	Match._territory._run_territory_step(1.0 / Match._territory_tuning.solve_hz)

	assert_eq(Match.state(), Match.State.END,
		"F1: a goal-capture winner during SUDDEN_DEATH must finish the match immediately, not only at the tiebreak")
	assert_signal_emitted_with_parameters(Events, "match_won", [1])


# --- Gift-chance ramp (spec 1.9: "climbs toward the maximum") ---------------
