class_name AudioConfig
extends Resource
## Typed event -> filename mapping for autoload/Sfx.gd's placeholder audio
## from the original Bontago install (assets-audio package). Filenames are
## lowercase; tools/install_original_assets.ps1 lowercases the originals
## (which mix `Top.jpg`/`top.jpg` case) on install so this file never has to
## special-case casing at runtime.
##
## Loaded once as config/audio_config.tres. Original SFX live in gitignored
## assets/original/audio/ and are referenced by filename only. Owner-created
## music is imported and committed under assets/music/, referenced by the
## typed AudioStream playlists below, and included in exported builds.

## Random thud on block impact (game/Block.gd's contact signal), one of five
## originals so repeated landings don't sound identical.
@export var thud_files: Array[String] = [
	"thud1.wav", "thud2.wav", "thud3.wav", "thud4.wav",
]
@export var rejected_file: String = "placement_rejected_pcm.wav"
@export var click_file: String = "select.wav"
@export var start_game_file: String = "start_game.mp3"
@export var hover_file: String = "button_hover_pcm.wav"
@export var drop_file: String = "block_placed.wav"
@export var bounce_file: String = "boing.wav"
@export var music_file: String = "bontago1.mp3"

## Legacy single-stream fallback (custom-folder overrides are disabled).
@export var bundled_theme: AudioStream = null
## Path form of the legacy theme (loaded on use, not resident at boot); played when
## contextual_music_enabled is false and bundled_theme is unset.
@export_file("*.mp3") var bundled_theme_path: String = ""

## Contextual tracks play once, with silence between songs instead of looping.
@export var contextual_music_enabled: bool = true
## Shipped playlists are path lists (Bontago-1pi.11.61): Sfx loads only the one
## track it is about to play (threaded prefetch, released afterwards) instead of
## every MP3 being resident from boot. The AudioStream arrays below are an
## optional pre-resolved override (tests, custom builds); when non-empty for a
## context they win over the paths.
@export var menu_playlist_paths: PackedStringArray = PackedStringArray()
@export var lobby_playlist_paths: PackedStringArray = PackedStringArray()
@export var gameplay_playlist_paths: PackedStringArray = PackedStringArray()
@export var menu_playlist: Array[AudioStream] = []
@export var lobby_playlist: Array[AudioStream] = []
@export var gameplay_playlist: Array[AudioStream] = []
@export_range(0.0, 30.0) var music_fade_in_seconds: float = 4.0
@export_range(0.0, 30.0) var music_fade_out_seconds: float = 5.0
@export_range(0.0, 300.0) var music_gap_min_seconds: float = 20.0
@export_range(0.0, 300.0) var music_gap_max_seconds: float = 50.0
@export_range(0.0, 30.0) var music_initial_delay_seconds: float = 2.0


func playlist_for_context(context: StringName) -> Array[AudioStream]:
	match context:
		&"menu":
			return menu_playlist
		&"lobby":
			return lobby_playlist
		&"gameplay":
			return gameplay_playlist
		_:
			return []


## Track resource paths for `context` (empty when a stream override is set).
func playlist_paths_for_context(context: StringName) -> PackedStringArray:
	if not playlist_for_context(context).is_empty():
		return PackedStringArray()
	match context:
		&"menu":
			return menu_playlist_paths
		&"lobby":
			return lobby_playlist_paths
		&"gameplay":
			return gameplay_playlist_paths
		_:
			return PackedStringArray()


## Number of tracks in `context`, from the stream override or else the paths.
func playlist_track_count(context: StringName) -> int:
	var streams: Array[AudioStream] = playlist_for_context(context)
	return streams.size() if not streams.is_empty() else playlist_paths_for_context(context).size()

## Two-stem adaptive music (spec 2.10 "adaptive... more intense as someone
## gets close to capturing"; docs/M7_PLAN.md P6). Sfx.gd crossfades between
## this and music_stem_tense_file as Events.goal_capture_progress moves past
## music_tense_progress_threshold. Defaults to the same file as music_file
## (still EVENT_MUSIC's own source below) so a checkout with no tense asset
## installed sounds identical to before this field existed.
@export var music_stem_calm_file: String = "bontago1.mp3"

