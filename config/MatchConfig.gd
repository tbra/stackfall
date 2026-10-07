class_name MatchConfig
extends Resource
## Every lobby setting from spec 2.8, plus the player palette, serializable to
## a Dictionary so M3 can send it over an RPC or store it as Steam lobby data
## (spec 3.4, 3.6).
##
## Loaded once as config/match_defaults.tres. Match.start_match() takes a
## duplicate, never the shared resource, so a match can never write back into
## the defaults on disk.

## Single owner: MapDef.MapShape (MapDef cannot import MatchConfig, MatchConfig can
## import MapDef). Same ordinals and names; tests/unit/test_enum_lockstep.gd pins them.
const MapVariant = MapDef.MapShape
## Spec 2.8 "Teams: Off / 2 / 3 / 4".
enum TeamMode { OFF, TEAMS_2, TEAMS_3, TEAMS_4 }
enum AiDifficulty { EASY, NORMAL, HARD }
## Spec 2.1.
enum TiltMode { SPECIALS_ONLY, PHYSICAL_BALANCE }
## Spec 2.2. TEMPORARY closes a hole hole_close_delay after the overlap ends;
## PERMANENT never closes it, so the board erodes over the match. OFF is the
## no-overlap v2 mode (docs/TERRITORY_V2_PLAN.md): no floor holes at all,
## ownership decided by TerritoryRaster's argmax fill.
##
## DECISION (config/MatchConfig.gd, Bontago-cmc.7): reverted to TEMPORARY as
## the default. SPEC.md's 2026-09-20 evidence audit ("Decisions made — current
## target": "restore overlap holes as the fidelity target... The no-overlap v2
## mode is optional, not the default") supersedes the earlier owner answer
## this comment used to cite -- the installed original's own tutorial text
## confirms overlap sinking (docs/ORIGINAL_INSTALL_EVIDENCE.md), which the v2
## OFF default contradicted. Point-ray placement, continuous solving and goal
## no-build zones are retained owner requirements and now apply under every
## mode (autoload/Match.gd, core/rules/PlacementRules.gd), not just OFF.
##
## DECISION (config/MatchConfig.gd): OFF is **appended** rather than inserted,
## so the existing two values keep their ints and every already-serialized raw
## 0 or 1 -- a .tres on disk, a saved lobby preset, a peer still running the
## previous build -- keeps meaning exactly what it meant.
enum HoleMode { TEMPORARY, PERMANENT, OFF }

## Weather (Bontago-22y.10, owner decisions Bontago-22y.14 and 470.1).
## DECISION (config/MatchConfig.gd): a TYPE mode (STORM/RAIN/SNOW/...) is that
## weather active CONSTANTLY for the whole match (short start delay, then full
## intensity, no calm gaps); RANDOM = one type drawn at match start, then
## constant; CHANGING = random events, calm most of the time, each event draws
## its own type (WeatherScheduleTuning.avoid_repeat_type); OFF = none.
## New weather types go BEFORE RANDOM (lobby labels are derived from these
## names, so the ints must stay contiguous and CHANGING last);
## MatchWeather.id_for_mode() maps a type mode to config/weather/<name>.tres by
## lower-casing its name.
enum WeatherMode { OFF, STORM, RAIN, SNOW, FOG, RANDOM, CHANGING }

## Lobby "Map" time of day (Bontago-470.4, owner 2026-09-30; reworked by
## Bontago-59o.18, docs/SKY_CYCLE_DEFAULT_PLAN.md). CYCLE = the running
## day/night cycle, the DEFAULT. DAY ("Sunset"), NIGHT and DAWN are that same
## cycle locked at a fixed phase (SkyThemeDef.locked_phase_for). RANDOM = the
## host picks one of the three locked ones at match start
## (autoload/match/MatchLifecycle.gd), never the running cycle, and replicates
## the concrete id in sky_theme_resolved, so every client shows the same sky.
## Append-only: these integer values ride in lobby data and network messages;
## an old DAY (0) now reads as the locked Sunset.
enum SkyThemeMode { DAY, NIGHT, RANDOM, CYCLE, DAWN }
## Concrete theme ids for host RANDOM rolls and resolved-id validation. The
## enum has non-concrete RANDOM/CYCLE entries, so its indices are not used here.
const SKY_ID_SUNSET: String = "sunset"
const SKY_ID_NIGHT: String = "night"
const SKY_ID_DAWN: String = "dawn"
const SKY_THEME_IDS: PackedStringArray = [SKY_ID_SUNSET, SKY_ID_NIGHT, SKY_ID_DAWN]
## Bontago-59o.18 (C1b follow-up): sky_variation_seed's "not resolved" value, and the
## largest seed (a 31-bit int, so core/SkyVariation's integer hash never overflows).
const SKY_VARIATION_SEED_UNRESOLVED: int = -1
const SKY_VARIATION_SEED_MAX: int = 2147483647
## Bontago-1pi.75: sky_start_phase's "not resolved" value (the cycle then opens at
## SkyThemeDef.cycle_start_phase).
const SKY_START_PHASE_UNRESOLVED: float = -1.0

