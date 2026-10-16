extends GutTest
## ClaimProgressExtrapolator: the shared client-side hold extrapolation (Sfx + HUD).

const HOLD_S: float = 20.0


func test_sparse_updates_rise_monotonically_and_snap() -> void:
	var ex: ClaimProgressExtrapolator = ClaimProgressExtrapolator.new()
	ex.snap(0, 0.1)
	var last: float = ex.progress()
	for i: int in range(5):
		assert_true(ex.advance(1.0, HOLD_S))
		assert_gt(ex.progress(), last)
		last = ex.progress()
	assert_almost_eq(last, 0.35, 0.0001)
	ex.snap(0, 0.6)
	assert_almost_eq(ex.progress(), 0.6, 0.0001)


func test_stops_on_break_team_change_and_clear() -> void:
	var ex: ClaimProgressExtrapolator = ClaimProgressExtrapolator.new()
	ex.snap(0, 0.5)
	ex.snap(-1, 0.0)
	assert_false(ex.advance(1.0, HOLD_S))
	ex.snap(0, 0.5)
	ex.snap(1, 0.2)
	assert_eq(ex.team(), 1)
	assert_almost_eq(ex.progress(), 0.2, 0.0001, "team change snaps, never carries over")
	ex.clear()
	assert_false(ex.is_holding())
	assert_false(ex.advance(1.0, HOLD_S))


func test_does_not_rise_while_the_value_is_falling() -> void:
	# An Elimination home claim fades slowly after a lapse: the received value
	# drops, so extrapolating it upward would fight the real decay.
	var ex: ClaimProgressExtrapolator = ClaimProgressExtrapolator.new()
	ex.snap(0, 0.5)
	assert_true(ex.advance(1.0, HOLD_S))
	ex.snap(0, 0.4)
	assert_false(ex.advance(1.0, HOLD_S), "falling value is not extrapolated up")
	assert_almost_eq(ex.progress(), 0.4, 0.0001)
	ex.snap(0, 0.45)
	assert_true(ex.advance(1.0, HOLD_S), "rising again resumes extrapolation")
