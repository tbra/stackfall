extends GutTest
## core/ai/BotSpecialPlanner.gd's per-type heuristics (docs/archive/M5_PLAN.md P3,
## Bontago-d5c.4; spec 2.6, 2.9 "do not aim a Rocket as if it homes or a
## Propeller as if it blows sideways").

const HOME: Vector2 = Vector2.ZERO


## Mirrors the shipped config/bot_tuning.tres flag combination (easy
## false/false, normal true/true, hard true/true) so a test can exercise
## `plan()`'s own difficulty-gated branch without loading the real .tres.
func _real_shaped_tuning() -> BotTuning:
	var tuning: BotTuning = BotTuning.new()
	var easy: BotDifficultyProfile = BotDifficultyProfile.new()
	easy.uses_defensive_specials = false
	easy.uses_offensive_specials = false
	var normal: BotDifficultyProfile = BotDifficultyProfile.new()
	normal.uses_defensive_specials = true
	normal.uses_offensive_specials = true
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
	assert_true(action.has_place_target, "records the intended target for a placed-with-intent heuristic")
	assert_eq(action.throw_origin, Vector2.ZERO, "the placed target lives in place_target, never throw_origin")


func test_rocket_never_should_throw_even_with_no_enemies() -> void:
	var tuning: BotTuning = _uniform_tuning(true, true)
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"rocket", HOME, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
		MatchConfig.AiDifficulty.HARD, tuning
	)
	assert_false(action.should_throw)
	assert_true(action.should_place_ordinarily)
	assert_false(action.has_place_target, "no enemies to cluster around -- the untouched default action")


func test_rocket_places_ordinarily_without_targeting_when_defensive_only() -> void:
	# DECISION (Bontago-d5c.9): Rocket/Bomb's aim-at-a-cluster behaviour is
	# offensive special use (spec 2.9's difficulty axis names defensive
	# special use only) -- a defensive-only (NORMAL-shaped) profile places a
	# held Rocket like an ordinary block, with no recorded target.
	var tuning: BotTuning = _uniform_tuning(true, false)
	var points: PackedVector2Array = PackedVector2Array([Vector2(1.0, 0.0), Vector2(-1.0, 0.0)])
	var enemies: PackedVector2Array = PackedVector2Array([Vector2(10.0, 0.0)])
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"rocket", HOME, points, enemies, PackedVector2Array(), MatchConfig.AiDifficulty.NORMAL, tuning
	)
	assert_false(action.should_throw)
	assert_true(action.should_place_ordinarily)
	assert_false(action.has_place_target, "defensive-only never aims a Rocket at a cluster")


# --- Bomb: thrown at the nearest/densest enemy cluster -----------------------

func test_bomb_should_throw_toward_the_cluster_under_the_speed_cap() -> void:
	# Bomb's aim-at-a-cluster throw is offensive special use (see the Rocket/
	# Bomb DECISION above) -- exercised here with an offensive-capable
	# profile (HARD-shaped: both flags true), not NORMAL's defensive-only one.
	var tuning: BotTuning = _uniform_tuning(true, true)
	var points: PackedVector2Array = PackedVector2Array([Vector2(1.0, 0.0), Vector2(-1.0, 0.0)])
	var cluster: Vector2 = Vector2(10.0, 0.0)
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"bomb", HOME, points, PackedVector2Array([cluster]), PackedVector2Array(),
		MatchConfig.AiDifficulty.HARD, tuning
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


func test_bomb_does_not_throw_when_defensive_only() -> void:
	# DECISION (Bontago-d5c.9): a defensive-only (NORMAL-shaped) profile must
	# not aim/throw a Bomb at all -- it places the held Bomb like an ordinary
	# block instead (spec 2.9's difficulty axis names defensive special use;
	# offensive use, including a Bomb's targeted throw, is the Hard tier).
	var tuning: BotTuning = _uniform_tuning(true, false)
	var points: PackedVector2Array = PackedVector2Array([Vector2(1.0, 0.0), Vector2(-1.0, 0.0)])
	var cluster: Vector2 = Vector2(10.0, 0.0)
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"bomb", HOME, points, PackedVector2Array([cluster]), PackedVector2Array(),
		MatchConfig.AiDifficulty.NORMAL, tuning
	)
	assert_false(action.should_throw, "defensive-only never throws a Bomb at a cluster")
	assert_true(action.should_place_ordinarily)
	assert_false(action.has_place_target, "falls back to the untouched default action, no recorded target")


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
	assert_true(action.has_place_target)
	assert_eq(action.place_target, Vector2(-1.0, 0.0), "defensive: near the border closest to any single enemy")


