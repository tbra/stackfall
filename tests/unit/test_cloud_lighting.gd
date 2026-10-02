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
