extends GutTest
## Sudden-death views: the round timer counts the remaining duration down (overtime label only when
## none is left), BeaconTimerText.latched_in_state reads a replicated mode state, and a goal beacon
## shows the latched team colour whatever the raster says (neutral, contested or another holder).

const FIELD_RADIUS: float = 20.0
const HOLD_S: float = 20.0
const CLAIM_RADIUS: float = 3.0
const COLORS: PackedColorArray = [Color(0.9, 0.25, 0.25), Color(0.25, 0.55, 0.95), Color(0.35, 0.8, 0.4)]
const NO_TEAM: int = -1

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")


func _timer() -> UiRoundTimer:
	var timer: UiRoundTimer = UiRoundTimer.new()
	add_child_autofree(timer)
	return timer


# --- UiRoundTimer ------------------------------------------------------------

func test_sudden_death_with_time_left_counts_it_down() -> void:
	var timer: UiRoundTimer = _timer()
	timer.show_match(5, 90.0, true, 999.0)
	assert_eq(timer.label.text, "1:30", "the host sudden-death clock, not the overtime label")
	timer.show_match(5, 89.2, true, 999.0)
	assert_eq(timer.label.text, "1:30", "rounded up like every countdown")
	timer.show_match(5, 0.2, true, 999.0)
	assert_eq(timer.label.text, "0:01")


func test_sudden_death_countdown_ignores_the_match_limit() -> void:
	var timer: UiRoundTimer = _timer()
	timer.show_match(0, 45.0, true, 12.0)
	assert_eq(timer.label.text, "0:45", "an untimed match still counts the sudden-death length down")


func test_sudden_death_countdown_keeps_the_overtime_look() -> void:
	var timer: UiRoundTimer = _timer()
	timer.show_match(5, 90.0, true, 0.0)
	assert_eq(timer.phase, UiRoundTimer.Phase.OVERTIME)
	assert_eq(timer.label.get_theme_color("font_color"), MenuStyleFactory.arcade_tuning().flare_color)
	assert_true(timer.visible)


func test_sudden_death_with_no_time_left_shows_the_overtime_label() -> void:
	var timer: UiRoundTimer = _timer()
	timer.show_match(5, 0.0, true, 999.0)
	assert_eq(timer.phase, UiRoundTimer.Phase.OVERTIME)
	assert_eq(timer.label.text, UiRoundTimer.tuning().round_timer_overtime_text)


func test_countdown_ends_back_on_the_normal_clock_outside_sudden_death() -> void:
	var timer: UiRoundTimer = _timer()
	timer.show_match(5, 90.0, true, 0.0)
	timer.show_match(5, 125.0, false, 0.0)
	assert_eq(timer.label.text, "2:05")
	assert_ne(timer.phase, UiRoundTimer.Phase.OVERTIME)


## A published mode state: the objective fields ride under "extra".
func _mode_state(extra: Dictionary) -> Dictionary:
	return {"extra": extra}


## BeaconTimerText.latched_in_state, called by name so the file still parses where the reader is missing.
func _latched(state: Dictionary, goal_index: int) -> int:
	return int((BeaconTimerText as GDScript).call(&"latched_in_state", state, goal_index))


# --- BeaconTimerText.latched_in_state ----------------------------------------

func test_latched_in_state_reads_each_goal_key() -> void:
	var state: Dictionary = _mode_state({"sd": 1, "l0": 2, "l1": NO_TEAM, "l2": 0})
	assert_eq(_latched(state, 0), 2)
	assert_eq(_latched(state, 1), NO_TEAM, "-1 is an unclaimed goal")
	assert_eq(_latched(state, 2), 0, "team 0 is a real owner")


func test_latched_in_state_is_no_team_when_absent() -> void:
	assert_eq(_latched({}, 0), NO_TEAM, "no sudden death: nothing latched")
	assert_eq(_latched(_mode_state({"sd": 1, "l0": 1}), 3), NO_TEAM, "a goal the state does not name")
	assert_eq(_latched({"round_left": 30.0, "extra": {"held_0": 2}}, 0), NO_TEAM, "other keys are not latches")


func test_latched_in_state_reads_the_highest_goal_index() -> void:
	var state: Dictionary = _mode_state({"l4": 3, "l0": 1})
	assert_eq(_latched(state, 4), 3)
	assert_eq(_latched(state, 0), 1)
	assert_eq(_latched(state, 1), NO_TEAM)


func test_latched_in_state_does_not_confuse_goal_indices() -> void:
	var state: Dictionary = _mode_state({"l1": 2, "l10": 1})
	assert_eq(_latched(state, 1), 2)
	assert_eq(_latched(state, 10), 1)


# --- beacon colour from a latch ----------------------------------------------

func _map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_sudden_death_view"
	map_def.field_radius = FIELD_RADIUS
	map_def.cell_size = 2.0
	map_def.territory_res = 32
	return map_def


func _placed(goals: int = 1) -> FieldFlags:
	var flags: FieldFlags = FieldFlags.new()
	flags.map_def = _map()
	flags.visuals = preload("res://config/territory/territory_visuals.tres")
	flags.tuning = preload("res://config/physics/physics_tuning.tres")
	flags.home_flag_scene = preload("res://game/flags/HomeFlag.tscn")
	flags.goal_flag_scene = preload("res://game/flags/GoalFlag.tscn")
	add_child_autofree(flags)
	flags.set_colors(COLORS)
	flags.place(2, goals, CLAIM_RADIUS, HOLD_S, false)
	return flags


