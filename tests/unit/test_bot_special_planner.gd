extends GutTest
## core/ai/BotSpecialPlanner.gd's per-type heuristics (docs/M5_PLAN.md P3,
## Bontago-d5c.4; spec 2.6, 2.9 "do not aim a Rocket as if it homes or a
## Propeller as if it blows sideways").

const HOME: Vector2 = Vector2.ZERO


## Mirrors the shipped config/bot_tuning.tres flag combination (easy
## false/false, normal true/false, hard true/true) so a test can exercise
## `plan()`'s own difficulty-gated branch without loading the real .tres.
func _real_shaped_tuning() -> BotTuning:
	var tuning: BotTuning = BotTuning.new()
	var easy: BotDifficultyProfile = BotDifficultyProfile.new()
	easy.uses_defensive_specials = false
	easy.uses_offensive_specials = false
	var normal: BotDifficultyProfile = BotDifficultyProfile.new()
	normal.uses_defensive_specials = true
	normal.uses_offensive_specials = false
	var hard: BotDifficultyProfile = BotDifficultyProfile.new()
	hard.uses_defensive_specials = true
	hard.uses_offensive_specials = true
	tuning.easy = easy
	tuning.normal = normal
	tuning.hard = hard
	return tuning


## A tuning whose easy/normal/hard profiles are all the same hand-picked
## defensive/offensive combination -- for tests that only care about one
## specific combination, independent of which difficulty enum value is passed.
func _uniform_tuning(defensive: bool, offensive: bool) -> BotTuning:
	var tuning: BotTuning = BotTuning.new()
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.uses_defensive_specials = defensive
	profile.uses_offensive_specials = offensive
	tuning.easy = profile
	tuning.normal = profile
	tuning.hard = profile
	return tuning


# --- Rocket: never thrown ----------------------------------------------------

func test_rocket_never_should_throw() -> void:
	var tuning: BotTuning = _uniform_tuning(true, true)
	var points: PackedVector2Array = PackedVector2Array([Vector2(1.0, 0.0), Vector2(-1.0, 0.0)])
	var enemies: PackedVector2Array = PackedVector2Array([Vector2(10.0, 0.0)])
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"rocket", HOME, points, enemies, PackedVector2Array(), MatchConfig.AiDifficulty.HARD, tuning
	)
	assert_false(action.should_throw, "a Rocket has no homing target -- it is always placed, never thrown")
	assert_true(action.should_place_ordinarily, "falls through to the ordinary placement path")


func test_rocket_never_should_throw_even_with_no_enemies() -> void:
	var tuning: BotTuning = _uniform_tuning(true, true)
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"rocket", HOME, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
		MatchConfig.AiDifficulty.HARD, tuning
	)
	assert_false(action.should_throw)
	assert_true(action.should_place_ordinarily)


# --- Bomb: thrown at the nearest/densest enemy cluster -----------------------

func test_bomb_should_throw_toward_the_cluster_under_the_speed_cap() -> void:
	var tuning: BotTuning = _uniform_tuning(true, false)
	var points: PackedVector2Array = PackedVector2Array([Vector2(1.0, 0.0), Vector2(-1.0, 0.0)])
	var cluster: Vector2 = Vector2(10.0, 0.0)
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"bomb", HOME, points, PackedVector2Array([cluster]), PackedVector2Array(),
		MatchConfig.AiDifficulty.NORMAL, tuning
	)
	assert_true(action.should_throw, "an impact is what activates a Bomb -- it is thrown at the cluster")
	assert_false(action.should_place_ordinarily)
	assert_eq(action.throw_origin, Vector2(1.0, 0.0), "the own-territory sample point nearest the cluster")
	assert_true(action.throw_velocity.x > 0.0, "aimed toward the cluster's +x direction")
	assert_true(action.throw_velocity.y > 0.0, "a ballistic estimate lofts upward")
	assert_almost_eq(
		action.throw_velocity.length(), tuning.special_throw_speed_mps, 0.01,
		"normalised to the BotTuning speed cap"
	)
	var special_tuning: SpecialTuning = SpecialTuning.new()
	assert_true(
		action.throw_velocity.length() <= special_tuning.throw_max_speed,
		"the AI's own pre-clamp speed must already sit at or under SpecialTuning.throw_max_speed"
	)


