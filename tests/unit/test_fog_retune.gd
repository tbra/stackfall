extends GutTest
## Bontago-mp0.130: fog retune. Ambient theme fog params load, the Skybox applies
## aerial perspective / sun scatter / height fog, weather fog adds aerial
## perspective and restores it, and exponential fog density at the arena's far
## rim stays under the readability threshold (pure function).

const THEME_IDS: Array[String] = ["dawn", "sunset", "storm", "night"]

var _fog: FogTuning = preload("res://config/weather/fog.tres")


func _rig(theme_id: String) -> Array:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = load("res://config/sky_themes/%s.tres" % theme_id) as SkyThemeDef
	add_child_autofree(skybox)
	skybox.apply_theme(skybox.theme)
	return [skybox, environment]


func test_exponential_keep_is_pure_and_monotonic() -> void:
	assert_almost_eq(FogTuning.exponential_keep(0.0, 100.0), 1.0, 0.0001)
	assert_almost_eq(FogTuning.exponential_keep(0.01, 0.0), 1.0, 0.0001)
	assert_lt(FogTuning.exponential_keep(0.01, 100.0), FogTuning.exponential_keep(0.01, 50.0))


func test_every_theme_keeps_the_far_rim_readable() -> void:
	for theme_id: String in THEME_IDS:
		var theme: SkyThemeDef = load("res://config/sky_themes/%s.tres" % theme_id) as SkyThemeDef
		var keep: float = FogTuning.exponential_keep(theme.fog_density, _fog.arena_far_rim_m)
		assert_gte(keep, _fog.ambient_min_rim_keep, "%s keeps the far rim readable (keep %.3f)" % [theme_id, keep])
		# Height fog is only dense below the arena: it must not start above the disc.
		assert_lte(theme.fog_height_m, 0.0, "%s height fog stays below the disc" % theme_id)


func test_themes_load_the_new_fog_params_and_skybox_applies_them() -> void:
	for theme_id: String in THEME_IDS:
		var parts: Array = _rig(theme_id)
		var environment: Environment = parts[1]
		var theme: SkyThemeDef = (parts[0] as Skybox).theme
		assert_gt(theme.fog_aerial_perspective, 0.0, "%s has aerial perspective" % theme_id)
		assert_almost_eq(environment.fog_aerial_perspective, theme.fog_aerial_perspective, 0.0001)
		assert_almost_eq(environment.fog_sun_scatter, theme.fog_sun_scatter, 0.0001)
		assert_almost_eq(environment.fog_height, theme.fog_height_m, 0.0001)
		assert_almost_eq(environment.fog_height_density, theme.fog_height_density, 0.0001)


func test_weather_fog_adds_aerial_perspective_and_restores_it() -> void:
	var parts: Array = _rig("sunset")
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var base: float = environment.fog_aerial_perspective
	skybox.set_weather_fog(1.0, _fog.max_opacity, _fog.depth_begin_m, _fog.depth_end_m,
		_fog.fog_color, _fog.fog_tint_strength, _fog.sky_affect, _fog.aerial_perspective_add)
	assert_gt(environment.fog_aerial_perspective, base)
	skybox.set_weather_fog(0.0, 0.0, 0.0, 0.0, Color.WHITE, 0.0)
	assert_almost_eq(environment.fog_aerial_perspective, base, 0.0001)


func test_weather_fog_depth_ramp_still_clears_the_near_field() -> void:
	assert_gte(_fog.depth_begin_m, _fog.clear_radius_m)
	var span: float = _fog.depth_end_m - _fog.depth_begin_m
	var t: float = clampf((_fog.far_reference_distance_m - _fog.depth_begin_m) / span, 0.0, 1.0)
	assert_gte(1.0 - _fog.max_opacity * t, _fog.far_min_visibility)


func test_ambient_haze_starts_beyond_the_arena_and_blends_with_weather() -> void:
	for theme_id: String in THEME_IDS:
		var theme: SkyThemeDef = load("res://config/sky_themes/%s.tres" % theme_id) as SkyThemeDef
		assert_gt(theme.haze_strength, 0.0, theme_id)
		assert_gte(theme.haze_begin_m, _fog.arena_far_rim_m * 1.2, "%s haze leaves the arena crisp" % theme_id)
	WeatherFogShader.set_ambient(0.5, 90.0, 480.0, Color.RED, null)
	WeatherFogShader.set_state(0.0, 0.7, 30.0, 110.0, Color.BLUE, null)
	assert_almost_eq(WeatherFogShader.strength, 0.5, 0.0001)
	WeatherFogShader.set_state(1.0, 0.7, 30.0, 110.0, Color.BLUE, null)
	assert_almost_eq(WeatherFogShader.strength, 0.7, 0.0001)
	WeatherFogShader.reset_to_launch(null)
	assert_eq(WeatherFogShader.strength, 0.0)
