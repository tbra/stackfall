class_name MatchLaunch
extends RefCounted
## Pure builders for the configs and CLI values of the non-lobby modes: no scene
## tree, no autoload.


## Lobby settings minus a few overrides. `sandbox` lets MatchConfig.sanitize()
## allow a player count below the normal floor; a preset's special_frequency_override
## (when >= 0) turns gifts on at that frequency.
static func sandbox_config(base: MatchConfig, player_count: int, preset: SandboxConfig) -> MatchConfig:
	var config: MatchConfig = base.duplicate(true) as MatchConfig
	config.player_count = player_count
	config.ai_count = 0
	config.sandbox = true
	if preset != null and preset.special_frequency_override >= 0:
		config.gifts_enabled = true
		config.special_frequency = preset.special_frequency_override
	return config


## One-player offline lesson on real rules: only the lesson's demo gift, scripted.
static func tutorial_config(base: MatchConfig, lesson: TutorialConfig) -> MatchConfig:
	var config: MatchConfig = base.duplicate(true) as MatchConfig
	config.player_count = 1
	config.ai_count = 0
	config.weather_mode = MatchConfig.WeatherMode.OFF
	config.gifts_enabled = true
	config.scripted_gifts = true
	config.enabled_specials = [lesson.demo_special_id] as Array[StringName]
	config.special_frequency = MatchConfig.SPECIAL_FREQUENCY_MIN
	# DECISION: no countdown and the longest block timer, so the lesson starts
	# at once and never pressures the learner.
	config.countdown_seconds = 0.0
	config.block_timer = MatchConfig.BLOCK_TIMER_MAX
	return config


## `--players=N` for the sandbox: the same "-"-stripping loop Net's command-line
## parsing uses; out-of-range values are clamped later by MatchConfig.sanitize().
static func sandbox_player_count(args: PackedStringArray, preset: SandboxConfig, defaults: SandboxConfig) -> int:
	const PREFIX: String = "players="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return int(text.substr(PREFIX.length()))
	if preset != null:
		return preset.default_player_count
	return defaults.default_player_count


## `--force-special=<id>`, or &"" when absent. The id is validated against the
## roster by Sandbox, not here.
static func forced_special_arg(args: PackedStringArray) -> StringName:
	const PREFIX: String = "force-special="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return StringName(text.substr(PREFIX.length()))
	return &""


## STUB (P7 plan section 2.1): returns null; P7-Ibuild moves the headless bot
## argument parsing here.
static func headless_bot_config(_args: PackedStringArray) -> MatchConfig:
	return null