## Game mode (Bontago-22y.11). Appended-only like the other enums: ints ride
## in to_dict() and in saved lobbies. Only the ids in SELECTABLE_GAME_MODES
## may be played; CAPTURE_THE_FLAG, ELIMINATION and REACH_THE_SKY are
## RESERVED ids for Bontago-22y.7/.8/.9. A reserved or out-of-range id is
## never an error: sanitize() (host, on every config it adopts) and
## from_dict() (so a wire value can never start a mode with no objective)
## fall back to CLASSIC. A mode package makes its id selectable by adding it
## to SELECTABLE_GAME_MODES and giving ModeObjective.create() a branch.
enum GameMode { CLASSIC, CAPTURE_THE_FLAG, ELIMINATION, REACH_THE_SKY, DOMINATION }
const SELECTABLE_GAME_MODES: Array[int] = [
	GameMode.CLASSIC, GameMode.CAPTURE_THE_FLAG, GameMode.ELIMINATION, GameMode.REACH_THE_SKY,
	GameMode.DOMINATION
]
## Lobby labels, indexed by GameMode.
const GAME_MODE_LABELS: PackedStringArray = ["Classic", "Capture the Flag", "Elimination", "Reach the Sky", "Domination"]
## Round timer (timed modes only), minutes. Classic keeps match_timer_minutes.
## DECISION (Bontago-1pi.30, owner playtest 2026-10-03): the lobby timer is a
## 2-30 minute slider defaulting to 5 (was 1-40, default 10). Classic's
## match_timer_minutes shares ROUND_TIMER_MAX_MINUTES as its ceiling, so an old
## saved/remote 40 is clamped to 30 by sanitize() like any other out-of-range value.
const ROUND_TIMER_MIN_MINUTES: int = 2
const ROUND_TIMER_MAX_MINUTES: int = 30
## Round length a CTF / Reach the Sky match starts from (matches round_timer_minutes).
const ROUND_TIMER_DEFAULT_MINUTES: int = 5
## Domination (Bontago-1pi.25) always needs a timer (it has no early win); this is
## the round length it starts from when the lobby has none to carry over.
## DECISION (Bontago-1pi.30): follows the owner's 5-minute default round timer
## (playtest 2026-10-03) like every other timed mode.
const DOMINATION_ROUND_MINUTES_DEFAULT: int = 5
## Elimination alone may switch its round timer off (0): it then runs until one
## team is left. Every other timed mode needs a timer to end.
const ROUND_TIMER_OFF_MINUTES: int = 0

## Lobby team picks (Bontago-1pi.53): 1..TEAM_PICK_MAX are explicit lobby team
## numbers (same number = same team), TEAM_PICK_RANDOM is resolved by the host at
## match start (core/rules/TeamAssigner.gd). TEAM_PICK_MAX is the largest
## TeamMode's team count.
const TEAM_PICK_RANDOM: int = 0
const TEAM_PICK_MAX: int = 4

