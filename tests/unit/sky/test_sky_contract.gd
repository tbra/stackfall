extends GutTest
## The typed sky cycle contract (config/sky/Sky*Def/Keyframe, core/sky/SkyFrame, SkyWeatherState):
## the shipped cycle and storm overlay against pinned literal values, the two SkyCycleDef helpers
## against pinned results, the weather state and the frame copy.
##
## The pinned literals were captured from the code that built the shipped data before the old theme
## files were retired: the old theme-to-cycle migration of the sunset, dawn and night themes and
## of the storm theme dumped through each resource's script variables (var_to_str), and the
## helper results from the old sunset theme's locked_phase_for / aurora_night_strength.

const Evaluator := preload("res://tests/unit/sky/test_sky_evaluator.gd")
## Relative: the pinned literals round-trip, so only float32 rounding of the printed value remains.
const LITERAL_TOLERANCE: float = 0.000001
const SUN_BASE_DIRECTION: Vector3 = Vector3(0.963087, 0.069011, -0.260192)
const LOCKED_PHASES_BY_ID: Dictionary[String, float] = {
	"sunset": 0.47, "dawn": 0.03, "night": 0.75, "": -1.0, "cycle": -1.0, "storm": -1.0,
}
## night mix -> aurora_night_strength with the shipped start/full mix (0.5, 0.95).
const AURORA_SHIPPED: Dictionary[float, float] = {
	0.0: 0.0, 0.25: 0.0, 0.5: 0.0, 0.7: 0.4170096021947873, 0.95: 1.0, 1.0: 1.0,
}
const AURORA_START_OVERRIDE: float = 0.9
const AURORA_FULL_OVERRIDE: float = 0.3
## night mix -> aurora_night_strength with start 0.9 and full 0.3 (a reversed pair).
const AURORA_REVERSED: Dictionary[float, float] = {
	0.0: 0.0, 0.25: 0.0, 0.5: 0.25925925925925924, 0.7: 0.7407407407407406, 0.95: 1.0, 1.0: 1.0,
}
const MIN_STRUCTURE_FIELDS: int = 100
const FRAME_PROBE_COLOR: Color = Color(0.25, 0.5, 0.75, 1.0)
const FRAME_PROBE_VECTOR: Vector3 = Vector3(0.1, 0.2, 0.3)
const FRAME_PROBE_FLOAT: float = 0.37
const FRAME_PROBE_INT: int = 7
const NIGHT_MOON_LIGHT_RATIO: float = 0.2
const LIFE_NIGHT_ON_MIX: float = 0.85
const LIFE_NIGHT_OFF_MIX: float = 0.15
const LIGHT_KEY_RAMP_SIN: float = 0.2

