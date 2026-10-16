extends GutTest
## UiRoundTimer (the match clock): m:ss format, hurry threshold from config, limited vs
## unlimited modes, sudden death, token colours, and the HUD wiring (a client shows the host's time).


func _timer() -> UiRoundTimer:
	var timer: UiRoundTimer = UiRoundTimer.new()
	add_child_autofree(timer)
	return timer


func test_format_is_minutes_and_two_digit_seconds() -> void:
	assert_eq(UiRoundTimer.format_clock(0), "0:00")
	assert_eq(UiRoundTimer.format_clock(9), "0:09")
	assert_eq(UiRoundTimer.format_clock(61), "1:01")
	assert_eq(UiRoundTimer.format_clock(209), "3:29")
	assert_eq(UiRoundTimer.format_clock(6000), "100:00")
	assert_eq(UiRoundTimer.format_clock(-5), "0:00")


func test_countdown_rounds_up_and_counts_elapsed_down() -> void:
	var timer: UiRoundTimer = _timer()
	timer.show_remaining(59.2)
	assert_eq(timer.label.text, "1:00", "never reads 0:00 before the end")
	timer.show_elapsed(59.9)
	assert_eq(timer.label.text, "0:59")


func test_hurry_starts_at_the_configured_seconds() -> void:
	var timer: UiRoundTimer = _timer()
	var n: float = UiRoundTimer.tuning().round_timer_hurry_seconds
	assert_eq(timer.hurry_seconds, n)
	timer.show_remaining(n + 1.0)
	assert_eq(timer.phase, UiRoundTimer.Phase.RUNNING)
	timer.show_remaining(n)
	assert_eq(timer.phase, UiRoundTimer.Phase.HURRY)
	timer.show_remaining(0.0)
	assert_eq(timer.phase, UiRoundTimer.Phase.HURRY)
	timer.hurry_seconds = 5.0
	timer.show_remaining(10.0)
	assert_eq(timer.phase, UiRoundTimer.Phase.RUNNING, "the threshold is a property fed from config")


func test_overtime_shows_flare_label() -> void:
	var timer: UiRoundTimer = _timer()
	timer.show_overtime()
	assert_eq(timer.phase, UiRoundTimer.Phase.OVERTIME)
	assert_eq(timer.label.text, UiRoundTimer.tuning().round_timer_overtime_text)
	assert_eq(timer.label.get_theme_color("font_color"), MenuStyleFactory.arcade_tuning().flare_color)


func test_show_match_limited_unlimited_and_sudden_death() -> void:
	var timer: UiRoundTimer = _timer()
	timer.show_match(5, 125.0, false, 999.0)
	assert_eq(timer.label.text, "2:05", "a limited match counts the host's time left down")
	timer.show_match(0, 0.0, false, 75.0)
	assert_eq(timer.label.text, "1:15", "no limit: time played counts up")
	timer.show_match(5, 0.0, true, 75.0)
	assert_eq(timer.phase, UiRoundTimer.Phase.OVERTIME)


func test_limit_minutes_follow_the_mode() -> void:
	var classic: MatchConfig = MatchConfig.new()
	classic.game_mode = MatchConfig.GameMode.CLASSIC
	classic.match_timer_minutes = 0
	assert_eq(UiRoundTimer.limit_minutes_for(classic), 0, "classic with the timer off has no limit")
	classic.match_timer_minutes = 10
	assert_eq(UiRoundTimer.limit_minutes_for(classic), 10)
	var ctf: MatchConfig = MatchConfig.new()
	ctf.game_mode = MatchConfig.GameMode.CAPTURE_THE_FLAG
	ctf.round_timer_minutes = 7
	assert_eq(UiRoundTimer.limit_minutes_for(ctf), 7)
	assert_eq(UiRoundTimer.limit_minutes_for(null), 0)