## -- Spec 2.8 table, in order -----------------------------------------------
@export var map_variant: MapVariant = MapVariant.ROUND
## Spec 2.8's map size; the enum lives on MapDef (see the note there).
@export var map_size: MapDef.MapSize = MapDef.MapSize.MEDIUM
## Total players including bots, 2-8.
@export var player_count: int = 4
## How many of `player_count` are bots. M2 is hot-seat only, so 0.
@export var ai_count: int = 0
## Default difficulty for every bot; slot_ai_difficulties overrides it per slot.
@export var ai_difficulty: AiDifficulty = AiDifficulty.NORMAL
@export var team_mode: TeamMode = TeamMode.OFF
## Lobby rework (Bontago-1pi.53, docs/LOBBY_REWORK_PLAN.md section 3). Per-seat
## team picks live in the lobby seat table; at Start the host resolves them
## (core/rules/TeamAssigner.gd) and writes the result here. All three arrays are
## OPTIONAL and empty by default, which is exactly the legacy behaviour (teams
## interleave by slot, one bot difficulty), so an old saved lobby, a dict from
## another build, `--bots=N` and the sandbox all keep working untouched.
## DECISION (config/MatchConfig.gd): `team_mode` stays the on/off switch and the
## pick cap (OFF, or 2/3/4 teams offered); the arrays are only honoured while it
## is not OFF, and sanitize() drops them when they are not self-consistent, so a
## bad wire value degrades to the legacy interleave instead of crashing a match.
## Dense team id (0..team_numbers.size()-1) of each slot, host-resolved at Start;
## one entry per slot (size == player_count) or empty.
@export var slot_team_ids: PackedInt32Array = PackedInt32Array()
## Lobby team number (1..TEAM_PICK_MAX, strictly ascending) of each dense team
## id, so labels read "Team 3" as the lobby showed it. Empty = unresolved.
@export var team_numbers: PackedInt32Array = PackedInt32Array()
## Difficulty (AiDifficulty int) of the bot in each slot, indexed by slot id
## (entries for human slots are ignored); empty or short = ai_difficulty.
@export var slot_ai_difficulties: PackedInt32Array = PackedInt32Array()
## Bontago-1pi.62: the name of each bot, by bot ordinal (bot k holds slot
## player_count - ai_count + k). Runtime state (exported only so duplicate() carries it): the host fills it at
## match start (BotNames.assign) and it rides in to_dict() so every client labels
## the same bots the same. Empty or short = "Player N" for the missing bots.
@export var bot_names: PackedStringArray = PackedStringArray()
## Block timer in seconds, 3-12.
@export var block_timer: float = 5.0
## Bontago-1pi.18.1: snapshot of the host's QolExperiments (all OFF by default)
## taken at start_match() and carried to clients in to_dict() (last key). Null
## means "no experiments", the default for every config built outside a match.
@export var qol: QolExperiments = null
## Lobby gravity multiplier, GRAVITY_MIN-GRAVITY_MAX, 1.0 = the shipped feel.
## DECISION (Bontago-59o.11): this is relative to PhysicsTuning.lobby_gravity_baseline
## (the old 1.4 Heavy & Bouncy factor); start_match() writes
## baseline * this into the shared tuning's gravity_multiplier, so the
## effective default gravity is unchanged while the lobby reads 1.0.
@export var gravity_multiplier: float = 1.0
## Goal flags, 1-5.
@export var goal_flag_count: int = 1
@export var gifts_enabled: bool = true
## Special frequency, 0-100.
@export var special_frequency: int = 30
## Empty means "every special enabled by default" (M4 populates it).
@export var enabled_specials: Array[StringName] = []
@export var tilt_mode: TiltMode = TiltMode.SPECIALS_ONLY
@export var hole_mode: HoleMode = HoleMode.TEMPORARY
## Match timer in minutes; 0 is off, otherwise up to ROUND_TIMER_MAX_MINUTES
## (the lobby slider skips 1 so on is 2-30; spec 2.8's 10-40 was superseded by
## the owner's 2026-10-03 playtest note, Bontago-1pi.30).
@export var match_timer_minutes: int = 0
@export var sudden_death: bool = false
## Spec 2.7 "Turn-based [NEW]": physics settles completely before the next
## player's turn starts. Orthogonal to team_mode and to hot_seat (M2's own
## single-PC test harness, spec Part 4 M2: "must not become normal play") --
## turn_based is a real, networkable mode B4 implements against active_slot/
## advance_turn(), the same machinery hot_seat already uses for its own,
## different (instant hand-off) trigger.
@export var turn_based: bool = false
## Which objective decides the match (see GameMode). Default CLASSIC.
@export var game_mode: GameMode = GameMode.CLASSIC
## Round length for timed modes (the objective's timer-end path finishes the
## match when it reaches zero). Ignored by CLASSIC, which keeps using
## match_timer_minutes + sudden_death exactly as before.
@export var round_timer_minutes: int = ROUND_TIMER_DEFAULT_MINUTES
## Reach the Sky only (Bontago-22y.9): false = a team's record is its best
## member's, true = the sum of its members' records. A plain bool, so it needs
## no clamp; the host still re-types it from the wire in from_dict().
@export var sky_team_sum: bool = false
## Weather event schedule (Bontago-22y.10); see WeatherMode.
@export var weather_mode: WeatherMode = WeatherMode.CHANGING
## Lobby "Map" time of day (see SkyThemeMode). DECISION (owner 2026-10-03,
## Bontago-59o.18): default CYCLE.
@export var sky_theme_mode: SkyThemeMode = SkyThemeMode.CYCLE
## The concrete theme id the host resolved at match start ("" = not resolved
## yet, and "" for CYCLE, which is not a concrete theme). Rides in to_dict() so
## clients never roll their own.
@export var sky_theme_resolved: String = ""
## Bontago-59o.18 (C1b follow-up): the seed of the cycle sky's exposure / cloud
## coverage variation (core/SkyVariation.gd). -1 = not resolved yet. The host rolls it
## once per match start (resolve_sky_variation_seed) and it rides in to_dict(), so the
## host and every client draw the same sky and each match gets its own curve. A match
## with a deterministic rng_seed (>= 0) needs no roll: effective_sky_variation_seed()
## falls back to it, keeping seeded tests and bot loops reproducible.
@export var sky_variation_seed: int = SKY_VARIATION_SEED_UNRESOLVED
## Bontago-1pi.75: the phase (0..1, Skybox cycle phase) a running Cycle sky opens at.
## -1 = not resolved (opens at SkyThemeDef.cycle_start_phase). The host rolls it once
## per match from the match seed (resolve_sky_start_phase) and it rides in to_dict(),
## so every peer, and the loading screen backdrop, agree. Unused by locked presets.
@export var sky_start_phase: float = SKY_START_PHASE_UNRESOLVED
## Spec 3.4 "Mid-match joins can be enabled in settings" (Bontago-8or.11): when
## true the host admits a new peer while a match runs (an open human seat, else
## a spectator) and replays the world to it. Off by default, so a match stays
## lobby-only exactly as before. Reconnects inside NetConfig.disconnect_grace
## are honoured either way (autoload/Net.gd). Lobby-replicated through
## to_dict(); from_dict() accepts only a real bool off the wire.
@export var allow_mid_match_join: bool = false

## -- Beyond the 2.8 table ---------------------------------------------------
## Bontago-mp0.27: seconds of pre-match 3-2-1 countdown (spec 3.7). 0 disables it.
## Host-only knob, deliberately not in to_dict(): clients mirror the host's
## replicated countdown ticks. Sandbox matches always skip it, see
## effective_countdown_seconds(). Match.COUNTDOWN_SECONDS is this default.
const COUNTDOWN_SECONDS_DEFAULT: float = 3.0
@export var countdown_seconds: float = COUNTDOWN_SECONDS_DEFAULT
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

