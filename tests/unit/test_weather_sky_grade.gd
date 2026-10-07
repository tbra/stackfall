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


func test_grade_params_are_ordered_and_authored_in_the_right_direction() -> void:
	assert_not_null(Skybox.load_theme("storm"))
	assert_gt(CEILING.rain_sky_blend, 0.0, "rain darkens the sky at least a little")
	assert_lt(CEILING.rain_sky_blend, CEILING.storm_sky_blend, "storm darkens more than rain")
	assert_gt(CEILING.snow_sky_exposure_gain, 1.0, "snow brightens")
	assert_lt(RAIN.overcast_sky_exposure_scale, 1.0, "rain overcast dims the exposure")


func test_grade_function_moves_the_right_way_with_each_input() -> void:
	var base: Color = Color(0.8, 0.7, 0.5)
	var storm: Color = Color(0.2, 0.2, 0.25)
	var clear: float = WeatherSkyGrade.sky_luminance(base, storm, 0.0, 0.5, 0.0, 2.0, 0.0)
	var half_storm: float = WeatherSkyGrade.sky_luminance(base, storm, 0.5, 0.5, 0.0, 2.0, 0.0)
	var full_storm: float = WeatherSkyGrade.sky_luminance(base, storm, 1.0, 0.5, 0.0, 2.0, 0.0)
	assert_gt(clear, half_storm, "more storm blend, darker")
	assert_gt(half_storm, full_storm)
	assert_lt(WeatherSkyGrade.sky_luminance(base, storm, 0.0, 0.5, 1.0, 2.0, 0.0), clear, "overcast exposure dims")
	assert_gt(WeatherSkyGrade.sky_luminance(base, storm, 0.0, 0.5, 0.0, 2.0, 1.0), clear, "snow gain brightens")


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
	# The blend is intensity-proportional, only rain and storm darken, and snow drives the
	# brighten target instead of the storm one.
	var rain_half: float = CEILING.sky_blend_for(&"rain", 0.5)
	var rain_full: float = CEILING.sky_blend_for(&"rain", 1.0)
	assert_gt(rain_full, rain_half)
	assert_gt(rain_half, 0.0)
	assert_eq(CEILING.sky_blend_for(&"rain", 0.0), 0.0)
	assert_gt(CEILING.sky_blend_for(&"storm", 1.0), rain_full)
	assert_eq(CEILING.sky_blend_for(&"snow", 1.0), 0.0)
	assert_eq(CEILING.sky_blend_for(&"clear", 1.0), 0.0)
	var ceiling: CloudCeiling = CloudCeiling.new()
	add_child_autofree(ceiling)
	ceiling.set_weather_intensity(&"snow", 1.0)
	assert_gt(ceiling.target_brighten(), 0.0)
	assert_eq(ceiling.target_storm(), 0.0)
	ceiling.set_weather_intensity(&"rain", 1.0)
	assert_almost_eq(ceiling.target_storm(), rain_full, 0.0001, "the node follows the tuning's blend")
