class_name AudioConfig
extends Resource
## Typed event -> filename mapping for autoload/Sfx.gd's placeholder audio
## from the original Bontago install (assets-audio package). Filenames are
## lowercase; tools/install_original_assets.ps1 lowercases the originals
## (which mix `Top.jpg`/`top.jpg` case) on install so this file never has to
## special-case casing at runtime.
##
## Loaded once as config/audio_config.tres. The files themselves live under
## the gitignored assets/original/audio/ (HARD CONSTRAINT: third-party
## copyrighted assets never enter the public repo) -- this Resource only
## records what filename plays for which event, not the bytes.

## Random thud on block impact (game/Block.gd's contact signal), one of five
## originals so repeated landings don't sound identical.
@export var thud_files: Array[String] = [
	"thud1.wav", "thud2.wav", "thud3.wav", "thud4.wav", "thud5.wav",
]
@export var rejected_file: String = "no.wav"
@export var click_file: String = "click.wav"
@export var hover_file: String = "mouseover.wav"
@export var drop_file: String = "whoosh.wav"
@export var bounce_file: String = "boing.wav"
@export var music_file: String = "bontago1.mp3"

## M4 specials (spec 2.6): registered now so the event map is complete, no
## hooks call these yet -- the specials themselves aren't implemented.
@export var bomb_file: String = "bomb.wav"
@export var rocket_file: String = "rocket.wav"
@export var volcano_file: String = "volcano.wav"
@export var quake_file: String = "quake2.wav"
@export var propeller_file: String = "propeller.wav"
@export var breakage_file: String = "breakage.wav"
@export var creak_file: String = "creak.wav"

## Below this impact speed (m/s), a block landing makes no sound at all.
@export var impact_speed_min: float = 1.0
## At or above this impact speed (m/s), a thud plays at its loudest.
@export var impact_speed_loud: float = 8.0
## Decibel offset applied to a thud at exactly impact_speed_min.
@export var impact_quiet_db_offset: float = -18.0
## Decibel offset applied to a thud at or above impact_speed_loud.
@export var impact_loud_db_offset: float = 0.0

@export var sfx_volume_db: float = 0.0
@export var music_volume_db: float = -10.0

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

const ALL_EVENTS: Array[StringName] = [
	EVENT_THUD, EVENT_REJECTED, EVENT_CLICK, EVENT_HOVER, EVENT_DROP, EVENT_BOUNCE,
	EVENT_MUSIC, EVENT_BOMB, EVENT_ROCKET, EVENT_VOLCANO, EVENT_QUAKE, EVENT_PROPELLER,
	EVENT_BREAKAGE, EVENT_CREAK,
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
