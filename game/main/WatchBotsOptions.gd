class_name WatchBotsOptions
extends RefCounted
## the choices of a debug "Watch bots" match (every seat a bot, the local player only
## watches), and the one place that turns them into a MatchConfig. The main-menu picker
## (ui/menus/WatchBotsDialog.gd) and the command line (`-- --watch-bots=<n> [--mode=<id>] [--difficulty=<level>]
## [--gifts=0] [--weather=0]`) both fill one of these and call build_config(), so both start the same match.
## Pure rules, no scene tree. The last picker values persist in user://watch_bots.cfg.

enum Difficulty { EASY, NORMAL, HARD, MIXED }

const TUNING_PATH: String = "res://config/match/watch_bots_tuning.tres"
const CLI_FLAG: String = "watch-bots"
const SAVE_PATH: String = "user://watch_bots.cfg"
const SECTION: String = "watch_bots"
const KEY_BOTS: String = "bots"
const KEY_MODE: String = "mode"
const KEY_DIFFICULTY: String = "difficulty"
const KEY_GIFTS: String = "gifts"
const KEY_WEATHER: String = "weather"
const DIFFICULTY_LABELS: PackedStringArray = ["Easy", "Normal", "Hard", "Mixed"]

static var _tuning: WatchBotsTuning = null

var bots: int = 0
var mode: int = MatchConfig.GameMode.CLASSIC
var difficulty: Difficulty = Difficulty.NORMAL
var gifts: bool = true
var weather: bool = true


func _init() -> void:
	bots = tuning().default_bots


static func tuning() -> WatchBotsTuning:
	if _tuning == null:
		_tuning = load(TUNING_PATH) as WatchBotsTuning
	return _tuning


static func defaults() -> WatchBotsOptions:
	return WatchBotsOptions.new()


## True when the command line asks for a watch match (`--watch-bots` or `--watch-bots=<n>`).
static func has_cli(args: PackedStringArray) -> bool:
	for raw: String in args:
		var text: String = _strip(raw)
		if text == CLI_FLAG or text.begins_with(CLI_FLAG + "="):
			return true
	return false


## The options a command line describes: saved/default values overridden by --watch-bots=<n>, --mode=,
## --difficulty=, --gifts=0 and --weather=0. Unknown values keep the saved/default one.
static func from_args(args: PackedStringArray, base: WatchBotsOptions = null) -> WatchBotsOptions:
	var options: WatchBotsOptions = base if base != null else defaults()
	var count: String = _value(args, CLI_FLAG + "=")
	if count.is_valid_int():
		options.bots = clampi(int(count), tuning().min_bots, tuning().max_bots)
	var mode_text: String = _value(args, "mode=").to_lower()
	if not mode_text.is_empty():
		var parsed_mode: int = mode_from_text(mode_text)
		if parsed_mode >= 0:
			options.mode = parsed_mode
	var level_text: String = _value(args, "difficulty=").to_lower()
	if not level_text.is_empty():
		var parsed_level: int = difficulty_from_text(level_text)
		if parsed_level >= 0:
			options.difficulty = parsed_level as Difficulty
	if _value(args, "gifts=") == "0":
		options.gifts = false
	if _value(args, "weather=") == "0":
		options.weather = false
	return options


## A mode name (classic, ctf, elimination, sky, domination) or selectable GameMode int; -1 when unknown.
static func mode_from_text(text: String) -> int:
	match text:
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
	if text.is_valid_int() and MatchConfig.is_game_mode_selectable(int(text)):
		return int(text)
	return -1


static func difficulty_from_text(text: String) -> int:
	match text:
		"easy":
			return Difficulty.EASY
		"normal":
			return Difficulty.NORMAL
		"hard":
			return Difficulty.HARD
		"mixed":
			return Difficulty.MIXED
	return -1


## The match this describes: `base` (the lobby's default config) with every seat a bot. player_count ==
## ai_count == bots, so no human seat exists. Never mutates `base`.
func build_config(base: MatchConfig) -> MatchConfig:
	var config: MatchConfig = base.duplicate(true) as MatchConfig
	var count: int = clampi(bots, tuning().min_bots, tuning().max_bots)
	config.player_count = count
	config.ai_count = count
	config.sandbox = false
	config.game_mode = MatchConfig.resolve_game_mode(mode)
	config.round_timer_minutes = MatchConfig.clamp_round_timer(config.round_timer_minutes, config.game_mode)
	config.gifts_enabled = gifts
	if not weather:
		config.weather_mode = MatchConfig.WeatherMode.OFF
	elif config.weather_mode == MatchConfig.WeatherMode.OFF:
		config.weather_mode = MatchConfig.WeatherMode.CHANGING
	config.slot_ai_difficulties = PackedInt32Array()
	if difficulty == Difficulty.MIXED:
		# DECISION: "mixed" spreads Easy/Normal/Hard over the seats in turn.
		for slot_id: int in range(count):
			config.slot_ai_difficulties.append(slot_id % MatchConfig.AiDifficulty.size())
	else:
		config.ai_difficulty = difficulty as MatchConfig.AiDifficulty
	return config


## Loads the last picker values (defaults when never saved or when persistence is off).
static func load_saved() -> WatchBotsOptions:
	var options: WatchBotsOptions = defaults()
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(_save_path()) != OK:
		return options
	options.bots = clampi(int(cfg.get_value(SECTION, KEY_BOTS, options.bots)), tuning().min_bots, tuning().max_bots)
	var saved_mode: int = int(cfg.get_value(SECTION, KEY_MODE, options.mode))
	options.mode = MatchConfig.resolve_game_mode(saved_mode)
	options.difficulty = clampi(int(cfg.get_value(SECTION, KEY_DIFFICULTY, options.difficulty)), 0, DIFFICULTY_LABELS.size() - 1) as Difficulty
	options.gifts = bool(cfg.get_value(SECTION, KEY_GIFTS, options.gifts))
	options.weather = bool(cfg.get_value(SECTION, KEY_WEATHER, options.weather))
	return options


func save() -> void:
	if not UserPaths.persistence_allowed():
		return
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION, KEY_BOTS, bots)
	cfg.set_value(SECTION, KEY_MODE, mode)
	cfg.set_value(SECTION, KEY_DIFFICULTY, int(difficulty))
	cfg.set_value(SECTION, KEY_GIFTS, gifts)
	cfg.set_value(SECTION, KEY_WEATHER, weather)
	cfg.save(_save_path())


static func _save_path() -> String:
	return UserPaths.gut_path(SAVE_PATH) if UserPaths.is_isolated_run() else SAVE_PATH


static func _strip(raw: String) -> String:
	return raw.lstrip("-")


static func _value(args: PackedStringArray, prefix: String) -> String:
	for raw: String in args:
		var text: String = _strip(raw)
		if text.begins_with(prefix):
			return text.substr(prefix.length())
	return ""
