extends GutTest
## The typed sky cycle contract (config/sky/Sky*Def/Keyframe, core/sky/SkyFrame, SkyWeatherState,
## SkyThemeMigration): migration field equality against the shipped themes, the two SkyCycleDef
## helpers against SkyThemeDef, the weather state and the frame copy.

const SUNSET_PATH: String = "res://config/sky/themes/sunset.tres"
const DAWN_PATH: String = "res://config/sky/themes/dawn.tres"
const NIGHT_PATH: String = "res://config/sky/themes/night.tres"
const STORM_PATH: String = "res://config/sky/themes/storm.tres"
## SkyCycleDef fields with no SkyThemeDef counterpart of the same name.
const CYCLE_ONLY_FIELDS: Array[StringName] = [
	&"sun_base_direction", &"light_key_ramp_sin", &"life_night_on_mix", &"life_night_off_mix",
	&"day_keyframes", &"night",
]
const UNIFORM_TO_FIELD: Dictionary[StringName, StringName] = {
	&"shadow_color": &"puff_shadow_color", &"mid_color": &"puff_mid_color",
	&"lit_color": &"puff_lit_color", &"rim_color": &"puff_rim_color",
}
const FRAME_PROBE_COLOR: Color = Color(0.25, 0.5, 0.75, 1.0)
const FRAME_PROBE_VECTOR: Vector3 = Vector3(0.1, 0.2, 0.3)
const FRAME_PROBE_FLOAT: float = 0.37
const FRAME_PROBE_INT: int = 7
const PUFF_PROBE_KEY: StringName = &"sea_color"


func _theme(path: String) -> SkyThemeDef:
	return load(path) as SkyThemeDef


func _cycle() -> SkyCycleDef:
	return SkyThemeMigration.cycle_from_themes(_theme(SUNSET_PATH), _theme(DAWN_PATH), _theme(NIGHT_PATH))


## Names of a script's own exported/plain variables, in declaration order.
func _script_vars(object: Object) -> Array[StringName]:
	var names: Array[StringName] = []
	for property: Dictionary in object.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			names.append(StringName(str(property["name"])))
	return names


func _param(material: Material, uniform: StringName) -> Color:
	return (material as ShaderMaterial).get_shader_parameter(uniform) as Color


func test_contract_class_names_load() -> void:
	assert_not_null(SkyCycleDef.new())
	assert_not_null(SkyKeyframe.new())
	assert_not_null(SkyNightKeyframe.new())
	assert_not_null(SkyOverlayDef.new())
	assert_not_null(SkyFrame.new())
	assert_not_null(SkyWeatherState.new())
	assert_not_null(SkyEvaluator.new())


func test_migration_structure_fields_equal_the_sunset_theme() -> void:
	var day: SkyThemeDef = _theme(SUNSET_PATH)
	var def: SkyCycleDef = _cycle()
	var checked: int = 0
	for field: StringName in _script_vars(def):
		if field in CYCLE_ONLY_FIELDS or not (field in _script_vars(day)):
			continue
		if field == &"sky_material" or field == &"cloud_puff_material":
			assert_same(def.get(field), day.get(field), "%s shares the theme material" % field)
		else:
			assert_eq(def.get(field), day.get(field), "field %s" % field)
		checked += 1
	assert_gt(checked, 100, "structure copy covers the whole field list")


func test_migration_cycle_only_fields_keep_their_documented_values() -> void:
	var def: SkyCycleDef = _cycle()
	var sky: ShaderMaterial = _theme(SUNSET_PATH).sky_material as ShaderMaterial
	assert_eq(def.sun_base_direction, sky.get_shader_parameter(&"sun_direction") as Vector3)
	assert_almost_eq(def.light_key_ramp_sin, 0.2, 0.0001)
	assert_almost_eq(def.life_night_on_mix, 0.85, 0.0001)
	assert_almost_eq(def.life_night_off_mix, 0.15, 0.0001)