## SkyCycleDef structure fields of the shipped cycle (every field the old theme copy carried).
const STRUCTURE: Dictionary[StringName, Variant] = {
	&"cycle_length_seconds": 300.0,
	&"cycle_start_phase": 0.1,
	&"cycle_random_start_min": 0.0,
	&"cycle_random_start_max": 0.62,
	&"cycle_locked_phase_sunset": 0.47,
	&"cycle_locked_phase_dawn": 0.03,
	&"cycle_locked_phase_night": 0.75,
	&"cycle_sun_peak_degrees": 65.0,
	&"cycle_twilight_width": 0.2,
	&"cycle_sun_energy_gain": 1.7,
	&"cycle_day_ambient_scale": 0.7,
	&"cycle_sun_contrast_full_sin": 0.6,
	&"cycle_star_brightness": 2.0,
	&"cycle_star_cells": 105.0,
	&"cycle_star_threshold": 0.92,
	&"cycle_star_radius": 0.12,
	&"cycle_star_horizon_fade": 0.22,
	&"cycle_moon_angular_radius_deg": 3.2,
	&"cycle_moon_halo_radius_deg": 14.0,
	&"cycle_moon_halo_strength": 0.6,
	&"cycle_moon_brightness": 1.0,
	&"cycle_moon_full_night_mix": 0.8,
	&"aurora_enabled": true,
	&"aurora_intensity": 0.45,
	&"aurora_color_low": Color(0.12, 1, 0.42, 1),
	&"aurora_color_mid": Color(0.08, 0.75, 0.8, 1),
	&"aurora_color_top": Color(0.55, 0.3, 0.95, 1),
	&"aurora_speed": 1.0,
	&"aurora_base_height": 0.1,
	&"aurora_curtain_height": 0.4,
	&"aurora_start_night_mix": 0.5,
	&"aurora_full_night_mix": 0.95,
	&"aurora_night_chance": 0.1,
	&"variation_enabled": true,
	&"variation_exposure_min": 0.8,
	&"variation_exposure_max": 0.95,
	&"variation_sea_coverage_min": 0.3,
	&"variation_sea_coverage_max": 0.48,
	&"variation_knots_per_cycle": 3,
	&"fog_sky_affect": 0.65,
	&"fog_aerial_perspective": 0.6,
	&"fog_sun_scatter": 0.0,
	&"fog_height_m": -5.0,
	&"fog_height_density": 0.03,
	&"haze_strength": 0.8,
	&"haze_begin_m": 90.0,
	&"haze_end_m": 480.0,
	&"cloud_deck_size_m": Vector3(800, 60, 800),
	&"cloud_deck_height_m": -40.0,
	&"glow_intensity": 0.5,
	&"glow_hdr_threshold": 1.3,
	&"proc_gradient_mid_height": 0.55,
	&"proc_gradient_power": 1.2,
	&"proc_sea_horizon_fade": 0.12,
	&"cloud_clump_count": 260,
	&"cloud_puffs_per_clump": 12,
	&"cloud_seed": 11,
	&"cloud_ring_inner_m": 80.0,
	&"cloud_ring_outer_m": 640.0,
	&"cloud_base_min_m": -120.0,
	&"cloud_base_max_m": -35.0,
	&"cloud_top_max_m": -18.0,
	&"cloud_clump_radius_min_m": 15.0,
	&"cloud_clump_radius_max_m": 36.0,
	&"cloud_clump_height_ratio": 0.65,
	&"cloud_flat_base": 0.15,
	&"cloud_puff_raise_m": 14.0,
	&"cloud_disc_clearance_ratio": 0.25,
	&"cloud_drift_speed_min_mps": 0.8,
	&"cloud_drift_speed_max_mps": 1.8,
	&"cloud_radial_bias": 1.0,
	&"cloud_bank_count": 50,
	&"cloud_bank_ring_inner_m": 300.0,
	&"cloud_bank_ring_outer_m": 760.0,
	&"cloud_bank_base_min_m": -85.0,
	&"cloud_bank_base_max_m": -5.0,
	&"cloud_bank_top_max_m": 60.0,
	&"cloud_bank_radius_min_m": 32.0,
	&"cloud_bank_radius_max_m": 62.0,
	&"proc_far_count": 450,
	&"proc_far_ring_inner_m": 150.0,
	&"proc_far_ring_outer_m": 2600.0,
	&"proc_far_radial_bias": 1.5,
	&"proc_far_base_min_m": -160.0,
	&"proc_far_base_max_m": -90.0,
	&"proc_far_top_max_m": -20.0,
	&"proc_far_radius_min_m": 40.0,
	&"proc_far_radius_max_m": 130.0,
	&"proc_far_fade_cap": 0.7,
	&"bird_flock_count": 2,
	&"bird_flock_size_min": 2,
	&"bird_flock_size_max": 7,
	&"bird_single_chance": 0.2,
	&"bird_gap_min_s": 90.0,
	&"bird_gap_max_s": 240.0,
	&"bird_first_delay_min_s": 10.0,
	&"bird_first_delay_max_s": 60.0,
	&"bird_seed": 0,
	&"bird_path_radius_m": 650.0,
	&"bird_distance_min_m": 150.0,
	&"bird_distance_max_m": 380.0,
	&"bird_altitude_min_m": 15.0,
	&"bird_altitude_max_m": 80.0,
	&"bird_climb_max_mps": 1.2,
	&"bird_speed_min_mps": 11.0,
	&"bird_speed_max_mps": 17.0,
	&"bird_size_min_m": 3.5,
	&"bird_size_max_m": 5.0,
	&"bird_spacing_m": 14.0,
	&"bird_v_chance": 0.55,
}
const MORNING_KEY: Dictionary[StringName, Variant] = {
	&"phase_window": Vector4(0, 0, 0, 0),
	&"fog_color": Color(1, 0.84, 0.7, 1),
	&"volumetric_fog_albedo": Color(1, 0.84, 0.7, 1),
	&"light_color": Color(1, 0.88, 0.72, 1),
	&"proc_zenith_color": Color(0.5, 0.65, 0.86, 1),
	&"proc_mid_color": Color(0.84, 0.8, 0.88, 1),
	&"proc_horizon_color": Color(1, 0.82, 0.62, 1),
	&"proc_horizon_glow_color": Color(1, 0.78, 0.5, 1),
	&"proc_sea_color_near": Color(0.98, 0.82, 0.74, 1),
	&"proc_sea_color_far": Color(0.7, 0.74, 0.88, 1),
	&"fog_density": 0.0025,
	&"volumetric_fog_density": 0.00015,
	&"light_energy": 0.8,
	&"ambient_energy": 0.6,
	&"proc_horizon_glow_width": 0.34,
	&"proc_sun_glow_strength": 0.8,
	&"sun_core_color": Color(1, 0.94, 0.82, 1),
	&"sun_halo_color": Color(1, 0.8, 0.55, 1),
	&"sun_ray_color": Color(1, 0.85, 0.6, 1),
	&"cloud_shadow_color": Color(0.6, 0.62, 0.78, 1),
	&"cloud_mid_color": Color(0.96, 0.8, 0.8, 1),
	&"cloud_lit_color": Color(1, 0.93, 0.8, 1),
	&"cloud_rim_color": Color(1, 0.96, 0.84, 1),
	&"puff_shadow_color": Color(0.6, 0.62, 0.78, 1),
	&"puff_mid_color": Color(0.92, 0.78, 0.8, 1),
	&"puff_lit_color": Color(1, 0.92, 0.8, 1),
	&"puff_rim_color": Color(1, 0.96, 0.85, 1),
}
const EVENING_KEY: Dictionary[StringName, Variant] = {
	&"phase_window": Vector4(0.3, 0.46, 0.9, 0.98),
	&"fog_color": Color(0.93, 0.58, 0.4, 1),
	&"volumetric_fog_albedo": Color(0.93, 0.58, 0.4, 1),
	&"light_color": Color(1, 0.94, 0.85, 1),
	&"proc_zenith_color": Color(0.3, 0.33, 0.52, 1),
	&"proc_mid_color": Color(0.72, 0.44, 0.42, 1),
	&"proc_horizon_color": Color(0.9, 0.66, 0.46, 1),
	&"proc_horizon_glow_color": Color(1, 0.68, 0.4, 1),
	&"proc_sea_color_near": Color(0.85, 0.5, 0.42, 1),
	&"proc_sea_color_far": Color(0.34, 0.27, 0.47, 1),
	&"fog_density": 0.0025,
	&"volumetric_fog_density": 0.00015,
	&"light_energy": 0.85,
	&"ambient_energy": 0.5,
	&"proc_horizon_glow_width": 0.3,
	&"proc_sun_glow_strength": 1.0,
	&"sun_core_color": Color(1, 0.94, 0.82, 1),
	&"sun_halo_color": Color(1, 0.62, 0.28, 1),
	&"sun_ray_color": Color(1, 0.72, 0.38, 1),
	&"cloud_shadow_color": Color(0.34, 0.27, 0.47, 1),
	&"cloud_mid_color": Color(0.82, 0.57, 0.56, 1),
	&"cloud_lit_color": Color(1, 0.85, 0.64, 1),
	&"cloud_rim_color": Color(1, 0.9, 0.66, 1),
	&"puff_shadow_color": Color(0.27, 0.32, 0.48, 1),
	&"puff_mid_color": Color(0.57, 0.41, 0.49, 1),
	&"puff_lit_color": Color(1, 0.7, 0.47, 1),
	&"puff_rim_color": Color(1, 0.78, 0.42, 1),
}
const NIGHT_KEY: Dictionary[StringName, Variant] = {
	&"zenith_color": Color(0.008, 0.018, 0.06, 1),
	&"horizon_color": Color(0.07, 0.11, 0.24, 1),
	&"below_color": Color(0.02, 0.035, 0.09, 1),
	&"fog_color": Color(0.06, 0.1, 0.22, 1),
	&"fog_density": 0.002,
	&"volumetric_fog_density": 0.00015,
	&"volumetric_fog_albedo": Color(0.06, 0.1, 0.22, 1),
	&"ambient_energy": 1.0,
	&"light_energy": 1.3,
	&"light_color": Color(0.62, 0.74, 1, 1),
	&"light_rotation_deg": Vector3(-18, -30, 0),
	&"moon_light_ratio": 0.2,
	&"puff_shadow_color": Color(0.04, 0.06, 0.14, 1),
	&"puff_mid_color": Color(0.14, 0.2, 0.37, 1),
	&"puff_lit_color": Color(0.4, 0.5, 0.7, 1),
	&"puff_rim_color": Color(0.75, 0.84, 1, 1),
	&"cloud_shadow_color": Color(0.015, 0.025, 0.07, 1),
	&"cloud_mid_color": Color(0.05, 0.08, 0.2, 1),
	&"cloud_lit_color": Color(0.35, 0.47, 0.72, 1),
	&"cloud_rim_color": Color(0.68, 0.8, 1, 1),
	&"grade_dark": Color(0.02, 0.03, 0.08, 1),
	&"grade_mid": Color(0.12, 0.17, 0.33, 1),
	&"grade_light": Color(0.55, 0.64, 0.82, 1),
	&"proc_sea_color_near": Color(0.06, 0.1, 0.22, 1),
	&"proc_sea_color_far": Color(0.03, 0.05, 0.12, 1),
}
const STORM_OVERLAY: Dictionary[StringName, Variant] = {
	&"fog_color": Color(0.16, 0.24, 0.27, 1),
	&"fog_density": 0.003,
	&"fog_sky_affect": 0.65,
	&"volumetric_fog_density": 0.00015,
	&"volumetric_fog_albedo": Color(0.16, 0.24, 0.27, 1),
	&"light_color": Color(0.6, 0.72, 0.78, 1),
	&"light_energy_share": 0.45,
	&"ambient_energy": 0.55,
	&"glow_intensity": 0.4,
	&"proc_zenith_color": Color(0.07, 0.1, 0.13, 1),
	&"proc_mid_color": Color(0.14, 0.2, 0.23, 1),
	&"proc_horizon_color": Color(0.22, 0.32, 0.34, 1),
	&"proc_horizon_glow_color": Color(0.3, 0.45, 0.45, 1),
	&"proc_gradient_mid_height": 0.55,
	&"proc_gradient_power": 1.2,
	&"proc_horizon_glow_width": 0.2,
	&"proc_sun_glow_strength": 0.0,
	&"proc_sea_color_near": Color(0.2, 0.28, 0.31, 1),
	&"proc_sea_color_far": Color(0.09, 0.13, 0.16, 1),
	&"puff_shadow_color": Color(0.1, 0.15, 0.18, 1),
	&"puff_mid_color": Color(0.22, 0.3, 0.33, 1),
	&"puff_lit_color": Color(0.4, 0.5, 0.52, 1),
	&"puff_rim_color": Color(0.55, 0.66, 0.66, 1),
	&"cloud_shadow_color": Color(0.12, 0.17, 0.2, 1),
	&"cloud_mid_color": Color(0.24, 0.32, 0.35, 1),
	&"cloud_lit_color": Color(0.44, 0.54, 0.56, 1),
	&"cloud_rim_color": Color(0.6, 0.7, 0.7, 1),
}

