class_name WeatherCeilingTuning
extends Resource
## Bontago-mp0.19: the overhead cloud ceiling that rain, snow and storm fall
## from, and the storm sky blend. One instance: config/weather/ceiling.tres
## (not a WeatherTuning: it is never scheduled, only fed by the active weather
## intensities). Presentation only, identical on host and client.

@export_group("Placement")
## World height (m) of the lowest ceiling layer. The play volume is 0..72 m.
@export var height_m: float = 96.0
## The ceiling never sits closer than this above the active camera.
@export var min_clearance_above_camera_m: float = 30.0
## Side (m) of each square layer; it follows the camera horizontally.
@export var size_m: float = 1400.0
## Extra layers stacked above the lowest one, and their vertical spacing.
@export var layer_count: int = 3
@export var layer_count_low: int = 1
@export var layer_spacing_m: float = 7.0
## Upper layers get up to this much less alpha (drop at the top layer).
@export_range(0.0, 1.0, 0.01) var upper_layer_alpha_drop: float = 0.25

@export_group("Look")
## Share of the sky covered at full weather intensity.
@export_range(0.0, 1.0, 0.01) var coverage: float = 0.62
## Cel edge softness of the cloud silhouette (0 = hard).
@export_range(0.0, 0.5, 0.01) var edge_softness: float = 0.06
## Noise texture cycles per metre, drift speed (m/s) and octaves.
@export var noise_scale: float = 0.005
@export var drift_speed_mps: float = 3.0
## Horizontal drift direction (normalised when used).
@export var drift_direction: Vector2 = Vector2(1.0, 0.35)
## Extra 0..1 darkening of the underside on top of the shared weather grade.
@export_range(0.0, 1.0, 0.01) var darkness: float = 0.15
## Extra darkness at full storm intensity (shared with the puffs through CloudLighting.dim).
@export_range(0.0, 1.0, 0.01) var storm_darkness_add: float = 0.35
## Bontago-mp0.29 shared weather grade (CloudLighting): overcast 1 darkens the
## puffs and ceiling by this share and moves their colours this far toward grey
## (storm counts as overcast for the desaturation).
@export_range(0.0, 1.0, 0.01) var cloud_overcast_dim: float = 0.2
@export_range(0.0, 1.0, 0.01) var cloud_overcast_desaturate: float = 0.5
## The ceiling is always at least this grey (weather cloud is never sunset-saturated).
@export_range(0.0, 1.0, 0.01) var min_desaturate: float = 0.25
## Light response: cloud on the sun/moon side of the sky is lit up by this much
## (body-thickness shift and rim glow), scaled down toward night by
## night_light_scale (0 = no moonlight response, 1 = same as the sun).
@export_range(0.0, 1.0, 0.01) var sun_side_bias: float = 0.22
@export_range(0.0, 1.0, 0.01) var night_light_scale: float = 0.35
## Shared overcast (CloudLighting.overcast) each weather drives at full intensity,
## so rain, snow and storm all dim and grey every cloud layer; the strongest wins.
@export_range(0.0, 1.0, 0.01) var overcast_rain: float = 1.0
@export_range(0.0, 1.0, 0.01) var overcast_snow: float = 0.8
@export_range(0.0, 1.0, 0.01) var overcast_storm: float = 1.0
## Camera distance (m) over which the layer edge fades into the horizon.
@export var fade_far_start_m: float = 350.0
@export var fade_far_end_m: float = 650.0
## Cel look shared with the cloud sea: flat shade steps, their edge softness (in
## step units) and how strongly lobes facing the sun/moon are lit.
@export_range(2, 8) var cel_bands: int = 4
@export_range(0.0, 0.5, 0.005) var band_softness: float = 0.1
@export_range(0.0, 20.0, 0.1) var light_contrast: float = 6.0
## View elevation (sine) below which the layer fades out near the horizon.
@export_range(0.0, 1.0, 0.01) var horizon_fade: float = 0.5
## Fade amount (0..1) at which the layers reach full opacity.
@export_range(0.05, 1.0, 0.01) var full_opacity_amount: float = 0.25

@export_group("Fades")
@export var fade_in_s: float = 5.0
@export var fade_out_s: float = 7.0
## Ids whose intensity drives the ceiling (the strongest one wins).
@export var weather_ids: Array[StringName] = [&"rain", &"snow", &"storm"]

@export_group("Storm sky")
@export var storm_id: StringName = &"storm"
@export var storm_theme_id: String = "storm"
## Blend toward the storm SkyThemeDef at full storm intensity.
@export_range(0.0, 1.0, 0.01) var storm_sky_blend: float = 1.0
## Storm blend amount at which the theme's sun flare switches off.
@export_range(0.0, 1.0, 0.01) var storm_flare_off_amount: float = 0.5

@export_group("Precipitation")
## Rain and snow spawn this far below the lowest layer.
@export var spawn_below_ceiling_m: float = 3.0
## Rain volume bottom, below the camera, and the tallest volume allowed.
@export var rain_below_camera_m: float = 20.0
@export var rain_max_height_m: float = 90.0
## Snow falls from the ceiling down to this far below the camera; the fall is
## capped, and quantised in steps so the flake lifetime is not rewritten every
## frame while the camera moves.
@export var snow_below_camera_m: float = 4.0
@export var snow_max_fall_m: float = 80.0
@export var snow_fall_step_m: float = 8.0


## World height of the lowest layer for a camera at `camera_y`.
func ceiling_y(camera_y: float) -> float:
	return maxf(height_m, camera_y + min_clearance_above_camera_m)


## Shared overcast amount a weather at `intensity` drives (0 for ids without one).
func overcast_for(weather_id: StringName, intensity: float) -> float:
	var weight: float = 0.0
	if weather_id == &"rain":
		weight = overcast_rain
	elif weather_id == &"snow":
		weight = overcast_snow
	elif weather_id == storm_id:
		weight = overcast_storm
	return clampf(intensity, 0.0, 1.0) * weight
