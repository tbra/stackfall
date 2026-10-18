class_name SkyFrame
extends RefCounted
## One evaluated sky state (plain typed fields, no Dictionary of Variants on the hot path;
## puff_shared is the one exception, the explicit puff-material snapshot). Produced by
## SkyEvaluator, consumed by the writers, which copy fields to their sink. Pure data: no scene tree.
## Field groups: time/sun, sky channel, environment channel, light channel, puff channel,
## cloud lighting inputs and flare.

# time / sun
## Cycle phase 0..1 this frame was evaluated at.
var phase: float = 0.0
## Unit direction toward the sun.
var sun_direction: Vector3 = Vector3(0.0, 1.0, 0.0)
## Daylight 0..1 (smoothstep of the sun elevation).
var daylight: float = 1.0
## Night mix, 1 - daylight.
var night: float = 0.0
## Whole cycles elapsed, the night id for the aurora roll.
var night_index: int = 0

# sky channel
## Sky shader use_global_dirs flag.
var use_global_dirs: float = 1.0
## Sky exposure after variation and overcast.
var exposure: float = 1.0
## Cloud-sea coverage threshold.
var proc_sea_coverage: float = 0.0
## Sky gradient zenith.
var proc_zenith_color: Color = Color.WHITE
## Sky gradient mid.
var proc_mid_color: Color = Color.WHITE
## Sky gradient horizon.
var proc_horizon_color: Color = Color.WHITE
## Horizon glow colour.
var proc_horizon_glow_color: Color = Color.WHITE
## Gradient mid stop height.
var proc_gradient_mid_height: float = 0.0
## Gradient exponent.
var proc_gradient_power: float = 1.0
## Horizon glow width.
var proc_horizon_glow_width: float = 0.0
## Sun glow strength.
var proc_sun_glow_strength: float = 0.0
## Cloud-sea near colour.
var proc_sea_color_near: Color = Color.WHITE
## Cloud-sea far colour.
var proc_sea_color_far: Color = Color.WHITE
## Cloud-sea horizon fade.
var proc_sea_horizon_fade: float = 0.0
## Sun core colour.
var sun_core_color: Color = Color.WHITE
## Sun halo colour.
var sun_halo_color: Color = Color.WHITE
## Sun ray colour.
var sun_ray_color: Color = Color.WHITE
## Sky cloud shadow tone.
var cloud_shadow_color: Color = Color.WHITE
## Sky cloud mid tone.
var cloud_mid_color: Color = Color.WHITE
## Sky cloud lit tone.
var cloud_lit_color: Color = Color.WHITE
## Sky cloud rim tone.
var cloud_rim_color: Color = Color.WHITE
## Night mix written to the sky shader.
var cycle_night_mix: float = 0.0
## Night zenith colour.
var cycle_night_zenith: Color = Color.WHITE
## Night horizon colour.
var cycle_night_horizon: Color = Color.WHITE
## Night below-horizon colour.
var cycle_night_below: Color = Color.WHITE
## Star brightness.
var cycle_star_brightness: float = 0.0
## Star grid density.
var cycle_star_cells: float = 0.0
## Star threshold.
var cycle_star_threshold: float = 0.0
## Star radius.
var cycle_star_radius: float = 0.0
## Star horizon fade.
var cycle_star_horizon_fade: float = 0.0
## Unit direction toward the moon.
var moon_direction: Vector3 = Vector3(0.0, -1.0, 0.0)
## Moon visibility 0..1.
var moon_visibility: float = 0.0
## Moon disc radius, degrees.
var moon_angular_radius_deg: float = 0.0
## Moon halo radius, degrees.
var moon_halo_radius_deg: float = 0.0
## Moon halo strength.
var moon_halo_strength: float = 0.0
## Moon brightness.
var moon_brightness: float = 0.0
## Aurora visibility 0..1.
var aurora_visibility: float = 0.0
## Aurora brightness.
var aurora_intensity: float = 0.0
## Aurora lower colour.
var aurora_color_low: Color = Color.WHITE
## Aurora middle colour.
var aurora_color_mid: Color = Color.WHITE
## Aurora upper colour.
var aurora_color_top: Color = Color.WHITE
## Aurora speed.
var aurora_speed: float = 0.0
## Aurora lower edge height.
var aurora_base_height: float = 0.0
## Aurora curtain height.
var aurora_curtain_height: float = 0.0
## Scale of the sun disc, halo and rays under weather.
var sun_effect_scale: float = 1.0

