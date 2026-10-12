extends GutTest
## Bontago-1pi.159.34: UiRoundTimer (the match clock): m:ss format, hurry threshold from config, limited vs
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


func test_hurry_turns_numerals_and_edge_rim_gold() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var timer: UiRoundTimer = _timer()
	timer.show_remaining(UiRoundTimer.tuning().round_timer_hurry_seconds + 30.0)
	assert_eq(timer.label.get_theme_color("font_color"), arcade.cream_color)
	timer.show_remaining(3.0)
	assert_eq(timer.label.get_theme_color("font_color"), arcade.rim_color)
	assert_eq((timer.get_theme_stylebox("panel") as StyleBoxFlat).border_color, arcade.rim_color)


func test_elapsed_never_hurries() -> void:
	var timer: UiRoundTimer = _timer()
	timer.show_elapsed(1.0)
	assert_eq(timer.phase, UiRoundTimer.Phase.RUNNING)


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


func test_clear_hides_the_plate() -> void:
	var timer: UiRoundTimer = _timer()
	timer.show_remaining(10.0)
	assert_true(timer.visible)
	timer.clear()
	assert_false(timer.visible)


func test_never_takes_focus_or_mouse() -> void:
	var timer: UiRoundTimer = _timer()
	assert_eq(timer.focus_mode, Control.FOCUS_NONE)
	assert_eq(timer.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_numerals_use_the_display_font_and_config_size() -> void:
	var timer: UiRoundTimer = _timer()
	timer.show_remaining(100.0)
	assert_eq(timer.label.get_theme_font_size("font_size"), UiRoundTimer.tuning().round_timer_font_px)
	var display: Font = (load("res://ui/theme/stackfall_theme.tres") as Theme).get_font(&"font", &"DisplayLabel")
	assert_eq(timer.label.get_theme_font("font"), display)


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


func test_hud_builds_a_hidden_round_timer_beside_the_feed_ring() -> void:
	var hud: HUD = HUD.new() if false else (load("res://ui/HUD.tscn") as PackedScene).instantiate() as HUD
	add_child_autofree(hud)
	assert_not_null(hud._round_timer)
	assert_false(hud._round_timer.visible, "hidden outside live play")
	var ring_right: float = hud._timer_ring.offset_right
	var slot: Control = hud._round_timer.get_parent() as Control
	assert_gt(slot.offset_left, ring_right, "the plate is right of the ring, not over it")
	assert_eq(slot.offset_top, hud._timer_ring.offset_top)