func test_bomb_with_no_enemies_does_not_throw_and_has_finite_velocity() -> void:
	var tuning: BotTuning = _uniform_tuning(true, true)
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"bomb", HOME, PackedVector2Array([Vector2(1.0, 0.0)]), PackedVector2Array(), PackedVector2Array(),
		MatchConfig.AiDifficulty.HARD, tuning
	)
	assert_false(action.should_throw, "nothing to aim at -- falls back to placing it ordinarily")
	assert_true(action.should_place_ordinarily)
	assert_true(action.throw_velocity.is_finite(), "never NaN even with no target")


# --- EASY (both flags false): always place ordinarily, regardless of id -----

func test_easy_always_places_ordinarily_regardless_of_id() -> void:
	var tuning: BotTuning = _real_shaped_tuning()
	var points: PackedVector2Array = PackedVector2Array([Vector2(1.0, 0.0), Vector2(-5.0, 0.0)])
	var enemies: PackedVector2Array = PackedVector2Array([Vector2(3.0, 0.0), Vector2(-2.0, 0.0)])
	var ids: Array[StringName] = [
		&"rocket", &"bomb", &"volcano", &"earthquake", &"anvil", &"propeller", &"jumping_bean", &"", &"magnet",
	]
	for id: StringName in ids:
		var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
			id, HOME, points, enemies, PackedVector2Array(), MatchConfig.AiDifficulty.EASY, tuning
		)
		assert_false(action.should_throw, "EASY never throws a special (id=%s)" % id)
		assert_true(action.should_place_ordinarily, "EASY always places ordinarily (id=%s)" % id)


# --- Unknown/unrecognized id: safe fallback ----------------------------------

func test_unknown_id_falls_back_to_ordinary_placement() -> void:
	var tuning: BotTuning = _real_shaped_tuning()
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"magnet", HOME, PackedVector2Array([Vector2(1.0, 0.0)]), PackedVector2Array([Vector2(5.0, 0.0)]),
		PackedVector2Array(), MatchConfig.AiDifficulty.HARD, tuning
	)
	assert_false(action.should_throw)
	assert_true(action.should_place_ordinarily)


# --- Empty enemy_circle_centers: never NaN/zero-direction, no throw ----------

func test_empty_enemy_list_never_throws_and_stays_finite_for_every_offensive_id() -> void:
	var tuning: BotTuning = _uniform_tuning(true, true)
	var points: PackedVector2Array = PackedVector2Array([Vector2(1.0, 0.0)])
	var ids: Array[StringName] = [&"rocket", &"bomb", &"volcano", &"jumping_bean"]
	for id: StringName in ids:
		var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
			id, HOME, points, PackedVector2Array(), PackedVector2Array(), MatchConfig.AiDifficulty.HARD, tuning
		)
		assert_false(action.should_throw, "no enemies to target (id=%s)" % id)
		assert_true(action.throw_velocity.is_finite(), "never NaN with an empty enemy list (id=%s)" % id)
		assert_true(action.should_place_ordinarily, "falls back to ordinary placement (id=%s)" % id)


# --- Volcano: defensive vs offensive selection by flags ----------------------

func _volcano_scenario() -> Dictionary:
	# Cluster of three near (3, *) -- densest by BotSpecialPlanner's own
	# risk_enemy_territory_radius_m (4.0 default) grouping -- and one lone
	# enemy at (-2, 0) that is nonetheless the *nearest single* enemy to HOME
	# (distance 2.0 vs. the cluster's 3.0), so "nearest enemy" (defensive
	# heuristic) and "densest cluster" (offensive heuristic) resolve to two
	# different points -- the two branches are only distinguishable if they
	# do not.
	var enemies: PackedVector2Array = PackedVector2Array([
		Vector2(3.0, 0.0), Vector2(3.0, 0.5), Vector2(3.0, 1.0), Vector2(-2.0, 0.0),
	])
	# Nearest own-territory sample point to the lone enemy (-2, 0) is (-1, 0);
	# nearest to the cluster center (3, 0) is (2, 0).
	var points: PackedVector2Array = PackedVector2Array([Vector2(-1.0, 0.0), Vector2(2.0, 0.0), Vector2(50.0, 50.0)])
	return {"enemies": enemies, "points": points}


