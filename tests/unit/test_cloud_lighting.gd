extends GutTest
## Bontago-mp0.29: the sea and the upper puff layer take one shared
## CloudLighting (palette, light, cycle, weather grade) from the Skybox. The
## upper layer is the cloud sea's own puff field, so it shares the very material.

const EPS: float = 0.0001


func _wired_skybox() -> Skybox:
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment: Environment = Environment.new()
	environment.sky = sky
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = Skybox.load_theme("sunset")
	add_child_autofree(skybox)
	return skybox


## The puff material equals the shared state, and the upper layer draws with it.
func _assert_layers_match(skybox: Skybox, label: String) -> void:
	var l: CloudLighting = skybox.cloud_lighting()
	var sea: CloudSea = skybox.get_cloud_sea()
	var puff: ShaderMaterial = sea.puff_material()
	assert_true((puff.get_shader_parameter(&"light_direction") as Vector3).normalized().is_equal_approx(l.light_direction), "%s puff light" % label)
	assert_true((puff.get_shader_parameter(&"lit_color") as Color).is_equal_approx(l.lit_color), "%s puff palette" % label)
	assert_almost_eq(float(puff.get_shader_parameter(&"weather_dim")), l.dim, EPS, "%s puff dim" % label)
	assert_almost_eq(float(puff.get_shader_parameter(&"weather_desaturate")), l.desaturate, EPS, "%s puff desaturate" % label)
	assert_not_null(sea.upper_instance(), "%s upper layer exists" % label)
	assert_same(sea.upper_instance().material_override, puff, "%s upper layer shares the puff material" % label)
	assert_same(sea.puff_instance().material_override, puff, "%s sea uses it too" % label)
	var sky: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
	if sky != null and sky.get_shader_parameter(&"sun_direction") is Vector3 and sky.get_shader_parameter(&"cycle_night_mix") is float:
		assert_true((sky.get_shader_parameter(&"sun_direction") as Vector3).is_equal_approx(l.light_direction), "%s sea light" % label)
		assert_almost_eq(float(sky.get_shader_parameter(&"cycle_night_mix")), l.night_mix, EPS, "%s sea night mix" % label)


func test_theme_change_reaches_every_layer() -> void:
	var skybox: Skybox = _wired_skybox()
	skybox.apply_theme(skybox.theme)
	var lit_before: Color = skybox.cloud_lighting().lit_color
	skybox.set_theme_by_id("night")
	assert_false(skybox.cloud_lighting().lit_color.is_equal_approx(lit_before), "palette changed with the theme")
	_assert_layers_match(skybox, "night theme")


func test_cycle_phase_reaches_every_layer() -> void:
	var skybox: Skybox = _wired_skybox()
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	var seen: Dictionary = {}
	for phase: float in [0.25, 0.5, 0.75, 0.9]:
		skybox.set_cycle_phase(phase)
		_assert_layers_match(skybox, "phase %s" % phase)
		seen[snappedf(skybox.cloud_lighting().night_mix, 0.01)] = true
	assert_gt(seen.size(), 1, "night mix actually moved")
	assert_gt(skybox.cloud_lighting().night_mix, 0.9, "deep night at phase 0.9")


func test_storm_and_overcast_reach_every_layer() -> void:
	var skybox: Skybox = _wired_skybox()
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	skybox.set_cycle_phase(0.3)
	skybox.set_overcast(0.6, 0.5, 0.6, 0.7, Color(0.6, 0.65, 0.7), 0.4)
	skybox.set_storm_sky(0.7, Skybox.load_theme("storm"))
	var l: CloudLighting = skybox.cloud_lighting()
	assert_almost_eq(l.storm, 0.7, EPS)
	assert_almost_eq(l.overcast, 0.6, EPS)
	assert_gt(l.dim, 0.0)
	assert_gt(l.desaturate, 0.0)
	_assert_layers_match(skybox, "storm")
	skybox.set_cycle_phase(0.6)
	_assert_layers_match(skybox, "storm then phase")
	skybox.set_storm_sky(0.0, Skybox.load_theme("storm"))
	skybox.set_overcast(0.0, 1.0, 1.0, 1.0, Color.WHITE, 0.0)
	assert_eq(skybox.cloud_lighting().storm, 0.0)
	assert_eq(skybox.cloud_lighting().dim, 0.0)
	_assert_layers_match(skybox, "cleared")


func test_puffs_follow_every_published_input() -> void:
	var skybox: Skybox = _wired_skybox()
	skybox.apply_theme(skybox.theme)
	var l: CloudLighting = skybox.cloud_lighting()
	var puff: ShaderMaterial = skybox.get_cloud_sea().puff_material()
	l.publish(l.shadow_color, l.mid_color, l.lit_color, l.rim_color, l.light_direction, l.light_color, l.night_mix, 1.0, 1.0, 0.5, 0.9)
	skybox.get_cloud_sea().apply_lighting(l)
	assert_almost_eq(float(puff.get_shader_parameter(&"weather_dim")), 0.5, EPS, "puffs follow the weather dim")
	assert_almost_eq(float(puff.get_shader_parameter(&"weather_desaturate")), 0.9, EPS, "puffs follow the weather desaturation")


