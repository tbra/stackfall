class_name SkyEvaluator
extends RefCounted
## Pure sky maths: (SkyCycleDef, phase, seed, night index, weather) -> SkyFrame, in three cached
## stages that mirror the old Skybox writers so the look stays the same.
##   A (evaluate_tick): day palette, sun, night mix, variation, puff channel, moon and aurora.
##   B (apply_storm): the storm overlay blended over the stage A frame.
##   C (apply_weather): overcast, snow, weather fog and sun dimming over the stage B frame.
## B and C read only the frame they are given (the last tick's values), never the phase, so a
## weather request landing between two ticks uses last-tick palette values exactly as the old
## code did. No scene tree, no RNG state, no clock.

## Floor of the moon full-night mix (a zero would divide by zero in the smoothstep).
const MIN_MOON_FULL_MIX: float = 0.0001
## Fallback tuning for a weather state (a lazily built, never mutated default shared by all
## calls; a static keeps the hot path allocation free) with none (defaults of the Resource).
static var _default_tuning: WeatherCeilingTuning = null


# --- stages -------------------------------------------------------------------------------

## Stage A (tick): day palette, sun, night mix, variation and the puff channel. The only stage
## that touches keyframes, variation and the night mix.
static func evaluate_tick(def: SkyCycleDef, phase: float, variation_seed: int, night_index: int,
		aurora_preset_on: bool, into: SkyFrame = null) -> SkyFrame:
	var frame: SkyFrame = into if into != null else SkyFrame.new()
	var wrapped: float = fposmod(phase, 1.0)
	var night_key: SkyNightKeyframe = _night_of(def)
	# Neutral weather state, so a reused frame never carries the last weather over.
	frame.storm_amount = 0.0
	frame.flare_enabled = true
	frame.flare_weather_scale = 1.0
	frame.sun_effect_scale = 1.0
	frame.sun_effects = 1.0
	frame.background_energy_scale = 1.0
	frame.fog_depth_mode = false
	frame.cloud_overcast = 0.0
	frame.weather_dim = 0.0
	frame.weather_desaturate = 0.0
	# 1. day palette
	day_palette(def, wrapped, frame)
	# 2. sun
	frame.phase = wrapped
	frame.night_index = night_index
	frame.sun_direction = sun_direction(def, wrapped)
	frame.daylight = daylight(def, wrapped)
	frame.night = 1.0 - frame.daylight
	# 3. sky channel from the palette and the structure, night gradient and stars
	frame.use_global_dirs = 1.0
	frame.proc_gradient_mid_height = def.proc_gradient_mid_height
	frame.proc_gradient_power = def.proc_gradient_power
	frame.proc_sea_horizon_fade = def.proc_sea_horizon_fade
	frame.cycle_night_mix = frame.night
	frame.cycle_night_zenith = night_key.zenith_color
	frame.cycle_night_horizon = night_key.horizon_color
	frame.cycle_night_below = night_key.below_color
	frame.cycle_star_brightness = def.cycle_star_brightness
	frame.cycle_star_cells = def.cycle_star_cells
	frame.cycle_star_threshold = def.cycle_star_threshold
	frame.cycle_star_radius = def.cycle_star_radius
	frame.cycle_star_horizon_fade = def.cycle_star_horizon_fade
	# Structure the environment channel carries unchanged.
	frame.fog_sky_affect = def.fog_sky_affect
	frame.fog_aerial_perspective = def.fog_aerial_perspective
	frame.fog_sun_scatter = def.fog_sun_scatter
	frame.fog_height = def.fog_height_m
	frame.fog_height_density = def.fog_height_density
	frame.haze_strength = def.haze_strength
	frame.haze_begin = def.haze_begin_m
	frame.haze_end = def.haze_end_m
	frame.glow_intensity = def.glow_intensity
	frame.glow_hdr_threshold = def.glow_hdr_threshold
	# 4. variation
	apply_variation(def, wrapped, variation_seed, frame)
	# 5. night mix and the puff channel's night mix (6)
	apply_night(def, frame)
	# 9 (tick-owned part): moon and aurora at clear weather
	apply_celestial(def, null, night_index, variation_seed, aurora_preset_on, frame)
	frame.lighting_light_color = frame.light_color
	return frame


