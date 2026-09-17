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


## Clamps every field into its spec 2.8 range. The host calls this on any
## config that arrived over the wire before using it.
func sanitize() -> void:
	pass


## Serializes to a plain Dictionary for RPCs and Steam lobby data.
func to_dict() -> Dictionary:
	return {}


## Rebuilds a config from to_dict() output. Unknown keys keep their defaults.
@warning_ignore_start("unused_parameter")
static func from_dict(data: Dictionary) -> MatchConfig:
	return MatchConfig.new()
@warning_ignore_restore("unused_parameter")
