class_name MatchConfig
extends Resource
## Every lobby setting from spec 2.8, plus the player palette, serializable to
## a Dictionary so M3 can send it over an RPC or store it as Steam lobby data
## (spec 3.4, 3.6).
##
## Loaded once as config/match_defaults.tres. Match.start_match() takes a
## duplicate, never the shared resource, so a match can never write back into
## the defaults on disk.

enum MapVariant { ROUND, OVAL, RING, TWIN, CROSS }
## Spec 2.8 "Teams: Off / 2 / 3 / 4".
enum TeamMode { OFF, TEAMS_2, TEAMS_3, TEAMS_4 }
enum AiDifficulty { EASY, NORMAL, HARD }
## Spec 2.1.
enum TiltMode { SPECIALS_ONLY, PHYSICAL_BALANCE }
## Spec 2.2. TEMPORARY closes a hole hole_close_delay after the overlap ends;
## PERMANENT never closes it, so the board erodes over the match.
enum HoleMode { TEMPORARY, PERMANENT }

## -- Spec 2.8 table, in order -----------------------------------------------
@export var map_variant: MapVariant = MapVariant.ROUND
## Spec 2.8's map size; the enum lives on MapDef (see the note there).
@export var map_size: MapDef.MapSize = MapDef.MapSize.MEDIUM
## Total players including bots, 2-8.
@export var player_count: int = 4
## How many of `player_count` are bots. M2 is hot-seat only, so 0.
@export var ai_count: int = 0
@export var ai_difficulty: AiDifficulty = AiDifficulty.NORMAL
@export var team_mode: TeamMode = TeamMode.OFF
## Block timer in seconds, 3-12.
@export var block_timer: float = 6.0
## Gravity multiplier, 0.5-2.0.
@export var gravity_multiplier: float = 1.0
## Goal flags, 1-5.
@export var goal_flag_count: int = 1
@export var gifts_enabled: bool = true
## Special frequency, 0-100.
@export var special_frequency: int = 35
## Empty means "every special enabled by default" (M4 populates it).
@export var enabled_specials: Array[StringName] = []
@export var tilt_mode: TiltMode = TiltMode.SPECIALS_ONLY
@export var hole_mode: HoleMode = HoleMode.TEMPORARY
## Match timer in minutes; 0 is off, otherwise 10-40 (spec 2.8).
@export var match_timer_minutes: int = 0
@export var sudden_death: bool = false

## -- Beyond the 2.8 table ---------------------------------------------------
## Spec "Still open" 1: was the block timer shared or per player? The spec's
## stated default is per player, which is what true means here.
@export var per_player_timer: bool = true
## M2 hot-seat: one PC, players take turns. M3 turns this off.
@export var hot_seat: bool = true
## Slot colors, indexed by slot_id. Eight entries, one per possible player.
@export var player_colors: PackedColorArray = PackedColorArray([
	Color(0.90, 0.25, 0.25),
	Color(0.25, 0.55, 0.95),
	Color(0.35, 0.80, 0.40),
	Color(0.95, 0.80, 0.25),
	Color(0.70, 0.40, 0.90),
	Color(0.95, 0.55, 0.20),
	Color(0.30, 0.85, 0.85),
	Color(0.95, 0.45, 0.75),
])

## Deterministic seed for the block bag and gift spawner; -1 randomizes.
@export var rng_seed: int = -1

## Shared source for player_colors' default so sanitize() can pad a config
## that arrived over the wire with too few entries, without duplicating the
## literal (CLAUDE.md: no magic numbers). A static func rather than a const,
## because GDScript constants can't be initialized from Color() constructor
## calls.
static func default_player_colors() -> PackedColorArray:
	return PackedColorArray([
		Color(0.90, 0.25, 0.25),
		Color(0.25, 0.55, 0.95),
		Color(0.35, 0.80, 0.40),
		Color(0.95, 0.80, 0.25),
		Color(0.70, 0.40, 0.90),
		Color(0.95, 0.55, 0.20),
		Color(0.30, 0.85, 0.85),
		Color(0.95, 0.45, 0.75),
	])

## Spec 2.8 ranges, so the lobby and the host's validation share one source.
const PLAYER_COUNT_MIN: int = 2
const PLAYER_COUNT_MAX: int = 8
const BLOCK_TIMER_MIN: float = 3.0
const BLOCK_TIMER_MAX: float = 12.0
const GRAVITY_MIN: float = 0.5
const GRAVITY_MAX: float = 2.0
const GOAL_FLAG_MIN: int = 1
const GOAL_FLAG_MAX: int = 5
const SPECIAL_FREQUENCY_MIN: int = 0
const SPECIAL_FREQUENCY_MAX: int = 100


## The MapDef this config's map_size selects.
func map_def() -> MapDef:
	return MapDef.for_size(map_size)


func field_radius() -> float:
	return map_def().field_radius


## How many teams this config has. TeamMode.OFF is free-for-all, which is
## modelled as one team per player so the rest of the code never branches.
func team_count() -> int:
	return player_count


## Which team a slot belongs to. Free-for-all gives every slot its own team.
func team_of_slot(slot_id: int) -> int:
	return slot_id