## Stage B (storm): the storm overlay over the cached stage A frame. Cheap; reruns on a storm
## amount or overlay change. A null overlay means no storm whatever the amount (the old
## set_storm_sky() treated a null storm theme as amount 0), so stage C sees storm_amount 0 too.
static func apply_storm(tick: SkyFrame, storm_amount: float, overlay: SkyOverlayDef,
		flare_off_amount: float, into: SkyFrame) -> void:
	if into != tick:
		into.copy_from(tick)
	var t: float = clampf(storm_amount, 0.0, 1.0)
	if t <= 0.0 or overlay == null:
		into.storm_amount = 0.0
		return
	into.storm_amount = t
	# The light orientation is never blended (the cycle owns the sun path).
	into.fog_light_color = tick.fog_light_color.lerp(overlay.fog_color, t)
	into.fog_density = lerpf(tick.fog_density, overlay.fog_density, t)
	into.fog_sky_affect = lerpf(tick.fog_sky_affect, overlay.fog_sky_affect, t)
	into.volumetric_fog_density = lerpf(tick.volumetric_fog_density, overlay.volumetric_fog_density, t)
	into.volumetric_fog_albedo = tick.volumetric_fog_albedo.lerp(overlay.volumetric_fog_albedo, t)
	into.light_color = tick.light_color.lerp(overlay.light_color, t)
	# DECISION: the storm scales the light energy of the hour by the overlay share (no fixed target),
	# so a night storm stays as dark as the night.
	into.light_energy = tick.light_energy * lerpf(1.0, overlay.light_energy_share, t)
	into.ambient_light_energy = lerpf(tick.ambient_light_energy, overlay.ambient_energy, t)
	into.glow_intensity = lerpf(tick.glow_intensity, overlay.glow_intensity, t)
	into.flare_enabled = tick.flare_enabled and t < flare_off_amount
	into.proc_zenith_color = tick.proc_zenith_color.lerp(overlay.proc_zenith_color, t)
	into.proc_mid_color = tick.proc_mid_color.lerp(overlay.proc_mid_color, t)
	into.proc_horizon_color = tick.proc_horizon_color.lerp(overlay.proc_horizon_color, t)
	into.proc_gradient_mid_height = lerpf(tick.proc_gradient_mid_height, overlay.proc_gradient_mid_height, t)
	into.proc_gradient_power = lerpf(tick.proc_gradient_power, overlay.proc_gradient_power, t)
	into.proc_horizon_glow_color = tick.proc_horizon_glow_color.lerp(overlay.proc_horizon_glow_color, t)
	into.proc_horizon_glow_width = lerpf(tick.proc_horizon_glow_width, overlay.proc_horizon_glow_width, t)
	into.proc_sun_glow_strength = lerpf(tick.proc_sun_glow_strength, overlay.proc_sun_glow_strength, t)
	into.proc_sea_color_near = tick.proc_sea_color_near.lerp(overlay.proc_sea_color_near, t)
	into.proc_sea_color_far = tick.proc_sea_color_far.lerp(overlay.proc_sea_color_far, t)
	into.deck_density = into.fog_density
	into.deck_albedo = into.fog_light_color
	into.lighting_light_color = into.light_color
	# Puff channel: cel and cloud tones lerp from the cycle values in effect. The far fade sea
	# colours lerp from the tick's night-mixed values toward the overlay sea, as the sky sea does (a
	# day storm matches the sky sea, a night storm starts from the night colours without a jump); the
	# exposure stays the tick's baseline (copy_from above).
	into.puff_shadow_color = tick.puff_shadow_color.lerp(overlay.puff_shadow_color, t)
	into.puff_mid_color = tick.puff_mid_color.lerp(overlay.puff_mid_color, t)
	into.puff_lit_color = tick.puff_lit_color.lerp(overlay.puff_lit_color, t)
	into.puff_rim_color = tick.puff_rim_color.lerp(overlay.puff_rim_color, t)
	into.puff_cloud_shadow_color = tick.puff_cloud_shadow_color.lerp(overlay.cloud_shadow_color, t)
	into.puff_cloud_mid_color = tick.puff_cloud_mid_color.lerp(overlay.cloud_mid_color, t)
	into.puff_cloud_lit_color = tick.puff_cloud_lit_color.lerp(overlay.cloud_lit_color, t)
	into.puff_cloud_rim_color = tick.puff_cloud_rim_color.lerp(overlay.cloud_rim_color, t)
	into.puff_sea_color_near = tick.puff_sea_color_near.lerp(overlay.proc_sea_color_near, t)
	into.puff_sea_color_far = tick.puff_sea_color_far.lerp(overlay.proc_sea_color_far, t)


