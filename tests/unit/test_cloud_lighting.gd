extends GutTest
## Bontago-mp0.29: the sea, the puffs and the weather ceiling take one shared
## CloudLighting (palette, light, cycle, weather grade) from the Skybox.

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


func _ceiling(skybox: Skybox) -> CloudCeiling:
	var ceiling: CloudCeiling = CloudCeiling.new()
	add_child_autofree(ceiling)
	ceiling.set_lighting(skybox.cloud_lighting())
	return ceiling


func _c3(color: Color) -> Vector3:
	return Vector3(color.r, color.g, color.b)


## Every layer's own copy of every input equals the shared state.
func _assert_layers_match(skybox: Skybox, ceiling: CloudCeiling, label: String) -> void:
	var l: CloudLighting = skybox.cloud_lighting()
	var puff: ShaderMaterial = skybox.get_cloud_sea().puff_material()
	var layer: ShaderMaterial = ceiling.layer_material(0)
	var desaturate: float = maxf(l.desaturate, ceiling.tuning.min_desaturate)
	assert_true((puff.get_shader_parameter(&"light_direction") as Vector3).normalized().is_equal_approx(l.light_direction), "%s puff light" % label)
	assert_true((layer.get_shader_parameter(&"light_direction") as Vector3).is_equal_approx(l.light_direction), "%s ceiling light" % label)
	assert_true((layer.get_shader_parameter(&"light_color") as Vector3).is_equal_approx(_c3(l.light_color)), "%s ceiling light colour" % label)
	assert_true((puff.get_shader_parameter(&"lit_color") as Color).is_equal_approx(l.lit_color), "%s puff palette" % label)
	var expected_lit: Color = CloudLighting.grade(l.lit_color, 0.0, desaturate)
	assert_true((layer.get_shader_parameter(&"lit_color") as Color).is_equal_approx(expected_lit), "%s ceiling palette" % label)
	assert_almost_eq(float(layer.get_shader_parameter(&"night_mix")), l.night_mix, EPS, "%s ceiling night mix" % label)
	assert_almost_eq(float(puff.get_shader_parameter(&"weather_dim")), l.dim, EPS, "%s puff dim" % label)
	assert_almost_eq(float(puff.get_shader_parameter(&"weather_desaturate")), l.desaturate, EPS, "%s puff desaturate" % label)
	assert_almost_eq(float(layer.get_shader_parameter(&"darkness")), clampf(l.dim + ceiling.tuning.darkness, 0.0, 1.0), EPS, "%s ceiling dim" % label)
	var sea: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
	if sea != null:
		assert_true((sea.get_shader_parameter(&"sun_direction") as Vector3).is_equal_approx(l.light_direction), "%s sea light" % label)
		assert_almost_eq(float(sea.get_shader_parameter(&"cycle_night_mix")), l.night_mix, EPS, "%s sea night mix" % label)


func test_theme_change_reaches_every_layer() -> void:
	var skybox: Skybox = _wired_skybox()
	skybox.apply_theme(skybox.theme)
	var ceiling: CloudCeiling = _ceiling(skybox)
	var lit_before: Color = skybox.cloud_lighting().lit_color
	skybox.set_theme_by_id("night")
	var l: CloudLighting = skybox.cloud_lighting()
	assert_false(l.lit_color.is_equal_approx(lit_before), "palette changed with the theme")
	var puff: ShaderMaterial = skybox.get_cloud_sea().puff_material()
	assert_true((puff.get_shader_parameter(&"lit_color") as Color).is_equal_approx(l.lit_color))
	assert_true((ceiling.layer_material(0).get_shader_parameter(&"light_direction") as Vector3).is_equal_approx(
		(puff.get_shader_parameter(&"light_direction") as Vector3).normalized()))
	var expected: Color = CloudLighting.grade(l.lit_color, 0.0, maxf(l.desaturate, ceiling.tuning.min_desaturate))
	assert_true((ceiling.layer_material(0).get_shader_parameter(&"lit_color") as Color).is_equal_approx(expected))


func test_cycle_phase_reaches_every_layer() -> void:
	var skybox: Skybox = _wired_skybox()
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	var ceiling: CloudCeiling = _ceiling(skybox)
	var seen: Dictionary = {}
	for phase: float in [0.25, 0.5, 0.75, 0.9]:
		skybox.set_cycle_phase(phase)
		_assert_layers_match(skybox, ceiling, "phase %s" % phase)
		seen[snappedf(skybox.cloud_lighting().night_mix, 0.01)] = true
	assert_gt(seen.size(), 1, "night mix actually moved")
	assert_gt(skybox.cloud_lighting().night_mix, 0.9, "deep night at phase 0.9")


