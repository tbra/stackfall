extends "res://tests/unit/match/match_world_test.gd"
## Match.punch_special_hole (spec 1.6): HoleMode gating, home-flag elimination, no punch after END.

func _real_time_config(hole_mode: MatchConfig.HoleMode) -> MatchConfig:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = 2
	config.block_timer = 6.0
	config.rng_seed = 12345
	config.hole_mode = hole_mode
	return config


func test_punch_special_hole_is_a_noop_under_hole_mode_off() -> void:
	Match.start_match(_real_time_config(MatchConfig.HoleMode.OFF))
	_run_countdown()
	watch_signals(Events)

	var home0: Vector2 = Match.slot(0).home_position
	Match.punch_special_hole(home0, 2.0, 2.0)

	var cell: Vector2i = Match.cell_grid().world_to_cell(home0)
	assert_false(Match.raster().is_hole(cell.x, cell.y), "OFF must never open a hole.")
	assert_signal_not_emitted(Events, "hole_cells_changed")
	assert_true(Match.slot(0).home_flag_alive, "OFF must not eliminate anyone either.")


# --- Radius and the change-set (TEMPORARY) ----------------------------------

# --- Home-flag elimination (orchestrator decision 2) -----------

func test_punch_special_hole_eliminates_a_home_flag_sitting_in_the_punched_disk() -> void:
	Match.start_match(_real_time_config(MatchConfig.HoleMode.TEMPORARY))
	_run_countdown()
	watch_signals(Events)

	var home0: Vector2 = Match.slot(0).home_position
	Match.punch_special_hole(home0, 2.0, 2.0)

	assert_false(Match.slot(0).home_flag_alive)
	assert_signal_emitted_with_parameters(Events, "player_eliminated", [0, 0])


# --- Match-state guard (SHOULD-FIX, review) ----------------------
#
# _finish_match() only sets State.END (autoload/match/MatchLifecycle.gd);
# nothing tears the raster down or stops a SpecialEffect's physics_tick(), so
# a Jumping Bean still hopping after a natural win could otherwise still
# punch a hole under a still-alive slot's home flag on the winning team and
# eliminate it after the match is already decided. Mirrors
# MatchPlacement.spawn_special_projectile()'s own State.PLAYING guard.
func test_punch_special_hole_is_a_noop_after_the_match_has_ended() -> void:
	Match.start_match(_real_time_config(MatchConfig.HoleMode.TEMPORARY))
	_run_countdown()
	assert_true(Match.slot(1).home_flag_alive, "Setup: slot 1 is still alive.")

	Match._lifecycle._finish_match(0)
	assert_eq(Match.state(), Match.State.END, "Setup: the match already has a winner.")
	watch_signals(Events)

	var home1: Vector2 = Match.slot(1).home_position
	Match.punch_special_hole(home1, 2.0, 2.0)

	var cell: Vector2i = Match.cell_grid().world_to_cell(home1)
	assert_false(Match.raster().is_hole(cell.x, cell.y),
		"A punch after State.END must not open a hole at all.")
	assert_true(Match.slot(1).home_flag_alive,
		"A slot still alive when the match ended must not be eliminated afterwards.")
	assert_signal_not_emitted(Events, "player_eliminated")