func _script_vars(object: Object) -> Array[StringName]:
	var names: Array[StringName] = []
	for property: Dictionary in object.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			names.append(StringName(str(property["name"])))
	return names


func _near(want: float, got: float) -> bool:
	return want == got or absf(want - got) <= LITERAL_TOLERANCE * maxf(absf(want), absf(got))


func _same(want: Variant, got: Variant) -> bool:
	if want is float and got is float:
		return _near(float(want), float(got))
	if want is Color and got is Color:
		var a: Color = want as Color
		var b: Color = got as Color
		return _near(a.r, b.r) and _near(a.g, b.g) and _near(a.b, b.b) and _near(a.a, b.a)
	if want is Vector3 and got is Vector3:
		var u: Vector3 = want as Vector3
		var v: Vector3 = got as Vector3
		return _near(u.x, v.x) and _near(u.y, v.y) and _near(u.z, v.z)
	if want is Vector4 and got is Vector4:
		var p: Vector4 = want as Vector4
		var q: Vector4 = got as Vector4
		return _near(p.x, q.x) and _near(p.y, q.y) and _near(p.z, q.z) and _near(p.w, q.w)
	return want == got


## Asserts every pinned field of `object` and returns how many were checked.
func _assert_fields(object: Object, pinned: Dictionary[StringName, Variant], label: String) -> int:
	for field: StringName in pinned:
		assert_true(_same(pinned[field], object.get(field)), "%s %s: want %s got %s" % [label, field, pinned[field], object.get(field)])
	return pinned.size()


