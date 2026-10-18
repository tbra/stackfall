class_name SkyEvaluator
extends RefCounted
## Pure sky maths: (SkyCycleDef, phase, seed, night index, weather) -> SkyFrame, in three cached
## stages. This file holds the contract only; the bodies land with the evaluator package, so
## every function asserts until then and returns the frame it was given (or a fresh one).

const NOT_IMPLEMENTED: String = "SKY-01b"


## Stage A (tick): day palette, sun, night mix, variation and the puff channel. The only stage
## that touches keyframes, variation and the night mix.
static func evaluate_tick(_def: SkyCycleDef, _phase: float, _variation_seed: int, _night_index: int,
		_aurora_preset_on: bool, into: SkyFrame = null) -> SkyFrame:
	assert(false, NOT_IMPLEMENTED)
	return into if into != null else SkyFrame.new()


## Stage B (storm): the storm overlay over the cached stage A frame. Cheap; reruns on a storm
## amount or overlay change.
static func apply_storm(_tick: SkyFrame, _storm_amount: float, _overlay: SkyOverlayDef,
		_flare_off_amount: float, _into: SkyFrame) -> void:
	assert(false, NOT_IMPLEMENTED)


## Stage C (weather): overcast, snow, weather fog and sun dimming over the cached stage B frame.
## Cheap; reruns on any weather or sun-dim change.
static func apply_weather(_source: SkyFrame, _weather: SkyWeatherState, _into: SkyFrame) -> void:
	assert(false, NOT_IMPLEMENTED)


## Stages A, B and C in order (tests and the golden fixture only).
static func evaluate(_def: SkyCycleDef, _phase: float, _variation_seed: int, _night_index: int,
		_weather: SkyWeatherState, _aurora_preset_on: bool, into: SkyFrame = null) -> SkyFrame:
	assert(false, NOT_IMPLEMENTED)
	return into if into != null else SkyFrame.new()


## Weight of a key whose phase window is `window` (x, y, z, w) at `phase`:
## smoothstep(x, y, p) * (1 - smoothstep(z, w, p)), wrapped into 0..1.
static func window_weight(_phase: float, _window: Vector4) -> float:
	assert(false, NOT_IMPLEMENTED)
	return 0.0


## Unit direction toward the sun at `phase`.
static func sun_direction(_def: SkyCycleDef, _phase: float) -> Vector3:
	assert(false, NOT_IMPLEMENTED)
	return Vector3.UP


## Daylight 0..1 at `phase` (smoothstep of the sun elevation over the twilight width).
static func daylight(_def: SkyCycleDef, _phase: float) -> float:
	assert(false, NOT_IMPLEMENTED)
	return 0.0


## Stage A step 1: writes the day palette at `phase` into `into`.
static func day_palette(_def: SkyCycleDef, _phase: float, _into: SkyFrame) -> void:
	assert(false, NOT_IMPLEMENTED)


## Stage A step 5: mixes the night layer over the day palette already in `into`.
static func apply_night(_def: SkyCycleDef, _into: SkyFrame) -> void:
	assert(false, NOT_IMPLEMENTED)


## Stage A step 4: the seeded exposure and sea-coverage variation at `phase`.
static func apply_variation(_def: SkyCycleDef, _phase: float, _variation_seed: int, _into: SkyFrame) -> void:
	assert(false, NOT_IMPLEMENTED)


## Moon, aurora and sun effects (tick-owned parts in stage A, weather-owned parts in stage C).
static func apply_celestial(_def: SkyCycleDef, _weather: SkyWeatherState, _night_index: int,
		_variation_seed: int, _aurora_preset_on: bool, _into: SkyFrame) -> void:
	assert(false, NOT_IMPLEMENTED)


## The puff-material far-fade snapshot (puff_shared) taken from `from_frame`.
static func puff_snapshot(_def: SkyCycleDef, _from_frame: SkyFrame, _into: SkyFrame) -> void:
	assert(false, NOT_IMPLEMENTED)
