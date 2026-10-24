extends GutTest
## ClearanceRaise.first_clear_raise (core/blocks/ClearanceRaise.gd): the shared "lift a pose
## straight up until it is clear" search. The overlap Callable models a floor at height h:
## a raise overlaps while raise < h. Expected values are hand-computed literals.

const TOL: float = 0.000001


func _floor(h: float, log: Array[float] = []) -> Callable:
	return func(r: float) -> bool:
		log.append(r)
		return r < h


func test_floor_with_linear_step_then_bisect_then_margin() -> void:
	# tries .001 .002 .003 overlap, .004 clears (low .003, high .004); bisect 4 gives
	# high .003625; margin .002 added.
	var got: float = ClearanceRaise.first_clear_raise(_floor(0.0036), 0.001, 1.0, 4, 0.002)
	assert_almost_eq(got, 0.005625, TOL)


func test_floor_on_exact_step_boundary() -> void:
	# .25 overlaps, .5 clears; bisect 3 never finds a clear point below .5 (high stays .5).
	var got: float = ClearanceRaise.first_clear_raise(_floor(0.5), 0.25, 2.0, 3, 0.0625)
	assert_almost_eq(got, 0.5625, TOL)


func test_clear_at_first_step_bisects_from_zero_low() -> void:
	# clear at .25 (low 0): mid .125 clears (high), mid .0625 overlaps (low) -> .125
	var got: float = ClearanceRaise.first_clear_raise(_floor(0.1), 0.25, 2.0, 2, 0.0)
	assert_almost_eq(got, 0.125, TOL)
	got = ClearanceRaise.first_clear_raise(_floor(0.1), 0.25, 2.0, 2, 0.01)
	assert_almost_eq(got, 0.135, TOL)


func test_zero_bisect_steps_returns_linear_hit_plus_margin() -> void:
	var got: float = ClearanceRaise.first_clear_raise(_floor(0.3), 0.25, 2.0, 0, 0.1)
	assert_almost_eq(got, 0.6, TOL)


func test_never_queries_zero_and_first_query_is_the_step() -> void:
	var log: Array[float] = []
	ClearanceRaise.first_clear_raise(_floor(0.6, log), 0.25, 2.0, 3, 0.0)
	assert_gt(log.size(), 0)
	assert_almost_eq(log[0], 0.25, TOL, "first query is at step")
	for r: float in log:
		assert_gt(r, 0.0, "overlaps(0.0) is the caller's check, never the core's")


func test_already_clear_at_first_step_with_no_bisect_queries_once() -> void:
	var log: Array[float] = []
	var got: float = ClearanceRaise.first_clear_raise(_floor(0.1, log), 0.25, 2.0, 0, 0.0)
	assert_almost_eq(got, 0.25, TOL)
	assert_eq(log.size(), 1)


func test_result_is_clamped_to_cap_by_margin() -> void:
	# clears at .4 (the cap); margin .5 would exceed it.
	var got: float = ClearanceRaise.first_clear_raise(_floor(0.35), 0.1, 0.4, 0, 0.5)
	assert_almost_eq(got, 0.4, TOL)


func test_clear_exactly_at_cap_is_found() -> void:
	var got: float = ClearanceRaise.first_clear_raise(_floor(1.0), 0.25, 1.0, 0, 0.0)
	assert_almost_eq(got, 1.0, TOL)


func test_last_step_clamped_to_cap_is_tried() -> void:
	# step .5, cap .99995: the second try (1.0) is within the cap slack and is clamped to
	# .99995, which clears; bisect 0 and margin .1 clamp to the cap.
	var got: float = ClearanceRaise.first_clear_raise(_floor(0.7), 0.5, 0.99995, 0, 0.1)
	assert_almost_eq(got, 0.99995, TOL)
	# with 2 bisections: mid .749975 clears, mid .6249875 overlaps -> high .749975, +.1
	got = ClearanceRaise.first_clear_raise(_floor(0.7), 0.5, 0.99995, 2, 0.1)
	assert_almost_eq(got, 0.849975, TOL)


func test_floor_above_cap_is_not_cleared() -> void:
	var got: float = ClearanceRaise.first_clear_raise(_floor(1.5), 0.25, 1.0, 4, 0.01)
	assert_eq(got, ClearanceRaise.NOT_CLEARED)


func test_floor_just_above_cap_is_not_cleared() -> void:
	var got: float = ClearanceRaise.first_clear_raise(_floor(1.0001), 0.25, 1.0, 4, 0.01)
	assert_eq(got, ClearanceRaise.NOT_CLEARED)


func test_overshooting_step_never_probes_the_cap_itself() -> void:
	# step .001, cap .0025: tries .001 .002 then .003 > cap + slack ends the walk, so a
	# floor at .0023 (clear at the cap) is still reported NOT_CLEARED (today's arithmetic).
	var got: float = ClearanceRaise.first_clear_raise(_floor(0.0023), 0.001, 0.0025, 4, 0.0)
	assert_eq(got, ClearanceRaise.NOT_CLEARED)


func test_zero_cap_is_not_cleared() -> void:
	var got: float = ClearanceRaise.first_clear_raise(_floor(0.0), 0.25, 0.0, 4, 0.0)
	assert_eq(got, ClearanceRaise.NOT_CLEARED)


func test_always_overlapping_terminates_not_cleared() -> void:
	var always: Callable = func(_r: float) -> bool: return true
	var got: float = ClearanceRaise.first_clear_raise(always, 0.25, 1.0, 4, 0.01)
	assert_eq(got, ClearanceRaise.NOT_CLEARED)


func test_tiny_or_nonpositive_step_is_floored() -> void:
	# a step below the .001 floor behaves as .001 (same literal as the first test).
	for step: float in [0.0005, 0.0, -1.0]:
		var got: float = ClearanceRaise.first_clear_raise(_floor(0.0036), step, 1.0, 4, 0.002)
		assert_almost_eq(got, 0.005625, TOL, "step %s" % step)


func test_step_landing_exactly_on_cap_plus_slack_is_still_tried() -> void:
	# step .5001 = cap + slack (.5 + .0001): the one try is allowed, clamped to the cap, clears.
	var got: float = ClearanceRaise.first_clear_raise(_floor(0.3), 0.5001, 0.5, 0, 0.0)
	assert_almost_eq(got, 0.5, TOL)


func test_every_bisection_step_runs() -> void:
	# floor .26, low .25, high .5: four bisections each clear, ending at .265625; three would end at .28125.
	var got: float = ClearanceRaise.first_clear_raise(_floor(0.26), 0.25, 2.0, 4, 0.0)
	assert_almost_eq(got, 0.265625, TOL)
