class_name SkyWeatherState
extends RefCounted
## The weather requests a sky evaluation applies on top of the cycle and the storm overlay:
## storm amount and look, overcast, snow brighten, weather fog and sun dimming. Presenters set
## these as state; SkyEvaluator.apply_weather reads them. Pure data, no scene tree.

## Tuning of the weather ceiling the evaluator reads thresholds from.
var tuning: WeatherCeilingTuning
## Storm blend amount 0..1 and the look it blends toward.
var storm_amount: float = 0.0
var storm_overlay: SkyOverlayDef = null
## Overcast amount 0..1 and the scales and fog tint it requests.
var overcast_amount: float = 0.0
var overcast_light_scale: float = 1.0
var overcast_ambient_scale: float = 1.0
var overcast_exposure_scale: float = 1.0
var overcast_fog_tint: Color = Color.WHITE
var overcast_fog_tint_strength: float = 0.0
## Cloud-only overcast from the weather ceiling.
var weather_cloud_overcast: float = 0.0
var snow_brighten: float = 0.0
## Weather fog: amount, opacity cap, depth range and tint.
var wfog_amount: float = 0.0
var wfog_max_opacity: float = 0.0
var wfog_depth_begin_m: float = 0.0
var wfog_depth_end_m: float = 0.0
var wfog_tint: Color = Color.WHITE
var wfog_tint_strength: float = 0.0
var wfog_sky_affect_add: float = 0.0
## Multiplier on the sun light while a cloud crosses the sun.
var sun_cloud_scale: float = 1.0


## Back to a fresh state: amount 0 and identity scales (the tuning reference is kept).
func clear() -> void:
	storm_amount = 0.0
	storm_overlay = null
	overcast_amount = 0.0
	weather_cloud_overcast = 0.0
	snow_brighten = 0.0
	overcast_light_scale = 1.0
	sun_cloud_scale = 1.0
	overcast_ambient_scale = 1.0
	overcast_exposure_scale = 1.0
	overcast_fog_tint = Color.WHITE
	overcast_fog_tint_strength = 0.0
	wfog_amount = 0.0
	wfog_max_opacity = 0.0
	wfog_depth_begin_m = 0.0
	wfog_depth_end_m = 0.0
	wfog_tint = Color.WHITE
	wfog_tint_strength = 0.0
	wfog_sky_affect_add = 0.0


## The overcast the cloud layers are graded by (strongest of the sources).
func cloud_overcast_amount() -> float:
	return maxf(overcast_amount, weather_cloud_overcast)


## True while any weather request is above zero (the sun-cloud scale is not a request).
func any_active() -> bool:
	return storm_amount > 0.0 or overcast_amount > 0.0 or weather_cloud_overcast > 0.0 \
		or snow_brighten > 0.0 or wfog_amount > 0.0
