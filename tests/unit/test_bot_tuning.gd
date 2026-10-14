extends GutTest
## config/BotTuning.gd + config/BotDifficultyProfile.gd (spec 2.9
## "Difficulty: candidate count sampled, aiming error, reaction delay, and
## whether the bot uses defensive specials"), Bontago-d5c P0.

const EXPORT_USAGE_MASK: int = PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE


func _is_exported_numeric_field(prop: Dictionary) -> bool:
	if (int(prop.get("usage", 0)) & EXPORT_USAGE_MASK) != EXPORT_USAGE_MASK:
		return false
	var t: int = int(prop.get("type", TYPE_NIL))
	return t == TYPE_INT or t == TYPE_FLOAT


# --- profile_for() picks the right profile per difficulty -------------------

func test_profile_for_easy_returns_the_easy_profile() -> void:
	var tuning: BotTuning = BotTuning.new()
	tuning.easy = BotDifficultyProfile.new()
	tuning.normal = BotDifficultyProfile.new()
	tuning.hard = BotDifficultyProfile.new()

	assert_same(tuning.profile_for(MatchConfig.AiDifficulty.EASY), tuning.easy)


func test_profile_for_normal_returns_the_normal_profile() -> void:
	var tuning: BotTuning = BotTuning.new()
	tuning.easy = BotDifficultyProfile.new()
	tuning.normal = BotDifficultyProfile.new()
	tuning.hard = BotDifficultyProfile.new()

	assert_same(tuning.profile_for(MatchConfig.AiDifficulty.NORMAL), tuning.normal)


func test_profile_for_hard_returns_the_hard_profile() -> void:
	var tuning: BotTuning = BotTuning.new()
	tuning.easy = BotDifficultyProfile.new()
	tuning.normal = BotDifficultyProfile.new()
	tuning.hard = BotDifficultyProfile.new()

	assert_same(tuning.profile_for(MatchConfig.AiDifficulty.HARD), tuning.hard)


const ZERO_ALLOWED_FIELDS: Array[String] = ["eval_top_k", "fill_share", "threat_lookahead_m"]


# --- The shipped config/bot_tuning.tres --------------------------------------

func test_shipped_bot_tuning_has_three_non_null_profiles() -> void:
	var tuning: BotTuning = load("res://config/bot_tuning.tres")
	assert_not_null(tuning, "fixture: config/bot_tuning.tres must load.")
	assert_not_null(tuning.easy, "easy profile must be assigned.")
	assert_not_null(tuning.normal, "normal profile must be assigned.")
	assert_not_null(tuning.hard, "hard profile must be assigned.")


func test_shipped_bot_tuning_profiles_have_positive_numeric_fields() -> void:
	var tuning: BotTuning = load("res://config/bot_tuning.tres")
	for profile_name: String in ["easy", "normal", "hard"]:
		var profile: BotDifficultyProfile = tuning.get(profile_name)
		var checked_any: bool = false
		for prop: Dictionary in profile.get_property_list():
			if not _is_exported_numeric_field(prop):
				continue
			checked_any = true
			var prop_name: String = str(prop.get("name", ""))
			# Bontago-1t5.23: these tier knobs are legitimately 0 on some tiers (Easy never
			# measures, only Easy fills, only Hard looks ahead, only Easy/Normal pool-pick).
			if prop_name in ZERO_ALLOWED_FIELDS:
				assert_gte(float(profile.get(prop_name)), 0.0, "%s.%s must not be negative." % [profile_name, prop_name])
				continue
			assert_gt(
				float(profile.get(prop_name)), 0.0,
				"%s.%s must be positive." % [profile_name, prop_name]
			)
		assert_true(checked_any, "fixture: BotDifficultyProfile must have at least one exported numeric field.")