# environment channel
## Environment fog colour.
var fog_light_color: Color = Color.WHITE
## Environment fog density.
var fog_density: float = 0.0
## Fog tint of the sky background.
var fog_sky_affect: float = 0.0
## Depth fog mode (weather fog) instead of exponential.
var fog_depth_mode: bool = false
## Depth fog start, metres.
var fog_depth_begin: float = 0.0
## Depth fog end, metres.
var fog_depth_end: float = 0.0
## Global volumetric fog density.
var volumetric_fog_density: float = 0.0
## Global volumetric fog tint.
var volumetric_fog_albedo: Color = Color.WHITE
## Environment ambient energy.
var ambient_light_energy: float = 0.0
## Background energy relative to the captured base.
var background_energy_scale: float = 1.0
## Environment glow intensity.
var glow_intensity: float = 0.0
## Environment glow threshold.
var glow_hdr_threshold: float = 0.0
## Aerial perspective blend.
var fog_aerial_perspective: float = 0.0
## Sun scatter blend.
var fog_sun_scatter: float = 0.0
## Height fog height, metres.
var fog_height: float = 0.0
## Height fog density.
var fog_height_density: float = 0.0
## Scenery haze strength.
var haze_strength: float = 0.0
## Scenery haze start, metres.
var haze_begin: float = 0.0
## Scenery haze end, metres.
var haze_end: float = 0.0
## Cloud-deck fog density.
var deck_density: float = 0.0
## Cloud-deck fog colour.
var deck_albedo: Color = Color.WHITE

# light channel
## Key light colour.
var light_color: Color = Color.WHITE
## Key light energy.
var light_energy: float = 0.0
## Key light follows the sun basis (else light_rotation_deg).
var light_uses_sun_basis: bool = true
## Key light rotation, degrees, when not following the sun.
var light_rotation_deg: Vector3 = Vector3.ZERO

# puff channel
## Puff cel shadow tone.
var puff_shadow_color: Color = Color.WHITE
## Puff cel mid tone.
var puff_mid_color: Color = Color.WHITE
## Puff cel lit tone.
var puff_lit_color: Color = Color.WHITE
## Puff cel rim tone.
var puff_rim_color: Color = Color.WHITE
## Puff-material sky cloud shadow tone.
var puff_cloud_shadow_color: Color = Color.WHITE
## Puff-material sky cloud mid tone.
var puff_cloud_mid_color: Color = Color.WHITE
## Puff-material sky cloud lit tone.
var puff_cloud_lit_color: Color = Color.WHITE
## Puff-material sky cloud rim tone.
var puff_cloud_rim_color: Color = Color.WHITE
## Moonlit grade dark stop.
var puff_grade_dark: Color = Color.WHITE
## Moonlit grade mid stop.
var puff_grade_mid: Color = Color.WHITE
## Moonlit grade light stop.
var puff_grade_light: Color = Color.WHITE
## Moonlit grade amount.
var puff_grade_amount: float = 0.0
## Puff far-fade sea near colour.
var puff_sea_color_near: Color = Color.WHITE
## Puff far-fade sea far colour.
var puff_sea_color_far: Color = Color.WHITE
## Puff exposure baseline.
var puff_exposure: float = 1.0
## Puff far-fade sea coverage.
var puff_sea_coverage: float = 0.0
## Puff light direction.
var puff_light_direction: Vector3 = Vector3(0.0, 1.0, 0.0)
## Puff sun direction.
var puff_sun_direction: Vector3 = Vector3(0.0, 1.0, 0.0)
## Snapshot of the sky values copied to the puff material for its far fade.
var puff_shared: Dictionary[StringName, Variant] = {}
## Storm overlay amount this frame was evaluated with.
var storm_amount: float = 0.0