## Stage C (weather): overcast, snow, weather fog and sun dimming over the cached stage B frame.
## Cheap; reruns on any weather or sun-dim change.
static func apply_weather(source: SkyFrame, weather: SkyWeatherState, into: SkyFrame) -> void:
	if into != source:
		into.copy_from(source)
	var tuning: WeatherCeilingTuning = _tuning_of(weather)
	var overcast: float = weather.overcast_amount
	# Overcast: ambient, background energy, sky exposure, fog tint.
	into.ambient_light_energy = source.ambient_light_energy * lerpf(1.0, weather.overcast_ambient_scale, overcast)
	into.background_energy_scale = lerpf(1.0, weather.overcast_exposure_scale, overcast) \
		* lerpf(1.0, tuning.snow_sky_exposure_gain, weather.snow_brighten)
	into.exposure = source.exposure * lerpf(1.0, weather.overcast_exposure_scale, overcast)
	var fog_color: Color = source.fog_light_color.lerp(weather.overcast_fog_tint, weather.overcast_fog_tint_strength * overcast)
	fog_color = fog_color.lerp(weather.wfog_tint, weather.wfog_tint_strength * weather.wfog_amount)
	into.fog_light_color = fog_color
	into.deck_albedo = fog_color
	# Weather fog: aerial perspective fades out, depth fog takes over above amount 0.
	into.fog_aerial_perspective = clampf(source.fog_aerial_perspective * (1.0 - weather.wfog_amount), 0.0, 1.0)
	into.fog_sky_affect = clampf(source.fog_sky_affect + weather.wfog_sky_affect_add * weather.wfog_amount, 0.0, 1.0)
	if weather.wfog_amount <= 0.0:
		into.fog_depth_mode = false
		into.fog_density = source.fog_density
	else:
		into.fog_depth_mode = true
		into.fog_depth_begin = weather.wfog_depth_begin_m
		into.fog_depth_end = weather.wfog_depth_end_m
		# In depth mode the density is the maximum opacity reached at the end distance.
		into.fog_density = clampf(weather.wfog_max_opacity * weather.wfog_amount, 0.0, 1.0)
	into.light_energy = source.light_energy * lerpf(1.0, weather.overcast_light_scale, overcast) * weather.sun_cloud_scale
	# Celestial and cloud lighting inputs.
	var cloud_overcast: float = weather.cloud_overcast_amount()
	var storm: float = source.storm_amount
	var keep: float = CloudLighting.sun_weather_keep(cloud_overcast, tuning.sun_overcast_attenuation,
		storm, tuning.sun_storm_attenuation)
	into.moon_visibility = source.moon_visibility * keep
	into.aurora_visibility = source.aurora_visibility * keep
	var dim: float = CloudLighting.combined_dim(tuning.cloud_overcast_dim, tuning.storm_darkness_add,
		cloud_overcast, storm, source.night, tuning.night_dim_relief, tuning.max_combined_dim)
	# Snow lifts the clouds (a negative dim brightens), not at night.
	dim -= tuning.snow_cloud_brighten * weather.snow_brighten * (1.0 - clampf(source.night, 0.0, 1.0))
	var cloud_weather: float = maxf(cloud_overcast, storm)
	into.lighting_light_color = source.light_color
	into.cloud_overcast = cloud_overcast
	into.weather_dim = dim
	into.weather_desaturate = tuning.cloud_overcast_desaturate * cloud_weather
	var sun_effects: float = CloudLighting.sun_effect_scale(source.night, tuning.sun_night_fade_end, cloud_overcast,
		tuning.sun_overcast_attenuation, storm, tuning.sun_storm_attenuation)
	into.sun_effects = sun_effects
	into.sun_effect_scale = sun_effects
	into.flare_weather_scale = sun_effects
	into.floor_color = CloudLighting.floor_for_tone(tuning.puff_floor_tint, tuning.puff_min_brightness, 1.0)
	into.floor_shadow_ratio = tuning.puff_floor_shadow_ratio
	into.floor_mid_ratio = tuning.puff_floor_mid_ratio


