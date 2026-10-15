extends GutTest
## core/ai/BotSpecialPlanner.gd's per-type heuristics (spec 2.6, 2.9 "do not aim a Rocket as if it
## homes or a Propeller as if it blows sideways"): plan_v2's chain-aware targeting.


func test_black_hole_radius_equals_special_def_radius() -> void:
	var def: SpecialDef = SpecialDef.find_by_id(&"black_hole")
	var effect: BlackHoleEffect = def.effect as BlackHoleEffect
	assert_gt(effect.pull_radius_m, 0.0)
	assert_eq(BotController.black_hole_pull_radius_m(), effect.pull_radius_m)


# --- plan_v2 (Bot V2, Bontago-1t5.24): chain-aware targeting -----------------

const V2_OWN_TEAM: int = 0
const V2_ENEMY_TEAM: int = 1
const V2_RADIUS: float = 6.0
const V2_OWN_HOME: Vector2 = Vector2(30.0, 0.0)
const V2_ENEMY_HOME: Vector2 = Vector2(-20.0, 0.0)
## Enemy fork (rooted at V2_ENEMY_HOME): A-B-C chain with a D-E branch off B; own chain 5-7.
const V2_A: int = 0
const V2_E: int = 4
const V2_OWN_TIP: int = 7
const V2_WIDE_REACH_M: float = 30.0
const V2_TALL_RADIUS: float = 9.0
const V2_THROW_RANGE_M: float = 25.0
const V2_PULL_RADIUS_M: float = 7.0
const V2_FAR_OFFSET_M: float = 5.0
const V2_NEAR_OFFSET_M: float = 1.0
const V2_VOLCANO_RADIUS_M: float = 2.5
const V2_DRAGGED_OWN: Vector2 = Vector2(-8.0, 3.0)


func _v2_profile(defensive: bool, offensive: bool) -> BotDifficultyProfile:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.uses_defensive_specials = defensive
	profile.uses_offensive_specials = offensive
	return profile


func _v2_view() -> BotWorldView:
	var view: BotWorldView = BotWorldView.new()
	view.team_id = V2_OWN_TEAM
	view.slot_id = 0
	view.own_home = V2_OWN_HOME
	view.has_home = true
	view.team_homes = PackedVector2Array([V2_OWN_HOME])
	view.enemy_homes = PackedVector2Array([V2_ENEMY_HOME])
	view.enemy_home_teams = PackedInt32Array([V2_ENEMY_TEAM])
	var enemy_points: Array[Vector2] = [
		Vector2(-12.0, 0.0), Vector2(-6.0, 0.0), Vector2(0.0, 0.0), Vector2(-6.0, 5.0), Vector2(-6.0, 10.0)
	]
	for point: Vector2 in enemy_points:
		_v2_circle(view, point, V2_ENEMY_TEAM, V2_RADIUS)
	var own_points: Array[Vector2] = [Vector2(24.0, 0.0), Vector2(18.0, 0.0), Vector2(12.0, 0.0)]
	for point: Vector2 in own_points:
		_v2_circle(view, point, V2_OWN_TEAM, V2_RADIUS)
	return view


func _v2_circle(view: BotWorldView, at: Vector2, team: int, radius: float) -> void:
	view.cx.append(at.x)
	view.cz.append(at.y)
	view.cr.append(radius)
	view.cteam.append(team)


func _v2_tuning(reach_m: float = V2_WIDE_REACH_M) -> BotTuning:
	var tuning: BotTuning = BotTuning.new()
	tuning.special_v2_reach_m = reach_m
	return tuning


func _v2_own_sites() -> PackedVector2Array:
	return PackedVector2Array([Vector2(24.0, 0.0), Vector2(18.0, 0.0), Vector2(12.0, 0.0), Vector2(14.0, 3.0)])


func _v2_plan(
	id: StringName, view: BotWorldView, profile: BotDifficultyProfile, tuning: BotTuning, range_m: float = 0.0
) -> BotSpecialPlanner.BotSpecialAction:
	return BotSpecialPlanner.plan_v2(
		id, view, BotChains.build(view), profile, tuning, _v2_own_sites(), range_m, V2_PULL_RADIUS_M
	)