func test_contract_class_names_load() -> void:
	assert_not_null(SkyCycleDef.new())
	assert_not_null(SkyKeyframe.new())
	assert_not_null(SkyNightKeyframe.new())
	assert_not_null(SkyOverlayDef.new())
	assert_not_null(SkyFrame.new())
	assert_not_null(SkyWeatherState.new())
	assert_not_null(SkyEvaluator.new())


func test_shipped_cycle_structure_fields_are_the_pinned_values() -> void:
	var def: SkyCycleDef = SkyTestKit.cycle()
	var present: Array[StringName] = _script_vars(def)
	for field: StringName in STRUCTURE:
		assert_true(field in present, "SkyCycleDef has %s" % field)
	var checked: int = _assert_fields(def, STRUCTURE, "cycle")
	assert_gt(checked, MIN_STRUCTURE_FIELDS, "the pinned list covers the whole structure copy")


func test_shipped_cycle_only_fields_keep_their_documented_values() -> void:
	var def: SkyCycleDef = SkyTestKit.cycle()
	assert_eq(def.sun_base_direction, SUN_BASE_DIRECTION)
	assert_almost_eq(def.light_key_ramp_sin, LIGHT_KEY_RAMP_SIN, 0.0001)
	assert_almost_eq(def.life_night_on_mix, LIFE_NIGHT_ON_MIX, 0.0001)
	assert_almost_eq(def.life_night_off_mix, LIFE_NIGHT_OFF_MIX, 0.0001)