## Stages A, B and C in order (tests and the golden fixture only).
static func evaluate(def: SkyCycleDef, phase: float, variation_seed: int, night_index: int,
		weather: SkyWeatherState, aurora_preset_on: bool, into: SkyFrame = null) -> SkyFrame:
	var tick: SkyFrame = evaluate_tick(def, phase, variation_seed, night_index, aurora_preset_on)
	var storm: SkyFrame = SkyFrame.new()
	apply_storm(tick, weather.storm_amount, weather.storm_overlay, _tuning_of(weather).storm_flare_off_amount, storm)
	var out: SkyFrame = into if into != null else SkyFrame.new()
	apply_weather(storm, weather, out)
	return out


# --- helpers ------------------------------------------------------------------------------

## Weight of a key whose phase window is `window` (x, y, z, w) at `phase`:
## smoothstep(x, y, p) * (1 - smoothstep(z, w, p)), wrapped into 0..1.
static func window_weight(phase: float, window: Vector4) -> float:
	var wrapped: float = fposmod(phase, 1.0)
	return _window_step(window.x, window.y, wrapped) * (1.0 - _window_step(window.z, window.w, wrapped))


## Unit direction toward the sun at `phase`.
static func sun_direction(def: SkyCycleDef, phase: float) -> Vector3:
	var base: Vector3 = def.sun_base_direction
	var horizontal: Vector3 = Vector3(base.x, 0.0, base.z).normalized()
	var azimuth: float = TAU * phase
	var elevation: float = deg_to_rad(def.cycle_sun_peak_degrees) * sin(azimuth)
	var direction: Vector3 = Vector3(
		horizontal.x * cos(azimuth) - horizontal.z * sin(azimuth), 0.0,
		horizontal.x * sin(azimuth) + horizontal.z * cos(azimuth)) * cos(elevation)
	direction.y = sin(elevation)
	return direction


## Daylight 0..1 at `phase` (smoothstep of the sun elevation over the twilight width).
static func daylight(def: SkyCycleDef, phase: float) -> float:
	return smoothstep(-def.cycle_twilight_width, def.cycle_twilight_width, sin(TAU * phase))


## `a` at weight 0 and `b` at weight 1 exactly (a plain lerp can miss `b` by a rounding step),
## the linear mix between.
static func mix_color(a: Color, b: Color, weight: float) -> Color:
	if weight <= 0.0:
		return a
	if weight >= 1.0:
		return b
	return a.lerp(b, weight)


## Scalar form of mix_color.
static func mix_scalar(a: float, b: float, weight: float) -> float:
	if weight <= 0.0:
		return a
	if weight >= 1.0:
		return b
	return lerpf(a, b, weight)


## Stage A step 1: writes the day palette at `phase` into `into`. Key 0 is the base; each later
## key mixes in by its phase window with exact endpoints. Writes only palette channels.
static func day_palette(def: SkyCycleDef, phase: float, into: SkyFrame) -> void:
	var keys: Array[SkyKeyframe] = def.day_keyframes
	_copy_key(keys[0] if not keys.is_empty() else SkyKeyframe.new(), into)
	for index: int in range(1, keys.size()):
		var key: SkyKeyframe = keys[index]
		var weight: float = clampf(window_weight(phase, key.phase_window), 0.0, 1.0)
		if weight > 0.0:
			_mix_key(key, weight, into)


