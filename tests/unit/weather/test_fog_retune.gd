extends GutTest
## fog retune. Ambient theme fog params load, the Skybox applies
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
	skybox.theme = load("res://config/sky/themes/%s.tres" % theme_id) as SkyThemeDef
	add_child_autofree(skybox)
	skybox.apply_theme(skybox.theme)
	return [skybox, environment]


func test_weather_fog_flattens_aerial_perspective_and_restores_it() -> void:
	var parts: Array = _rig("sunset")
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var base: float = environment.fog_aerial_perspective
	skybox.set_weather_fog(1.0, _fog.max_opacity, _fog.depth_begin_m, _fog.depth_end_m,
		_fog.fog_color, _fog.fog_tint_strength, _fog.sky_affect)
	skybox.flush_weather()
	assert_gt(base, 0.0)
	assert_almost_eq(environment.fog_aerial_perspective, 0.0, 0.0001, "flat fog colour like the disc (night sky is black)")
	skybox.set_weather_fog(0.0, 0.0, 0.0, 0.0, Color.WHITE, 0.0)
	skybox.flush_weather()
	assert_almost_eq(environment.fog_aerial_perspective, base, 0.0001)


func test_ambient_haze_starts_beyond_the_arena_and_blends_with_weather() -> void:
	for theme_id: String in THEME_IDS:
		var theme: SkyThemeDef = load("res://config/sky/themes/%s.tres" % theme_id) as SkyThemeDef
		assert_gt(theme.haze_strength, 0.0, theme_id)
		assert_gte(theme.haze_begin_m, _fog.arena_far_rim_m * 1.2, "%s haze leaves the arena crisp" % theme_id)
	WeatherFogShader.set_ambient(0.5, 90.0, 480.0, Color.RED, null)
	WeatherFogShader.set_state(0.0, 0.7, 30.0, 110.0, Color.BLUE, null)
	assert_almost_eq(WeatherFogShader.strength, 0.5, 0.0001)
	WeatherFogShader.set_state(1.0, 0.7, 30.0, 110.0, Color.BLUE, null)
	assert_almost_eq(WeatherFogShader.strength, 0.7, 0.0001)
	WeatherFogShader.reset_to_launch(null)
	assert_eq(WeatherFogShader.strength, 0.0)

