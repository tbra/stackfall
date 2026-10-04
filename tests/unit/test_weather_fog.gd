extends GutTest
## Fog weather (Bontago-470.3): data registration, the Skybox-owned apply /
## restore (including a live theme switch), the disc's own matching fog, the
## Low variant, and what stays visible. Fog is presentation only: no host effect.

const SUNSET_PATH: String = "res://config/sky_themes/sunset.tres"
const NIGHT_PATH: String = "res://config/sky_themes/night.tres"

var _fog: FogTuning = preload("res://config/weather/fog.tres")


func _rig() -> Array:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = load(SUNSET_PATH) as SkyThemeDef
	add_child_autofree(skybox)
	skybox.apply_theme(skybox.theme)
	return [skybox, environment]


func _presentation(reduced: int = 0) -> FogPresentation:
	var presentation: FogPresentation = load("res://vfx/weather/fog_presentation.tscn").instantiate() as FogPresentation
	presentation.configure(_fog, reduced)
	add_child_autofree(presentation)
	return presentation


## Fraction of colour kept at `distance_m` for DEPTH fog: nothing before begin,
## linear to max opacity at end (Godot's depth mode, curve 1).
func _visibility(opacity: float, distance_m: float) -> float:
	var t: float = clampf((distance_m - _fog.depth_begin_m) / (_fog.depth_end_m - _fog.depth_begin_m), 0.0, 1.0)
	return 1.0 - opacity * t


func test_fog_is_registered_as_data_and_has_no_physics_effect() -> void:
	assert_true(load("res://config/weather/fog.tres") is FogTuning)
	assert_eq(_fog.id, &"fog")
	assert_eq(_fog.effect_script, "", "the host sets nothing physical")
	assert_true(load(_fog.presentation_scene) is PackedScene)
	assert_eq(MatchWeather.id_for_mode(MatchConfig.WeatherMode.FOG), &"fog")
	assert_eq(MatchWeather.mode_labels()[MatchConfig.WeatherMode.FOG], "Fog")