## Stage A step 5 (and the puff channel's night mix): mixes the night layer over the day palette
## already in `into`, using `into.night` and `into.sun_direction`. Plain lerps, as the old code.
static func apply_night(def: SkyCycleDef, into: SkyFrame) -> void:
	var night_key: SkyNightKeyframe = _night_of(def)
	var night: float = into.night
	var direction: Vector3 = into.sun_direction
	# Puff channel first: it reads the day values the environment mix below overwrites.
	into.puff_shadow_color = into.puff_shadow_color.lerp(night_key.puff_shadow_color, night)
	into.puff_mid_color = into.puff_mid_color.lerp(night_key.puff_mid_color, night)
	into.puff_lit_color = into.puff_lit_color.lerp(night_key.puff_lit_color, night)
	into.puff_rim_color = into.puff_rim_color.lerp(night_key.puff_rim_color, night)
	into.puff_cloud_shadow_color = into.cloud_shadow_color.lerp(night_key.cloud_shadow_color, night)
	into.puff_cloud_mid_color = into.cloud_mid_color.lerp(night_key.cloud_mid_color, night)
	into.puff_cloud_lit_color = into.cloud_lit_color.lerp(night_key.cloud_lit_color, night)
	into.puff_cloud_rim_color = into.cloud_rim_color.lerp(night_key.cloud_rim_color, night)
	into.puff_grade_dark = night_key.grade_dark
	into.puff_grade_mid = night_key.grade_mid
	into.puff_grade_light = night_key.grade_light
	into.puff_grade_amount = night
	into.puff_sea_color_near = into.proc_sea_color_near.lerp(night_key.proc_sea_color_near, night)
	into.puff_sea_color_far = into.proc_sea_color_far.lerp(night_key.proc_sea_color_far, night)
	into.puff_light_direction = direction
	into.puff_sun_direction = direction
	# Environment channel.
	into.fog_light_color = into.fog_light_color.lerp(night_key.fog_color, night)
	into.fog_density = lerpf(into.fog_density, night_key.fog_density, night)
	into.volumetric_fog_density = lerpf(into.volumetric_fog_density, night_key.volumetric_fog_density, night)
	into.volumetric_fog_albedo = into.volumetric_fog_albedo.lerp(night_key.volumetric_fog_albedo, night)
	into.ambient_light_energy = lerpf(into.ambient_light_energy, night_key.ambient_energy, night)
	# Stronger sun, weaker sky ambient with the sun high (identity at the horizon and at night).
	into.ambient_light_energy *= SunContrast.ambient_scale(direction.y, def.cycle_day_ambient_scale,
		def.cycle_sun_contrast_full_sin)
	# One key light serves the sun by day and a dim authored direction after sunset.
	var sun_key: float = smoothstep(0.0, def.light_key_ramp_sin, direction.y)
	var moon_key: float = smoothstep(0.0, def.light_key_ramp_sin, -direction.y)
	into.light_energy = into.light_energy * sun_key * SunContrast.light_scale(direction.y,
		def.cycle_sun_energy_gain, def.cycle_sun_contrast_full_sin) \
		+ night_key.light_energy * night_key.moon_light_ratio * moon_key
	if direction.y < 0.0:
		into.light_color = night_key.light_color
	into.light_uses_sun_basis = direction.y >= 0.0
	into.light_rotation_deg = night_key.light_rotation_deg
	into.deck_density = into.fog_density
	into.deck_albedo = into.fog_light_color


