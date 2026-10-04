class_name WeatherTuning
extends Resource
## One weather's tunables and registry entry (Bontago-22y.10). One .tres per
## weather under res://config/weather/; WeatherTuning.load_all() is the
## registry. Effects (Storm 22y.4, Rain 22y.5, Snow 22y.6) read their own
## strength numbers from a subclass or a sibling resource; this base only
## carries what the framework itself needs.

## Where the registry scans. Architecture, not a tunable.
const WEATHER_DIR: String = "res://config/weather/"

## What each lifecycle phase of one active weather means. Wire values: keep
## the order.
enum Phase { RAMP_IN, HOLD, RAMP_OUT }

## Stable machine id; also the wire id. Lobby modes map onto these ids
## (MatchWeather.id_for_mode()).
@export var id: StringName = &""
@export var display_name: String = ""
## Peak intensity 0..1 the ramp climbs to. Effects scale their strength by
## the ramped value, so this is the one per-weather strength dial.
@export_range(0.0, 1.0, 0.01) var intensity: float = 1.0
## Seconds to climb from 0 to `intensity` after the weather starts.
@export var ramp_in_s: float = 4.0
## Seconds to fall from `intensity` to 0 before the weather is removed.
@export var ramp_out_s: float = 4.0
## Changing mode: how long one appearance holds at full intensity (after the
## ramp-in, before the ramp-out), drawn uniformly from this range by the
## host's seeded schedule.
@export var hold_min_s: float = 40.0
@export var hold_max_s: float = 80.0
## Client-side presentation scene (instanced by vfx/weather/WeatherPresenter).
## Empty means "no visuals". Never used by the host's physics.
@export_file("*.tscn") var presentation_scene: String = ""
## Host-side physics effect: a script extending WeatherEffect. Empty means the
## weather has no physics effect (visual-only, or a later package's slot).
@export_file("*.gd") var effect_script: String = ""
## Looping ambience bed (Bontago-mp0.118), played on every peer while this
## weather is active; its volume follows the ramped intensity. Empty = silent.
@export_file("*.wav") var ambience_loop: String = ""
## Bed volume (dB) at full intensity, before the Master/SFX sliders.
@export_range(-40.0, 6.0, 0.5) var ambience_volume_db: float = 0.0


## The ramp factor 0..1 for `phase` after `phase_t` seconds in it.
func ramp_factor(phase: int, phase_t: float) -> float:
	match phase:
		Phase.RAMP_IN:
			return 1.0 if ramp_in_s <= 0.0 else clampf(phase_t / ramp_in_s, 0.0, 1.0)
		Phase.RAMP_OUT:
			return 0.0 if ramp_out_s <= 0.0 else clampf(1.0 - phase_t / ramp_out_s, 0.0, 1.0)
	return 1.0


## Effective intensity 0..1: the ramp factor scaled by the peak.
func intensity_at(phase: int, phase_t: float) -> float:
	return clampf(intensity, 0.0, 1.0) * ramp_factor(phase, phase_t)


## Every WeatherTuning under WEATHER_DIR, sorted by id (the sort is what makes
## seeded random picks reproducible on every machine).
static func load_all() -> Array[WeatherTuning]:
	var defs: Array[WeatherTuning] = []
	var dir: DirAccess = DirAccess.open(WEATHER_DIR)
	if dir == null:
		return defs
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		# Exported PCKs list text resources as "<name>.tres.remap".
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			var def: WeatherTuning = load(WEATHER_DIR + file_name) as WeatherTuning
			if def != null and def.id != &"":
				defs.append(def)
		file_name = dir.get_next()
	dir.list_dir_end()
	defs.sort_custom(func(a: WeatherTuning, b: WeatherTuning) -> bool: return String(a.id) < String(b.id))
	return defs
