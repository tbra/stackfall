extends GutTest
## pure rules for airborne gifts / incoming enemy specials in the bot world view.


func test_ballistic_impact_drop_and_throw() -> void:
	var drop: Vector3 = BotWorldView.ballistic_impact(Vector2(1.0, 2.0), 20.0, Vector2.ZERO, 0.0, 10.0)
	assert_eq(Vector2(drop.x, drop.y), Vector2(1.0, 2.0), "a straight drop lands below itself")
	assert_almost_eq(drop.z, 2.0, 0.001, "t = sqrt(2h/g)")
	var arc: Vector3 = BotWorldView.ballistic_impact(Vector2.ZERO, 0.0, Vector2(3.0, 0.0), 5.0, 10.0)
	assert_almost_eq(arc.z, 1.0, 0.001, "up at 5 m/s from the surface returns after 1 s")
	assert_almost_eq(arc.x, 3.0, 0.001, "horizontal travel over the flight time")


func test_ballistic_impact_degenerate_inputs_return_own_point() -> void:
	var at_rest: Vector3 = BotWorldView.ballistic_impact(Vector2(4.0, 5.0), 0.0, Vector2(1.0, 1.0), -1.0, 10.0)
	assert_eq(Vector2(at_rest.x, at_rest.y), Vector2(4.0, 5.0))
	assert_eq(at_rest.z, 0.0)
	var no_gravity: Vector3 = BotWorldView.ballistic_impact(Vector2.ZERO, 5.0, Vector2(1.0, 0.0), 0.0, 0.0)
	assert_eq(no_gravity.z, 0.0)


func test_incoming_special_risk_zero_without_incoming() -> void:
	var view: BotWorldView = BotWorldView.new()
	var candidate: BotCandidate = BotCandidate.new()
	assert_eq(BotEvaluator.incoming_special_risk(candidate, view), 0.0)


func test_incoming_special_risk_grades_by_distance() -> void:
	var view: BotWorldView = BotWorldView.new()
	view.add_incoming_special(Vector2(10.0, 0.0), 3.0)
	view.add_incoming_special(Vector2(0.0, 0.0), 0.0)
	assert_eq(view.incoming_points.size(), 1, "a zero-radius special is skipped")
	var near: BotCandidate = BotCandidate.new()
	near.origin = Vector2(10.0, 0.0)
	var edge: BotCandidate = BotCandidate.new()
	edge.origin = Vector2(10.0 + 3.0 + BotEvaluator.tuning.incoming_margin_m, 0.0)
	var mid: BotCandidate = BotCandidate.new()
	mid.origin = Vector2(12.0, 0.0)
	var weight: float = BotEvaluator.tuning.incoming_special_weight
	assert_almost_eq(BotEvaluator.incoming_special_risk(near, view), weight, 0.0001, "full at the impact point")
	assert_eq(BotEvaluator.incoming_special_risk(edge, view), 0.0, "none at the zone edge")
	var mid_risk: float = BotEvaluator.incoming_special_risk(mid, view)
	assert_true(mid_risk > 0.0 and mid_risk < weight, "graded in between")
