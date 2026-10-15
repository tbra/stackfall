extends GutTest
## config/bots/BotTuning.gd + config/bots/BotDifficultyProfile.gd (spec 2.9
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


const ZERO_ALLOWED_FIELDS: Array[String] = ["eval_top_k", "fill_share", "threat_lookahead_m", "think_reserve_frames"]


# --- The shipped config/bots/bot_tuning.tres --------------------------------------

func test_shipped_bot_tuning_has_three_non_null_profiles() -> void:
	var tuning: BotTuning = load("res://config/bots/bot_tuning.tres")
	assert_not_null(tuning, "fixture: config/bots/bot_tuning.tres must load.")
	assert_not_null(tuning.easy, "easy profile must be assigned.")
	assert_not_null(tuning.normal, "normal profile must be assigned.")
	assert_not_null(tuning.hard, "hard profile must be assigned.")


func test_shipped_bot_tuning_profiles_have_positive_numeric_fields() -> void:
	var tuning: BotTuning = load("res://config/bots/bot_tuning.tres")
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


func test_shipped_bot_tuning_ladder_is_precision_only() -> void:
	# Bontago-1t5.57: the tiers share Hard's mechanics; only aim noise (precision) is a ladder
	# (the full field audit is test_bot_tier_parity).
	var tuning: BotTuning = load("res://config/bots/bot_tuning.tres")
	assert_gt(tuning.easy.aim_noise_m, tuning.normal.aim_noise_m, "easy aim noise above normal")
	assert_gt(tuning.normal.aim_noise_m, tuning.hard.aim_noise_m, "normal aim noise above hard")


func test_controller_resolves_its_tier_profile() -> void:
	var tuning: BotTuning = load("res://config/bots/bot_tuning.tres")
	var controller: BotController = BotController.new()
	add_child_autofree(controller)
	controller.setup(0, MatchConfig.AiDifficulty.EASY, null, null)
	assert_same(controller._profile, tuning.easy, "a bot uses its tier's profile")