## DECISION (config/AudioConfig.gd, Bontago-xtq.31): no real "tense" mix of
## the original score has shipped yet (docs/M7_PLAN.md P6's own asset-risk
## note) -- this points at a filename nothing installs today so
## Sfx.tense_stem_available() is false out of the box and the adaptive
## crossfade quietly does nothing until a real file lands here, the same
## "supported absence" this file's own header documents for the whole
## assets-audio package.
@export var music_stem_tense_file: String = "bontago1_tense.mp3"

## Crossfade duration (seconds) for Sfx's Tween between the calm and tense
## stems.
@export var music_crossfade_seconds: float = 3.0

## Events.goal_capture_progress value (0..1) at or above which Sfx crossfades
## toward the tense stem; below it, toward the calm stem (including the 0.0
## a broken/reset capture reports -- see Events.gd's own doc comment).
@export var music_tense_progress_threshold: float = 0.6

## Hysteresis margin (docs/M7_PLAN.md P6 review, Bontago-xtq.31) subtracted
## from music_tense_progress_threshold to get the *release* point once the
## tense stem is active, so progress hovering right at the threshold doesn't
## flap the crossfade back and forth every frame. The *rising* edge (calm ->
## tense) always uses the plain threshold above; only the falling edge
## (tense -> calm) is relaxed by this margin. 0.0 reproduces the old
## single-threshold behaviour exactly.
@export var music_tense_release_margin: float = 0.1

## DECISION (config/AudioConfig.gd, Bontago-6y2): the local slot's own gift
## claim (spec 2.6, Events.gift_claimed). No dedicated original asset for
## "you got a reward" exists in the SoundFX pack, and EVENT_BOUNCE/bounce_file
## already registers "boing.wav" as an upbeat, positive bloop with no consumer
## wired to it yet (nothing calls Sfx.play(EVENT_BOUNCE)) -- reusing that same
## filename here keeps the "no new binary assets" rule (see this file's own
## header) while giving the claim its own event/field so it can get its own
## sound and tuning later without touching EVENT_BOUNCE.
@export var gift_claimed_file: String = "boing.wav"
## Original three-note chime bundled with the game, heard when a new crate
## descends (see assets/effects/README.md for provenance).
@export var gift_spawn_file: String = "gift_spawn_jingle.wav"
## Minimum seconds between gift-spawn jingles (spam limit).
@export var gift_spawn_min_interval_s: float = 2.0

## M4 specials (spec 2.6): registered now so the event map is complete, no
## hooks call these yet -- the specials themselves aren't implemented.
@export var bomb_file: String = "bomb.wav"
@export var rocket_file: String = "rocket.wav"
@export var volcano_file: String = "volcano.wav"
@export var quake_file: String = "quake2.wav"
@export var propeller_file: String = "propeller.wav"
@export var breakage_file: String = "eliminated.wav"
@export var creak_file: String = "creak.wav"

## Below this impact speed (m/s), a block landing makes no sound at all.
@export var impact_speed_min: float = 1.0
## At or above this impact speed (m/s), a thud plays at its loudest.
@export var impact_speed_loud: float = 8.0
## Decibel offset applied to a thud at exactly impact_speed_min.
@export var impact_quiet_db_offset: float = -18.0
## Decibel offset applied to a thud at or above impact_speed_loud.
@export var impact_loud_db_offset: float = 0.0

## DECISION (Bontago-1pi.28): effects were near-inaudible because the bundled
## wavs sat at -29..-12 dBFS window-RMS AND this baseline was -16 dB (6 dB
## below the music's). tools/measure_audio.py --normalize now brings every
## bundled wav to -16 dBFS short-window RMS (peak <= -1 dBFS); with this -3 dB
## baseline a full-scale cue lands near -19 dBFS RMS, ~5 dB above the music bed
## (music_volume_db below on ~-14 dBFS-RMS mastered tracks, never measured:
## no ffmpeg here). There is no AudioServer bus layout and Sfx uses plain 2D
## AudioStreamPlayers, so there is no bus or distance attenuation on top.
@export var sfx_volume_db: float = -3.0
@export var music_volume_db: float = -10.0