func test_volcano_offensive_targets_the_densest_enemy_cluster() -> void:
	var scenario: Dictionary = _volcano_scenario()
	var tuning: BotTuning = _uniform_tuning(false, true)
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"volcano", HOME, scenario["points"], scenario["enemies"], PackedVector2Array(),
		MatchConfig.AiDifficulty.NORMAL, tuning
	)
	assert_false(action.should_throw)
	assert_true(action.should_place_ordinarily)
	assert_true(action.has_place_target)
	assert_eq(action.place_target, Vector2(2.0, 0.0), "offensive: near the densest enemy cluster")


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
		assert_true(action.has_place_target, "id=%s" % id)
		assert_eq(action.place_target, Vector2(-5.0, 0.0), "the farthest own-territory sample point (id=%s)" % id)


func test_tilt_specials_never_crash_with_no_territory_samples() -> void:
	var tuning: BotTuning = _uniform_tuning(true, true)
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"anvil", HOME, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
		MatchConfig.AiDifficulty.HARD, tuning
	)
	assert_false(action.should_throw)
	assert_true(action.should_place_ordinarily)
	assert_true(action.has_place_target)
	assert_eq(action.place_target, HOME, "falls back to the bot's own home with no territory samples at all")


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
	assert_true(action.has_place_target)
	assert_eq(action.place_target, Vector2(4.0, 0.0), "the own edge point nearest the enemy home")


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
	assert_false(action.has_place_target, "the untouched default action -- no offensive targeting applied")


## Bontago-1t5.7 (owner 1t5.5 = B): the shipped NORMAL profile throws a Bomb
## like Hard, but with a larger aim error and a longer reaction delay.
func test_shipped_normal_throws_bomb_with_worse_aim_and_delay_than_hard() -> void:
	var tuning: BotTuning = load("res://config/bot_tuning.tres") as BotTuning
	var points: PackedVector2Array = PackedVector2Array([Vector2(1.0, 0.0), Vector2(-1.0, 0.0)])
	var enemies: PackedVector2Array = PackedVector2Array([Vector2(10.0, 0.0)])
	var normal_action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"bomb", HOME, points, enemies, PackedVector2Array(), MatchConfig.AiDifficulty.NORMAL, tuning
	)
	var hard_action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"bomb", HOME, points, enemies, PackedVector2Array(), MatchConfig.AiDifficulty.HARD, tuning
	)
	assert_true(normal_action.should_throw, "NORMAL throws offensive specials")
	assert_true(hard_action.should_throw)
	assert_gt(tuning.normal.aim_noise_m, tuning.hard.aim_noise_m)
	assert_gt(tuning.normal.reaction_delay_s, tuning.hard.reaction_delay_s)
	var easy_action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"bomb", HOME, points, enemies, PackedVector2Array(), MatchConfig.AiDifficulty.EASY, tuning
	)
	assert_false(easy_action.should_throw, "EASY still uses no specials")


# --- Black hole (Bontago-8or.27) --------------------------------------------

func _pull_radius() -> float:
	return BotController.black_hole_pull_radius_m()


func _bh_plan(
	points: PackedVector2Array,
	samples: Array[BotSpecialPlanner.BotBlockSample],
	difficulty: MatchConfig.AiDifficulty,
	tuning: BotTuning
) -> BotSpecialPlanner.BotSpecialAction:
	return BotSpecialPlanner.plan(
		&"black_hole", HOME, points, PackedVector2Array(), PackedVector2Array(), difficulty, tuning, samples, 0.0, _pull_radius()
	)


func test_black_hole_targets_near_enemy_tower_away_from_own_blocks() -> void:
	var tuning: BotTuning = _real_shaped_tuning()
	var tower: Vector2 = Vector2(12.0, 0.0)
	var points: PackedVector2Array = PackedVector2Array([Vector2(-10.0, 0.0), Vector2(0.0, 0.0), Vector2(9.0, 0.0)])
	var samples: Array[BotSpecialPlanner.BotBlockSample] = [
		BotSpecialPlanner.BotBlockSample.make(tower, 4.0, false),
		BotSpecialPlanner.BotBlockSample.make(tower + Vector2(1.0, 0.0), 3.0, false),
		BotSpecialPlanner.BotBlockSample.make(Vector2(-10.0, 0.0), 1.0, true),
	]
	var action: BotSpecialPlanner.BotSpecialAction = _bh_plan(points, samples, MatchConfig.AiDifficulty.HARD, tuning)
	assert_true(action.has_place_target)
	assert_false(action.should_throw)
	assert_lt(action.place_target.distance_to(tower), _pull_radius())


