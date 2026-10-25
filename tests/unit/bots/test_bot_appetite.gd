extends GutTest
## core/ai/BotAppetite.gd: the draw, the four gated behaviours and the fall/height risk, through the
## public interface only. Tunables come from the shipped Resource; tiers come from bot_tuning.tres.

const SKY: int = MatchConfig.GameMode.REACH_THE_SKY
const BASE_TALL: int = 2
const SEEDS: int = 40
const TOLERANCE: float = 0.0001
## Appetite samples used by the monotone checks.
const LEVELS: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
## [appetite, expected variants] straddling the rounding steps for base 2.
const TALL_CASES: Array = [[0.2, 0], [0.5, 1], [0.9, 2]]
const SLACKS_UNSOUND: Array[float] = [0.0, -0.01, -0.05, -1.0]

var _tuning: BotAppetiteTuning = BotAppetite.SHIPPED_TUNING
var _bots: BotTuning = preload("res://config/bots/bot_tuning.tres")


func _covered_modes() -> Array[int]:
	var out: Array[int] = []
	for mode: int in MatchConfig.GameMode.values():
		if mode != SKY and _tuning.covers(mode):
			out.append(mode)
	return out


func _all_modes() -> Array[int]:
	var out: Array[int] = []
	for mode: int in MatchConfig.GameMode.values():
		out.append(mode)
	return out


## Shipped tuning with `mode` switched back to the shipped behaviour.
func _without(mode: int) -> BotAppetiteTuning:
	var t: BotAppetiteTuning = _tuning.duplicate() as BotAppetiteTuning
	t.appetite_modes = t.appetite_modes & ~(1 << mode)
	return t


func _profile(difficulty: MatchConfig.AiDifficulty) -> BotDifficultyProfile:
	return _bots.profile_for(difficulty)


func _drawn(seed_value: int, profile: BotDifficultyProfile) -> BotAppetite:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return BotAppetite.draw(rng, profile)


# ---- draw ----------------------------------------------------------------------------------------

func test_draw_same_seed_gives_the_same_value() -> void:
	var profile: BotDifficultyProfile = _profile(MatchConfig.AiDifficulty.NORMAL)
	assert_eq(_drawn(7, profile).value, _drawn(7, profile).value)


func test_draw_different_seeds_give_different_values() -> void:
	var profile: BotDifficultyProfile = _profile(MatchConfig.AiDifficulty.NORMAL)
	var seen: Dictionary = {}
	for s: int in range(SEEDS):
		seen[_drawn(s, profile).value] = true
	assert_gt(seen.size(), SEEDS / 2, "a wide range yields many distinct appetites")


func test_draw_stays_inside_each_tier_range() -> void:
	for difficulty: MatchConfig.AiDifficulty in MatchConfig.AiDifficulty.values():
		var profile: BotDifficultyProfile = _profile(difficulty)
		var lo: float = profile.appetite_range.x
		var hi: float = profile.appetite_range.y
		var low_seen: float = INF
		var high_seen: float = -INF
		for s: int in range(SEEDS):
			var v: float = _drawn(s, profile).value
			assert_between(v, lo, hi, "tier %d seed %d" % [difficulty, s])
			low_seen = minf(low_seen, v)
			high_seen = maxf(high_seen, v)
		if hi > lo:
			assert_gt(high_seen - low_seen, (hi - lo) * 0.5, "tier %d covers its range, not one point" % difficulty)


func test_draw_with_a_zero_width_range_returns_that_value() -> void:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.appetite_range = Vector2(0.4, 0.4)
	assert_almost_eq(_drawn(3, profile).value, 0.4, TOLERANCE)


func test_draw_consumes_exactly_one_random_number() -> void:
	var profile: BotDifficultyProfile = _profile(MatchConfig.AiDifficulty.HARD)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	var reference: RandomNumberGenerator = RandomNumberGenerator.new()
	reference.seed = 99
	BotAppetite.draw(rng, profile)
	reference.randf_range(profile.appetite_range.x, profile.appetite_range.y)
	assert_eq(rng.randf(), reference.randf(), "the next draw on the stream is the reference's second")


func test_draw_uses_the_given_tuning() -> void:
	var strict: BotAppetiteTuning = _tuning.duplicate() as BotAppetiteTuning
	strict.unsound_top_skip_below = 2.0
	var profile: BotDifficultyProfile = _profile(MatchConfig.AiDifficulty.HARD)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var bot: BotAppetite = BotAppetite.draw(rng, profile, strict)
	for mode: int in _covered_modes():
		assert_true(bot.skips_unsound_tops(mode), "every appetite is below the custom threshold")


# ---- tall_variants -------------------------------------------------------------------------------

func test_tall_variants_in_sky_is_the_base_for_any_appetite() -> void:
	for v: float in LEVELS:
		assert_eq(BotAppetite.new(v).tall_variants(SKY, BASE_TALL), BASE_TALL, "appetite %s" % v)


