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


## `--<prefix>value` (any number of leading dashes, or none): the value text of the
## first matching argument, "" when absent. The one owner of the "-"-stripping.
static func arg_value(args: PackedStringArray, prefix: String) -> String:
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(prefix):
			return text.substr(prefix.length())
	return ""


## `--match-seed=<int>` is present and an integer.
static func has_match_seed_arg(args: PackedStringArray) -> bool:
	return arg_value(args, "match-seed=").is_valid_int()


## `--match-seed=<int>`, clamped to >= 0 (negative means "random" elsewhere); -1 when absent.
static func match_seed_arg(args: PackedStringArray) -> int:
	var text: String = arg_value(args, "match-seed=")
	return maxi(int(text), 0) if text.is_valid_int() else -1


## `--mode=<name|id>`, -1 when absent or unrecognised.
static func mode_arg(args: PackedStringArray) -> int:
	var value: String = arg_value(args, "mode=").to_lower()
	if value.is_empty():
		return -1
	match value:
		"classic":
			return MatchConfig.GameMode.CLASSIC
		"ctf", "capture_the_flag":
			return MatchConfig.GameMode.CAPTURE_THE_FLAG
		"elimination":
			return MatchConfig.GameMode.ELIMINATION
		"sky", "reach_the_sky":
			return MatchConfig.GameMode.REACH_THE_SKY
		"domination":
			return MatchConfig.GameMode.DOMINATION
	if value.is_valid_int():
		var id: int = int(value)
		if MatchConfig.resolve_game_mode(id) != id:
			push_warning("--mode=%s is reserved or unselectable; falling back to %d" % [value, MatchConfig.resolve_game_mode(id)])
		return id
	push_warning("--mode=%s is not a known mode id; keeping the configured mode" % value)
	return -1


## A real (non-sandbox) match of `bots` bot seats from `base`, shaped by the headless
## flags in `args`. `--players=<n>` may raise the seat count past `bots` (idle human
## seats); there is no countdown. `base` is never modified.
static func headless_bot_config(base: MatchConfig, bots: int, args: PackedStringArray) -> MatchConfig:
	var config: MatchConfig = base.duplicate(true) as MatchConfig
	var players_arg: int = int(arg_value(args, "players="))
	config.ai_count = bots
	config.player_count = maxi(bots, players_arg)
	config.sandbox = false
	# DECISION: no human to wait for, so no 3-2-1 countdown (harnesses and loops stay fast).
	config.countdown_seconds = 0.0
	var disc_step: int = _int_arg_or(args, "disc-size=", -1)
	if disc_step >= 0:
		config.disc_size_step = DiscSizeTuning.shared().clamp_step(disc_step)
	var difficulty_override: int = _bot_difficulty_arg(args)
	if difficulty_override >= 0:
		config.ai_difficulty = difficulty_override as MatchConfig.AiDifficulty
		config.slot_ai_difficulties = PackedInt32Array()  # the flag covers every bot slot
	_apply_bot_difficulty_slots(config, args, bots, players_arg)
	if has_match_seed_arg(args):
		config.rng_seed = match_seed_arg(args)
	var goals_override: int = _int_arg_or(args, "goals=", 0)
	if goals_override > 0:
		config.goal_flag_count = clampi(goals_override, MatchConfig.GOAL_FLAG_MIN, MatchConfig.GOAL_FLAG_MAX)
	var mode_override: int = mode_arg(args)
	if mode_override >= 0:
		config.game_mode = MatchConfig.resolve_game_mode(mode_override)
		config.round_timer_minutes = MatchConfig.clamp_round_timer(config.round_timer_minutes, config.game_mode)
	# After the mode: 0 = no round timer (Elimination only; other modes clamp to their minimum).
	var timer_override: int = _round_timer_arg(args)
	if timer_override >= 0:
		config.round_timer_minutes = MatchConfig.clamp_round_timer(timer_override, config.game_mode)
	if arg_value(args, "gifts=") == "0":
		config.gifts_enabled = false
	# `--weather=1` only turns weather on when the configured mode is OFF.
	var weather_arg: String = arg_value(args, "weather=")
	if weather_arg == "0":
		config.weather_mode = MatchConfig.WeatherMode.OFF
	elif weather_arg == "1" and config.weather_mode == MatchConfig.WeatherMode.OFF:
		config.weather_mode = MatchConfig.WeatherMode.CHANGING
	return config


## `--<prefix>N` as an int, `absent` when the flag is missing.
static func _int_arg_or(args: PackedStringArray, prefix: String, absent: int) -> int:
	var text: String = arg_value(args, prefix)
	return int(text) if not text.is_empty() else absent


## `--round-timer=<minutes>`, -1 when absent or not a non-negative integer (bad values warn).
static func _round_timer_arg(args: PackedStringArray) -> int:
	var value: String = arg_value(args, "round-timer=")
	if value.is_empty():
		return -1
	if value.is_valid_int() and int(value) >= 0:
		return int(value)
	push_warning("--round-timer=%s is not a non-negative minute count; keeping the configured timer" % value)
	return -1


## `--bot-difficulty-slots=<slot:level,...>` fills config.slot_ai_difficulties for the
## named bot slots (absolute slot ids: bots take the last `bots` of the seats); every
## other slot keeps its current difficulty. Unknown slots or levels warn and are skipped.
static func _apply_bot_difficulty_slots(config: MatchConfig, args: PackedStringArray, bots: int, players_arg: int) -> void:
	var text: String = arg_value(args, "bot-difficulty-slots=")
	if text.is_empty():
		return
	var first_slot: int = maxi(bots, players_arg) - bots
	var levels: PackedInt32Array = PackedInt32Array()
	for slot_id: int in range(config.player_count):
		levels.append(int(config.ai_difficulty_for_slot(slot_id)))
	for part: String in text.split(",", false):
		var pair: PackedStringArray = part.strip_edges().split(":")
		var slot_id: int = int(pair[0]) if pair.size() == 2 and pair[0].is_valid_int() else -1
		if slot_id < first_slot or slot_id >= first_slot + bots or slot_id >= levels.size():
			push_warning("--bot-difficulty-slots: '%s' is not a bot slot; ignored" % part)
			continue
		var level: int = _difficulty_level_from_text(pair[1].to_lower())
		if level < 0:
			push_warning("--bot-difficulty-slots: '%s' level is not easy|normal|hard|0..2; ignored" % part)
			continue
		levels[slot_id] = level
	config.slot_ai_difficulties = levels


## `--bot-difficulty=`, -1 when absent/unknown (unknown values warn).
static func _bot_difficulty_arg(args: PackedStringArray) -> int:
	var value: String = arg_value(args, "bot-difficulty=").to_lower()
	if value.is_empty():
		return -1
	var level: int = _difficulty_level_from_text(value)
	if level >= 0:
		return level
	push_warning("--bot-difficulty=%s is not easy|normal|hard; keeping the configured difficulty" % value)
	return -1


## easy|normal|hard|0..2 (lower case) as an AiDifficulty int, -1 when unknown.
static func _difficulty_level_from_text(value: String) -> int:
	match value:
		"easy", "0":
			return MatchConfig.AiDifficulty.EASY
		"normal", "1":
			return MatchConfig.AiDifficulty.NORMAL
		"hard", "2":
			return MatchConfig.AiDifficulty.HARD
	return -1