func test_shipped_day_keyframes_are_dawn_then_sunset() -> void:
	var def: SkyCycleDef = SkyTestKit.cycle()
	assert_eq(def.day_keyframes.size(), 2)
	_assert_fields(def.day_keyframes[0], MORNING_KEY, "morning")
	_assert_fields(def.day_keyframes[1], EVENING_KEY, "evening")


func test_shipped_night_is_the_pinned_night() -> void:
	var night: SkyNightKeyframe = SkyTestKit.cycle().night
	assert_not_null(night)
	_assert_fields(night, NIGHT_KEY, "night")
	assert_not_null(night.ambient_life, "night carries its ambient-life config")
	assert_almost_eq(night.moon_light_ratio, NIGHT_MOON_LIGHT_RATIO, 0.0001)


func test_shipped_storm_overlay_is_the_pinned_overlay() -> void:
	var overlay: SkyOverlayDef = SkyTestKit.storm_overlay()
	assert_not_null(overlay)
	var checked: int = _assert_fields(overlay, STORM_OVERLAY, "overlay")
	assert_gt(checked, 20)


func test_locked_phase_for_every_id() -> void:
	var def: SkyCycleDef = SkyTestKit.cycle()
	for sky_id: String in LOCKED_PHASES_BY_ID:
		assert_almost_eq(def.locked_phase_for(sky_id), LOCKED_PHASES_BY_ID[sky_id], 0.00001, sky_id)
	assert_eq(def.locked_phase_for(""), -1.0)