## Block impact variation set (Bontago-mp0.116, assets/effects/impact_variation_v1).
## Folder under assets/effects holding the soft/medium/hard x block/disc wavs.
@export var impact_variation_dir: String = "impact_variation_v1"
## Normalized impact strength t = clamp((speed - impact_speed_min) /
## (impact_speed_loud - impact_speed_min), 0, 1). Below impact_soft_max_t is
## SOFT, below impact_medium_max_t is MEDIUM, otherwise HARD.
@export_range(0.0, 1.0) var impact_soft_max_t: float = 1.0 / 3.0
@export_range(0.0, 1.0) var impact_medium_max_t: float = 2.0 / 3.0
## Sample variants per "<surface>_<tier>" key (SURFACE_* / TIER_* below). Sfx picks
## one at random, never the same twice in a row while a second exists.
@export var impact_variation_files: Dictionary[StringName, PackedStringArray] = {
	&"block_soft": PackedStringArray(["impact_block_soft_01.wav", "impact_block_soft_02.wav"]),
	&"block_medium": PackedStringArray(["impact_block_medium_01.wav", "impact_block_medium_02.wav"]),
	&"block_hard": PackedStringArray(["impact_block_hard_01.wav", "impact_block_hard_02.wav"]),
	&"disc_soft": PackedStringArray(["impact_disc_soft_01.wav", "impact_disc_soft_02.wav"]),
	&"disc_medium": PackedStringArray(["impact_disc_medium_01.wav", "impact_disc_medium_02.wav"]),
	&"disc_hard": PackedStringArray(["impact_disc_hard_01.wav", "impact_disc_hard_02.wav"]),
}
## The impact event carries only (speed, position); Sfx classifies the surface
## with a sphere query of this radius (m) at the impact point. At least
## impact_block_surface_min_blocks distinct Blocks inside it (the faller plus
## what it hit) means block-on-block; anything else is the disc/platform.
@export var impact_surface_query_radius_m: float = 0.75
@export var impact_block_surface_min_blocks: int = 2

## Lobby/loading UI cues (Bontago-mp0.117, assets/effects/lobby_ui_cues_v1).
@export var ui_cue_dir: String = "lobby_ui_cues_v1"
@export var ui_cue_files: Dictionary[StringName, String] = {
	&"player_joined": "player_joined.wav",
	&"player_left": "player_left.wav",
	&"ready_on": "ready_on.wav",
	&"ready_off": "ready_off.wav",
	&"team_change": "team_change.wav",
	&"colour_change": "colour_change.wav",
	&"bot_added": "bot_added.wav",
	&"bot_removed": "bot_removed.wav",
	&"section_expanded": "section_expanded.wav",
	&"section_collapsed": "section_collapsed.wav",
	&"all_players_ready": "all_players_ready.wav",
}
## Extra gain (dB) on top of sfx_volume_db for UI cues (files carry their own level).
@export var ui_cue_volume_db: float = 0.0

## Sfx's AudioStreamPlayer pool size (spec: "max_simultaneous"). One extra
## player is always reserved for music, on top of this many for one-shot sfx.
@export var max_simultaneous: int = 8

## Kill switch for impact-thud detection (game/Block.gd's velocity-based
## _physics_process check, no contact_monitor -- an earlier revision's
## contact_monitor approach cost ~5-7 ms/physics step at 300 blocks
## (tests/bench/bench_rain.gd), well over budget, and was replaced by
## comparing frame-to-frame linear_velocity instead, which re-measured within
## noise. This flag stays as a plain kill switch in case that ever needs
## disabling again without another Block.gd edit.
@export var impacts_enabled: bool = true

const EVENT_THUD: StringName = &"thud"
const EVENT_REJECTED: StringName = &"rejected"
const EVENT_CLICK: StringName = &"click"
const EVENT_START_GAME: StringName = &"start_game"
const EVENT_HOVER: StringName = &"hover"
const EVENT_DROP: StringName = &"drop"
const EVENT_BOUNCE: StringName = &"bounce"
const EVENT_MUSIC: StringName = &"music"
const EVENT_BOMB: StringName = &"bomb"
const EVENT_ROCKET: StringName = &"rocket"
const EVENT_VOLCANO: StringName = &"volcano"
const EVENT_QUAKE: StringName = &"quake"
const EVENT_PROPELLER: StringName = &"propeller"
const EVENT_BREAKAGE: StringName = &"breakage"
const EVENT_CREAK: StringName = &"creak"
const EVENT_GIFT_CLAIMED: StringName = &"gift_claimed"
const EVENT_GIFT_SPAWNED: StringName = &"gift_spawned"

