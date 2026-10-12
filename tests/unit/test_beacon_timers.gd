extends GutTest
## Bontago-1pi.188 / 1pi.189: goal-beacon timer labels (Classic countdown, CTF
## count-up) and the CTF score-multiplier chip, plus the pure text helpers.

const CTF: int = MatchConfig.GameMode.CAPTURE_THE_FLAG
const HOLD_S: float = 20.0
const TEAM_COLOR: Color = Color(0.9, 0.2, 0.2)

var _flag: GoalFlag


func before_each() -> void:
	_flag = autofree((load("res://game/GoalFlag.tscn") as PackedScene).instantiate() as GoalFlag)
	add_child_autofree(_flag)


func _claim(team: int) -> void:
	_flag.set_control(team, TEAM_COLOR if team >= 0 else Color.WHITE, PackedColorArray())


func test_clock_formats_minutes_and_clamps() -> void:
	assert_eq(BeaconTimerText.clock(0), "0:00")
	assert_eq(BeaconTimerText.clock(75), "1:15")
	assert_eq(BeaconTimerText.clock(-5), "0:00")


func test_classic_text_counts_down_and_hides_when_idle() -> void:
	assert_eq(BeaconTimerText.classic_text(-1, 0.5, HOLD_S), "", "nobody claiming")
	assert_eq(BeaconTimerText.classic_text(0, 0.0, HOLD_S), "", "no progress yet")
	assert_eq(BeaconTimerText.classic_text(0, 0.25, HOLD_S), "0:15")
	assert_eq(BeaconTimerText.classic_text(1, 0.99, HOLD_S), "0:01", "rounds up")


func test_ctf_text_counts_up_for_holder_only() -> void:
	assert_eq(BeaconTimerText.ctf_text(-1, 12.0), "")
	assert_eq(BeaconTimerText.ctf_text(2, 0.0), "0:00")
	assert_eq(BeaconTimerText.ctf_text(2, 65.9), "1:05")


func test_multiplier_text_needs_two_beacons() -> void:
	assert_eq(BeaconTimerText.multiplier_text(0), "")
	assert_eq(BeaconTimerText.multiplier_text(1), "")
	assert_eq(BeaconTimerText.multiplier_text(3), "x3")


func test_multiplier_in_state_reads_ctf_held_counts() -> void:
	var state: Dictionary = {"mode_id": CTF, "extra": {"held_0": 2, "held_1": 1}}
	assert_eq(BeaconTimerText.multiplier_text_in_state(state, 0), "x2")
	assert_eq(BeaconTimerText.multiplier_text_in_state(state, 1), "")
	assert_eq(BeaconTimerText.multiplier_text_in_state(state, -1), "")
	assert_eq(BeaconTimerText.multiplier_text_in_state({"mode_id": MatchConfig.GameMode.CLASSIC, "extra": {"held_0": 3}}, 0), "")


func test_classic_flag_label_follows_capture_and_ticks_down() -> void:
	assert_eq(_flag.timer_text(), "", "neutral beacon shows nothing")
	_flag.set_countdown(0, 0.5, HOLD_S)
	assert_eq(_flag.timer_text(), "0:10")
	_flag._process(4.0)
	assert_eq(_flag.timer_text(), "0:06")
	_flag.set_countdown(-1, 0.0, HOLD_S)
	assert_eq(_flag.timer_text(), "", "claim lost: hidden")


func test_ctf_flag_counts_up_while_held_and_resets_on_new_holder() -> void:
	_flag.set_timer_counts_up(true)
	assert_eq(_flag.timer_text(), "", "unheld")
	_claim(0)
	_flag._process(3.2)
	assert_eq(_flag.timer_text(), "0:03")
	_claim(1)
	assert_eq(_flag.timer_text(), "0:00", "new holder restarts the clock")
	_flag._process(61.0)
	assert_eq(_flag.timer_text(), "1:01")
	_claim(GoalControl.NEUTRAL)
	assert_eq(_flag.timer_text(), "")


func test_ctf_multiplier_chip_shows_only_for_held_multiples() -> void:
	_flag.set_timer_counts_up(true)
	_claim(0)
	_flag.set_multiplier(2)
	assert_eq(_flag.multiplier_chip_text(), "x2")
	_flag.set_multiplier(1)
	assert_eq(_flag.multiplier_chip_text(), "")
	_flag.set_multiplier(3)
	_claim(GoalControl.NEUTRAL)
	assert_eq(_flag.multiplier_chip_text(), "", "no chip on an unheld beacon")


func test_labels_billboard_and_sit_above_the_crystal() -> void:
	var label: Label3D = _flag.get_node("TimerLabel") as Label3D
	assert_eq(label.billboard, BaseMaterial3D.BILLBOARD_ENABLED)
	var tuning: BeaconVisualTuning = _flag.beacon_visuals
	assert_gt(label.position.y, tuning.beacon_top_height(_flag.banner_scale()))


func test_field_feeds_multiplier_from_replicated_mode_state() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = load("res://config/maps/round_medium.tres") as MapDef
	add_child_autofree(field)
	field.place_flags(2, PackedColorArray([Color.RED, Color.BLUE]), 2)
	var flags: Array[GoalFlag] = field.goal_flags()
	for flag: GoalFlag in flags:
		flag.set_timer_counts_up(true)
		flag.set_control(0, Color.RED, PackedColorArray())
	Events.mode_state_changed.emit({"mode_id": CTF, "scores": [0.0, 0.0], "extra": {"held_0": 2, "held_1": 0}})
	assert_eq(flags[0].multiplier_chip_text(), "x2")
	assert_eq(flags[1].multiplier_chip_text(), "x2")
	Events.mode_state_changed.emit({"mode_id": CTF, "scores": [0.0, 0.0], "extra": {"held_0": 1, "held_1": 0}})
	assert_eq(flags[0].multiplier_chip_text(), "")


func test_hud_row_chip_text_for_team() -> void:
	var state: Dictionary = {"mode_id": CTF, "extra": {"held_0": 2}}
	assert_eq(BeaconTimerText.multiplier_text_in_state(state, 0), "x2")