func test_aurora_night_strength_matches_the_pinned_ramp() -> void:
	var def: SkyCycleDef = SkyTestKit.cycle()
	for mix: float in AURORA_SHIPPED:
		assert_almost_eq(def.aurora_night_strength(mix), AURORA_SHIPPED[mix], 0.00001, "mix %s" % mix)
	def.aurora_start_night_mix = AURORA_START_OVERRIDE
	def.aurora_full_night_mix = AURORA_FULL_OVERRIDE
	for mix: float in AURORA_REVERSED:
		assert_almost_eq(def.aurora_night_strength(mix), AURORA_REVERSED[mix], 0.00001, "reversed mix %s" % mix)


func test_weather_state_defaults_are_inactive() -> void:
	var state: SkyWeatherState = SkyWeatherState.new()
	assert_false(state.any_active())
	assert_eq(state.cloud_overcast_amount(), 0.0)
	assert_eq(state.sun_cloud_scale, 1.0)


func test_weather_state_any_active_per_request() -> void:
	var state: SkyWeatherState = SkyWeatherState.new()
	for field: StringName in [&"storm_amount", &"overcast_amount", &"weather_cloud_overcast",
			&"snow_brighten", &"wfog_amount"]:
		state.clear()
		state.set(field, 0.4)
		assert_true(state.any_active(), "%s makes the weather active" % field)
	state.clear()
	state.sun_cloud_scale = 0.5
	assert_false(state.any_active(), "the sun-cloud scale alone is not a weather request")


func test_weather_state_cloud_overcast_is_the_strongest_source() -> void:
	var state: SkyWeatherState = SkyWeatherState.new()
	state.overcast_amount = 0.3
	state.weather_cloud_overcast = 0.6
	assert_almost_eq(state.cloud_overcast_amount(), 0.6, 0.00001)
	state.overcast_amount = 0.8
	assert_almost_eq(state.cloud_overcast_amount(), 0.8, 0.00001)


func test_weather_state_clear_restores_identity() -> void:
	var state: SkyWeatherState = SkyWeatherState.new()
	var fresh: SkyWeatherState = SkyWeatherState.new()
	state.storm_amount = 0.5
	state.storm_overlay = SkyOverlayDef.new()
	state.overcast_amount = 0.5
	state.overcast_light_scale = 0.4
	state.overcast_ambient_scale = 0.3
	state.overcast_exposure_scale = 0.2
	state.overcast_fog_tint = Color.RED
	state.overcast_fog_tint_strength = 0.9
	state.weather_cloud_overcast = 0.7
	state.snow_brighten = 0.6
	state.wfog_amount = 0.5
	state.wfog_max_opacity = 0.8
	state.wfog_depth_begin_m = 12.0
	state.wfog_depth_end_m = 90.0
	state.wfog_tint = Color.BLUE
	state.wfog_tint_strength = 0.5
	state.wfog_sky_affect_add = 0.3
	state.sun_cloud_scale = 0.5
	state.clear()
	for field: StringName in _script_vars(fresh):
		assert_eq(state.get(field), fresh.get(field), "clear() resets %s" % field)
	assert_false(state.any_active())


func test_frame_copy_from_round_trips_every_field() -> void:
	var source: SkyFrame = SkyFrame.new()
	var fields: Array[StringName] = _script_vars(source)
	assert_gt(fields.size(), 100)
	for field: StringName in fields:
		var current: Variant = source.get(field)
		if current is Color:
			source.set(field, FRAME_PROBE_COLOR)
		elif current is Vector3:
			source.set(field, FRAME_PROBE_VECTOR)
		elif current is bool:
			source.set(field, not (current as bool))
		elif current is int:
			source.set(field, FRAME_PROBE_INT)
		elif current is float:
			source.set(field, FRAME_PROBE_FLOAT)
	var copy: SkyFrame = SkyFrame.new()
	copy.copy_from(source)
	for field: StringName in fields:
		assert_ne(copy.get(field), SkyFrame.new().get(field), "%s was probed away from its default" % field)
		assert_eq(copy.get(field), source.get(field), "copy_from copies %s" % field)
	assert_eq(Evaluator.frame_values(copy), Evaluator.frame_values(source))
