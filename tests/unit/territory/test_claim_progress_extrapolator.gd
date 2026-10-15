extends GutTest
## Bontago-1pi.117: the shared client-side hold extrapolation (Sfx + HUD).

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


func test_caps_at_full_hold() -> void:
	var ex: ClaimProgressExtrapolator = ClaimProgressExtrapolator.new()
	ex.snap(2, 0.9)
	ex.advance(1000.0, HOLD_S)
	assert_almost_eq(ex.progress(), 1.0, 0.0001)
	assert_false(ex.advance(1.0, HOLD_S))


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


func test_invalid_hold_does_not_advance() -> void:
	var ex: ClaimProgressExtrapolator = ClaimProgressExtrapolator.new()
	ex.snap(0, 0.5)
	assert_false(ex.advance(1.0, 0.0))
	assert_false(ex.advance(-1.0, HOLD_S))