## True only for the unlisted `godot --path . -- --sandbox` debug entry point
## (Bontago-mv0.8; game/Main.gd's _build_sandbox_config()). Never set by the
## lobby, a wire message or Steam lobby data — Main sets it only on the
## sandbox config it builds itself, offline.
##
## DECISION (config/MatchConfig.gd): a MatchConfig field rather than a
## dedicated PLAYER_COUNT_MIN-like constant, because sanitize() needs to know
## *this config's* intent, not add a second global floor every other caller
## would have to remember not to use. It does exactly one thing here: lets
## sanitize() allow a 1-player match, so a sandbox tester can place blocks
## for one slot alone without needing a second seat. It carries no other
## meaning — the feed-timer-disabled default Match starts a sandbox match
## with is a runtime flag on Match itself (autoload/Match.gd's
## _feed_timer_enabled), read once from this at start_match() and then
## flippable by ui/SandboxPanel.gd's sandbox_toggle_timer hotkey without
## touching this Resource again.
@export var sandbox: bool = false

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
## Old effective range 0.5-2.0 divided by the 1.4 baseline, rounded.
const GRAVITY_MIN: float = 0.35
const GRAVITY_MAX: float = 1.45
## Saved/networked dicts without a "gravity_scale_version" key hold the old
## absolute multiplier; from_dict() divides it by this legacy baseline.
const LEGACY_GRAVITY_BASELINE: float = 1.4
const GOAL_FLAG_MIN: int = 1
const GOAL_FLAG_MAX: int = 5
const SPECIAL_FREQUENCY_MIN: int = 0
const SPECIAL_FREQUENCY_MAX: int = 100


## Bontago-6fc.1: the lobby shows ONE timer control whose range follows the
## mode. Classic edits match_timer_minutes (0 = off); CTF and Reach the Sky edit
## round_timer_minutes (minimum 1); Elimination edits round_timer_minutes with 0
## meaning "no limit".
static func timer_is_match_timer(mode: int) -> bool:
	return resolve_game_mode(mode) == GameMode.CLASSIC


## Lowest value of the mode's timer control, minutes.
static func timer_min_minutes(mode: int) -> int:
	if resolve_game_mode(mode) == GameMode.CLASSIC:
		return 0
	return clamp_round_timer(0, mode)


## Value the timer control takes when the mode changes family: classic off,
## Elimination no limit, CTF/Sky the shipped round length.
static func timer_default_minutes(mode: int) -> int:
	match resolve_game_mode(mode):
		GameMode.CLASSIC, GameMode.ELIMINATION:
			return 0
		GameMode.DOMINATION:
			return DOMINATION_ROUND_MINUTES_DEFAULT
	return ROUND_TIMER_DEFAULT_MINUTES


## True when two modes share one timer meaning (so a mode switch keeps the value).
static func same_timer_family(a: int, b: int) -> bool:
	return timer_is_match_timer(a) == timer_is_match_timer(b) and timer_min_minutes(a) == timer_min_minutes(b)


## True when `mode` may be chosen in the lobby and played.
static func is_game_mode_selectable(mode: int) -> bool:
	return SELECTABLE_GAME_MODES.has(mode)


## Round timer minutes clamped for `mode`: 0 (off) survives only for Elimination.
static func clamp_round_timer(minutes: int, mode: int) -> int:
	var lowest: int = ROUND_TIMER_OFF_MINUTES if mode == GameMode.ELIMINATION else ROUND_TIMER_MIN_MINUTES
	return clampi(minutes, lowest, ROUND_TIMER_MAX_MINUTES)


## `mode` itself when selectable, otherwise CLASSIC (the reserved/unknown
## fallback documented at GameMode).
static func resolve_game_mode(mode: int) -> GameMode:
	return mode as GameMode if is_game_mode_selectable(mode) else GameMode.CLASSIC


## Bontago-6fc.2: true when `mode` plays with goal flags (Classic, CTF).
## Reach the Sky and Elimination have no goal flag at all.
static func mode_uses_goal_flags(mode: int) -> bool:
	var resolved: GameMode = resolve_game_mode(mode)
	return resolved != GameMode.REACH_THE_SKY and resolved != GameMode.ELIMINATION and resolved != GameMode.DOMINATION


## Goal flags this match actually spawns: goal_flag_count, or 0 when the mode
## has none. The sandbox keeps its beacon in every mode (it never wins on it,
## see MatchTerritory._finish_objective_step).
func effective_goal_flag_count() -> int:
	if sandbox or mode_uses_goal_flags(game_mode):
		return goal_flag_count
	return 0


## The MapDef this config's map_variant + map_size select.
func map_def() -> MapDef:
	return MapDef.for_variant_and_size(map_variant, map_size)


func field_radius() -> float:
	return map_def().field_radius


## Number of teams `mode` selects (TeamMode.OFF excluded -- team_count()
## already special-cases it before ever calling this). TeamMode's own
## ordinals encode the count directly: TEAMS_2/3/4 sit at ordinals 1/2/3, one
## below the team count each name promises, so `int(mode) + 1` reads it back
## with no lookup table that could drift from the enum if a fifth team size
## were ever added.
func team_mode_team_count(mode: TeamMode) -> int:
	return int(mode) + 1


## How many teams this config has. TeamMode.OFF is free-for-all, which is
## modelled as one team per player so the rest of the code never branches. With
## host-resolved lobby teams (see teams_resolved()) it is how many distinct teams
## the seats actually formed; ids are dense, so range(team_count()) stays valid.
func team_count() -> int:
	if team_mode == TeamMode.OFF:
		return player_count
	if teams_resolved():
		return team_numbers.size()
	return mini(team_mode_team_count(team_mode), player_count)