## Stage A step 4: the seeded exposure and sea-coverage variation at `phase`. With variation off
## the cycle's own fixed sky-material uniforms stand in (a missing uniform leaves the frame as is).
static func apply_variation(def: SkyCycleDef, phase: float, variation_seed: int, into: SkyFrame) -> void:
	var exposure: float = NAN
	var sea_coverage: float = NAN
	if def.variation_enabled:
		exposure = SkyVariation.value_at(def.variation_exposure_min, def.variation_exposure_max,
			def.variation_knots_per_cycle, phase, variation_seed, SkyVariation.CHANNEL_EXPOSURE)
		sea_coverage = SkyVariation.value_at(def.variation_sea_coverage_min, def.variation_sea_coverage_max,
			def.variation_knots_per_cycle, phase, variation_seed, SkyVariation.CHANNEL_SEA_COVERAGE)
	else:
		exposure = _fixed_uniform(def.sky_material, &"exposure")
		sea_coverage = _fixed_uniform(def.sky_material, &"proc_sea_coverage")
	if not is_nan(exposure):
		into.exposure = exposure
		into.puff_exposure = exposure
	if not is_nan(sea_coverage):
		into.proc_sea_coverage = sea_coverage
		into.puff_sea_coverage = sea_coverage


## Moon, aurora and sun effects. With `weather` null this is the tick-owned clear-weather part
## (stage A); with a weather state the weather-owned scaling is applied too (stage C does the
## same from the frame it is given). Reads `into.night`.
static func apply_celestial(def: SkyCycleDef, weather: SkyWeatherState, night_index: int,
		variation_seed: int, aurora_preset_on: bool, into: SkyFrame) -> void:
	var night: float = into.night
	into.moon_direction = -into.sun_direction
	into.moon_angular_radius_deg = def.cycle_moon_angular_radius_deg
	into.moon_halo_radius_deg = def.cycle_moon_halo_radius_deg
	into.moon_halo_strength = def.cycle_moon_halo_strength
	into.moon_brightness = def.cycle_moon_brightness
	into.moon_visibility = smoothstep(0.0, maxf(def.cycle_moon_full_night_mix, MIN_MOON_FULL_MIX), night)
	# One seeded roll per night; the integer cycle count is the night id.
	var strength: float = 0.0
	if def.aurora_enabled and aurora_preset_on \
			and SkyVariation.aurora_night_shown(variation_seed, night_index, def.aurora_night_chance):
		strength = def.aurora_night_strength(night)
	into.aurora_visibility = strength
	into.aurora_intensity = def.aurora_intensity
	into.aurora_color_low = def.aurora_color_low
	into.aurora_color_mid = def.aurora_color_mid
	into.aurora_color_top = def.aurora_color_top
	into.aurora_speed = def.aurora_speed
	into.aurora_base_height = def.aurora_base_height
	into.aurora_curtain_height = def.aurora_curtain_height
	if weather != null:
		var tuning: WeatherCeilingTuning = _tuning_of(weather)
		var keep: float = CloudLighting.sun_weather_keep(weather.cloud_overcast_amount(),
			tuning.sun_overcast_attenuation, weather.storm_amount, tuning.sun_storm_attenuation)
		into.moon_visibility *= keep
		into.aurora_visibility *= keep


# --- private ------------------------------------------------------------------------------

## smoothstep(from, to, x) that stays a clean 0/1 step when the window is empty or reversed
## (a mis-authored Vector4 must not produce NaN).
static func _window_step(from: float, to: float, x: float) -> float:
	if to <= from:
		return 1.0 if x >= from else 0.0
	return smoothstep(from, to, x)


static func _night_of(def: SkyCycleDef) -> SkyNightKeyframe:
	return def.night if def.night != null else SkyNightKeyframe.new()


static func _tuning_of(weather: SkyWeatherState) -> WeatherCeilingTuning:
	if weather != null and weather.tuning != null:
		return weather.tuning
	if _default_tuning == null:
		_default_tuning = WeatherCeilingTuning.new()
	return _default_tuning


static func _fixed_uniform(material: ShaderMaterial, uniform: StringName) -> float:
	if material == null:
		return NAN
	var value: Variant = material.get_shader_parameter(uniform)
	return float(value) if value is float else NAN


