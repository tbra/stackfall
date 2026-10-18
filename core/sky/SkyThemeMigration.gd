class_name SkyThemeMigration
extends RefCounted
## Transitional adapter: converts the shipped SkyThemeDef resources into the SkyCycleDef and
## SkyOverlayDef that replace them, by plain field copies (no maths). Used to generate the new
## data and by tests until the old themes are deleted.

## SkyThemeDef fields that SkyCycleDef keeps under the same name, copied from the day theme.
const STRUCTURE_FIELDS: Array[StringName] = [
	&"cycle_length_seconds",
	&"cycle_start_phase",
	&"cycle_random_start_min",
	&"cycle_random_start_max",
	&"cycle_locked_phase_sunset",
	&"cycle_locked_phase_dawn",
	&"cycle_locked_phase_night",
	&"cycle_sun_peak_degrees",
	&"cycle_twilight_width",
	&"cycle_sun_energy_gain",
	&"cycle_day_ambient_scale",
	&"cycle_sun_contrast_full_sin",
	&"cycle_star_brightness",
	&"cycle_star_cells",
	&"cycle_star_threshold",
	&"cycle_star_radius",
	&"cycle_star_horizon_fade",
	&"cycle_moon_angular_radius_deg",
	&"cycle_moon_halo_radius_deg",
	&"cycle_moon_halo_strength",
	&"cycle_moon_brightness",
	&"cycle_moon_full_night_mix",
	&"aurora_enabled",
	&"aurora_intensity",
	&"aurora_color_low",
	&"aurora_color_mid",
	&"aurora_color_top",
	&"aurora_speed",
	&"aurora_base_height",
	&"aurora_curtain_height",
	&"aurora_start_night_mix",
	&"aurora_full_night_mix",
	&"aurora_night_chance",
	&"variation_enabled",
	&"variation_exposure_min",
	&"variation_exposure_max",
	&"variation_sea_coverage_min",
	&"variation_sea_coverage_max",
	&"variation_knots_per_cycle",
	&"fog_sky_affect",
	&"fog_aerial_perspective",
	&"fog_sun_scatter",
	&"fog_height_m",
	&"fog_height_density",
	&"haze_strength",
	&"haze_begin_m",
	&"haze_end_m",
	&"cloud_deck_size_m",
	&"cloud_deck_height_m",
	&"glow_intensity",
	&"glow_hdr_threshold",
	&"proc_gradient_mid_height",
	&"proc_gradient_power",
	&"proc_sea_horizon_fade",
	&"cloud_clump_count",
	&"cloud_puffs_per_clump",
	&"cloud_seed",
	&"cloud_ring_inner_m",
	&"cloud_ring_outer_m",
	&"cloud_base_min_m",
	&"cloud_base_max_m",
	&"cloud_top_max_m",
	&"cloud_clump_radius_min_m",
	&"cloud_clump_radius_max_m",
	&"cloud_clump_height_ratio",
	&"cloud_flat_base",
	&"cloud_puff_raise_m",
	&"cloud_disc_clearance_ratio",
	&"cloud_drift_speed_min_mps",
	&"cloud_drift_speed_max_mps",
	&"cloud_radial_bias",
	&"cloud_bank_count",
	&"cloud_bank_ring_inner_m",
	&"cloud_bank_ring_outer_m",
	&"cloud_bank_base_min_m",
	&"cloud_bank_base_max_m",
	&"cloud_bank_top_max_m",
	&"cloud_bank_radius_min_m",
	&"cloud_bank_radius_max_m",
	&"proc_far_count",
	&"proc_far_ring_inner_m",
	&"proc_far_ring_outer_m",
	&"proc_far_radial_bias",
	&"proc_far_base_min_m",
	&"proc_far_base_max_m",
	&"proc_far_top_max_m",
	&"proc_far_radius_min_m",
	&"proc_far_radius_max_m",
	&"proc_far_fade_cap",
	&"bird_flock_count",
	&"bird_flock_size_min",
	&"bird_flock_size_max",
	&"bird_single_chance",
	&"bird_gap_min_s",
	&"bird_gap_max_s",
	&"bird_first_delay_min_s",
	&"bird_first_delay_max_s",
	&"bird_seed",
	&"bird_path_radius_m",
	&"bird_distance_min_m",
	&"bird_distance_max_m",
	&"bird_altitude_min_m",
	&"bird_altitude_max_m",
	&"bird_climb_max_mps",
	&"bird_speed_min_mps",
	&"bird_speed_max_mps",
	&"bird_size_min_m",
	&"bird_size_max_m",
	&"bird_spacing_m",
	&"bird_v_chance",
]
const SUN_DIRECTION_UNIFORM: StringName = &"sun_direction"


