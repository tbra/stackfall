extends GutTest
## Fog weather: data registration, the Skybox-owned apply /
## restore (including a live theme switch), the disc's own matching fog, the
## Low variant, and what stays visible. Fog is presentation only: no host effect.

var _fog: FogTuning = preload("res://config/weather/fog.tres")
var _original_preset_id: StringName = &""


func before_each() -> void:
	_original_preset_id = Settings.graphics_base_preset_id()
	Settings.set_graphics_preset(&"high")


func after_each() -> void:
	Settings.set_graphics_preset(_original_preset_id)


func _rig() -> Array:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	add_child_autofree(skybox)
	# The boot sky is the cycle; the sunset the fog is measured against is the cycle locked there.
	skybox.set_locked_phase(skybox.sky_def.locked_phase_for("sunset"))
	return [skybox, environment]


func _presentation() -> FogPresentation:
	var presentation: FogPresentation = load("res://game/weather/fog_presentation.tscn").instantiate() as FogPresentation
	add_child_autofree(presentation)
	return presentation


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
	var skybox: Skybox = parts[0]
	var base_mode: Environment.FogMode = environment.fog_mode
	var base_begin: float = environment.fog_depth_begin
	var base_density: float = environment.fog_density
	var base_sky_affect: float = environment.fog_sky_affect
	var base_end: float = environment.fog_depth_end
	# The locked-sunset evaluation (Q4), not the static theme colour, is what the weather must restore.
	var base_color: Color = environment.fog_light_color
	var presentation: FogPresentation = _presentation()
	presentation.set_intensity(0.5)
	var half: float = environment.fog_density
	presentation.set_intensity(1.0)
	assert_eq(environment.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_eq(environment.fog_depth_begin, _fog.depth_begin_m, "near blocks are not fogged")
	assert_eq(environment.fog_depth_end, _fog.depth_end_m)
	assert_almost_eq(environment.fog_density, _fog.max_opacity, 0.00001)
	assert_almost_eq(half, _fog.max_opacity * 0.5, 0.00001, "scales with intensity")
	assert_ne(environment.fog_light_color, base_color, "cool tint")
	assert_almost_eq(environment.fog_sky_affect, clampf(skybox.sky_def.fog_sky_affect + _fog.sky_affect, 0.0, 1.0), 0.00001, "horizon washes out")
	presentation.set_intensity(0.0)
	assert_eq(environment.fog_mode, base_mode)
	assert_eq(environment.fog_depth_begin, base_begin)
	assert_eq(environment.fog_depth_end, base_end)
	assert_almost_eq(environment.fog_density, base_density, 0.00001)
	assert_eq(environment.fog_light_color, base_color)
	assert_almost_eq(environment.fog_sky_affect, base_sky_affect, 0.00001)
	assert_almost_eq(base_sky_affect, skybox.sky_def.fog_sky_affect, 0.00001, "the clear sky carries the cycle's own sky affect")


func test_the_low_preset_caps_the_fog_opacity() -> void:
	var parts: Array = _rig()
	var environment: Environment = parts[1]
	Settings.set_graphics_preset(&"low")
	var presentation: FogPresentation = _presentation()
	presentation.set_intensity(1.0)
	assert_almost_eq(environment.fog_density, _fog.max_opacity * _fog.low_preset_opacity, 0.00001)


func test_removing_the_presentation_restores_the_fog() -> void:
	var parts: Array = _rig()
	var environment: Environment = parts[1]
	var base_mode: Environment.FogMode = environment.fog_mode
	var base_density: float = environment.fog_density
	var presentation: FogPresentation = _presentation()
	presentation.set_intensity(1.0)
	remove_child(presentation)
	assert_eq(environment.fog_mode, base_mode, "weather stopped or match ended")
	assert_almost_eq(environment.fog_density, base_density, 0.00001)
	presentation.free()


func test_theme_switch_during_fog_rebases_and_restores_on_the_new_theme() -> void:
	var parts: Array = _rig()
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var night: Array = _rig()
	var night_skybox: Skybox = night[0]
	var night_env: Environment = night[1]
	night_skybox.set_locked_phase(night_skybox.sky_def.locked_phase_for("night"))
	SkyTestKit.settle(night_skybox)
	# Read before any weather runs: the presentation fogs every Skybox in the tree.
	var night_density: float = night_env.fog_density
	var night_color: Color = night_env.fog_light_color
	var base_mode: Environment.FogMode = environment.fog_mode
	var presentation: FogPresentation = _presentation()
	presentation.set_intensity(1.0)
	skybox.set_locked_phase(skybox.sky_def.locked_phase_for("night"))
	assert_eq(environment.fog_mode, Environment.FOG_MODE_DEPTH, "fog persists over the switch")
	assert_almost_eq(environment.fog_density, _fog.max_opacity, 0.00001)
	presentation.set_intensity(0.0)
	assert_eq(environment.fog_mode, base_mode)
	assert_almost_eq(environment.fog_density, night_density, 0.00001)
	assert_true(environment.fog_light_color.is_equal_approx(night_color), "night fog colour of the cycle locked at night")


func test_the_disc_applies_the_same_distance_fog_and_restores() -> void:
	var map_def: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	var overlay: TerritoryOverlay = TerritoryOverlay.new()
	overlay.configure(map_def, load("res://config/territory/territory_visuals.tres"), load("res://config/territory/territory_tuning.tres"))
	add_child_autofree(overlay)
	var material: ShaderMaterial = overlay.material()
	assert_null(material.get_shader_parameter(&"wfog_strength"), "off by default (shader default 0)")
	overlay.set_weather_fog(1.0, _fog.max_opacity, _fog.depth_begin_m, _fog.depth_end_m, _fog.fog_color)
	assert_almost_eq(float(material.get_shader_parameter(&"wfog_strength")), _fog.max_opacity, 0.00001)
	assert_eq(float(material.get_shader_parameter(&"wfog_begin")), _fog.depth_begin_m, "same begin as the Environment fog")
	assert_eq(float(material.get_shader_parameter(&"wfog_end")), _fog.depth_end_m)
	overlay.set_weather_fog(0.0, _fog.max_opacity, _fog.depth_begin_m, _fog.depth_end_m, _fog.fog_color)
	assert_eq(float(material.get_shader_parameter(&"wfog_strength")), 0.0, "off again")


func test_fog_replicates_like_any_weather_and_needs_no_host_effect() -> void:
	var w: MatchWeather = MatchWeather.new()
	w.set_defs([_fog])
	WeatherTestHost.bind_host(self, w, true)
	assert_true(w.start_event(&"fog"))
	assert_eq(w.active_id(), &"fog")
	w.reset()
	assert_eq(w.active_id(), &"")


func test_cloud_sea_puffs_join_the_fog_and_follow_it() -> void:
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	var def: SkyCycleDef = (load("res://config/sky/sky_cycle.tres") as SkyCycleDef)
	sea.configure_cycle(def, null, 1.0)
	if sea.get_child_count() == 0:
		pending("no puff material in this environment")
		return
	var presentation: FogPresentation = _presentation()
	presentation.set_intensity(1.0)
	assert_true(sea.is_in_group(WeatherFogShader.GROUP))
	presentation.set_intensity(0.0)
