extends GutTest
## Bontago-1t5.39: `--bot-brain=` parsing shared by lobby matches and the headless flow.


func test_absent_is_legacy() -> void:
	assert_eq(MainHeadlessBotsFlow.brain_from_args(PackedStringArray(["--bots=2"])), BotController.Brain.LEGACY)


func test_v2_flag() -> void:
	assert_eq(MainHeadlessBotsFlow.brain_from_args(PackedStringArray(["--bot-brain=v2"])), BotController.Brain.V2)
	assert_eq(MainHeadlessBotsFlow.brain_from_args(PackedStringArray(["--bot-brain=V2"])), BotController.Brain.V2)


func test_legacy_flag() -> void:
	assert_eq(MainHeadlessBotsFlow.brain_from_args(PackedStringArray(["--bot-brain=legacy"])), BotController.Brain.LEGACY)


func test_unknown_value_is_legacy() -> void:
	assert_eq(MainHeadlessBotsFlow.brain_from_args(PackedStringArray(["--bot-brain=zzz"])), BotController.Brain.LEGACY)