## A raster where each (x, team) home circle reaches the field centre, where the first goal stands.
func _raster(homes: Array[Vector2i]) -> TerritoryRaster:
	var circles: Array[InfluenceCircle] = []
	for home: Vector2i in homes:
		circles.append(InfluenceCircle.new(Vector2(float(home.x), 0.0), _tuning.home_radius, home.y, home.y, true, -1))
	var raster: TerritoryRaster = TerritoryRaster.new(CellGrid.new(FIELD_RADIUS, 1.0), _tuning)
	raster.fill_ownership(circles, TerritorySolver.new(_tuning).solve(circles), true)
	raster.adopt_fill(raster, 0.1, true, false)
	return raster


func _latch(goal_team: Dictionary) -> Dictionary:
	var extra: Dictionary = {"sd": 1}
	for goal: int in goal_team:
		extra["l" + str(goal)] = goal_team[goal]
	return _mode_state(extra)


func test_latch_colours_a_neutral_goal() -> void:
	var flags: FieldFlags = _placed()
	Events.territory_replicated.emit(_raster([]))
	assert_eq(flags.goal_flags()[0].control(), GoalControl.NEUTRAL, "fixture: the raster holds nothing")
	Events.mode_state_changed.emit(_latch({0: 1}))
	assert_eq(flags.goal_flags()[0].control(), 1)
	assert_eq(flags.goal_flags()[0].color(), COLORS[1], "the latched team colour")


func test_latch_colours_the_goal_when_the_state_arrives_before_the_raster() -> void:
	var flags: FieldFlags = _placed()
	Events.mode_state_changed.emit(_latch({0: 2}))
	Events.territory_replicated.emit(_raster([]))
	assert_eq(flags.goal_flags()[0].control(), 2)
	assert_eq(flags.goal_flags()[0].color(), COLORS[2])


func test_latch_keeps_its_colour_while_the_goal_is_contested() -> void:
	var flags: FieldFlags = _placed()
	Events.mode_state_changed.emit(_latch({0: 0}))
	Events.territory_replicated.emit(_raster([Vector2i(-3, 0), Vector2i(3, 1)]))
	assert_eq(flags.goal_flags()[0].control(), 0, "a contested latched flag stays owned")
	assert_eq(flags.goal_flags()[0].color(), COLORS[0])


func test_latch_wins_over_the_team_the_raster_shows() -> void:
	var flags: FieldFlags = _placed()
	Events.mode_state_changed.emit(_latch({0: 0}))
	Events.territory_replicated.emit(_raster([Vector2i(-3, 1)]))
	assert_eq(flags.goal_flags()[0].control(), 0, "the latch stays until the host re-claims")
	assert_eq(flags.goal_flags()[0].color(), COLORS[0])


func test_a_new_latch_flips_the_colour_without_a_new_raster() -> void:
	var flags: FieldFlags = _placed()
	Events.territory_replicated.emit(_raster([]))
	Events.mode_state_changed.emit(_latch({0: 0}))
	Events.mode_state_changed.emit(_latch({0: 1}))
	assert_eq(flags.goal_flags()[0].control(), 1)
	assert_eq(flags.goal_flags()[0].color(), COLORS[1])


func test_an_unlatched_goal_follows_the_raster() -> void:
	var flags: FieldFlags = _placed()
	Events.mode_state_changed.emit(_latch({0: NO_TEAM}))
	Events.territory_replicated.emit(_raster([Vector2i(-3, 1)]))
	assert_eq(flags.goal_flags()[0].control(), 1, "-1 is no latch: raster control as before")
	Events.territory_replicated.emit(_raster([]))
	assert_eq(flags.goal_flags()[0].control(), GoalControl.NEUTRAL)


func test_a_state_without_latches_leaves_raster_control() -> void:
	var flags: FieldFlags = _placed()
	Events.mode_state_changed.emit({})
	Events.territory_replicated.emit(_raster([Vector2i(-3, 1)]))
	assert_eq(flags.goal_flags()[0].control(), 1)


func test_clearing_the_state_returns_the_goal_to_the_raster() -> void:
	var flags: FieldFlags = _placed()
	Events.territory_replicated.emit(_raster([]))
	Events.mode_state_changed.emit(_latch({0: 2}))
	Events.mode_state_changed.emit({})
	assert_eq(flags.goal_flags()[0].control(), GoalControl.NEUTRAL)


func test_each_goal_shows_its_own_latch() -> void:
	var flags: FieldFlags = _placed(3)
	Events.territory_replicated.emit(_raster([]))
	Events.mode_state_changed.emit(_latch({0: 2, 1: 0}))
	assert_eq(flags.goal_flags()[0].control(), 2)
	assert_eq(flags.goal_flags()[1].control(), 0)
	assert_eq(flags.goal_flags()[2].control(), GoalControl.NEUTRAL, "an unlatched goal stays neutral")
	assert_eq(flags.goal_flags()[1].color(), COLORS[0])


func test_placing_a_new_match_drops_the_old_latches() -> void:
	var flags: FieldFlags = _placed()
	Events.mode_state_changed.emit(_latch({0: 2}))
	flags.place(2, 1, CLAIM_RADIUS, HOLD_S, false)
	Events.territory_replicated.emit(_raster([Vector2i(-3, 1)]))
	assert_eq(flags.goal_flags()[0].control(), 1, "the previous match latch is gone")
