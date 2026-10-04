extends GutTest
## Bontago-mp0.128: rain uses the storm sky lighter, storm is darkest, snow brightest.

const CEILING: WeatherCeilingTuning = preload("res://config/weather/ceiling.tres")
const RAIN: RainTuning = preload("res://config/weather/rain.tres")


func _luma(base: Color, weather: StringName) -> float:
	var storm_theme: SkyThemeDef = Skybox.load_theme("storm")
	var storm: Color = storm_theme.proc_horizon_color
	var blend: float = CEILING.sky_blend_for(weather, 1.0)
	var overcast: float = 1.0 if weather == &"rain" else 0.0
	var snow: float = 1.0 if weather == &"snow" else 0.0
	return WeatherSkyGrade.sky_luminance(base, storm, blend, RAIN.overcast_sky_exposure_scale, overcast,
		CEILING.snow_sky_exposure_gain, snow)


func test_params_load() -> void:
	assert_not_null(Skybox.load_theme("storm"))
	assert_gt(CEILING.rain_sky_blend, 0.0)
	assert_lt(CEILING.rain_sky_blend, CEILING.storm_sky_blend)
	assert_gt(CEILING.snow_sky_exposure_gain, 1.0)
	assert_gt(CEILING.snow_cloud_brighten, 0.0)


func test_luminance_ordering_at_each_phase() -> void:
	for theme_id: String in ["sunset", "dawn", "night"]:
		var base: Color = Skybox.load_theme(theme_id).proc_horizon_color
		var snow: float = _luma(base, &"snow")
		var rain: float = _luma(base, &"rain")
		var storm: float = _luma(base, &"storm")
		var clear: float = _luma(base, &"clear")
		assert_gt(snow, clear, "%s: snow brighter than clear" % theme_id)
		# Night is already darker than the storm sky, so only day, dawn and dusk order them.
		if theme_id != "night":
			assert_gt(rain, storm, "%s: rain lighter than storm" % theme_id)
			assert_gt(snow, rain, "%s: snow > rain" % theme_id)


func test_ceiling_targets() -> void:
	assert_almost_eq(CEILING.sky_blend_for(&"rain", 1.0), CEILING.rain_sky_blend, 0.0001)
	assert_almost_eq(CEILING.sky_blend_for(&"storm", 1.0), CEILING.storm_sky_blend, 0.0001)
	assert_eq(CEILING.sky_blend_for(&"snow", 1.0), 0.0)
	var ceiling: CloudCeiling = CloudCeiling.new()
	add_child_autofree(ceiling)
	ceiling.set_weather_intensity(&"snow", 1.0)
	assert_almost_eq(ceiling.target_brighten(), 1.0, 0.0001)
	assert_eq(ceiling.target_storm(), 0.0)
	ceiling.set_weather_intensity(&"rain", 1.0)
	assert_almost_eq(ceiling.target_storm(), CEILING.rain_sky_blend, 0.0001)
