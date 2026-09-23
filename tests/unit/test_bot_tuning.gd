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
			assert_gt(
				float(profile.get(prop_name)), 0.0,
				"%s.%s must be positive." % [profile_name, prop_name]
			)
		assert_true(checked_any, "fixture: BotDifficultyProfile must have at least one exported numeric field.")


func test_shipped_bot_tuning_difficulty_ordering_gets_harder() -> void:
	var tuning: BotTuning = load("res://config/bot_tuning.tres")
	# Spec 2.9: harder difficulties sample more candidates, aim more precisely
	# (lower noise) and react faster (lower delay).
	assert_lt(tuning.easy.candidate_count, tuning.normal.candidate_count)
	assert_lt(tuning.normal.candidate_count, tuning.hard.candidate_count)
	assert_gt(tuning.easy.aim_noise_m, tuning.normal.aim_noise_m)
	assert_gt(tuning.normal.aim_noise_m, tuning.hard.aim_noise_m)
	assert_gt(tuning.easy.reaction_delay_s, tuning.normal.reaction_delay_s)
	assert_gt(tuning.normal.reaction_delay_s, tuning.hard.reaction_delay_s)