func test_migration_day_keyframes_match_dawn_then_sunset() -> void:
	var def: SkyCycleDef = _cycle()
	assert_eq(def.day_keyframes.size(), 2)
	_assert_keyframe_equals_theme(def.day_keyframes[0], _theme(DAWN_PATH), "morning")
	_assert_keyframe_equals_theme(def.day_keyframes[1], _theme(SUNSET_PATH), "evening")
	assert_eq(def.day_keyframes[1].phase_window, _theme(SUNSET_PATH).cycle_dusk_weight_phases)
	assert_eq(def.evening_keyframe(), def.day_keyframes[1])


func _assert_keyframe_equals_theme(key: SkyKeyframe, theme: SkyThemeDef, label: String) -> void:
	for field: StringName in [&"fog_color", &"volumetric_fog_albedo", &"light_color", &"proc_zenith_color",
			&"proc_mid_color", &"proc_horizon_color", &"proc_horizon_glow_color", &"proc_sea_color_near",
			&"proc_sea_color_far", &"fog_density", &"volumetric_fog_density", &"light_energy",
			&"ambient_energy", &"proc_horizon_glow_width", &"proc_sun_glow_strength"]:
		assert_eq(key.get(field), theme.get(field), "%s %s" % [label, field])
	for field: StringName in [&"sun_core_color", &"sun_halo_color", &"sun_ray_color",
			&"cloud_shadow_color", &"cloud_mid_color", &"cloud_lit_color", &"cloud_rim_color"]:
		assert_eq(key.get(field), _param(theme.sky_material, field), "%s %s" % [label, field])
	for uniform: StringName in UNIFORM_TO_FIELD:
		assert_eq(key.get(UNIFORM_TO_FIELD[uniform]), _param(theme.cloud_puff_material, uniform),
			"%s %s" % [label, UNIFORM_TO_FIELD[uniform]])


func test_migration_night_matches_the_night_theme() -> void:
	var theme: SkyThemeDef = _theme(NIGHT_PATH)
	var night: SkyNightKeyframe = _cycle().night
	assert_not_null(night)
	assert_eq(night.zenith_color, theme.sky_top_color)
	assert_eq(night.horizon_color, theme.sky_horizon_color)
	assert_eq(night.below_color, theme.ground_bottom_color)
	for field: StringName in [&"fog_color", &"fog_density", &"volumetric_fog_density", &"volumetric_fog_albedo",
			&"ambient_energy", &"light_energy", &"light_color", &"light_rotation_deg",
			&"proc_sea_color_near", &"proc_sea_color_far", &"ambient_life"]:
		assert_eq(night.get(field), theme.get(field), "night %s" % field)
	for uniform: StringName in UNIFORM_TO_FIELD:
		assert_eq(night.get(UNIFORM_TO_FIELD[uniform]), _param(theme.cloud_puff_material, uniform))
	for field: StringName in [&"cloud_shadow_color", &"cloud_mid_color", &"cloud_lit_color", &"cloud_rim_color"]:
		assert_eq(night.get(field), _param(theme.sky_material, field), "night %s" % field)
	# The night grade lives on the night sky material.
	for field: StringName in [&"grade_dark", &"grade_mid", &"grade_light"]:
		assert_eq(night.get(field), _param(theme.sky_material, field), "night %s" % field)
	assert_almost_eq(night.moon_light_ratio, 0.2, 0.0001)