func test_tall_variants_in_a_covered_mode_scales_with_appetite() -> void:
	for mode: int in _covered_modes():
		for pair: Array in TALL_CASES:
			assert_eq(BotAppetite.new(pair[0]).tall_variants(mode, BASE_TALL), pair[1], "mode %d appetite %s" % [mode, pair[0]])


func test_tall_variants_is_zero_for_a_mode_masked_out() -> void:
	for mode: int in _covered_modes():
		var bot: BotAppetite = BotAppetite.new(1.0, _without(mode))
		assert_eq(bot.tall_variants(mode, BASE_TALL), 0)


func test_tall_variants_with_base_zero_is_zero() -> void:
	for mode: int in _covered_modes():
		assert_eq(BotAppetite.new(1.0).tall_variants(mode, 0), 0)


# ---- skips_unsound_tops --------------------------------------------------------------------------

func test_sky_always_skips_unsound_tops() -> void:
	for v: float in LEVELS:
		assert_true(BotAppetite.new(v).skips_unsound_tops(SKY), "appetite %s" % v)


func test_covered_mode_skips_below_the_threshold_only() -> void:
	var edge: float = _tuning.unsound_top_skip_below
	for mode: int in _covered_modes():
		assert_true(BotAppetite.new(0.0).skips_unsound_tops(mode), "cautious skips")
		assert_true(BotAppetite.new(edge - 0.01).skips_unsound_tops(mode), "just below the threshold skips")
		assert_false(BotAppetite.new(edge).skips_unsound_tops(mode), "at the threshold builds")
		assert_false(BotAppetite.new(1.0).skips_unsound_tops(mode), "bold builds")


func test_masked_out_mode_never_skips_unsound_tops() -> void:
	for mode: int in _covered_modes():
		assert_false(BotAppetite.new(0.0, _without(mode)).skips_unsound_tops(mode))


# ---- fall_probability ----------------------------------------------------------------------------

func test_sound_site_never_falls() -> void:
	for mode: int in _all_modes():
		for v: float in LEVELS:
			var bot: BotAppetite = BotAppetite.new(v)
			assert_eq(bot.fall_probability(0.3, mode), 0.0, "mode %d appetite %s" % [mode, v])
			assert_eq(bot.fall_probability(INF, mode), 0.0, "unevaluated site, mode %d" % mode)


func test_cautious_bot_and_sky_keep_the_binary_charge() -> void:
	for slack: float in SLACKS_UNSOUND:
		for mode: int in _covered_modes():
			assert_eq(BotAppetite.new(0.0).fall_probability(slack, mode), 1.0, "cautious, slack %s" % slack)
		for v: float in LEVELS:
			assert_eq(BotAppetite.new(v).fall_probability(slack, SKY), 1.0, "Sky, appetite %s, slack %s" % [v, slack])


func test_masked_out_mode_keeps_the_binary_charge() -> void:
	for mode: int in _covered_modes():
		var bot: BotAppetite = BotAppetite.new(1.0, _without(mode))
		assert_eq(bot.fall_probability(-0.01, mode), 1.0)
		assert_eq(bot.fall_probability(0.1, mode), 0.0)


func test_bold_bot_pays_the_floor_at_slack_zero() -> void:
	for mode: int in _covered_modes():
		assert_almost_eq(BotAppetite.new(1.0).fall_probability(0.0, mode), _tuning.unsound_fall_floor, TOLERANCE)


func test_certain_fall_at_the_band_depth_and_beyond() -> void:
	for mode: int in _covered_modes():
		for v: float in LEVELS:
			var bot: BotAppetite = BotAppetite.new(v)
			assert_almost_eq(bot.fall_probability(-_tuning.unsound_band_m, mode), 1.0, TOLERANCE, "appetite %s" % v)
			assert_almost_eq(bot.fall_probability(-_tuning.unsound_band_m * 3.0, mode), 1.0, TOLERANCE)


func test_fall_probability_matches_the_interpolation_in_between() -> void:
	var slack: float = -_tuning.unsound_band_m * 0.5
	for mode: int in _covered_modes():
		var expected: float = 1.0 - (1.0 - _tuning.unsound_fall_floor) * 0.8 * 0.5
		assert_almost_eq(BotAppetite.new(0.8).fall_probability(slack, mode), expected, TOLERANCE)


