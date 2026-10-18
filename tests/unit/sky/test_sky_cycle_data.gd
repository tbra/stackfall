extends GutTest
## The shipped sky data (config/sky/sky_cycle.tres, storm_overlay.tres, sky_dome.tres,
## cloud_puffs.tres) loads, owns its materials, and evaluates to the golden fixture; the fixture
## is well formed. Field-by-field values are pinned in test_sky_contract.gd.

const Live := preload("res://tests/unit/sky/test_sky_parity_live.gd")
const Evaluator := preload("res://tests/unit/sky/test_sky_evaluator.gd")
const CYCLE_PATH: String = "res://config/sky/sky_cycle.tres"
const OVERLAY_PATH: String = "res://config/sky/storm_overlay.tres"
const DOME_PATH: String = "res://config/sky/sky_dome.tres"
const PUFFS_PATH: String = "res://config/sky/cloud_puffs.tres"
const RES_PREFIX: String = "res://"
const MIN_CYCLE_FIELDS: int = 100
const REQUIRED_RETIRED: Array[String] = [
	"sky_yaw_offset_deg", "sky_pitch_offset_deg", "cloud_layer_opacity", "cloud_warp_amount",
	"cloud_light_probe", "cloud_light_contrast", "cloud_rim_width", "proc_strata2_stretch",
	"cloud_cards", "sun_core_intensity", "sun_halo_intensity",
]
const MIN_STATES: int = 60
const GOLDEN_GROUPS: Array[String] = ["L_", "W_", "P_", "R"]
const RELATIVE_TOLERANCE: float = 0.000001

## Effective shader parameters (set value, else shader default; textures by path) of the sunset
## theme sky and puff materials, and the script variables of its two ambient-life configs, captured
## from the old theme resources (var_to_str) before they were retired. Textures are pinned by file
## name; the perch colour array is written as an Array of Color.