## Bontago-mv0.7: networked play only has as many real players as connected
## peers -- bots don't exist until M5 -- so a lobby that starts with
## player_count above that count leaves a slot with no peer behind it. That
## slot still gets a feed timer (autoload/Match.gd's _tick_feed) and
## auto-drops a block at its home flag on every expiry
## (net/MatchNet.gd's _on_feed_timer_expired), which reads as a phantom
## player taking a turn. `peer_count` is Net.peer_ids().size() (or a test
## double's), which counts the host too. Pure and Resource-owned (CLAUDE.md:
## no scene-tree dependence in config/), so ui/Lobby.gd's own
## DECISION on where to call this from stays the only place that needs to
## know about Net.
func clamp_to_connected_peers(peer_count: int) -> void:
	player_count = clampi(peer_count, PLAYER_COUNT_MIN, PLAYER_COUNT_MAX)
	ai_count = 0


## Clamps every field into its spec 2.8 range. The host calls this on any
## config that arrived over the wire before using it.
func sanitize() -> void:
	map_variant = clampi(map_variant, MapVariant.ROUND, MapVariant.CROSS)
	map_size = clampi(map_size, MapDef.MapSize.SMALL, MapDef.MapSize.LARGE) as MapDef.MapSize
	player_count = clampi(player_count, PLAYER_COUNT_MIN, PLAYER_COUNT_MAX)
	ai_count = clampi(ai_count, 0, player_count)
	ai_difficulty = clampi(ai_difficulty, AiDifficulty.EASY, AiDifficulty.HARD)
	team_mode = clampi(team_mode, TeamMode.OFF, TeamMode.TEAMS_4)
	block_timer = clampf(block_timer, BLOCK_TIMER_MIN, BLOCK_TIMER_MAX)
	gravity_multiplier = clampf(gravity_multiplier, GRAVITY_MIN, GRAVITY_MAX)
	goal_flag_count = clampi(goal_flag_count, GOAL_FLAG_MIN, GOAL_FLAG_MAX)
	special_frequency = clampi(special_frequency, SPECIAL_FREQUENCY_MIN, SPECIAL_FREQUENCY_MAX)
	tilt_mode = clampi(tilt_mode, TiltMode.SPECIALS_ONLY, TiltMode.PHYSICAL_BALANCE)
	hole_mode = clampi(hole_mode, HoleMode.TEMPORARY, HoleMode.PERMANENT)
	match_timer_minutes = maxi(match_timer_minutes, 0)
	if player_colors.size() < PLAYER_COUNT_MAX:
		var defaults: PackedColorArray = default_player_colors()
		var padded: PackedColorArray = player_colors.duplicate()
		for i: int in range(padded.size(), PLAYER_COUNT_MAX):
			padded.append(defaults[i])
		player_colors = padded


## Serializes to a plain Dictionary for RPCs and Steam lobby data.
func to_dict() -> Dictionary:
	return {
		"map_variant": map_variant,
		"map_size": map_size,
		"player_count": player_count,
		"ai_count": ai_count,
		"ai_difficulty": ai_difficulty,
		"team_mode": team_mode,
		"block_timer": block_timer,
		"gravity_multiplier": gravity_multiplier,
		"goal_flag_count": goal_flag_count,
		"gifts_enabled": gifts_enabled,
		"special_frequency": special_frequency,
		"enabled_specials": enabled_specials.duplicate(),
		"tilt_mode": tilt_mode,
		"hole_mode": hole_mode,
		"match_timer_minutes": match_timer_minutes,
		"sudden_death": sudden_death,
		"per_player_timer": per_player_timer,
		"hot_seat": hot_seat,
		"player_colors": player_colors.duplicate(),
		"rng_seed": rng_seed,
	}


## Rebuilds a config from to_dict() output. Unknown keys keep their defaults.
static func from_dict(data: Dictionary) -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.map_variant = int(data.get("map_variant", config.map_variant))
	config.map_size = int(data.get("map_size", config.map_size)) as MapDef.MapSize
	config.player_count = int(data.get("player_count", config.player_count))
	config.ai_count = int(data.get("ai_count", config.ai_count))
	config.ai_difficulty = int(data.get("ai_difficulty", config.ai_difficulty))
	config.team_mode = int(data.get("team_mode", config.team_mode))
	config.block_timer = float(data.get("block_timer", config.block_timer))
	config.gravity_multiplier = float(data.get("gravity_multiplier", config.gravity_multiplier))
	config.goal_flag_count = int(data.get("goal_flag_count", config.goal_flag_count))
	config.gifts_enabled = bool(data.get("gifts_enabled", config.gifts_enabled))
	config.special_frequency = int(data.get("special_frequency", config.special_frequency))
	if data.has("enabled_specials"):
		var specials: Array[StringName] = []
		for value: Variant in (data["enabled_specials"] as Array):
			specials.append(StringName(value))
		config.enabled_specials = specials
	config.tilt_mode = int(data.get("tilt_mode", config.tilt_mode))
	config.hole_mode = int(data.get("hole_mode", config.hole_mode))
	config.match_timer_minutes = int(data.get("match_timer_minutes", config.match_timer_minutes))
	config.sudden_death = bool(data.get("sudden_death", config.sudden_death))
	config.per_player_timer = bool(data.get("per_player_timer", config.per_player_timer))
	config.hot_seat = bool(data.get("hot_seat", config.hot_seat))
	if data.has("player_colors"):
		config.player_colors = PackedColorArray(data["player_colors"])
	config.rng_seed = int(data.get("rng_seed", config.rng_seed))
	return config