func test_black_hole_skipped_when_own_blocks_dominate_every_spot() -> void:
	var tuning: BotTuning = _real_shaped_tuning()
	var points: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(8.0, 0.0)])
	var samples: Array[BotSpecialPlanner.BotBlockSample] = [
		BotSpecialPlanner.BotBlockSample.make(Vector2(0.5, 0.0), 1.0, true),
		BotSpecialPlanner.BotBlockSample.make(Vector2(1.0, 0.0), 1.0, true),
		BotSpecialPlanner.BotBlockSample.make(Vector2(8.5, 0.0), 1.0, true),
		BotSpecialPlanner.BotBlockSample.make(Vector2(9.0, 0.0), 1.0, true),
		BotSpecialPlanner.BotBlockSample.make(Vector2(4.0, 0.0), 0.0, false),
	]
	var action: BotSpecialPlanner.BotSpecialAction = _bh_plan(points, samples, MatchConfig.AiDifficulty.NORMAL, tuning)
	assert_false(action.has_place_target)
	assert_true(action.should_place_ordinarily)


func test_black_hole_radius_equals_special_def_radius() -> void:
	var def: SpecialDef = SpecialDef.find_by_id(&"black_hole")
	var effect: BlackHoleEffect = def.effect as BlackHoleEffect
	assert_gt(effect.pull_radius_m, 0.0)
	assert_eq(BotController.black_hole_pull_radius_m(), effect.pull_radius_m)


func test_black_hole_own_tower_in_best_enemy_spot_is_penalised() -> void:
	var tuning: BotTuning = _real_shaped_tuning()
	var radius: float = _pull_radius()
	# Spot A sits on the tall enemy mass but also on a big own tower; spot B is
	# far from both and catches a smaller enemy group.
	var spot_a: Vector2 = Vector2(0.0, 0.0)
	var spot_b: Vector2 = Vector2(radius * 4.0, 0.0)
	var points: PackedVector2Array = PackedVector2Array([spot_a, spot_b])
	var samples: Array[BotSpecialPlanner.BotBlockSample] = []
	for i: int in range(3):
		samples.append(BotSpecialPlanner.BotBlockSample.make(spot_a + Vector2(0.5 * i, 0.0), 2.0, false))
	for i: int in range(4):
		samples.append(BotSpecialPlanner.BotBlockSample.make(spot_a + Vector2(0.0, 0.5 * i), 1.0, true))
	for i: int in range(3):
		samples.append(BotSpecialPlanner.BotBlockSample.make(spot_b + Vector2(0.5 * i, 0.0), 0.0, false))
	var action: BotSpecialPlanner.BotSpecialAction = _bh_plan(points, samples, MatchConfig.AiDifficulty.HARD, tuning)
	assert_true(action.has_place_target)
	assert_eq(action.place_target, spot_b, "own tower makes spot A a net loss")
	# Without the own blocks, spot A wins.
	var enemy_only: Array[BotSpecialPlanner.BotBlockSample] = []
	for sample: BotSpecialPlanner.BotBlockSample in samples:
		if not sample.is_own:
			enemy_only.append(sample)
	var clean: BotSpecialPlanner.BotSpecialAction = _bh_plan(points, enemy_only, MatchConfig.AiDifficulty.HARD, tuning)
	assert_eq(clean.place_target, spot_a)


func test_black_hole_easy_never_uses_it() -> void:
	var tuning: BotTuning = _real_shaped_tuning()
	var points: PackedVector2Array = PackedVector2Array([Vector2(9.0, 0.0)])
	var samples: Array[BotSpecialPlanner.BotBlockSample] = [
		BotSpecialPlanner.BotBlockSample.make(Vector2(12.0, 0.0), 4.0, false),
	]
	var action: BotSpecialPlanner.BotSpecialAction = _bh_plan(points, samples, MatchConfig.AiDifficulty.EASY, tuning)
	assert_false(action.has_place_target)


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


func test_v2_tilt_keeps_legacy_heuristic() -> void:
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
	var clean: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan_v2(
		&"black_hole", view, chains, profile, _v2_tuning(), sites, 0.0, V2_PULL_RADIUS_M
	)
	assert_true(clean.has_place_target, "the enemy joint is far from own blocks")
	var own_penalised: BotTuning = _v2_tuning()
	own_penalised.black_hole_own_penalty = 100.0
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
