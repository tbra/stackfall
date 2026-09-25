extends GutTest
## Spec 2.8's last two stub rows (M6 A3): the match timer and sudden death.
##
## Fixture mirrors test_match_territory_punch.gd's own before_each exactly
## (TinyMapMatchConfig over a manually-registered Field/BlockRegistry, no
## full Main scene -- this package touches none of the world-build wiring
## that file's own header explains test_match_lifecycle.gd needs).
##
## Several tests fast-forward by writing straight into MatchLifecycle's
## private accumulators (Match._lifecycle._match_timer_left,
## _sudden_death_elapsed) rather than simulating real minutes of match time
## through Match._process() -- the same direct-access convention
## test_gift_claim.gd already uses to fast-forward GiftConfig.life_s.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _tiny_map_config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	return config


func _config(player_count: int) -> MatchConfig:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = player_count
	config.hot_seat = true
	config.block_timer = 6.0
	config.rng_seed = 12345
	config.hole_mode = MatchConfig.HoleMode.TEMPORARY
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


# --- Match timer (spec 2.8: "Off / 10-40 min") ------------------------------

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


func test_match_timer_at_zero_stays_playing_when_sudden_death_is_off() -> void:
	var config: MatchConfig = _config(2)
	config.match_timer_minutes = 1
	config.sudden_death = false
	Match.start_match(config)
	_run_countdown()

	Match._lifecycle._match_timer_left = 0.05
	Match._process(0.1)

	assert_eq(Match.state(), Match.State.PLAYING,
		"spec 2.8: sudden_death is independently toggleable -- the timer is cosmetic once off")
	assert_almost_eq(Match.match_timer_left(), 0.0, 0.0001)


func test_sudden_death_never_fires_when_the_match_timer_is_off() -> void:
	var config: MatchConfig = _config(2)
	config.match_timer_minutes = 0
	config.sudden_death = true
	Match.start_match(config)
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING)

	for _i: int in range(5):
		Match._process(1.0 / Engine.physics_ticks_per_second)

	assert_eq(Match.state(), Match.State.PLAYING, "match_timer_minutes == 0 (Off) must never arm sudden death")
	assert_almost_eq(Match.match_timer_left(), 0.0, 0.0001)


# --- Match._process()'s SUDDEN_DEATH branch (regression against the audit --
# named gap: this state used to have no case at all, so everything froze) ---

func test_sudden_death_branch_keeps_ticking_feed_and_territory() -> void:
	var config: MatchConfig = _config(2)
	Match.start_match(config)
	_run_countdown()
	Match._lifecycle._begin_sudden_death()
	assert_eq(Match.state(), Match.State.SUDDEN_DEATH)

	watch_signals(Events)
	for _i: int in range(int(ceil(config.block_timer * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)

	assert_signal_emitted(Events, "feed_timer_expired",
		"SUDDEN_DEATH must still tick the feed, not silently freeze it")
	assert_signal_emitted(Events, "territory_updated",
		"SUDDEN_DEATH must still tick the territory solve")


# --- shrink_to_radius() (spec 2.8: "crumbles inward by 1 m every 10 s") -----

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


func test_shrink_to_radius_never_reopens_a_cell_even_when_called_with_a_larger_radius_later() -> void:
	Match.start_match(_config(2))
	_run_countdown()
	var grid: CellGrid = Match.cell_grid()

	Match._territory.shrink_to_radius(8.0)
	var punched_at_8: Array[int] = []
	for index: int in grid.in_disk_cells():
		var coords: Vector2i = grid.cell_coords(index)
		if Match.raster().is_hole(coords.x, coords.y):
			punched_at_8.append(index)
	assert_true(punched_at_8.size() > 0, "fixture: radius 8 punches something on a 20 m map")

	Match._territory.shrink_to_radius(15.0)

	for index: int in punched_at_8:
		var coords: Vector2i = grid.cell_coords(index)
		assert_true(Match.raster().is_hole(coords.x, coords.y),
			"a cell already punched at a smaller radius must never reopen, even for a later larger radius")


# --- Radius-8 tiebreak (spec 2.8, verbatim numbers) -------------------------

func test_sudden_death_tiebreak_picks_the_team_with_strictly_more_territory_share() -> void:
	Match.start_match(_config(2))
	_run_countdown()
	Match._lifecycle._begin_sudden_death()
	watch_signals(Events)

	Match._raster._team_counts = {0: 1, 1: 5}

	Match._lifecycle._resolve_sudden_death_tiebreak()

	assert_eq(Match.state(), Match.State.END)
	assert_signal_emitted_with_parameters(Events, "match_won", [1])


func test_sudden_death_tiebreak_is_deterministic_lowest_team_id_on_a_tie() -> void:
	Match.start_match(_config(3))
	_run_countdown()
	Match._lifecycle._begin_sudden_death()
	watch_signals(Events)

	Match._raster._team_counts = {0: 2, 1: 5, 2: 5}

	Match._lifecycle._resolve_sudden_death_tiebreak()

	assert_eq(Match.state(), Match.State.END)
	# team 1 and team 2 tie at the same share; the lowest team id must win.
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


# --- Gift-chance ramp (spec 2.8: "climbs toward the maximum") ---------------

func test_effective_special_frequency_lerps_monotonically_and_clamps_at_the_ramp() -> void:
	var config: MatchConfig = _config(2)
	config.special_frequency = 20.0
	Match.start_match(config)
	_run_countdown()

	var max_frequency: float = float(MatchConfig.SPECIAL_FREQUENCY_MAX)

	assert_almost_eq(Match._gifts._effective_special_frequency(), 20.0, 0.0001,
		"unchanged outside sudden death")

	Match._lifecycle._begin_sudden_death()
	assert_almost_eq(Match._gifts._effective_special_frequency(), 20.0, 0.0001,
		"starts at the base frequency the instant sudden death begins")

	var ramp_s: float = Match._territory_tuning.sudden_death_ramp_s
	Match._lifecycle._sudden_death_elapsed = ramp_s * 0.5
	assert_almost_eq(Match._gifts._effective_special_frequency(), lerpf(20.0, max_frequency, 0.5), 0.0001,
		"halfway through the ramp is halfway from 20 to MatchConfig.SPECIAL_FREQUENCY_MAX")

	Match._lifecycle._sudden_death_elapsed = ramp_s * 2.0
	assert_almost_eq(Match._gifts._effective_special_frequency(), max_frequency, 0.0001,
		"clamped at MatchConfig.SPECIAL_FREQUENCY_MAX once the ramp window has passed")