func test_publish_is_quiet_when_nothing_changed() -> void:
	var l: CloudLighting = CloudLighting.new()
	var count: Array[int] = [0]
	l.changed.connect(func() -> void: count[0] += 1)
	assert_false(l.publish(l.shadow_color, l.mid_color, l.lit_color, l.rim_color, l.light_direction, l.light_color,
		l.night_mix, l.overcast, l.storm, l.dim, l.desaturate))
	assert_eq(count[0], 0)
	assert_true(l.publish(l.shadow_color, l.mid_color, l.lit_color, l.rim_color, l.light_direction, l.light_color,
		0.5, l.overcast, l.storm, l.dim, l.desaturate))
	assert_eq(count[0], 1)


const CEILING: WeatherCeilingTuning = preload("res://config/weather/ceiling.tres")
const NIGHT_SHADOW: Color = Color(0.04, 0.06, 0.14)
const NIGHT_LIT: Color = Color(0.4, 0.5, 0.7)


func _floor(ratio: float) -> Color:
	return CloudLighting.floor_for_tone(CEILING.puff_floor_tint, CEILING.puff_min_brightness, ratio)


func test_night_storm_dim_is_capped_and_relieved() -> void:
	var stacked: float = CloudLighting.combined_dim(CEILING.cloud_overcast_dim, CEILING.storm_darkness_add, 1.0, 1.0,
		1.0, CEILING.night_dim_relief, CEILING.max_combined_dim)
	var day_storm: float = CloudLighting.combined_dim(CEILING.cloud_overcast_dim, CEILING.storm_darkness_add, 1.0, 1.0,
		0.0, CEILING.night_dim_relief, CEILING.max_combined_dim)
	assert_lt(stacked, day_storm, "night relieves the weather dim instead of stacking")
	assert_lte(CloudLighting.combined_dim(1.0, 1.0, 1.0, 1.0, 0.0, 0.0, CEILING.max_combined_dim), CEILING.max_combined_dim)


func test_night_storm_puff_base_never_below_minimum() -> void:
	var dim: float = CloudLighting.combined_dim(CEILING.cloud_overcast_dim, CEILING.storm_darkness_add, 1.0, 1.0,
		1.0, CEILING.night_dim_relief, CEILING.max_combined_dim)
	var desaturate: float = CEILING.cloud_overcast_desaturate
	var shadow: Color = CloudLighting.graded_floored(NIGHT_SHADOW, dim, desaturate, _floor(CEILING.puff_floor_shadow_ratio))
	var lit: Color = CloudLighting.graded_floored(NIGHT_LIT, dim, desaturate, _floor(1.0))
	assert_gte(shadow.get_luminance(), CEILING.puff_min_brightness * CEILING.puff_floor_shadow_ratio - EPS, "shadow tone keeps its floor")
	assert_gte(lit.get_luminance(), CEILING.puff_min_brightness - EPS, "lit tone keeps the minimum brightness")
	assert_gt(lit.get_luminance(), shadow.get_luminance(), "cel tones stay distinct")
	# Even an absurd worst case (black palette, full dim) is lifted to the floor.
	var black: Color = CloudLighting.graded_floored(Color.BLACK, 1.0, 1.0, _floor(1.0))
	assert_gte(black.get_luminance(), CEILING.puff_min_brightness - EPS)


func test_sun_effects_off_at_night_reduced_by_overcast() -> void:
	var clear: float = CloudLighting.sun_effect_scale(0.0, CEILING.sun_night_fade_end, 0.0, CEILING.sun_overcast_attenuation, 0.0, CEILING.sun_storm_attenuation)
	var overcast: float = CloudLighting.sun_effect_scale(0.0, CEILING.sun_night_fade_end, 1.0, CEILING.sun_overcast_attenuation, 0.0, CEILING.sun_storm_attenuation)
	var storm: float = CloudLighting.sun_effect_scale(0.0, CEILING.sun_night_fade_end, 1.0, CEILING.sun_overcast_attenuation, 1.0, CEILING.sun_storm_attenuation)
	var night: float = CloudLighting.sun_effect_scale(1.0, CEILING.sun_night_fade_end, 0.0, CEILING.sun_overcast_attenuation, 0.0, CEILING.sun_storm_attenuation)
	assert_almost_eq(clear, 1.0, EPS)
	assert_lt(overcast, clear, "overcast reduces the sun effects")
	assert_lt(storm, 0.05, "a heavy storm hides them")
	assert_almost_eq(night, 0.0, EPS, "night turns them off")


func test_skybox_publishes_sun_scale_to_sky_and_flare() -> void:
	var skybox: Skybox = _wired_skybox()
	skybox.apply_theme(skybox.theme)
	skybox.set_overcast(1.0, 1.0, 1.0, 1.0, Color.WHITE, 1.0)
	var scale: float = skybox.cloud_lighting().sun_scale
	assert_lt(scale, 1.0, "overcast attenuates the published sun scale")
	var sky: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
	assert_almost_eq(float(sky.get_shader_parameter(&"sun_effect_scale")), scale, EPS)