## Which team a slot belongs to. Free-for-all gives every slot its own team.
##
## DECISION (config/MatchConfig.gd): teams interleave (`slot_id %
## team_count`) rather than block-assign (first half one team, second half
## the other). MapDef.home_flag_position() already spaces every slot's home
## flag evenly around the disk by `slot_id` (config/MapDef.gd:221-223), so
## interleaving spreads each team's starting positions around the disk
## instead of clustering them on one arc -- a reasonable default reading of
## "exact original team-win/home-anchor semantics remain unverified" (spec
## 2.2). `mini(..., player_count)` in team_count() guards the degenerate case
## (TEAMS_4 with player_count == 2: team_count() returns 2, not 4, so no team
## is ever empty).
##
## Lobby rework (Bontago-1pi.53): once the host has resolved the lobby team picks
## (slot_team_ids) a slot the array covers uses its resolved id; the interleave
## stays the fallback for everything else, so a lobby with no picks, an old
## config and `--bots=N` behave exactly as before.
func team_of_slot(slot_id: int) -> int:
	if team_mode == TeamMode.OFF:
		return slot_id
	if teams_resolved() and slot_id >= 0 and slot_id < slot_team_ids.size():
		return slot_team_ids[slot_id]
	return posmod(slot_id, team_count())


## True when teams are on (any TeamMode but OFF).
func teams_enabled() -> bool:
	return team_mode != TeamMode.OFF


## True when the host has resolved the lobby team picks into slot_team_ids /
## team_numbers (teams on and both arrays present). False means "legacy
## interleave".
func teams_resolved() -> bool:
	return team_mode != TeamMode.OFF and not slot_team_ids.is_empty() and not team_numbers.is_empty()


## The highest explicit team number a seat may pick: 0 while teams are off, else
## the team count the mode offers (2/3/4). The lobby's team button cycles
## 1..team_pick_cap() then Random (TeamAssigner.next_pick()).
func team_pick_cap() -> int:
	if team_mode == TeamMode.OFF:
		return 0
	return team_mode_team_count(team_mode)


## Lobby number (1-based) of the dense team `team_id`, for labels: the number the
## team had in the lobby when resolved, else team_id + 1 (the legacy label).
func team_number_for(team_id: int) -> int:
	if teams_resolved() and team_id >= 0 and team_id < team_numbers.size():
		return team_numbers[team_id]
	return team_id + 1


## Difficulty of the bot in `slot_id`: its slot_ai_difficulties entry when the
## array covers the slot, else the lobby-wide ai_difficulty.
func ai_difficulty_for_slot(slot_id: int) -> AiDifficulty:
	if slot_id >= 0 and slot_id < slot_ai_difficulties.size():
		return clampi(slot_ai_difficulties[slot_id], AiDifficulty.EASY, AiDifficulty.HARD) as AiDifficulty
	return clampi(ai_difficulty, AiDifficulty.EASY, AiDifficulty.HARD) as AiDifficulty


## Colour of each TEAM, indexed by team id, for the territory overlay and minimap.
## Legacy and FFA (OFF or unresolved) return player_colors untouched: there team id
## t is slot t (slot_id % count == t for t < count), so player_colors[t] is already
## the right colour. With resolved teams a team shows the colour of its lowest
## slot; per-player colours (block tints, flags) stay independent of this.
## DECISION (plan D4, config/MatchConfig.gd): lowest slot, not an extra palette
## pick, so a team's colour is always one its members actually own.
func territory_colors() -> PackedColorArray:
	if not teams_resolved():
		return player_colors
	var fallback: PackedColorArray = default_player_colors()
	var colors: PackedColorArray = PackedColorArray()
	for team_id: int in range(team_numbers.size()):
		var lowest_slot: int = slot_team_ids.find(team_id)
		if lowest_slot < 0:
			lowest_slot = team_id
		if lowest_slot < player_colors.size():
			colors.append(player_colors[lowest_slot])
		else:
			colors.append(fallback[lowest_slot % fallback.size()])
	return colors


## Bontago-mv0.7: networked play only has as many real players as connected
## peers, so a lobby that starts with player_count above that count leaves a
## slot with no peer behind it. That slot still gets a feed timer
## (autoload/Match.gd's _tick_feed) and auto-drops a block at its home flag on
## every expiry (net/MatchNet.gd's _on_feed_timer_expired), which reads as a
## phantom player taking a turn -- unless M5's `ai_count` claims it as a bot
## seat instead (autoload/match/MatchLifecycle.gd's _build_slots()).
## `peer_count` is Net.peer_ids().size() (or a test double's), which counts
## the host too. Pure and Resource-owned (CLAUDE.md: no scene-tree dependence
## in config/), so ui/Lobby.gd's own DECISION on where to call this from
## stays the only place that needs to know about Net.
##
## DECISION (config/MatchConfig.gd, Bontago-d5c, M5): a bot never needs a
## connected peer behind it -- only ai_count and the spec 2.8 range bound it.
## Humans outrank bots for the available seats: peer_count is never reduced
## to make room for a bot, and a stale ai_count that doesn't fit is trimmed
## down to whatever room is left, never zeroed outright unless there is none.
## With ai_count == 0 this reduces to the exact old formula (player_count =
## clampi(peer_count, MIN, MAX), ai_count stays 0), so every existing caller
## that never touches ai_count sees no behaviour change.
func clamp_to_connected_peers(peer_count: int) -> void:
	var wanted_total: int = clampi(peer_count + ai_count, peer_count, PLAYER_COUNT_MAX)
	ai_count = clampi(wanted_total - peer_count, 0, PLAYER_COUNT_MAX - peer_count)
	player_count = clampi(peer_count + ai_count, PLAYER_COUNT_MIN, PLAYER_COUNT_MAX)