func test_v2_area_specials_aim_at_highest_downstream_joint_not_nearest_tip() -> void:
	var view: BotWorldView = _v2_view()
	assert_eq(BotChains.build(view).downstream(V2_A), 5, "fixture: the root-side joint is the biggest cut")
	for id: StringName in [&"rocket", &"volcano", &"jumping_bean"]:
		var action: BotSpecialPlanner.BotSpecialAction = _v2_plan(id, view, _v2_profile(true, true), _v2_tuning())
		assert_true(action.has_place_target, "%s has a target" % id)
		assert_false(action.should_throw, "%s is placed, never thrown" % id)
		assert_eq(action.place_target, Vector2(12.0, 0.0), "%s snaps to the own site nearest the root joint" % id)


func test_v2_out_of_reach_or_small_cut_spends_special_normally() -> void:
	var view: BotWorldView = _v2_view()
	var far: BotSpecialPlanner.BotSpecialAction = _v2_plan(&"rocket", view, _v2_profile(true, true), _v2_tuning(1.0))
	assert_false(far.has_place_target, "nothing within 1 m of own land")
	var short: BotSpecialPlanner.BotSpecialAction = _v2_plan(
		&"rocket", view, _v2_profile(true, true), _v2_tuning(V2_RADIUS)
	)
	assert_false(short.has_place_target, "only the leaf C is in reach and a leaf cuts too little")


func test_v2_bomb_throws_from_range_matched_origin() -> void:
	var view: BotWorldView = _v2_view()
	var tuning: BotTuning = _v2_tuning()
	var action: BotSpecialPlanner.BotSpecialAction = _v2_plan(
		&"bomb", view, _v2_profile(true, true), tuning, V2_THROW_RANGE_M
	)
	assert_true(action.should_throw)
	assert_false(action.should_place_ordinarily)
	assert_true(action.throw_velocity.x < 0.0, "thrown toward the enemy side")
	var origin_error: float = absf(action.throw_origin.distance_to(Vector2(-12.0, 0.0)) - V2_THROW_RANGE_M)
	assert_true(origin_error <= tuning.special_v2_throw_tolerance_m, "release point is within tolerance of the range")
	var short_range: BotSpecialPlanner.BotSpecialAction = _v2_plan(&"bomb", view, _v2_profile(true, true), tuning, 1.0)
	assert_false(short_range.should_throw, "no release point matches a 1 m range")


func test_v2_paintball_targets_tallest_enemy_stack() -> void:
	var view: BotWorldView = _v2_view()
	view.cr[V2_E] = V2_TALL_RADIUS
	var sites: PackedVector2Array = PackedVector2Array([Vector2(12.0, 0.0), Vector2(-4.0, 10.0)])
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan_v2(
		&"paintball", view, BotChains.build(view), _v2_profile(true, true), _v2_tuning(), sites
	)
	assert_true(action.has_place_target)
	assert_eq(action.place_target, Vector2(-4.0, 10.0), "own site nearest the tall branch tip (-6, 10)")


func test_v2_freeze_prefers_goal_covering_own_tower() -> void:
	var view: BotWorldView = _v2_view()
	view.goals = PackedVector2Array([Vector2(18.0, 1.0)])
	var action: BotSpecialPlanner.BotSpecialAction = _v2_plan(&"freeze", view, _v2_profile(true, true), _v2_tuning())
	assert_true(action.has_place_target)
	assert_eq(action.place_target, Vector2(18.0, 0.0))
	var glue: BotSpecialPlanner.BotSpecialAction = _v2_plan(&"glue", view, _v2_profile(true, true), _v2_tuning())
	assert_eq(glue.place_target, Vector2(18.0, 0.0), "glue defends the same tower")


func test_v2_freeze_without_goal_picks_threatened_tower() -> void:
	var view: BotWorldView = _v2_view()
	var tuning: BotTuning = _v2_tuning()
	tuning.special_v2_threat_gap_m = -1.0
	var calm: BotSpecialPlanner.BotSpecialAction = _v2_plan(&"freeze", view, _v2_profile(true, true), tuning)
	assert_false(calm.has_place_target, "no own circle is closer than -1 m (overlapping) to an enemy")
	tuning.special_v2_threat_gap_m = 8.0
	var action: BotSpecialPlanner.BotSpecialAction = _v2_plan(&"freeze", view, _v2_profile(true, true), tuning)
	assert_true(action.has_place_target)
	assert_eq(action.place_target, Vector2(18.0, 0.0), "the highest-downstream own circle with an enemy inside the gap")


