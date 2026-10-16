extends GutTest
## The tiers share Hard's mechanics; Easy and
## Normal differ only in precision (aim_noise_m) plus the strategy-level fields.

## Fields that control how the bot searches, probes, scores, picks or times a think.
const MECHANICAL_FIELDS: Array[String] = [
	"candidate_count", "candidates_per_frame", "stability_raycast_count", "reaction_delay_s",
	"think_budget_us", "think_frame_cap_us", "think_reserve_frames", "eval_top_k",
	"pick_temperature", "pick_pool", "fill_share",
]
## Strategy / goal fields that may differ per tier.
const STRATEGY_FIELDS: Array[String] = [
	"uses_defensive_specials", "uses_offensive_specials", "intent_mask", "threat_lookahead_m",
	"gift_claim_scale",
]
## Precision, the one intended difference.
const PRECISION_FIELDS: Array[String] = ["aim_noise_m"]
const SLIGHTLY_WORSE_MAX_M: float = 1.0
const CANDIDATE_COUNT: int = 110

var _tuning: BotTuning = null


func before_each() -> void:
	_tuning = (load("res://config/bots/bot_tuning.tres") as BotTuning)


func test_every_profile_field_is_classified() -> void:
	var known: Dictionary = {}
	for f: String in MECHANICAL_FIELDS + STRATEGY_FIELDS + PRECISION_FIELDS:
		known[f] = true
	for prop: Dictionary in BotDifficultyProfile.new().get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		assert_true(known.has(String(prop["name"])), "classify profile field %s" % prop["name"])


func test_mechanical_fields_match_hard() -> void:
	for f: String in MECHANICAL_FIELDS:
		assert_eq(_tuning.easy.get(f), _tuning.hard.get(f), "easy.%s == hard" % f)
		assert_eq(_tuning.normal.get(f), _tuning.hard.get(f), "normal.%s == hard" % f)


func test_precision_is_the_ladder() -> void:
	assert_gt(_tuning.easy.aim_noise_m, _tuning.normal.aim_noise_m)
	assert_gt(_tuning.normal.aim_noise_m, _tuning.hard.aim_noise_m)
	assert_true(_tuning.easy.aim_noise_m <= SLIGHTLY_WORSE_MAX_M, "Easy is only slightly worse")


func test_tier_mapping_returns_the_tier_profiles() -> void:
	assert_same(_tuning.profile_for(MatchConfig.AiDifficulty.EASY), _tuning.easy)
	assert_same(_tuning.profile_for(MatchConfig.AiDifficulty.NORMAL), _tuning.normal)
	assert_same(_tuning.profile_for(MatchConfig.AiDifficulty.HARD), _tuning.hard)


func test_easy_tower_intent_generates_targeted_stack_sites() -> void:
	var profile: BotDifficultyProfile = _tuning.easy.duplicate() as BotDifficultyProfile
	profile.candidate_count = CANDIDATE_COUNT
	var helper: Object = load("res://tests/unit/bots/test_bot_candidate_gen.gd").new()
	helper.before_each()
	var view: BotWorldView = helper._view(helper._pillar, true)
	var intent: BotIntent = helper._intent(BotIntent.Kind.ANCHOR)
	var rng: RandomNumberGenerator = helper._rng()
	var sites: Array[BotCandidate] = _site_list(view, intent, profile, rng, helper._tuning)
	var stack_sites: int = 0
	for c: BotCandidate in sites:
		if c.site_kind == BotCandidateGen.SITE_STACK:
			stack_sites += 1
	assert_gt(stack_sites, 0, "Easy now builds targeted STACK sites, not only FILL")
	helper.free()


func test_think_deadline_is_the_same_for_every_tier() -> void:
	var ticks: Array[int] = []
	for difficulty: MatchConfig.AiDifficulty in [
		MatchConfig.AiDifficulty.EASY, MatchConfig.AiDifficulty.NORMAL, MatchConfig.AiDifficulty.HARD
	]:
		var controller: BotController = BotController.new()
		add_child_autofree(controller)
		controller.setup(0, difficulty, null, null)
		ticks.append(controller.think_deadline_ticks())
	assert_eq(ticks[0], ticks[2], "Easy deadline == Hard")
	assert_eq(ticks[1], ticks[2], "Normal deadline == Hard")


## The sites `BotCandidateGen.begin` builds once its fill has run to the end.
func _site_list(
	view: BotWorldView, intent: BotIntent, profile: BotDifficultyProfile,
	rng: RandomNumberGenerator, tuning: BotGenTuning = null
) -> Array[BotCandidate]:
	var job: BotCandidateGen.SiteJob = BotCandidateGen.begin(view, intent, profile, rng, tuning)
	while not job.fill_step(job.attempts_left()):
		pass
	return job.out