## Cycle from the Sunset theme (`day`: structure, materials, birds, day ambient life, evening
## key), the Dawn theme (key 0, the morning palette) and the Night theme (the night layer).
## Key 1's phase window is the day theme's cycle_dusk_weight_phases. The materials are shared
## with `day`, not duplicated.
static func cycle_from_themes(day: SkyThemeDef, dawn: SkyThemeDef, night: SkyThemeDef) -> SkyCycleDef:
	var def: SkyCycleDef = SkyCycleDef.new()
	if day == null:
		return def
	for field: StringName in STRUCTURE_FIELDS:
		def.set(field, day.get(field))
	def.sky_material = day.sky_material as ShaderMaterial
	def.cloud_puff_material = day.cloud_puff_material as ShaderMaterial
	def.bird_material = day.bird_material
	def.ambient_life = day.ambient_life
	var sky: ShaderMaterial = day.sky_material as ShaderMaterial
	if sky != null and sky.get_shader_parameter(SUN_DIRECTION_UNIFORM) is Vector3:
		def.sun_base_direction = sky.get_shader_parameter(SUN_DIRECTION_UNIFORM) as Vector3
	var morning: SkyKeyframe = _keyframe_from(dawn if dawn != null else day)
	var evening: SkyKeyframe = _keyframe_from(day)
	evening.phase_window = day.cycle_dusk_weight_phases
	var keys: Array[SkyKeyframe] = [morning, evening]
	def.day_keyframes = keys
	if night != null:
		def.night = _night_from(night)
	return def


## Overlay from the Storm theme: its fog, light, ambient, glow, sky gradient, sea and cloud
## colours as the full-amount targets.
static func overlay_from_theme(storm: SkyThemeDef) -> SkyOverlayDef:
	var overlay: SkyOverlayDef = SkyOverlayDef.new()
	if storm == null:
		return overlay
	overlay.fog_color = storm.fog_color
	overlay.fog_density = storm.fog_density
	overlay.fog_sky_affect = storm.fog_sky_affect
	overlay.volumetric_fog_density = storm.volumetric_fog_density
	overlay.volumetric_fog_albedo = storm.volumetric_fog_albedo
	overlay.light_color = storm.light_color
	overlay.light_energy = storm.light_energy
	overlay.ambient_energy = storm.ambient_energy
	overlay.glow_intensity = storm.glow_intensity
	overlay.proc_zenith_color = storm.proc_zenith_color
	overlay.proc_mid_color = storm.proc_mid_color
	overlay.proc_horizon_color = storm.proc_horizon_color
	overlay.proc_horizon_glow_color = storm.proc_horizon_glow_color
	overlay.proc_gradient_mid_height = storm.proc_gradient_mid_height
	overlay.proc_gradient_power = storm.proc_gradient_power
	overlay.proc_horizon_glow_width = storm.proc_horizon_glow_width
	overlay.proc_sun_glow_strength = storm.proc_sun_glow_strength
	overlay.proc_sea_color_near = storm.proc_sea_color_near
	overlay.proc_sea_color_far = storm.proc_sea_color_far
	var puffs: ShaderMaterial = storm.cloud_puff_material as ShaderMaterial
	overlay.puff_shadow_color = _color_param(puffs, &"shadow_color", overlay.puff_shadow_color)
	overlay.puff_mid_color = _color_param(puffs, &"mid_color", overlay.puff_mid_color)
	overlay.puff_lit_color = _color_param(puffs, &"lit_color", overlay.puff_lit_color)
	overlay.puff_rim_color = _color_param(puffs, &"rim_color", overlay.puff_rim_color)
	var sky: ShaderMaterial = storm.sky_material as ShaderMaterial
	overlay.cloud_shadow_color = _color_param(sky, &"cloud_shadow_color", overlay.cloud_shadow_color)
	overlay.cloud_mid_color = _color_param(sky, &"cloud_mid_color", overlay.cloud_mid_color)
	overlay.cloud_lit_color = _color_param(sky, &"cloud_lit_color", overlay.cloud_lit_color)
	overlay.cloud_rim_color = _color_param(sky, &"cloud_rim_color", overlay.cloud_rim_color)
	return overlay