const DOME_VALUES: Dictionary[StringName, Variant] = {
	&"use_global_dirs": null,
	&"radiance_tick": null,
	&"exposure": 0.8,
	&"sun_direction": Vector3(0.963087, 0.069011, -0.260192),
	&"cycle_night_mix": null,
	&"cycle_night_zenith": null,
	&"cycle_night_horizon": null,
	&"cycle_night_below": null,
	&"cycle_star_brightness": null,
	&"cycle_star_cells": null,
	&"cycle_star_threshold": null,
	&"cycle_star_radius": null,
	&"cycle_star_horizon_fade": null,
	&"moon_disc_tex": null,
	&"moon_halo_tex": null,
	&"moon_direction": null,
	&"moon_visibility": null,
	&"moon_angular_radius_deg": null,
	&"moon_halo_radius_deg": null,
	&"moon_halo_strength": null,
	&"moon_brightness": null,
	&"moon_disc_fill": null,
	&"moon_halo_fill": null,
	&"aurora_visibility": null,
	&"aurora_intensity": null,
	&"aurora_color_low": null,
	&"aurora_color_mid": null,
	&"aurora_color_top": null,
	&"aurora_speed": null,
	&"aurora_base_height": null,
	&"aurora_curtain_height": null,
	&"sun_core_color": Color(1, 0.94, 0.82, 1),
	&"sun_halo_color": Color(1, 0.62, 0.28, 1),
	&"sun_ray_color": Color(1, 0.72, 0.38, 1),
	&"sun_core_angular_radius_deg": 1.6,
	&"sun_halo_angular_radius_deg": 9.0,
	&"sun_halo_softness_deg": 10.0,
	&"ray_count": 14.0,
	&"ray_sharpness": 5.0,
	&"ray_wide_count": 4.0,
	&"ray_wide_sharpness": 2.0,
	&"ray_length_deg": 55.0,
	&"ray_intensity": 0.35,
	&"ray_shimmer_speed": 0.15,
	&"ray_shimmer_amount": 0.08,
	&"sun_effect_scale": null,
	&"noise_tex": "cloud_noise.tres",
	&"cloud_cel_edge": 0.08,
	&"cloud_shadow_color": Color(0.34, 0.27, 0.47, 1),
	&"cloud_mid_color": Color(0.82, 0.57, 0.56, 1),
	&"cloud_lit_color": Color(1, 0.85, 0.64, 1),
	&"cloud_rim_color": Color(1, 0.9, 0.66, 1),
	&"procedural_sea_mix": null,
	&"proc_zenith_color": null,
	&"proc_mid_color": null,
	&"proc_horizon_color": null,
	&"proc_gradient_mid_height": null,
	&"proc_gradient_power": null,
	&"proc_horizon_glow_color": null,
	&"proc_horizon_glow_width": null,
	&"proc_sun_glow_strength": null,
	&"proc_sea_color_near": null,
	&"proc_sea_color_far": null,
	&"proc_sea_horizon_fade": null,
	&"proc_gradient_bands": null,
	&"proc_gradient_band_edge": null,
	&"proc_sun_edge_deg": null,
	&"proc_sun_halo_bands": null,
	&"proc_sun_halo_strength": null,
	&"proc_horizon_glow_strength": null,
	&"proc_horizon_glow_sun_bias": null,
	&"proc_sea_params": Vector4(0.9, 1.5, 0.004, 5),
	&"proc_sea_heights": Vector2(1, 0.6),
	&"proc_sea_wind": Vector2(1, 0.35),
	&"proc_sea_coverage": 0.4,
	&"proc_sea_softness": 0.04,
	&"proc_sea_band_edge": 0.08,
}
const PUFF_VALUES: Dictionary[StringName, Variant] = {
	&"exposure": 0.8,
	&"grade_amount": 0.0,
	&"grade_dark": Color(0.02, 0.03, 0.08, 1),
	&"grade_mid": Color(0.12, 0.17, 0.33, 1),
	&"grade_light": Color(0.55, 0.64, 0.82, 1),
	&"grade_gamma": 1.2,
	&"procedural_sea_mix": null,
	&"noise_tex": null,
	&"sun_direction": null,
	&"proc_zenith_color": null,
	&"proc_mid_color": null,
	&"proc_horizon_color": null,
	&"proc_gradient_mid_height": null,
	&"proc_gradient_power": null,
	&"proc_gradient_bands": null,
	&"proc_gradient_band_edge": null,
	&"proc_horizon_glow_color": null,
	&"proc_horizon_glow_width": null,
	&"proc_horizon_glow_strength": null,
	&"proc_horizon_glow_sun_bias": null,
	&"proc_sea_color_near": null,
	&"proc_sea_color_far": null,
	&"proc_sea_horizon_fade": null,
	&"proc_sea_params": null,
	&"proc_sea_heights": null,
	&"proc_sea_wind": null,
	&"proc_sea_coverage": null,
	&"proc_sea_softness": null,
	&"proc_sea_band_edge": null,
	&"cloud_shadow_color": null,
	&"cloud_mid_color": null,
	&"cloud_lit_color": null,
	&"cloud_rim_color": null,
	&"flat_base": 0.15,
	&"light_direction": Vector3(0.963087, 0.069011, -0.260192),
	&"min_light_elevation": 0.3,
	&"shadow_color": Color(0.27, 0.32, 0.48, 1),
	&"mid_color": Color(0.57, 0.41, 0.49, 1),
	&"lit_color": Color(1, 0.7, 0.47, 1),
	&"rim_color": Color(1, 0.78, 0.42, 1),
	&"mid_threshold": 0.38,
	&"lit_threshold": 0.64,
	&"band_edge_px": 1.0,
	&"light_weight": 0.7,
	&"height_weight": 0.2,
	&"ambient_shade": -0.05,
	&"underside_shade": 0.25,
	&"base_rim_start": null,
	&"base_bounce": null,
	&"base_stagger_m": null,
	&"round_base_from": null,
	&"round_under_start": null,
	&"base_clear_start_m": null,
	&"base_clear_end_m": null,
	&"rim_power": 4.0,
	&"rim_sun_side": 0.9,
	&"rim_backlight": 1.4,
	&"rim_threshold": 0.5,
	&"rim_softness": 0.08,
	&"upper_rim_down_shift": null,
	&"puff_noise": "puff_noise.tres",
	&"lump_frequency": 0.4,
	&"lump_cell_radius": 1.0,
	&"lump_height": 0.35,
	&"lump_vertex_scale": 0.7,
	&"lump_detail_scale": 2.3,
	&"lump_detail_weight": 0.4,
	&"lump_shade": 0.35,
	&"lump_bias": 0.6,
	&"lump_speed": 0.004,
	&"detail_lod_m": 260.0,
	&"billow_amount": 0.03,
	&"billow_speed": 0.35,
	&"billow_frequency": 2.0,
	&"hull_margin": 0.04,
	&"hull_chord_margin": null,
	&"wfog_strength": null,
	&"wfog_begin": null,
	&"wfog_end": null,
	&"wfog_color": null,
	&"fade_start_m": 160.0,
	&"fade_end_m": 650.0,
	&"depth_fade_start_m": 40.0,
	&"depth_fade_end_m": 140.0,
	&"depth_fade_amount": 0.45,
	&"far_fade_cap": null,
	&"near_fade_start_m": 5.0,
	&"near_fade_end_m": 16.0,
	&"drift_offset": null,
	&"drift_edge_fade_m": null,
	&"drift_exclusion_fade_m": null,
	&"weather_dim": null,
	&"weather_desaturate": null,
	&"weather_floor": null,
	&"floor_shadow_ratio": null,
	&"floor_mid_ratio": null,
}
const AMBIENT_LIFE_SUNSET: Dictionary[StringName, Variant] = {
	&"perch_bird_count": 8,
	&"perch_bird_length_min_m": 0.25,
	&"perch_bird_length_max_m": 0.35,
	&"perch_bird_scale": 1.5,
	&"perch_min_player_distance_m": 16.0,
	&"perch_min_goal_distance_m": 9.0,
	&"perch_min_camera_distance_m": 14.0,
	&"perch_min_block_distance_m": 6.0,
	&"perch_edge_margin_m": 3.0,
	&"perch_spot_tries": 24,
	&"perch_tower_fraction": 0.4,
	&"perch_tower_min_settle_s": 4.0,
	&"perch_tower_min_top_size_m": 0.9,
	&"perch_tower_clear_height_m": 2.0,
	&"flee_camera_radius_m": 9.0,
	&"flee_cursor_radius_m": 8.0,
	&"flee_impact_radius_m": 14.0,
	&"flee_overhead_radius_m": 4.0,
	&"flee_moving_block_radius_m": 5.5,
	&"flee_block_moved_epsilon_m": 0.02,
	&"block_settled_window_s": 0.75,
	&"perch_min_bird_spacing_m": 3.5,
	&"threat_poll_interval_s": 0.12,
	&"flock_size_min": 1,
	&"flock_size_max": 6,
	&"flock_count_max": 2,
	&"flock_arrival_stagger_s": 0.35,
	&"flock_arrival_spread_deg": 9.0,
	&"flock_circle_radius_jitter_m": 4.0,
	&"flock_circle_altitude_jitter_m": 2.5,
	&"flock_landing_stagger_s": 1.5,
	&"flock_perch_radius_m": 2.2,
	&"flock_member_spacing_m": 0.7,
	&"flock_tower_radius_m": 6.0,
	&"flock_social_interval_min_s": 3.0,
	&"flock_social_interval_max_s": 9.0,
	&"flock_swap_chance": 0.35,
	&"flock_chase_chance": 0.3,
	&"flock_chase_duration_s": 2.4,
	&"flock_chase_radius_m": 1.4,
	&"flock_chase_height_m": 0.9,
	&"flock_takeoff_stagger_max_s": 0.45,
	&"perch_stay_min_s": 14.0,
	&"perch_stay_max_s": 34.0,
	&"spawn_delay_min_s": 2.0,
	&"spawn_delay_max_s": 14.0,
	&"idle_action_min_s": 0.8,
	&"idle_action_max_s": 2.6,
	&"idle_hop_chance": 0.25,
	&"idle_hop_distance_m": 0.3,
	&"idle_hop_height_m": 0.12,
	&"approach_circle_radius_min_m": 55.0,
	&"approach_circle_radius_max_m": 85.0,
	&"approach_altitude_min_m": 14.0,
	&"approach_altitude_max_m": 26.0,
	&"approach_circle_time_min_s": 3.0,
	&"approach_circle_time_max_s": 8.0,
	&"flight_speed_mps": 9.0,
	&"flap_rate_hz": 9.0,
	&"flee_speed_mps": 13.0,
	&"flee_climb_deg": 32.0,
	&"flee_turn_rate_deg": 38.0,
	&"flee_accel_time_s": 0.7,
	&"despawn_distance_m": 130.0,
	&"perch_body_colors": [Color(0.12, 0.15, 0.24, 1), Color(0.16, 0.13, 0.21, 1), Color(0.11, 0.17, 0.2, 1)],
	&"perch_belly_color": Color(0.97, 0.86, 0.68, 1),
	&"perch_breast_color": Color(0.85, 0.42, 0.2, 1),
	&"perch_wing_color": Color(0.05, 0.06, 0.11, 1),
	&"perch_beak_color": Color(1, 0.72, 0.2, 1),
	&"perch_outline_color": Color(0.07, 0.05, 0.09, 1),
	&"fireflies_count": 0,
	&"fireflies_above_disc_fraction": 0.07,
	&"fireflies_rim_offset_min_m": -1.0,
	&"fireflies_rim_offset_max_m": 14.0,
	&"fireflies_rim_height_min_m": -12.0,
	&"fireflies_rim_height_max_m": 4.0,
	&"fireflies_above_inset_m": 8.0,
	&"fireflies_above_height_min_m": 2.0,
	&"fireflies_above_height_max_m": 9.0,
	&"fireflies_drift_radius_m": 2.6,
	&"fireflies_drift_speed": 0.35,
	&"fireflies_blink_hz": 0.35,
	&"fireflies_size_m": 0.5,
	&"fireflies_color": Color(0.72, 1, 0.28, 1),
	&"fireflies_emission_energy": 4.0,
	&"fireflies_fade_far_m": 140.0,
	&"fireflies_seed": 5,
}
const AMBIENT_LIFE_NIGHT: Dictionary[StringName, Variant] = {
	&"perch_bird_count": 0,
	&"perch_bird_length_min_m": 0.25,
	&"perch_bird_length_max_m": 0.35,
	&"perch_bird_scale": 1.5,
	&"perch_min_player_distance_m": 16.0,
	&"perch_min_goal_distance_m": 9.0,
	&"perch_min_camera_distance_m": 14.0,
	&"perch_min_block_distance_m": 6.0,
	&"perch_edge_margin_m": 3.0,
	&"perch_spot_tries": 24,
	&"perch_tower_fraction": 0.4,
	&"perch_tower_min_settle_s": 4.0,
	&"perch_tower_min_top_size_m": 0.9,
	&"perch_tower_clear_height_m": 2.0,
	&"flee_camera_radius_m": 9.0,
	&"flee_cursor_radius_m": 8.0,
	&"flee_impact_radius_m": 14.0,
	&"flee_overhead_radius_m": 4.0,
	&"flee_moving_block_radius_m": 5.5,
	&"flee_block_moved_epsilon_m": 0.02,
	&"block_settled_window_s": 0.75,
	&"perch_min_bird_spacing_m": 3.5,
	&"threat_poll_interval_s": 0.12,
	&"flock_size_min": 1,
	&"flock_size_max": 6,
	&"flock_count_max": 2,
	&"flock_arrival_stagger_s": 0.35,
	&"flock_arrival_spread_deg": 9.0,
	&"flock_circle_radius_jitter_m": 4.0,
	&"flock_circle_altitude_jitter_m": 2.5,
	&"flock_landing_stagger_s": 1.5,
	&"flock_perch_radius_m": 2.2,
	&"flock_member_spacing_m": 0.7,
	&"flock_tower_radius_m": 6.0,
	&"flock_social_interval_min_s": 3.0,
	&"flock_social_interval_max_s": 9.0,
	&"flock_swap_chance": 0.35,
	&"flock_chase_chance": 0.3,
	&"flock_chase_duration_s": 2.4,
	&"flock_chase_radius_m": 1.4,
	&"flock_chase_height_m": 0.9,
	&"flock_takeoff_stagger_max_s": 0.45,
	&"perch_stay_min_s": 14.0,
	&"perch_stay_max_s": 34.0,
	&"spawn_delay_min_s": 2.0,
	&"spawn_delay_max_s": 14.0,
	&"idle_action_min_s": 0.8,
	&"idle_action_max_s": 2.6,
	&"idle_hop_chance": 0.25,
	&"idle_hop_distance_m": 0.3,
	&"idle_hop_height_m": 0.12,
	&"approach_circle_radius_min_m": 55.0,
	&"approach_circle_radius_max_m": 85.0,
	&"approach_altitude_min_m": 14.0,
	&"approach_altitude_max_m": 26.0,
	&"approach_circle_time_min_s": 3.0,
	&"approach_circle_time_max_s": 8.0,
	&"flight_speed_mps": 9.0,
	&"flap_rate_hz": 9.0,
	&"flee_speed_mps": 13.0,
	&"flee_climb_deg": 32.0,
	&"flee_turn_rate_deg": 38.0,
	&"flee_accel_time_s": 0.7,
	&"despawn_distance_m": 130.0,
	&"perch_body_colors": [Color(0.12, 0.15, 0.24, 1), Color(0.16, 0.13, 0.21, 1), Color(0.11, 0.17, 0.2, 1)],
	&"perch_belly_color": Color(0.97, 0.86, 0.68, 1),
	&"perch_breast_color": Color(0.85, 0.42, 0.2, 1),
	&"perch_wing_color": Color(0.05, 0.06, 0.11, 1),
	&"perch_beak_color": Color(1, 0.72, 0.2, 1),
	&"perch_outline_color": Color(0.07, 0.05, 0.09, 1),
	&"fireflies_count": 220,
	&"fireflies_above_disc_fraction": 0.07,
	&"fireflies_rim_offset_min_m": -1.0,
	&"fireflies_rim_offset_max_m": 14.0,
	&"fireflies_rim_height_min_m": -12.0,
	&"fireflies_rim_height_max_m": 4.0,
	&"fireflies_above_inset_m": 8.0,
	&"fireflies_above_height_min_m": 2.0,
	&"fireflies_above_height_max_m": 9.0,
	&"fireflies_drift_radius_m": 2.6,
	&"fireflies_drift_speed": 0.35,
	&"fireflies_blink_hz": 0.35,
	&"fireflies_size_m": 0.5,
	&"fireflies_color": Color(0.72, 1, 0.28, 1),
	&"fireflies_emission_energy": 4.0,
	&"fireflies_fade_far_m": 140.0,
	&"fireflies_seed": 5,
}