func test_fog_uses_depth_mode_from_a_begin_distance_and_restores_the_theme_exactly() -> void:
	var parts: Array = _rig()
	var environment: Environment = parts[1]
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var base_mode: Environment.FogMode = environment.fog_mode
	var base_begin: float = environment.fog_depth_begin
	var base_end: float = environment.fog_depth_end
	var presentation: FogPresentation = _presentation()
	presentation.set_intensity(0.5)
	var half: float = environment.fog_density
	presentation.set_intensity(1.0)
	assert_eq(environment.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_eq(environment.fog_depth_begin, _fog.depth_begin_m, "near blocks are not fogged")
	assert_eq(environment.fog_depth_end, _fog.depth_end_m)
	assert_almost_eq(environment.fog_density, _fog.max_opacity, 0.00001)
	assert_almost_eq(half, _fog.max_opacity * 0.5, 0.00001, "scales with intensity")
	assert_ne(environment.fog_light_color, sunset.fog_color, "cool tint")
	assert_almost_eq(environment.fog_sky_affect, clampf(sunset.fog_sky_affect + _fog.sky_affect, 0.0, 1.0), 0.00001, "horizon washes out")
	presentation.set_intensity(0.0)
	assert_eq(environment.fog_mode, base_mode)
	assert_eq(environment.fog_depth_begin, base_begin)
	assert_eq(environment.fog_depth_end, base_end)
	assert_almost_eq(environment.fog_density, sunset.fog_density, 0.00001)
	assert_eq(environment.fog_light_color, sunset.fog_color)
	assert_almost_eq(environment.fog_sky_affect, sunset.fog_sky_affect, 0.00001)


func test_removing_the_presentation_restores_the_fog() -> void:
	var parts: Array = _rig()
	var environment: Environment = parts[1]
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var base_mode: Environment.FogMode = environment.fog_mode
	var presentation: FogPresentation = _presentation()
	presentation.set_intensity(1.0)
	remove_child(presentation)
	assert_eq(environment.fog_mode, base_mode, "weather stopped or match ended")
	assert_almost_eq(environment.fog_density, sunset.fog_density, 0.00001)
	presentation.free()


func test_theme_switch_during_fog_rebases_and_restores_on_the_new_theme() -> void:
	var parts: Array = _rig()
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var night: SkyThemeDef = load(NIGHT_PATH) as SkyThemeDef
	var base_mode: Environment.FogMode = environment.fog_mode
	var presentation: FogPresentation = _presentation()
	presentation.set_intensity(1.0)
	skybox.apply_theme(night)
	assert_eq(environment.fog_mode, Environment.FOG_MODE_DEPTH, "fog persists over the switch")
	assert_almost_eq(environment.fog_density, _fog.max_opacity, 0.00001)
	presentation.set_intensity(0.0)
	assert_eq(environment.fog_mode, base_mode)
	assert_almost_eq(environment.fog_density, night.fog_density, 0.00001)
	assert_eq(environment.fog_light_color, night.fog_color)


func test_low_variant_has_a_lower_maximum_opacity() -> void:
	var parts: Array = _rig()
	var environment: Environment = parts[1]
	var presentation: FogPresentation = _presentation(1)
	presentation.set_intensity(1.0)
	assert_almost_eq(environment.fog_density, _fog.max_opacity * _fog.low_preset_opacity, 0.00001)


func test_local_area_keeps_full_colour_and_far_things_stay_faintly_visible() -> void:
	assert_gte(_fog.depth_begin_m, _fog.clear_radius_m, "fog begins beyond the local play area")
	assert_eq(_visibility(_fog.max_opacity, _fog.clear_radius_m), 1.0, "blocks near the camera keep full colour")
	assert_gte(_visibility(_fog.max_opacity, _fog.far_reference_distance_m), _fog.far_min_visibility, "far beacon/contours faintly visible")
	assert_lt(_visibility(_fog.max_opacity, _fog.far_reference_distance_m), 0.4, "distant objects do fade")
	assert_gt(_fog.max_opacity, 0.0)
	assert_lt(_fog.max_opacity, 1.0, "never fully opaque")


func test_the_disc_applies_the_same_distance_fog_and_restores() -> void:
	var map_def: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	var overlay: TerritoryOverlay = TerritoryOverlay.new()
	overlay.configure(map_def, load("res://config/territory_visuals.tres"), load("res://config/territory_tuning.tres"))
	add_child_autofree(overlay)
	var material: ShaderMaterial = overlay.material()
	assert_null(material.get_shader_parameter(&"wfog_strength"), "off by default (shader default 0)")
	overlay.set_weather_fog(1.0, _fog.max_opacity, _fog.depth_begin_m, _fog.depth_end_m, _fog.fog_color)
	assert_almost_eq(float(material.get_shader_parameter(&"wfog_strength")), _fog.max_opacity, 0.00001)
	assert_eq(float(material.get_shader_parameter(&"wfog_begin")), _fog.depth_begin_m, "same begin as the Environment fog")
	assert_eq(float(material.get_shader_parameter(&"wfog_end")), _fog.depth_end_m)
	overlay.set_weather_fog(0.0, _fog.max_opacity, _fog.depth_begin_m, _fog.depth_end_m, _fog.fog_color)
	assert_eq(float(material.get_shader_parameter(&"wfog_strength")), 0.0, "off again")


func test_territory_shader_still_opts_out_of_environment_fog_but_fogs_itself() -> void:
	var text: String = FileAccess.get_file_as_string("res://shaders/territory.gdshader")
	assert_true(text.contains("fog_disabled"), "the theme fog must not brown the disc")
	assert_true(text.contains("wfog_strength"), "but weather fog is applied in the shader, matching the blocks")


func test_fog_replicates_like_any_weather_and_needs_no_host_effect() -> void:
	var w: MatchWeather = MatchWeather.new()
	w.set_defs([_fog])
	w.set_host_override(true)
	assert_true(w.start_event(&"fog"))
	assert_eq(w.active_id(), &"fog")
	w.reset()
	assert_eq(w.active_id(), &"")


func test_scenery_shaders_fade_by_the_same_distance_rule() -> void:
	for path: String in ["res://shaders/cloud_puffs.gdshader", "res://shaders/distant_birds.gdshader", "res://shaders/fireflies.gdshader"]:
		assert_true(FileAccess.get_file_as_string(path).contains("wfog_strength"), "%s fogs by distance" % path)
	var material: ShaderMaterial = ShaderMaterial.new()
	var presentation: FogPresentation = _presentation()
	presentation.set_intensity(1.0)
	WeatherFogShader.apply(material)
	assert_almost_eq(float(material.get_shader_parameter(&"wfog_strength")), _fog.max_opacity, 0.00001)
	assert_eq(float(material.get_shader_parameter(&"wfog_begin")), _fog.depth_begin_m)
	assert_eq(float(material.get_shader_parameter(&"wfog_end")), _fog.depth_end_m)
	presentation.set_intensity(0.0)
	WeatherFogShader.apply(material)
	assert_almost_eq(float(material.get_shader_parameter(&"wfog_strength")), WeatherFogShader.ambient_strength, 0.00001, "restored to the theme ambient haze")


func test_cloud_sea_puffs_join_the_fog_and_follow_it() -> void:
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure(load(SUNSET_PATH) as SkyThemeDef, 1.0, null)
	if sea.get_child_count() == 0:
		pending("no puff material in this environment")
		return
	var presentation: FogPresentation = _presentation()
	presentation.set_intensity(1.0)
	assert_true(sea.is_in_group(WeatherFogShader.GROUP))
	presentation.set_intensity(0.0)