# cloud lighting inputs
## Light colour feeding the cloud lighting.
var lighting_light_color: Color = Color.WHITE
## Overcast amount grading the clouds.
var cloud_overcast: float = 0.0
## Weather dim of the clouds.
var weather_dim: float = 0.0
## Weather desaturation of the clouds.
var weather_desaturate: float = 0.0
## Sun effects scale of the cloud lighting.
var sun_effects: float = 1.0
## Cloud floor tone.
var floor_color: Color = Color.BLACK
## Cloud floor shadow ratio.
var floor_shadow_ratio: float = 0.0
## Cloud floor mid ratio.
var floor_mid_ratio: float = 0.0

# flare
## Whether the sun flare is drawn.
var flare_enabled: bool = true
## Weather scale of the sun flare.
var flare_weather_scale: float = 1.0


## Copies every field of `other` into this frame (the puff snapshot is duplicated, not shared).
func copy_from(other: SkyFrame) -> void:
	phase = other.phase
	sun_direction = other.sun_direction
	daylight = other.daylight
	night = other.night
	night_index = other.night_index
	use_global_dirs = other.use_global_dirs
	exposure = other.exposure
	proc_sea_coverage = other.proc_sea_coverage
	proc_zenith_color = other.proc_zenith_color
	proc_mid_color = other.proc_mid_color
	proc_horizon_color = other.proc_horizon_color
	proc_horizon_glow_color = other.proc_horizon_glow_color
	proc_gradient_mid_height = other.proc_gradient_mid_height
	proc_gradient_power = other.proc_gradient_power
	proc_horizon_glow_width = other.proc_horizon_glow_width
	proc_sun_glow_strength = other.proc_sun_glow_strength
	proc_sea_color_near = other.proc_sea_color_near
	proc_sea_color_far = other.proc_sea_color_far
	proc_sea_horizon_fade = other.proc_sea_horizon_fade
	sun_core_color = other.sun_core_color
	sun_halo_color = other.sun_halo_color
	sun_ray_color = other.sun_ray_color
	cloud_shadow_color = other.cloud_shadow_color
	cloud_mid_color = other.cloud_mid_color
	cloud_lit_color = other.cloud_lit_color
	cloud_rim_color = other.cloud_rim_color
	cycle_night_mix = other.cycle_night_mix
	cycle_night_zenith = other.cycle_night_zenith
	cycle_night_horizon = other.cycle_night_horizon
	cycle_night_below = other.cycle_night_below
	cycle_star_brightness = other.cycle_star_brightness
	cycle_star_cells = other.cycle_star_cells
	cycle_star_threshold = other.cycle_star_threshold
	cycle_star_radius = other.cycle_star_radius
	cycle_star_horizon_fade = other.cycle_star_horizon_fade
	moon_direction = other.moon_direction
	moon_visibility = other.moon_visibility
	moon_angular_radius_deg = other.moon_angular_radius_deg
	moon_halo_radius_deg = other.moon_halo_radius_deg
	moon_halo_strength = other.moon_halo_strength
	moon_brightness = other.moon_brightness
	aurora_visibility = other.aurora_visibility
	aurora_intensity = other.aurora_intensity
	aurora_color_low = other.aurora_color_low
	aurora_color_mid = other.aurora_color_mid
	aurora_color_top = other.aurora_color_top
	aurora_speed = other.aurora_speed
	aurora_base_height = other.aurora_base_height
	aurora_curtain_height = other.aurora_curtain_height
	sun_effect_scale = other.sun_effect_scale
	fog_light_color = other.fog_light_color
	fog_density = other.fog_density
	fog_sky_affect = other.fog_sky_affect
	fog_depth_mode = other.fog_depth_mode
	fog_depth_begin = other.fog_depth_begin
	fog_depth_end = other.fog_depth_end
	volumetric_fog_density = other.volumetric_fog_density
	volumetric_fog_albedo = other.volumetric_fog_albedo
	ambient_light_energy = other.ambient_light_energy
	background_energy_scale = other.background_energy_scale
	glow_intensity = other.glow_intensity
	glow_hdr_threshold = other.glow_hdr_threshold
	fog_aerial_perspective = other.fog_aerial_perspective
	fog_sun_scatter = other.fog_sun_scatter
	fog_height = other.fog_height
	fog_height_density = other.fog_height_density
	haze_strength = other.haze_strength
	haze_begin = other.haze_begin
	haze_end = other.haze_end
	deck_density = other.deck_density
	deck_albedo = other.deck_albedo
	light_color = other.light_color
	light_energy = other.light_energy
	light_uses_sun_basis = other.light_uses_sun_basis
	light_rotation_deg = other.light_rotation_deg
	puff_shadow_color = other.puff_shadow_color
	puff_mid_color = other.puff_mid_color
	puff_lit_color = other.puff_lit_color
	puff_rim_color = other.puff_rim_color
	puff_cloud_shadow_color = other.puff_cloud_shadow_color
	puff_cloud_mid_color = other.puff_cloud_mid_color
	puff_cloud_lit_color = other.puff_cloud_lit_color
	puff_cloud_rim_color = other.puff_cloud_rim_color
	puff_grade_dark = other.puff_grade_dark
	puff_grade_mid = other.puff_grade_mid
	puff_grade_light = other.puff_grade_light
	puff_grade_amount = other.puff_grade_amount
	puff_sea_color_near = other.puff_sea_color_near
	puff_sea_color_far = other.puff_sea_color_far
	puff_exposure = other.puff_exposure
	puff_sea_coverage = other.puff_sea_coverage
	puff_light_direction = other.puff_light_direction
	puff_sun_direction = other.puff_sun_direction
	puff_shared = other.puff_shared.duplicate()
	storm_amount = other.storm_amount
	lighting_light_color = other.lighting_light_color
	cloud_overcast = other.cloud_overcast
	weather_dim = other.weather_dim
	weather_desaturate = other.weather_desaturate
	sun_effects = other.sun_effects
	floor_color = other.floor_color
	floor_shadow_ratio = other.floor_shadow_ratio
	floor_mid_ratio = other.floor_mid_ratio
	flare_enabled = other.flare_enabled
	flare_weather_scale = other.flare_weather_scale