func test_fall_probability_falls_with_appetite_and_rises_with_depth() -> void:
	var mode: int = _covered_modes()[0]
	var slack: float = -_tuning.unsound_band_m * 0.5
	var previous: float = INF
	for v: float in LEVELS:
		var p: float = BotAppetite.new(v).fall_probability(slack, mode)
		assert_true(p >= 0.0 and p <= 1.0, "a probability")
		assert_true(p <= previous + TOLERANCE, "bolder never falls more (appetite %s)" % v)
		previous = p
	assert_lt(BotAppetite.new(1.0).fall_probability(slack, mode), BotAppetite.new(0.0).fall_probability(slack, mode))
	var bold: BotAppetite = BotAppetite.new(1.0)
	var shallower: float = -_tuning.unsound_band_m * 0.25
	var deeper: float = -_tuning.unsound_band_m * 0.75
	assert_lt(bold.fall_probability(shallower, mode), bold.fall_probability(slack, mode))
	assert_lt(bold.fall_probability(slack, mode), bold.fall_probability(deeper, mode))


# ---- height_risk ---------------------------------------------------------------------------------

func test_no_height_risk_at_or_below_the_start() -> void:
	for mode: int in _covered_modes():
		for v: float in LEVELS:
			assert_eq(BotAppetite.new(v).height_risk(0.0, mode), 0.0)
			assert_eq(BotAppetite.new(v).height_risk(_tuning.height_risk_start_m, mode), 0.0, "exactly at the start")


func test_cautious_bot_pays_the_maximum_at_the_end_of_the_span() -> void:
	var top: float = _tuning.height_risk_start_m + _tuning.height_risk_span_m
	for mode: int in _covered_modes():
		var bot: BotAppetite = BotAppetite.new(0.0)
		assert_almost_eq(bot.height_risk(top, mode), _tuning.height_risk_max, TOLERANCE)
		assert_almost_eq(bot.height_risk(top * 3.0, mode), _tuning.height_risk_max, TOLERANCE, "clamped above the span")


func test_height_risk_rises_linearly_with_the_top() -> void:
	var mode: int = _covered_modes()[0]
	var bot: BotAppetite = BotAppetite.new(0.0)
	var halfway: float = _tuning.height_risk_start_m + _tuning.height_risk_span_m * 0.5
	assert_almost_eq(bot.height_risk(halfway, mode), _tuning.height_risk_max * 0.5, TOLERANCE)
	assert_lt(bot.height_risk(halfway - 1.0, mode), bot.height_risk(halfway, mode))
	assert_lt(bot.height_risk(halfway, mode), bot.height_risk(halfway + 1.0, mode))


func test_height_risk_falls_with_appetite_to_the_relief_share() -> void:
	var top: float = _tuning.height_risk_start_m + _tuning.height_risk_span_m
	var mode: int = _covered_modes()[0]
	var previous: float = INF
	for v: float in LEVELS:
		var r: float = BotAppetite.new(v).height_risk(top, mode)
		assert_true(r <= previous + TOLERANCE, "bolder pays no more (appetite %s)" % v)
		previous = r
	assert_almost_eq(BotAppetite.new(1.0).height_risk(top, mode), _tuning.height_risk_max * (1.0 - _tuning.height_risk_relief), TOLERANCE)


func test_height_risk_is_zero_in_sky_and_for_a_masked_out_mode() -> void:
	var top: float = _tuning.height_risk_start_m + _tuning.height_risk_span_m
	for v: float in LEVELS:
		assert_eq(BotAppetite.new(v).height_risk(top, SKY), 0.0, "Sky keeps its objective")
	for mode: int in _covered_modes():
		assert_eq(BotAppetite.new(0.0, _without(mode)).height_risk(top, mode), 0.0)


# ---- shipped() -----------------------------------------------------------------------------------

func test_shipped_is_the_pre_appetite_behaviour_in_every_mode() -> void:
	var bot: BotAppetite = BotAppetite.shipped()
	var top: float = _tuning.height_risk_start_m + _tuning.height_risk_span_m
	for mode: int in _all_modes():
		var is_sky: bool = mode == SKY
		assert_eq(bot.tall_variants(mode, BASE_TALL), BASE_TALL if is_sky else 0, "tall, mode %d" % mode)
		assert_eq(bot.skips_unsound_tops(mode), is_sky, "skip, mode %d" % mode)
		assert_eq(bot.fall_probability(0.2, mode), 0.0, "sound, mode %d" % mode)
		assert_eq(bot.fall_probability(INF, mode), 0.0, "unevaluated, mode %d" % mode)
		for slack: float in SLACKS_UNSOUND:
			assert_eq(bot.fall_probability(slack, mode), 1.0, "binary, mode %d slack %s" % [mode, slack])
		assert_eq(bot.height_risk(top, mode), 0.0, "no height risk, mode %d" % mode)


func test_shipped_differs_from_a_cautious_bot() -> void:
	var mode: int = _covered_modes()[0]
	var top: float = _tuning.height_risk_start_m + _tuning.height_risk_span_m
	assert_gt(BotAppetite.new(0.0).height_risk(top, mode), BotAppetite.shipped().height_risk(top, mode))
	assert_true(BotAppetite.new(0.0).skips_unsound_tops(mode))
	assert_false(BotAppetite.shipped().skips_unsound_tops(mode))