## Clamps every field into its spec 2.8 range. The host calls this on any
## config that arrived over the wire before using it.
func sanitize() -> void:
	map_variant = clampi(map_variant, MapVariant.ROUND, MapVariant.CROSS)
	map_size = clampi(map_size, MapDef.MapSize.SMALL, MapDef.MapSize.LARGE) as MapDef.MapSize
	# Spec 2.8's floor is 2 players; sandbox is the one path allowed below it
	# (down to 1), for solo rules/physics testing (Bontago-mv0.8).
	var min_player_count: int = 1 if sandbox else PLAYER_COUNT_MIN
	player_count = clampi(player_count, min_player_count, PLAYER_COUNT_MAX)
	ai_count = clampi(ai_count, 0, player_count)
	ai_difficulty = clampi(ai_difficulty, AiDifficulty.EASY, AiDifficulty.HARD)
	team_mode = clampi(team_mode, TeamMode.OFF, TeamMode.TEAMS_4)
	block_timer = clampf(block_timer, BLOCK_TIMER_MIN, BLOCK_TIMER_MAX)
	gravity_multiplier = clampf(gravity_multiplier, GRAVITY_MIN, GRAVITY_MAX)
	goal_flag_count = clampi(goal_flag_count, GOAL_FLAG_MIN, GOAL_FLAG_MAX)
	special_frequency = clampi(special_frequency, SPECIAL_FREQUENCY_MIN, SPECIAL_FREQUENCY_MAX)
	tilt_mode = clampi(tilt_mode, TiltMode.SPECIALS_ONLY, TiltMode.PHYSICAL_BALANCE)
	hole_mode = clampi(hole_mode, HoleMode.TEMPORARY, HoleMode.OFF) as HoleMode
	match_timer_minutes = clampi(match_timer_minutes, ROUND_TIMER_OFF_MINUTES, ROUND_TIMER_MAX_MINUTES)
	if qol != null:
		qol.sanitize()
	game_mode = resolve_game_mode(game_mode)
	round_timer_minutes = clamp_round_timer(round_timer_minutes, game_mode)
	# turn_based is a plain bool -- no range to clamp.
	weather_mode = clampi(weather_mode, WeatherMode.OFF, WeatherMode.CHANGING) as WeatherMode
	sky_theme_mode = clampi(sky_theme_mode, SkyThemeMode.DAY, SkyThemeMode.DAWN) as SkyThemeMode
	if not SKY_THEME_IDS.has(sky_theme_resolved):
		sky_theme_resolved = ""
	sky_variation_seed = clampi(sky_variation_seed, SKY_VARIATION_SEED_UNRESOLVED, SKY_VARIATION_SEED_MAX)
	sky_start_phase = clampf(sky_start_phase, SKY_START_PHASE_UNRESOLVED, 1.0)
	if player_colors.size() < PLAYER_COUNT_MAX:
		var defaults: PackedColorArray = default_player_colors()
		var padded: PackedColorArray = player_colors.duplicate()
		for i: int in range(padded.size(), PLAYER_COUNT_MAX):
			padded.append(defaults[i])
		player_colors = padded
	_sanitize_team_data()


## Lobby rework arrays (see slot_team_ids). slot_ai_difficulties is clamped per
## entry (an oversized array is dropped: it falls back to ai_difficulty). The two
## team arrays are all-or-nothing: they survive only while teams are on and they
## agree (one id per slot, ids dense 0..n-1 each used, numbers strictly ascending
## within 1..team_pick_cap()); otherwise both are cleared and the legacy interleave
## applies. Runs last in sanitize(), after team_mode and player_count are clamped.
func _sanitize_team_data() -> void:
	if slot_ai_difficulties.size() > PLAYER_COUNT_MAX:
		slot_ai_difficulties = PackedInt32Array()
	for i: int in range(slot_ai_difficulties.size()):
		slot_ai_difficulties[i] = clampi(slot_ai_difficulties[i], AiDifficulty.EASY, AiDifficulty.HARD)
	if not _team_data_is_consistent():
		slot_team_ids = PackedInt32Array()
		team_numbers = PackedInt32Array()


func _team_data_is_consistent() -> bool:
	if slot_team_ids.is_empty() and team_numbers.is_empty():
		return true
	if team_mode == TeamMode.OFF or slot_team_ids.is_empty() or team_numbers.is_empty():
		return false
	if slot_team_ids.size() != player_count or team_numbers.size() > team_pick_cap():
		return false
	var previous_number: int = TEAM_PICK_RANDOM
	for number: int in team_numbers:
		if number <= previous_number or number > team_pick_cap():
			return false
		previous_number = number
	var used: PackedInt32Array = PackedInt32Array()
	used.resize(team_numbers.size())
	for team_id: int in slot_team_ids:
		if team_id < 0 or team_id >= team_numbers.size():
			return false
		used[team_id] += 1
	return not used.has(0)