func _script_vars(object: Object) -> Array[StringName]:
	var names: Array[StringName] = []
	for property: Dictionary in object.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			names.append(StringName(str(property["name"])))
	return names


func _material_values(material: ShaderMaterial) -> Dictionary:
	var values: Dictionary = {}
	for entry: Dictionary in material.shader.get_shader_uniform_list():
		var uniform_name: StringName = StringName(str(entry["name"]))
		var value: Variant = material.get_shader_parameter(uniform_name)
		if value is Texture2D:
			value = (value as Texture2D).resource_path
		values[uniform_name] = value
	return values


static func _near(want: float, got: float) -> bool:
	return want == got or absf(want - got) <= RELATIVE_TOLERANCE * maxf(absf(want), absf(got))


static func _same(want: Variant, got: Variant) -> bool:
	if want is float and (got is float or got is int):
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
	if want is Vector2 and got is Vector2:
		var m: Vector2 = want as Vector2
		var n: Vector2 = got as Vector2
		return _near(m.x, n.x) and _near(m.y, n.y)
	if want is String and got is String:
		return (got as String).get_file() == want or got == want
	return want == got


func _assert_pinned(pinned: Dictionary[StringName, Variant], actual: Dictionary, label: String) -> void:
	for key: StringName in pinned:
		assert_true(actual.has(key), "%s has %s" % [label, key])
		if actual.has(key):
			assert_true(_same(pinned[key], actual[key]), "%s %s: want %s got %s" % [label, key, pinned[key], actual[key]])