func test_volcano_defensive_targets_the_nearest_single_enemy_border() -> void:
	var scenario: Dictionary = _volcano_scenario()
	var tuning: BotTuning = _uniform_tuning(true, false)
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"volcano", HOME, scenario["points"], scenario["enemies"], PackedVector2Array(),
		MatchConfig.AiDifficulty.NORMAL, tuning
	)
	assert_false(action.should_throw, "an eruption doesn't benefit from a throw's flight time")
	assert_true(action.should_place_ordinarily)
	assert_eq(action.throw_origin, Vector2(-1.0, 0.0), "defensive: near the border closest to any single enemy")


func test_volcano_offensive_targets_the_densest_enemy_cluster() -> void:
	var scenario: Dictionary = _volcano_scenario()
	var tuning: BotTuning = _uniform_tuning(false, true)
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"volcano", HOME, scenario["points"], scenario["enemies"], PackedVector2Array(),
		MatchConfig.AiDifficulty.NORMAL, tuning
	)
	assert_false(action.should_throw)
	assert_true(action.should_place_ordinarily)
	assert_eq(action.throw_origin, Vector2(2.0, 0.0), "offensive: near the densest enemy cluster")


func test_volcano_with_no_enemies_places_ordinarily() -> void:
	var tuning: BotTuning = _uniform_tuning(true, true)
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"volcano", HOME, PackedVector2Array([Vector2(1.0, 0.0)]), PackedVector2Array(), PackedVector2Array(),
		MatchConfig.AiDifficulty.HARD, tuning
	)
	assert_false(action.should_throw)
	assert_true(action.should_place_ordinarily)


# --- Earthquake/Anvil/Propeller: farthest own-territory point from home -----

func test_tilt_specials_pick_the_point_farthest_from_own_home() -> void:
	var tuning: BotTuning = _uniform_tuning(true, false)
	var points: PackedVector2Array = PackedVector2Array([Vector2(1.0, 0.0), Vector2(-5.0, 0.0), Vector2(0.0, 3.0)])
	for id: StringName in [&"earthquake", &"anvil", &"propeller"]:
		var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
			id, HOME, points, PackedVector2Array(), PackedVector2Array(), MatchConfig.AiDifficulty.NORMAL, tuning
		)
		assert_false(action.should_throw, "a tilt effect self-triggers -- never thrown (id=%s)" % id)
		assert_true(action.should_place_ordinarily, "id=%s" % id)
		assert_eq(action.throw_origin, Vector2(-5.0, 0.0), "the farthest own-territory sample point (id=%s)" % id)


func test_tilt_specials_never_crash_with_no_territory_samples() -> void:
	var tuning: BotTuning = _uniform_tuning(true, true)
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"anvil", HOME, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
		MatchConfig.AiDifficulty.HARD, tuning
	)
	assert_false(action.should_throw)
	assert_true(action.should_place_ordinarily)
	assert_eq(action.throw_origin, HOME, "falls back to the bot's own home with no territory samples at all")


# --- Jumping Bean: only when uses_offensive_specials -------------------------

func test_jumping_bean_targets_own_edge_nearest_an_enemy_home_when_offensive() -> void:
	var tuning: BotTuning = _uniform_tuning(false, true)
	var points: PackedVector2Array = PackedVector2Array([Vector2(-1.0, 0.0), Vector2(4.0, 0.0)])
	var enemies: PackedVector2Array = PackedVector2Array([Vector2(5.0, 0.0)])
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"jumping_bean", HOME, points, enemies, PackedVector2Array(), MatchConfig.AiDifficulty.HARD, tuning
	)
	assert_false(action.should_throw)
	assert_true(action.should_place_ordinarily)
	assert_eq(action.throw_origin, Vector2(4.0, 0.0), "the own edge point nearest the enemy home")


func test_jumping_bean_falls_back_to_ordinary_without_offensive_specials() -> void:
	# uses_defensive_specials = true, uses_offensive_specials = false (the
	# shipped NORMAL profile's own combination) -- Jumping Bean's hop-hole is
	# an offensive threat, so a defensive-only bot places it like an ordinary
	# block instead.
	var tuning: BotTuning = _uniform_tuning(true, false)
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"jumping_bean", HOME, PackedVector2Array([Vector2(1.0, 0.0)]), PackedVector2Array([Vector2(5.0, 0.0)]),
		PackedVector2Array(), MatchConfig.AiDifficulty.NORMAL, tuning
	)
	assert_false(action.should_throw)
	assert_true(action.should_place_ordinarily)
	assert_eq(action.throw_origin, Vector2.ZERO, "the untouched default action -- no offensive targeting applied")