## Host only, at match start: turns sky_theme_mode into a concrete theme id.
## `roll` picks one of the concrete themes for RANDOM; callers pass randi() % size.
## CYCLE has no concrete id: it resolves to "" (the running cycle).
func resolve_sky_theme(roll: int) -> void:
	match sky_theme_mode:
		SkyThemeMode.NIGHT:
			sky_theme_resolved = "night"
		SkyThemeMode.DAWN:
			sky_theme_resolved = "dawn"
		SkyThemeMode.RANDOM:
			sky_theme_resolved = SKY_THEME_IDS[posmod(roll, SKY_THEME_IDS.size())]
		SkyThemeMode.CYCLE:
			sky_theme_resolved = ""
		_:
			sky_theme_resolved = "sunset"


## Host only, at match start (next to resolve_sky_theme): gives the cycle sky's
## variation a seed of its own when the match has none. `roll` is any int (callers
## pass randi()); it is folded into 0..SKY_VARIATION_SEED_MAX. A seed that is already
## resolved is kept (resolving is once per match), and a match with a deterministic
## rng_seed (>= 0) is left unresolved on purpose: it already has a reproducible seed
## (effective_sky_variation_seed).
func resolve_sky_variation_seed(roll: int) -> void:
	if sky_variation_seed >= 0 or rng_seed >= 0:
		return
	sky_variation_seed = posmod(roll, SKY_VARIATION_SEED_MAX + 1)


## Host only, at match start after resolve_sky_variation_seed: picks the phase a running
## Cycle opens at, uniformly in [phase_min, phase_max], from a RandomNumberGenerator
## seeded with effective_sky_variation_seed() (the host-rolled seed, or the match's
## deterministic rng_seed), so a seed always gives the same phase and two seeds differ.
## `roll` is used only when the match has no seed at all. Locked presets and an already
## resolved phase are left alone.
func resolve_sky_start_phase(roll: int, phase_min: float, phase_max: float) -> void:
	if not is_sky_cycle_running() or sky_start_phase >= 0.0:
		return
	var seed_value: int = effective_sky_variation_seed()
	if seed_value < 0:
		seed_value = posmod(roll, SKY_VARIATION_SEED_MAX + 1)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	sky_start_phase = clampf(rng.randf_range(phase_min, phase_max), 0.0, 1.0)


## The seed the cycle sky's variation should use, or SKY_VARIATION_SEED_UNRESOLVED
## (-1) when this config has none (the sky then falls back to SkyVariation's shared
## default curve). The host's resolved sky_variation_seed wins; otherwise the match's
## deterministic rng_seed (>= 0). Derived only from replicated fields, so every peer
## agrees.
func effective_sky_variation_seed() -> int:
	if sky_variation_seed >= 0:
		return sky_variation_seed
	if rng_seed >= 0:
		return rng_seed
	return SKY_VARIATION_SEED_UNRESOLVED


## The theme id a match should show: the host's resolved id when present, else
## the mode's own (an unresolved RANDOM falls back to DAY, i.e. "sunset"). A
## running CYCLE has no theme of its own and also reads "sunset" here (the
## structural theme the cycle is built from); use is_sky_cycle_running() /
## locked_sky_id() to tell the cycle apart.
func effective_sky_theme() -> String:
	if sky_theme_resolved != "":
		return sky_theme_resolved
	if sky_theme_mode == SkyThemeMode.NIGHT:
		return "night"
	if sky_theme_mode == SkyThemeMode.DAWN:
		return "dawn"
	return "sunset"


## True while the sky is the running day/night cycle (the default).
func is_sky_cycle_running() -> bool:
	return sky_theme_mode == SkyThemeMode.CYCLE


## The concrete id ("sunset", "night" or "dawn") the cycle is locked at, or ""
## while the cycle is running. Derived only from replicated fields, so every
## peer agrees; feed it to SkyThemeDef.locked_phase_for().
func locked_sky_id() -> String:
	if is_sky_cycle_running():
		return ""
	return effective_sky_theme()