const SURFACE_BLOCK: StringName = &"block"
const SURFACE_DISC: StringName = &"disc"
const TIER_SOFT: StringName = &"soft"
const TIER_MEDIUM: StringName = &"medium"
const TIER_HARD: StringName = &"hard"

const ALL_EVENTS: Array[StringName] = [
	EVENT_THUD, EVENT_REJECTED, EVENT_CLICK, EVENT_START_GAME, EVENT_HOVER, EVENT_DROP, EVENT_BOUNCE,
	EVENT_MUSIC, EVENT_BOMB, EVENT_ROCKET, EVENT_VOLCANO, EVENT_QUAKE, EVENT_PROPELLER,
	EVENT_BREAKAGE, EVENT_CREAK, EVENT_GIFT_CLAIMED, EVENT_GIFT_SPAWNED,
]


## One or more candidate filenames for `event`; Sfx picks one at random when
## there is more than one (e.g. EVENT_THUD). Empty when `event` isn't known.
func files_for_event(event: StringName) -> Array[String]:
	match event:
		EVENT_THUD:
			return thud_files
		EVENT_REJECTED:
			return [rejected_file]
		EVENT_CLICK:
			return [click_file]
		EVENT_START_GAME:
			return [start_game_file]
		EVENT_HOVER:
			return [hover_file]
		EVENT_DROP:
			return [drop_file]
		EVENT_BOUNCE:
			return [bounce_file]
		EVENT_MUSIC:
			return [music_file]
		EVENT_BOMB:
			return [bomb_file]
		EVENT_ROCKET:
			return [rocket_file]
		EVENT_VOLCANO:
			return [volcano_file]
		EVENT_QUAKE:
			return [quake_file]
		EVENT_PROPELLER:
			return [propeller_file]
		EVENT_BREAKAGE:
			return [breakage_file]
		EVENT_CREAK:
			return [creak_file]
		EVENT_GIFT_CLAIMED:
			return [gift_claimed_file]
		EVENT_GIFT_SPAWNED:
			return [gift_spawn_file]
		_:
			return []


## Decibel offset for a thud at `speed` m/s, clamped to
## [impact_quiet_db_offset, impact_loud_db_offset] regardless of how far
## outside [impact_speed_min, impact_speed_loud] `speed` falls. Callers gate
## playback below impact_speed_min separately (Sfx._on_block_impacted): this
## function only answers "how loud", never "whether at all".
func impact_volume_db(speed: float) -> float:
	var span: float = maxf(impact_speed_loud - impact_speed_min, 0.001)
	var t: float = clampf((speed - impact_speed_min) / span, 0.0, 1.0)
	return lerpf(impact_quiet_db_offset, impact_loud_db_offset, t)


## Strength tier (TIER_*) for an impact at `speed` m/s; uses the same span guard
## as impact_volume_db().
func impact_tier(speed: float) -> StringName:
	var span: float = maxf(impact_speed_loud - impact_speed_min, 0.001)
	var t: float = clampf((speed - impact_speed_min) / span, 0.0, 1.0)
	if t < impact_soft_max_t:
		return TIER_SOFT
	if t < impact_medium_max_t:
		return TIER_MEDIUM
	return TIER_HARD


## Variant filenames (relative to assets/effects) for `surface` x `tier`, empty
## when the set is not configured.
func impact_variation_for(surface: StringName, tier: StringName) -> Array[String]:
	var out: Array[String] = []
	var names: PackedStringArray = impact_variation_files.get(StringName("%s_%s" % [surface, tier]), PackedStringArray())
	for filename: String in names:
		out.append(impact_variation_dir.path_join(filename))
	return out


## Filename (relative to assets/effects) of lobby UI cue `cue`, "" when unknown.
func ui_cue_file(cue: StringName) -> String:
	var filename: String = ui_cue_files.get(cue, "")
	return "" if filename.is_empty() else ui_cue_dir.path_join(filename)