static func _keyframe_from(theme: SkyThemeDef) -> SkyKeyframe:
	var key: SkyKeyframe = SkyKeyframe.new()
	key.fog_color = theme.fog_color
	key.volumetric_fog_albedo = theme.volumetric_fog_albedo
	key.light_color = theme.light_color
	key.proc_zenith_color = theme.proc_zenith_color
	key.proc_mid_color = theme.proc_mid_color
	key.proc_horizon_color = theme.proc_horizon_color
	key.proc_horizon_glow_color = theme.proc_horizon_glow_color
	key.proc_sea_color_near = theme.proc_sea_color_near
	key.proc_sea_color_far = theme.proc_sea_color_far
	key.fog_density = theme.fog_density
	key.volumetric_fog_density = theme.volumetric_fog_density
	key.light_energy = theme.light_energy
	key.ambient_energy = theme.ambient_energy
	key.proc_horizon_glow_width = theme.proc_horizon_glow_width
	key.proc_sun_glow_strength = theme.proc_sun_glow_strength
	var sky: ShaderMaterial = theme.sky_material as ShaderMaterial
	key.sun_core_color = _color_param(sky, &"sun_core_color", key.sun_core_color)
	key.sun_halo_color = _color_param(sky, &"sun_halo_color", key.sun_halo_color)
	key.sun_ray_color = _color_param(sky, &"sun_ray_color", key.sun_ray_color)
	key.cloud_shadow_color = _color_param(sky, &"cloud_shadow_color", key.cloud_shadow_color)
	key.cloud_mid_color = _color_param(sky, &"cloud_mid_color", key.cloud_mid_color)
	key.cloud_lit_color = _color_param(sky, &"cloud_lit_color", key.cloud_lit_color)
	key.cloud_rim_color = _color_param(sky, &"cloud_rim_color", key.cloud_rim_color)
	var puffs: ShaderMaterial = theme.cloud_puff_material as ShaderMaterial
	key.puff_shadow_color = _color_param(puffs, &"shadow_color", key.puff_shadow_color)
	key.puff_mid_color = _color_param(puffs, &"mid_color", key.puff_mid_color)
	key.puff_lit_color = _color_param(puffs, &"lit_color", key.puff_lit_color)
	key.puff_rim_color = _color_param(puffs, &"rim_color", key.puff_rim_color)
	return key


static func _night_from(theme: SkyThemeDef) -> SkyNightKeyframe:
	var key: SkyNightKeyframe = SkyNightKeyframe.new()
	key.zenith_color = theme.sky_top_color
	key.horizon_color = theme.sky_horizon_color
	key.below_color = theme.ground_bottom_color
	key.fog_color = theme.fog_color
	key.fog_density = theme.fog_density
	key.volumetric_fog_density = theme.volumetric_fog_density
	key.volumetric_fog_albedo = theme.volumetric_fog_albedo
	key.ambient_energy = theme.ambient_energy
	key.light_energy = theme.light_energy
	key.light_color = theme.light_color
	key.light_rotation_deg = theme.light_rotation_deg
	key.proc_sea_color_near = theme.proc_sea_color_near
	key.proc_sea_color_far = theme.proc_sea_color_far
	key.ambient_life = theme.ambient_life
	var puffs: ShaderMaterial = theme.cloud_puff_material as ShaderMaterial
	key.puff_shadow_color = _color_param(puffs, &"shadow_color", key.puff_shadow_color)
	key.puff_mid_color = _color_param(puffs, &"mid_color", key.puff_mid_color)
	key.puff_lit_color = _color_param(puffs, &"lit_color", key.puff_lit_color)
	key.puff_rim_color = _color_param(puffs, &"rim_color", key.puff_rim_color)
	var sky: ShaderMaterial = theme.sky_material as ShaderMaterial
	key.cloud_shadow_color = _color_param(sky, &"cloud_shadow_color", key.cloud_shadow_color)
	key.cloud_mid_color = _color_param(sky, &"cloud_mid_color", key.cloud_mid_color)
	key.cloud_lit_color = _color_param(sky, &"cloud_lit_color", key.cloud_lit_color)
	key.cloud_rim_color = _color_param(sky, &"cloud_rim_color", key.cloud_rim_color)
	# The moonlit grade is authored on the night sky material (CloudSea reads it there).
	key.grade_dark = _color_param(sky, &"grade_dark", key.grade_dark)
	key.grade_mid = _color_param(sky, &"grade_mid", key.grade_mid)
	key.grade_light = _color_param(sky, &"grade_light", key.grade_light)
	return key


## The Color shader parameter `uniform` of `material`, or `fallback` when the material is null
## or leaves it unset.
static func _color_param(material: ShaderMaterial, uniform: StringName, fallback: Color) -> Color:
	if material == null:
		return fallback
	var value: Variant = material.get_shader_parameter(uniform)
	if value is Color:
		return value as Color
	return fallback