func test_migration_overlay_matches_the_storm_theme() -> void:
	var theme: SkyThemeDef = _theme(STORM_PATH)
	var overlay: SkyOverlayDef = SkyThemeMigration.overlay_from_theme(theme)
	for field: StringName in [&"fog_color", &"fog_density", &"fog_sky_affect", &"volumetric_fog_density",
			&"volumetric_fog_albedo", &"light_color", &"light_energy", &"ambient_energy", &"glow_intensity",
			&"proc_zenith_color", &"proc_mid_color", &"proc_horizon_color", &"proc_horizon_glow_color",
			&"proc_gradient_mid_height", &"proc_gradient_power", &"proc_horizon_glow_width",
			&"proc_sun_glow_strength", &"proc_sea_color_near", &"proc_sea_color_far"]:
		assert_eq(overlay.get(field), theme.get(field), "overlay %s" % field)
	for uniform: StringName in UNIFORM_TO_FIELD:
		assert_eq(overlay.get(UNIFORM_TO_FIELD[uniform]), _param(theme.cloud_puff_material, uniform))
	for field: StringName in [&"cloud_shadow_color", &"cloud_mid_color", &"cloud_lit_color", &"cloud_rim_color"]:
		assert_eq(overlay.get(field), _param(theme.sky_material, field), "overlay %s" % field)


func test_migration_tolerates_null_themes() -> void:
	assert_not_null(SkyThemeMigration.cycle_from_themes(null, null, null))
	assert_not_null(SkyThemeMigration.overlay_from_theme(null))
	var only_day: SkyCycleDef = SkyThemeMigration.cycle_from_themes(_theme(SUNSET_PATH), null, null)
	assert_eq(only_day.day_keyframes.size(), 2)
	assert_null(only_day.night)


func test_locked_phase_for_equals_the_theme_for_every_id() -> void:
	var theme: SkyThemeDef = _theme(SUNSET_PATH)
	var def: SkyCycleDef = _cycle()
	for sky_id: String in ["sunset", "dawn", "night", "", "cycle", "storm"]:
		assert_almost_eq(def.locked_phase_for(sky_id), theme.locked_phase_for(sky_id), 0.00001, sky_id)
	assert_eq(def.locked_phase_for(""), -1.0)


func test_aurora_night_strength_equals_the_theme() -> void:
	var theme: SkyThemeDef = _theme(SUNSET_PATH)
	var def: SkyCycleDef = _cycle()
	var samples: Array[float] = [0.0, 0.25, 0.5, 0.7, 0.95, 1.0]
	for mix: float in samples:
		assert_almost_eq(def.aurora_night_strength(mix), theme.aurora_night_strength(mix), 0.00001)
	def.aurora_start_night_mix = 0.9
	def.aurora_full_night_mix = 0.3
	theme.aurora_start_night_mix = 0.9
	theme.aurora_full_night_mix = 0.3
	for mix: float in samples:
		assert_almost_eq(def.aurora_night_strength(mix), theme.aurora_night_strength(mix), 0.00001)


func test_evening_keyframe_is_null_without_keys() -> void:
	assert_null(SkyCycleDef.new().evening_keyframe())


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
	source.puff_shared[PUFF_PROBE_KEY] = FRAME_PROBE_COLOR
	var copy: SkyFrame = SkyFrame.new()
	copy.copy_from(source)
	for field: StringName in fields:
		if field == &"puff_shared":
			continue
		assert_ne(copy.get(field), SkyFrame.new().get(field), "%s was probed away from its default" % field)
		assert_eq(copy.get(field), source.get(field), "copy_from copies %s" % field)
	assert_eq(copy.puff_shared, source.puff_shared)
	assert_eq(copy.to_dict(), source.to_dict())


func test_frame_copy_from_does_not_share_the_puff_snapshot() -> void:
	var source: SkyFrame = SkyFrame.new()
	source.puff_shared[PUFF_PROBE_KEY] = FRAME_PROBE_COLOR
	var copy: SkyFrame = SkyFrame.new()
	copy.copy_from(source)
	source.puff_shared[PUFF_PROBE_KEY] = Color.BLACK
	assert_eq(copy.puff_shared[PUFF_PROBE_KEY], FRAME_PROBE_COLOR)


func test_frame_to_dict_has_one_stable_key_per_field() -> void:
	var frame: SkyFrame = SkyFrame.new()
	var dict: Dictionary = frame.to_dict()
	var fields: Array[StringName] = _script_vars(frame)
	assert_eq(dict.size(), fields.size())
	for field: StringName in fields:
		assert_true(dict.has(field), "to_dict has %s" % field)