func test_shipped_bot_tuning_hard_is_stronger_than_easy() -> void:
	var tuning: BotTuning = load("res://config/bot_tuning.tres")
	# Spec 2.9: harder difficulties sample more candidates, aim more precisely
	# (lower noise) and react faster (lower delay). Only the extremes are
	# related, so retuning the Normal middle never breaks this; it fails if the
	# profiles are swapped or the direction of a knob is inverted.
	assert_lt(tuning.easy.candidate_count, tuning.hard.candidate_count)
	assert_gt(tuning.easy.aim_noise_m, tuning.hard.aim_noise_m)
	assert_gt(tuning.easy.reaction_delay_s, tuning.hard.reaction_delay_s)
	for field: String in ["candidate_count", "aim_noise_m", "reaction_delay_s"]:
		var lo: float = minf(float(tuning.easy.get(field)), float(tuning.hard.get(field)))
		var hi: float = maxf(float(tuning.easy.get(field)), float(tuning.hard.get(field)))
		var mid: float = float(tuning.normal.get(field))
		assert_between(mid, lo, hi, "normal.%s sits between easy and hard" % field)


func test_shipped_bot_tuning_v2_ladder_is_precision_only() -> void:
	# Bontago-1t5.57: the V2 tiers share Hard's mechanics; only aim noise (precision) is a ladder
	# (the full field audit is test_bot_tier_parity_1014).
	var tuning: BotTuning = load("res://config/bot_tuning.tres")
	var easy_v: float = tuning.easy_v2.aim_noise_m
	var normal_v: float = tuning.normal_v2.aim_noise_m
	var hard_v: float = tuning.hard_v2.aim_noise_m
	assert_gt(easy_v, normal_v, "easy aim noise above normal")
	assert_gt(normal_v, hard_v, "normal aim noise above hard")


func test_legacy_profiles_keep_their_pre_v2_values() -> void:
	# Bontago-1t5.34: the retune is V2-only; the shipped legacy brain keeps today's feel.
	var tuning: BotTuning = load("res://config/bot_tuning.tres")
	assert_eq(tuning.easy.candidate_count, 40)
	assert_eq(tuning.easy.aim_noise_m, 0.6)
	assert_eq(tuning.normal.candidate_count, 70)
	assert_eq(tuning.normal.aim_noise_m, 0.3)
	assert_eq(tuning.hard.candidate_count, 110)
	assert_eq(tuning.hard.aim_noise_m, 0.05)


func test_profile_for_brain_picks_v2_profile_per_difficulty() -> void:
	var tuning: BotTuning = load("res://config/bot_tuning.tres")
	assert_same(tuning.profile_for_brain(MatchConfig.AiDifficulty.EASY, true), tuning.easy_v2)
	assert_same(tuning.profile_for_brain(MatchConfig.AiDifficulty.NORMAL, true), tuning.normal_v2)
	assert_same(tuning.profile_for_brain(MatchConfig.AiDifficulty.HARD, true), tuning.hard_v2)
	assert_same(tuning.profile_for_brain(MatchConfig.AiDifficulty.NORMAL, false), tuning.normal)
	assert_eq(tuning.hard_v2.think_budget_us, tuning.hard.think_budget_us)


func test_controller_resolves_profile_after_set_brain() -> void:
	var tuning: BotTuning = load("res://config/bot_tuning.tres")
	var controller: BotController = BotController.new()
	add_child_autofree(controller)
	controller.setup(0, MatchConfig.AiDifficulty.EASY, null, null)
	assert_eq(controller.brain(), BotController.Brain.V2, "P7: V2 is the default brain")
	assert_same(controller._profile, tuning.easy_v2, "a default bot uses the V2 tier profile")
	controller.set_brain(BotController.Brain.LEGACY)
	assert_same(controller._profile, tuning.easy, "legacy flag keeps the legacy profile")
	controller.set_brain(BotController.Brain.V2)
	assert_same(controller._profile, tuning.easy_v2, "set_brain after setup picks the V2 profile")