## Every field under a stable key, for the golden fixture and debug dumps.
func to_dict() -> Dictionary:
	return {
		&"phase": phase,
		&"sun_direction": sun_direction,
		&"daylight": daylight,
		&"night": night,
		&"night_index": night_index,
		&"use_global_dirs": use_global_dirs,
		&"exposure": exposure,
		&"proc_sea_coverage": proc_sea_coverage,
		&"proc_zenith_color": proc_zenith_color,
		&"proc_mid_color": proc_mid_color,
		&"proc_horizon_color": proc_horizon_color,
		&"proc_horizon_glow_color": proc_horizon_glow_color,
		&"proc_gradient_mid_height": proc_gradient_mid_height,
		&"proc_gradient_power": proc_gradient_power,
		&"proc_horizon_glow_width": proc_horizon_glow_width,
		&"proc_sun_glow_strength": proc_sun_glow_strength,
		&"proc_sea_color_near": proc_sea_color_near,
		&"proc_sea_color_far": proc_sea_color_far,
		&"proc_sea_horizon_fade": proc_sea_horizon_fade,
		&"sun_core_color": sun_core_color,
		&"sun_halo_color": sun_halo_color,
		&"sun_ray_color": sun_ray_color,
		&"cloud_shadow_color": cloud_shadow_color,
		&"cloud_mid_color": cloud_mid_color,
		&"cloud_lit_color": cloud_lit_color,
		&"cloud_rim_color": cloud_rim_color,
		&"cycle_night_mix": cycle_night_mix,
		&"cycle_night_zenith": cycle_night_zenith,
		&"cycle_night_horizon": cycle_night_horizon,
		&"cycle_night_below": cycle_night_below,
		&"cycle_star_brightness": cycle_star_brightness,
		&"cycle_star_cells": cycle_star_cells,
		&"cycle_star_threshold": cycle_star_threshold,
		&"cycle_star_radius": cycle_star_radius,
		&"cycle_star_horizon_fade": cycle_star_horizon_fade,
		&"moon_direction": moon_direction,
		&"moon_visibility": moon_visibility,
		&"moon_angular_radius_deg": moon_angular_radius_deg,
		&"moon_halo_radius_deg": moon_halo_radius_deg,
		&"moon_halo_strength": moon_halo_strength,
		&"moon_brightness": moon_brightness,
		&"aurora_visibility": aurora_visibility,
		&"aurora_intensity": aurora_intensity,
		&"aurora_color_low": aurora_color_low,
		&"aurora_color_mid": aurora_color_mid,
		&"aurora_color_top": aurora_color_top,
		&"aurora_speed": aurora_speed,
		&"aurora_base_height": aurora_base_height,
		&"aurora_curtain_height": aurora_curtain_height,
		&"sun_effect_scale": sun_effect_scale,
		&"fog_light_color": fog_light_color,
		&"fog_density": fog_density,
		&"fog_sky_affect": fog_sky_affect,
		&"fog_depth_mode": fog_depth_mode,
		&"fog_depth_begin": fog_depth_begin,
		&"fog_depth_end": fog_depth_end,
		&"volumetric_fog_density": volumetric_fog_density,
		&"volumetric_fog_albedo": volumetric_fog_albedo,
		&"ambient_light_energy": ambient_light_energy,
		&"background_energy_scale": background_energy_scale,
		&"glow_intensity": glow_intensity,
		&"glow_hdr_threshold": glow_hdr_threshold,
		&"fog_aerial_perspective": fog_aerial_perspective,
		&"fog_sun_scatter": fog_sun_scatter,
		&"fog_height": fog_height,
		&"fog_height_density": fog_height_density,
		&"haze_strength": haze_strength,
		&"haze_begin": haze_begin,
		&"haze_end": haze_end,
		&"deck_density": deck_density,
		&"deck_albedo": deck_albedo,
		&"light_color": light_color,
		&"light_energy": light_energy,
		&"light_uses_sun_basis": light_uses_sun_basis,
		&"light_rotation_deg": light_rotation_deg,
		&"puff_shadow_color": puff_shadow_color,
		&"puff_mid_color": puff_mid_color,
		&"puff_lit_color": puff_lit_color,
		&"puff_rim_color": puff_rim_color,
		&"puff_cloud_shadow_color": puff_cloud_shadow_color,
		&"puff_cloud_mid_color": puff_cloud_mid_color,
		&"puff_cloud_lit_color": puff_cloud_lit_color,
		&"puff_cloud_rim_color": puff_cloud_rim_color,
		&"puff_grade_dark": puff_grade_dark,
		&"puff_grade_mid": puff_grade_mid,
		&"puff_grade_light": puff_grade_light,
		&"puff_grade_amount": puff_grade_amount,
		&"puff_sea_color_near": puff_sea_color_near,
		&"puff_sea_color_far": puff_sea_color_far,
		&"puff_exposure": puff_exposure,
		&"puff_sea_coverage": puff_sea_coverage,
		&"puff_light_direction": puff_light_direction,
		&"puff_sun_direction": puff_sun_direction,
		&"puff_shared": puff_shared.duplicate(),
		&"storm_amount": storm_amount,
		&"lighting_light_color": lighting_light_color,
		&"cloud_overcast": cloud_overcast,
		&"weather_dim": weather_dim,
		&"weather_desaturate": weather_desaturate,
		&"sun_effects": sun_effects,
		&"floor_color": floor_color,
		&"floor_shadow_ratio": floor_shadow_ratio,
		&"floor_mid_ratio": floor_mid_ratio,
		&"flare_enabled": flare_enabled,
		&"flare_weather_scale": flare_weather_scale,
	}