## Serializes to a plain Dictionary for RPCs and Steam lobby data.
func to_dict() -> Dictionary:
	var data: Dictionary = {
		"map_variant": map_variant,
		"map_size": map_size,
		"player_count": player_count,
		"ai_count": ai_count,
		"ai_difficulty": ai_difficulty,
		"team_mode": team_mode,
		"block_timer": block_timer,
		"gravity_multiplier": gravity_multiplier,
		"gravity_scale_version": 2,
		"goal_flag_count": goal_flag_count,
		"gifts_enabled": gifts_enabled,
		"special_frequency": special_frequency,
		"enabled_specials": enabled_specials.duplicate(),
		"tilt_mode": tilt_mode,
		"hole_mode": hole_mode,
		"match_timer_minutes": match_timer_minutes,
		"sudden_death": sudden_death,
		"turn_based": turn_based,
		"game_mode": game_mode,
		"round_timer_minutes": round_timer_minutes,
		"sky_team_sum": sky_team_sum,
		"weather_mode": weather_mode,
		"sky_theme_mode": sky_theme_mode,
		"sky_theme_resolved": sky_theme_resolved,
		"sky_variation_seed": sky_variation_seed,
		"sky_start_phase": sky_start_phase,
		"allow_mid_match_join": allow_mid_match_join,
		"per_player_timer": per_player_timer,
		"hot_seat": hot_seat,
		"player_colors": player_colors.duplicate(),
		"rng_seed": rng_seed,
	}
	# Lobby rework arrays ride only when set, so a legacy config's dict is unchanged.
	if not slot_team_ids.is_empty():
		data["slot_team_ids"] = slot_team_ids.duplicate()
	if not team_numbers.is_empty():
		data["team_numbers"] = team_numbers.duplicate()
	if not slot_ai_difficulties.is_empty():
		data["slot_ai_difficulties"] = slot_ai_difficulties.duplicate()
	if not bot_names.is_empty():
		data["bot_names"] = bot_names.duplicate()
	if qol != null:
		data["qol"] = qol.to_dict()
	return data


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
	# DECISION (Bontago-59o.11): a dict without the version key is pre-rescale,
	# so its multiplier was absolute; convert to the new baseline-relative scale.
	if data.has("gravity_multiplier") and not data.has("gravity_scale_version"):
		config.gravity_multiplier /= LEGACY_GRAVITY_BASELINE
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
	config.turn_based = bool(data.get("turn_based", config.turn_based))
	config.game_mode = resolve_game_mode(int(data.get("game_mode", config.game_mode)))
	config.round_timer_minutes = clamp_round_timer(
		int(data.get("round_timer_minutes", config.round_timer_minutes)), config.game_mode
	)
	config.sky_team_sum = bool(data.get("sky_team_sum", config.sky_team_sum))
	config.weather_mode = int(data.get("weather_mode", config.weather_mode)) as WeatherMode
	config.sky_theme_mode = int(data.get("sky_theme_mode", config.sky_theme_mode)) as SkyThemeMode
	config.sky_theme_resolved = String(data.get("sky_theme_resolved", config.sky_theme_resolved))
	# An old config without the key (or a mistyped value) stays unresolved; sanitize()
	# clamps a stray number into range.
	var variation_seed: Variant = data.get("sky_variation_seed", config.sky_variation_seed)
	if variation_seed is int or variation_seed is float:
		config.sky_variation_seed = clampi(int(variation_seed), SKY_VARIATION_SEED_UNRESOLVED, SKY_VARIATION_SEED_MAX)
	var start_phase: Variant = data.get("sky_start_phase", config.sky_start_phase)
	if start_phase is int or start_phase is float:
		config.sky_start_phase = clampf(float(start_phase), SKY_START_PHASE_UNRESOLVED, 1.0)
	# Host-validated (Bontago-8or.11): bool("false") is true, so a String or
	# any other type from Steam lobby data or an old build keeps the default.
	var mid_match_join: Variant = data.get("allow_mid_match_join", config.allow_mid_match_join)
	if mid_match_join is bool:
		config.allow_mid_match_join = mid_match_join
	config.per_player_timer = bool(data.get("per_player_timer", config.per_player_timer))
	config.hot_seat = bool(data.get("hot_seat", config.hot_seat))
	if data.has("player_colors"):
		config.player_colors = PackedColorArray(data["player_colors"])
	config.rng_seed = int(data.get("rng_seed", config.rng_seed))
	config.slot_team_ids = _int_array_from(data.get("slot_team_ids"))
	config.team_numbers = _int_array_from(data.get("team_numbers"))
	config.slot_ai_difficulties = _int_array_from(data.get("slot_ai_difficulties"))
	config.bot_names = _names_from(data.get("bot_names"))
	if data.get("qol") is Dictionary:
		config.qol = QolExperiments.from_dict(data["qol"] as Dictionary)
	return config


## Bot names from whatever the wire delivered: only String entries survive, at
## most PLAYER_COUNT_MAX of them, each cleaned like a human's name. Anything else
## gives an empty array (the "Player N" fallback).
static func _names_from(value: Variant) -> PackedStringArray:
	var parsed: PackedStringArray = PackedStringArray()
	if not (value is Array or value is PackedStringArray):
		return parsed
	var items: Array = Array(value)
	if items.size() > PLAYER_COUNT_MAX:
		return parsed
	for item: Variant in items:
		if not (item is String or item is StringName):
			return PackedStringArray()
		parsed.append(PlayerNames.clean(String(item), PlayerNames.BOT_NAME_MAX_LENGTH))
	return parsed


## A PackedInt32Array from whatever the wire delivered: a PackedInt32Array/
## PackedInt64Array (RPC) or an Array of numbers (JSON through the Steam lobby
## tee, where ints come back as floats). Missing, mistyped, non-numeric or longer
## than PLAYER_COUNT_MAX gives an empty array, i.e. the legacy behaviour; this
## never errors on foreign data.
static func _int_array_from(value: Variant) -> PackedInt32Array:
	var parsed: PackedInt32Array = PackedInt32Array()
	if not (value is Array or value is PackedInt32Array or value is PackedInt64Array):
		return parsed
	var items: Array = Array(value)
	if items.size() > PLAYER_COUNT_MAX:
		return parsed
	for item: Variant in items:
		if not (item is int or item is float):
			return PackedInt32Array()
		parsed.append(int(item))
	return parsed


## Bontago-mp0.27. # DECISION: sandbox (and the tutorial, which is a sandbox
## config) skip the countdown: a lone tester wants to place immediately.
## Headless bot matches set countdown_seconds = 0 in Main.
func effective_countdown_seconds() -> float:
	if sandbox:
		return 0.0
	return maxf(countdown_seconds, 0.0)