func _config_values(config: Object) -> Dictionary:
	var values: Dictionary = {}
	for field: StringName in _script_vars(config):
		var value: Variant = config.get(field)
		if value is PackedColorArray:
			value = Array(value as PackedColorArray)
		values[field] = value
	return values


func test_dome_and_puffs_hold_the_pinned_sunset_values() -> void:
	_assert_pinned(DOME_VALUES, _material_values(load(DOME_PATH) as ShaderMaterial), "sky_dome")
	_assert_pinned(PUFF_VALUES, _material_values(load(PUFFS_PATH) as ShaderMaterial), "cloud_puffs")


func test_cycle_ambient_life_configs_hold_the_pinned_values() -> void:
	var def: SkyCycleDef = SkyTestKit.cycle()
	_assert_pinned(AMBIENT_LIFE_SUNSET, _config_values(def.ambient_life), "ambient_life (day)")
	_assert_pinned(AMBIENT_LIFE_NIGHT, _config_values(def.night.ambient_life), "ambient_life (night)")


func test_shipped_cycle_and_overlay_load_with_their_structure() -> void:
	var saved: SkyCycleDef = load(CYCLE_PATH) as SkyCycleDef
	assert_not_null(saved, "sky_cycle.tres loads as SkyCycleDef")
	assert_eq(saved.day_keyframes.size(), 2)
	assert_not_null(saved.night)
	assert_not_null(saved.ambient_life)
	assert_gt(_script_vars(saved).size(), MIN_CYCLE_FIELDS)
	var overlay: SkyOverlayDef = load(OVERLAY_PATH) as SkyOverlayDef
	assert_not_null(overlay, "storm_overlay.tres loads as SkyOverlayDef")