func test_storm_and_overcast_reach_every_layer() -> void:
	var skybox: Skybox = _wired_skybox()
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	skybox.set_cycle_phase(0.3)
	var ceiling: CloudCeiling = _ceiling(skybox)
	var dry: float = float(ceiling.layer_material(0).get_shader_parameter(&"darkness"))
	skybox.set_overcast(0.6, 0.5, 0.6, 0.7, Color(0.6, 0.65, 0.7), 0.4)
	skybox.set_storm_sky(0.7, Skybox.load_theme("storm"))
	var l: CloudLighting = skybox.cloud_lighting()
	assert_almost_eq(l.storm, 0.7, EPS)
	assert_almost_eq(l.overcast, 0.6, EPS)
	assert_gt(l.dim, 0.0)
	assert_gt(l.desaturate, 0.0)
	assert_gt(float(ceiling.layer_material(0).get_shader_parameter(&"darkness")), dry, "ceiling darkens with the storm")
	_assert_layers_match(skybox, ceiling, "storm")
	skybox.set_cycle_phase(0.6)
	_assert_layers_match(skybox, ceiling, "storm then phase")
	skybox.set_storm_sky(0.0, Skybox.load_theme("storm"))
	skybox.set_overcast(0.0, 1.0, 1.0, 1.0, Color.WHITE, 0.0)
	assert_eq(skybox.cloud_lighting().storm, 0.0)
	assert_eq(skybox.cloud_lighting().dim, 0.0)
	_assert_layers_match(skybox, ceiling, "cleared")


func test_no_layer_ignores_an_input() -> void:
	var skybox: Skybox = _wired_skybox()
	skybox.apply_theme(skybox.theme)
	var ceiling: CloudCeiling = _ceiling(skybox)
	var layer: ShaderMaterial = ceiling.layer_material(0)
	var l: CloudLighting = skybox.cloud_lighting()
	var puff: ShaderMaterial = skybox.get_cloud_sea().puff_material()
	# Light direction and colour.
	l.publish(l.shadow_color, l.mid_color, l.lit_color, l.rim_color, Vector3(0.0, 1.0, 0.0), Color(1.0, 0.0, 0.0),
		l.night_mix, l.overcast, l.storm, l.dim, l.desaturate)
	assert_true((layer.get_shader_parameter(&"light_direction") as Vector3).is_equal_approx(Vector3.UP), "ceiling follows the light direction")
	assert_true((layer.get_shader_parameter(&"light_color") as Vector3).is_equal_approx(Vector3(1.0, 0.0, 0.0)), "ceiling follows the light colour")
	# Cycle phase.
	l.publish(l.shadow_color, l.mid_color, l.lit_color, l.rim_color, l.light_direction, l.light_color, 1.0, l.overcast, l.storm, l.dim, l.desaturate)
	assert_almost_eq(float(layer.get_shader_parameter(&"night_mix")), 1.0, EPS, "ceiling follows the cycle")
	assert_lt(float(layer.get_shader_parameter(&"sun_side_strength")), ceiling.tuning.sun_side_bias, "moonlight is weaker than sunlight")
	# Weather.
	l.publish(l.shadow_color, l.mid_color, l.lit_color, l.rim_color, l.light_direction, l.light_color, l.night_mix, 1.0, 1.0, 0.5, 0.9)
	assert_almost_eq(float(layer.get_shader_parameter(&"darkness")), 0.5 + ceiling.tuning.darkness, EPS, "ceiling follows the weather dim")
	skybox.get_cloud_sea().apply_lighting(l)
	assert_almost_eq(float(puff.get_shader_parameter(&"weather_dim")), 0.5, EPS, "puffs follow the weather dim")
	assert_almost_eq(float(puff.get_shader_parameter(&"weather_desaturate")), 0.9, EPS, "puffs follow the weather desaturation")


func test_ceiling_binds_to_the_skybox_when_weather_starts() -> void:
	var skybox: Skybox = _wired_skybox()
	skybox.apply_theme(skybox.theme)
	var ceiling: CloudCeiling = CloudCeiling.new()
	add_child_autofree(ceiling)
	ceiling.set_weather_intensity(&"storm", 1.0)
	ceiling.step(0.1)
	assert_same(ceiling.lighting(), skybox.cloud_lighting(), "ceiling reads the Skybox lighting")


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
