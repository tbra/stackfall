class_name WeatherCeilingTuning
extends Resource
## Bontago-mp0.19: the overhead puff layer that rain, snow and storm fall
## from, and the storm sky blend. One instance: config/weather/ceiling.tres
## (not a WeatherTuning: it is never scheduled, only fed by the active weather
## intensities). Presentation only, identical on host and client.

@export_group("Placement")
## World height (m) of the upper puff layer's flat bases. The play volume is 0..72 m.
## Rain and snow spawn just below it.
@export var height_m: float = 96.0
## Rain and snow never start closer than this above the active camera.
@export var min_clearance_above_camera_m: float = 30.0

@export_group("Upper puffs")
## Bontago-mp0.29: the overcast layer is the cloud sea's own puff field (same
## mesh, shader, noise and CloudLighting) duplicated above the disc. Clump count
## (before GraphicsPreset.cloud_puff_density) on Medium/High and on Low.
@export var upper_clump_count: int = 70
@export var upper_clump_count_low: int = 22
## Clumps are spread over a disc of this radius (m) around the disc axis.
@export var upper_ring_outer_m: float = 800.0
## Clump radius range (m); they are wider than the sea's so they read overhead.
@export var upper_clump_radius_min_m: float = 50.0
@export var upper_clump_radius_max_m: float = 110.0
## Bases are spread this far above height_m.
@export var upper_base_spread_m: float = 24.0
## Bontago-mp0.93: the overcast clumps are seen from below, where a flat base is one
## huge featureless slab. This is the base plane's height in each puff's unit-sphere
## space below its centre: 0.15 = the sea's flat-bottomed cumulus, 1 = a fully round
## bottom (the underside is the lumpy lower half of the puffs, no plane at all).
@export_range(0.05, 1.0, 0.01) var upper_flat_base: float = 1.0
## Vertical size of an upper puff as a share of its horizontal radius. With round bottoms
## the puffs would otherwise stand as tall as they are wide; squashed they keep the low,
## wide cumulus profile (1 = round balls).
@export_range(0.2, 1.0, 0.01) var upper_puff_squash: float = 0.6
## How far (m) a puff may hang below its clump's base level (random per puff), so the
## round bottoms of one clump never rest on a common plane. The whole layer starts
## this much higher so nothing hangs below height_m.
@export var upper_base_sink_m: float = 8.0
## How far down the clump's small "cauliflower" puffs may sit on the big ones (0 =
## upper half only, like the sea; 0.7 = they also bulge from the underside, so the
## bottom is lumpy).
@export_range(0.0, 0.95, 0.01) var upper_belly_depth: float = 0.7
## A camera close beneath the layer fades the cloud surfaces nearest its own height
## (ordered dither) so it never sees a razor-flat cloud bottom edge-on: surfaces less than
## the start height above the camera vanish, those above the end height are solid.
@export var upper_clear_fade_start_m: float = 6.0
@export var upper_clear_fade_end_m: float = 26.0
## Added to the theme's cloud_seed so the upper field differs from the sea.
@export var upper_seed_offset: int = 7919

@export_group("Look")
## Extra darkness at full storm intensity (shared with the puffs through CloudLighting.dim).
@export_range(0.0, 1.0, 0.01) var storm_darkness_add: float = 0.35
## Bontago-mp0.29 shared weather grade (CloudLighting): overcast 1 darkens the
## puffs by this share and moves their colours this far toward grey
## (storm counts as overcast for the desaturation).
@export_range(0.0, 1.0, 0.01) var cloud_overcast_dim: float = 0.2
@export_range(0.0, 1.0, 0.01) var cloud_overcast_desaturate: float = 0.5
## Shared overcast (CloudLighting.overcast) each weather drives at full intensity,
## so rain, snow and storm all dim and grey every cloud layer; the strongest wins.
@export_range(0.0, 1.0, 0.01) var overcast_rain: float = 1.0
@export_range(0.0, 1.0, 0.01) var overcast_snow: float = 0.8
@export_range(0.0, 1.0, 0.01) var overcast_storm: float = 1.0

@export_group("Night and storm floor")
## Bontago-mp0.34: the combined weather darkening never exceeds this.
@export_range(0.0, 1.0, 0.01) var max_combined_dim: float = 0.5
## Share of the weather darkening removed at full night (the night palette is already dark).
@export_range(0.0, 1.0, 0.01) var night_dim_relief: float = 0.7
## Minimum luminance of the lit puff tone after the weather grade; the shadow and
## mid tones keep these ratios of it so the cel bands stay readable.
@export_range(0.0, 1.0, 0.01) var puff_min_brightness: float = 0.34
@export_range(0.0, 1.0, 0.01) var puff_floor_shadow_ratio: float = 0.55
@export_range(0.0, 1.0, 0.01) var puff_floor_mid_ratio: float = 0.8
## Hue of the floor (deep slate blue); only its colour direction matters.
@export var puff_floor_tint: Color = Color(0.42, 0.5, 0.68)
## Soft silhouette width (pixels) of the upper puffs (0 = hard cut).
@export_range(0.0, 8.0, 0.1) var upper_edge_softness_px: float = 1.5

@export_group("Sun effects")
## Share of the sun flare, god rays and sun glow removed at full overcast / storm.
@export_range(0.0, 1.0, 0.01) var sun_overcast_attenuation: float = 0.6
@export_range(0.0, 1.0, 0.01) var sun_storm_attenuation: float = 0.97
## Night mix at which the sun effects are fully off (they fade in dusk).
@export_range(0.01, 1.0, 0.01) var sun_night_fade_end: float = 0.35

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