func test_dome_and_puffs_are_shader_materials_the_cycle_owns() -> void:
	var dome: ShaderMaterial = load(DOME_PATH) as ShaderMaterial
	var puffs: ShaderMaterial = load(PUFFS_PATH) as ShaderMaterial
	assert_not_null(dome)
	assert_not_null(puffs)
	assert_not_null(dome.shader, "the dome has its shader")
	assert_not_null(puffs.shader, "the puffs have their shader")
	assert_gt(_material_values(dome).size(), 0)
	assert_gt(_material_values(puffs).size(), 0)


func test_cycle_owns_its_materials() -> void:
	var saved: SkyCycleDef = load(CYCLE_PATH) as SkyCycleDef
	assert_eq(saved.sky_material.resource_path, DOME_PATH)
	assert_eq(saved.cloud_puff_material.resource_path, PUFFS_PATH)
	assert_not_null(saved.bird_material, "the cycle carries the bird material")
	for path: String in [CYCLE_PATH, OVERLAY_PATH, DOME_PATH, PUFFS_PATH]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_ne(text, "", "%s is readable" % path)
		for line: String in text.split("\n"):
			if not line.begins_with("[ext_resource"):
				continue
			var start: int = line.find(RES_PREFIX)
			var end: int = line.find("\"", start)
			assert_true(start >= 0 and end > start and ResourceLoader.exists(line.substr(start, end - start)),
				"%s references a missing resource: %s" % [path, line])