static func _copy_key(key: SkyKeyframe, into: SkyFrame) -> void:
	into.fog_light_color = key.fog_color
	into.volumetric_fog_albedo = key.volumetric_fog_albedo
	into.light_color = key.light_color
	into.proc_zenith_color = key.proc_zenith_color
	into.proc_mid_color = key.proc_mid_color
	into.proc_horizon_color = key.proc_horizon_color
	into.proc_horizon_glow_color = key.proc_horizon_glow_color
	into.proc_sea_color_near = key.proc_sea_color_near
	into.proc_sea_color_far = key.proc_sea_color_far
	into.fog_density = key.fog_density
	into.volumetric_fog_density = key.volumetric_fog_density
	into.light_energy = key.light_energy
	into.ambient_light_energy = key.ambient_energy
	into.proc_horizon_glow_width = key.proc_horizon_glow_width
	into.proc_sun_glow_strength = key.proc_sun_glow_strength
	into.sun_core_color = key.sun_core_color
	into.sun_halo_color = key.sun_halo_color
	into.sun_ray_color = key.sun_ray_color
	into.cloud_shadow_color = key.cloud_shadow_color
	into.cloud_mid_color = key.cloud_mid_color
	into.cloud_lit_color = key.cloud_lit_color
	into.cloud_rim_color = key.cloud_rim_color
	into.puff_shadow_color = key.puff_shadow_color
	into.puff_mid_color = key.puff_mid_color
	into.puff_lit_color = key.puff_lit_color
	into.puff_rim_color = key.puff_rim_color


static func _mix_key(key: SkyKeyframe, weight: float, into: SkyFrame) -> void:
	into.fog_light_color = mix_color(into.fog_light_color, key.fog_color, weight)
	into.volumetric_fog_albedo = mix_color(into.volumetric_fog_albedo, key.volumetric_fog_albedo, weight)
	into.light_color = mix_color(into.light_color, key.light_color, weight)
	into.proc_zenith_color = mix_color(into.proc_zenith_color, key.proc_zenith_color, weight)
	into.proc_mid_color = mix_color(into.proc_mid_color, key.proc_mid_color, weight)
	into.proc_horizon_color = mix_color(into.proc_horizon_color, key.proc_horizon_color, weight)
	into.proc_horizon_glow_color = mix_color(into.proc_horizon_glow_color, key.proc_horizon_glow_color, weight)
	into.proc_sea_color_near = mix_color(into.proc_sea_color_near, key.proc_sea_color_near, weight)
	into.proc_sea_color_far = mix_color(into.proc_sea_color_far, key.proc_sea_color_far, weight)
	into.fog_density = mix_scalar(into.fog_density, key.fog_density, weight)
	into.volumetric_fog_density = mix_scalar(into.volumetric_fog_density, key.volumetric_fog_density, weight)
	into.light_energy = mix_scalar(into.light_energy, key.light_energy, weight)
	into.ambient_light_energy = mix_scalar(into.ambient_light_energy, key.ambient_energy, weight)
	into.proc_horizon_glow_width = mix_scalar(into.proc_horizon_glow_width, key.proc_horizon_glow_width, weight)
	into.proc_sun_glow_strength = mix_scalar(into.proc_sun_glow_strength, key.proc_sun_glow_strength, weight)
	into.sun_core_color = mix_color(into.sun_core_color, key.sun_core_color, weight)
	into.sun_halo_color = mix_color(into.sun_halo_color, key.sun_halo_color, weight)
	into.sun_ray_color = mix_color(into.sun_ray_color, key.sun_ray_color, weight)
	into.cloud_shadow_color = mix_color(into.cloud_shadow_color, key.cloud_shadow_color, weight)
	into.cloud_mid_color = mix_color(into.cloud_mid_color, key.cloud_mid_color, weight)
	into.cloud_lit_color = mix_color(into.cloud_lit_color, key.cloud_lit_color, weight)
	into.cloud_rim_color = mix_color(into.cloud_rim_color, key.cloud_rim_color, weight)
	into.puff_shadow_color = mix_color(into.puff_shadow_color, key.puff_shadow_color, weight)
	into.puff_mid_color = mix_color(into.puff_mid_color, key.puff_mid_color, weight)
	into.puff_lit_color = mix_color(into.puff_lit_color, key.puff_lit_color, weight)
	into.puff_rim_color = mix_color(into.puff_rim_color, key.puff_rim_color, weight)
