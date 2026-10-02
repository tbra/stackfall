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
@export var noise_scale: float = 0.0025
@export var drift_speed_mps: float = 3.0
## Horizontal drift direction (normalised when used).
@export var drift_direction: Vector2 = Vector2(1.0, 0.35)
@export_range(1, 5) var noise_octaves: int = 4
@export_range(1, 5) var noise_octaves_low: int = 2
## Cel colours of the underside (shadow = thickest part) and 0..1 darkening.
@export var shadow_color: Color = Color(0.17, 0.2, 0.25, 1.0)
@export var mid_color: Color = Color(0.34, 0.39, 0.45, 1.0)
@export var lit_color: Color = Color(0.55, 0.6, 0.66, 1.0)
@export_range(0.0, 1.0, 0.01) var darkness: float = 0.15
## Extra darkness at full storm intensity.
@export_range(0.0, 1.0, 0.01) var storm_darkness_add: float = 0.35
## Cel band thresholds on the cloud thickness (0..1).
@export_range(0.0, 1.0, 0.01) var mid_threshold: float = 0.45
@export_range(0.0, 1.0, 0.01) var shadow_threshold: float = 0.72
## Camera distance (m) over which the layer edge fades into the horizon.
@export var fade_far_start_m: float = 350.0
@export var fade_far_end_m: float = 650.0
## Share of the noise-height blended with the round cumulus lobes (3+ octaves),
## the lobe field's scale relative to the broad field, and the cel band edge
## softness (thickness units).
@export_range(0.0, 1.0, 0.01) var lobe_mix: float = 0.45
@export var lobe_scale: float = 1.7
@export_range(0.0, 0.2, 0.005) var band_softness: float = 0.03
## View elevation (sine) below which the layer fades out near the horizon.
@export_range(0.0, 1.0, 0.01) var horizon_fade: float = 0.25
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