func test_golden_fixture_is_well_formed() -> void:
	var golden: Dictionary = Live.load_golden()
	assert_false(golden.is_empty(), "fixture loads")
	var states: Dictionary = golden.get("states", {}) as Dictionary
	assert_gte(states.size(), MIN_STATES)
	for prefix: String in GOLDEN_GROUPS:
		var found: int = 0
		for state: String in states.keys():
			found += 1 if state.begins_with(prefix) else 0
		assert_gt(found, 0, "group %s present" % prefix)
	var retired: Array = golden.get("retired_uniforms", []) as Array
	for uniform_name: String in REQUIRED_RETIRED:
		assert_true(retired.has(uniform_name), "retired list names %s" % uniform_name)
	var dome: ShaderMaterial = load(DOME_PATH) as ShaderMaterial
	var declared: Array[String] = []
	for entry: Dictionary in dome.shader.get_shader_uniform_list():
		declared.append(str(entry["name"]))
	for uniform_name: String in retired:
		assert_false(uniform_name in declared, "%s is retired from the sky shader" % uniform_name)
	for key: String in ["sky", "puff", "env", "light", "fog_volume", "lighting", "flare", "life_is_night", "globals", "facade"]:
		assert_true((states["L_0.25"] as Dictionary).has(key), "state group %s" % key)
	var aurora: Dictionary = (states["W_match_night_aurora_seed"] as Dictionary)["sky"] as Dictionary
	assert_gt(float(aurora["aurora_visibility"]), 0.0, "the aurora seed shows the aurora")
	for preset: String in ["low", "medium", "high"]:
		assert_true(states.has("P_%s_boot" % preset), "preset %s boot state" % preset)


func test_evaluate_of_the_shipped_cycle_equals_the_golden() -> void:
	var states: Dictionary = Live.load_golden().get("states", {}) as Dictionary
	var def: SkyCycleDef = SkyTestKit.cycle()
	var compared: int = 0
	for phase: float in Evaluator.LOCKED_GOLDEN_PHASES:
		var name: String = "L_%.2f" % phase
		var frame: SkyFrame = SkyEvaluator.evaluate(def, phase, SkyVariation.DEFAULT_SEED, 0, Evaluator.clear_weather(), true)
		var problems: Array[String] = Evaluator.golden_mismatches(frame, states[name] as Dictionary, name)
		for problem: String in problems:
			fail_test(problem)
		compared += 1
	assert_eq(compared, Evaluator.LOCKED_GOLDEN_PHASES.size())