func test_v2_stackfall_at_own_tip_toward_goal() -> void:
	var view: BotWorldView = _v2_view()
	view.goals = PackedVector2Array([Vector2(0.0, 0.0)])
	var action: BotSpecialPlanner.BotSpecialAction = _v2_plan(&"stackfall", view, _v2_profile(true, true), _v2_tuning())
	assert_true(action.has_place_target)
	assert_eq(action.place_target, Vector2(12.0, 0.0))


func test_v2_tilt_takes_the_farthest_own_site() -> void:
	var view: BotWorldView = _v2_view()
	var action: BotSpecialPlanner.BotSpecialAction = _v2_plan(&"propeller", view, _v2_profile(true, true), _v2_tuning())
	assert_eq(action.place_target, Vector2(12.0, 0.0), "own site farthest from the home flag")


func test_v2_easy_never_and_defensive_only_never_offensive() -> void:
	var view: BotWorldView = _v2_view()
	for id: StringName in [&"rocket", &"bomb", &"freeze", &"stackfall", &"paintball", &"propeller"]:
		var easy: BotSpecialPlanner.BotSpecialAction = _v2_plan(
			id, view, _v2_profile(false, false), _v2_tuning(), V2_THROW_RANGE_M
		)
		assert_false(easy.has_place_target or easy.should_throw, "easy never uses %s" % id)
	for id: StringName in [&"rocket", &"bomb", &"volcano", &"paintball", &"black_hole"]:
		var calm: BotSpecialPlanner.BotSpecialAction = _v2_plan(
			id, view, _v2_profile(true, false), _v2_tuning(), V2_THROW_RANGE_M
		)
		assert_false(calm.has_place_target or calm.should_throw, "defensive-only never uses offensive %s" % id)


func test_v2_black_hole_skips_target_that_drags_in_own_tower() -> void:
	var view: BotWorldView = _v2_view()
	var sites: PackedVector2Array = PackedVector2Array([Vector2(-10.0, 0.0)])
	var chains: BotChains = BotChains.build(view)
	var profile: BotDifficultyProfile = _v2_profile(true, true)
	var own_penalised: BotTuning = _v2_tuning()
	own_penalised.black_hole_own_penalty = 100.0
	var clean: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan_v2(
		&"black_hole", view, chains, profile, _v2_tuning(), sites, 0.0, V2_PULL_RADIUS_M
	)
	assert_true(clean.has_place_target, "the enemy joint is far from own blocks")
	view.cx[V2_OWN_TIP] = V2_DRAGGED_OWN.x
	view.cz[V2_OWN_TIP] = V2_DRAGGED_OWN.y
	var dragged: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan_v2(
		&"black_hole", view, BotChains.build(view), profile, own_penalised, sites, 0.0, V2_PULL_RADIUS_M
	)
	assert_false(dragged.has_place_target, "an own circle inside the pull radius cancels every joint")


func test_v2_placed_special_skips_when_own_land_is_beyond_effect_radius() -> void:
	var view: BotWorldView = _v2_view()
	var profile: BotDifficultyProfile = _v2_profile(true, true)
	var tuning: BotTuning = _v2_tuning()
	var chains: BotChains = BotChains.build(view)
	var target: Vector2 = Vector2(-12.0, 0.0)
	var far_site: PackedVector2Array = PackedVector2Array([target + Vector2(V2_FAR_OFFSET_M, 0.0)])
	var near_site: PackedVector2Array = PackedVector2Array([target + Vector2(V2_NEAR_OFFSET_M, 0.0)])
	var far: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan_v2(
		&"volcano", view, chains, profile, tuning, far_site, 0.0, 0.0, V2_VOLCANO_RADIUS_M
	)
	assert_false(far.has_place_target, "5 m off own land is outside a 2.5 m volcano")
	var near: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan_v2(
		&"volcano", view, chains, profile, tuning, near_site, 0.0, 0.0, V2_VOLCANO_RADIUS_M
	)
	assert_true(near.has_place_target, "1 m off is inside the effect radius")
	assert_eq(near.place_target, near_site[0])
