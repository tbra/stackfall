extends GutTest
## the sea and the upper puff layer take one shared
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


## The live puff instance of a CloudSea layer (`upper` picks the overcast layer; `far` its impostor twin):
## a child of the sea told apart by its per-instance shader flags (a rebuild renames nodes), skipping
## instances a rebuild has queued for deletion.
func _puffs(sea: CloudSea, upper: bool, far: bool = false) -> MultiMeshInstance3D:
	for child: Node in sea.get_children():
		if not child is MultiMeshInstance3D or child.is_queued_for_deletion():
			continue
		var node: MultiMeshInstance3D = child as MultiMeshInstance3D
		if (node.get_instance_shader_parameter(&"floor_on") != null) == upper \
				and (node.get_instance_shader_parameter(&"billboard") != null) == far:
			return node
	return null


## The puff material equals the shared state, and the upper layer draws with it.
func _assert_layers_match(skybox: Skybox, label: String) -> void:
	var l: CloudLighting = skybox.cloud_lighting()
	var sea: CloudSea = skybox.get_node("CloudSea") as CloudSea
	var puff: ShaderMaterial = sea.puff_material()
	assert_true((puff.get_shader_parameter(&"light_direction") as Vector3).normalized().is_equal_approx(l.light_direction), "%s puff light" % label)
	assert_true((puff.get_shader_parameter(&"lit_color") as Color).is_equal_approx(l.lit_color), "%s puff palette" % label)
	assert_almost_eq(float(puff.get_shader_parameter(&"weather_dim")), l.dim, EPS, "%s puff dim" % label)
	assert_almost_eq(float(puff.get_shader_parameter(&"weather_desaturate")), l.desaturate, EPS, "%s puff desaturate" % label)
	assert_not_null(_puffs(sea, true), "%s upper layer exists" % label)
	assert_same(_puffs(sea, true).material_override, puff, "%s upper layer shares the puff material" % label)
	assert_same(_puffs(sea, false).material_override, puff, "%s sea uses it too" % label)
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


## One sun term, as the player sees it: its share of the clear-weather strength.
func _sun_shares(skybox: Skybox, clear_glow: float, clear_ray: float) -> Dictionary:
	var sky: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
	var scale: float = float(sky.get_shader_parameter(&"sun_effect_scale"))
	var flare: SunFlare = get_tree().get_nodes_in_group(SunFlare.GROUP)[0] as SunFlare
	return {
		&"glow": float(sky.get_shader_parameter(&"proc_sun_glow_strength")) / clear_glow,
		&"halo": float(sky.get_shader_parameter(&"sun_halo_intensity")) * scale,
		&"core": float(sky.get_shader_parameter(&"sun_core_intensity")) * scale,
		&"rays": float(sky.get_shader_parameter(&"ray_intensity")) * scale / clear_ray,
		&"rays_absolute": float(sky.get_shader_parameter(&"ray_intensity")) * scale,
		&"flare": flare._weather_scale if flare._theme_enabled else 0.0,
	}


## The effective sun terms on the live sky material and flare at storm 0.3 / 0.6 / 1 with
## overcast 1, in the running cycle, a locked phase and a static theme: none of the halo,
## rays or flare may exceed the disc glow, and all are 0 once the disc is gone.
func test_every_sun_term_fades_with_the_disc_in_storm() -> void:
	var storm_theme: SkyThemeDef = Skybox.load_theme("storm")
	for mode: String in ["cycle", "locked_dawn", "static"]:
		var skybox: Skybox = _wired_skybox()
		var flare: SunFlare = SunFlare.new()
		add_child_autofree(flare)
		if mode == "static":
			skybox.apply_theme(skybox.theme)
		else:
			var config: MatchConfig = MatchConfig.new()
			config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE if mode == "cycle" else MatchConfig.SkyThemeMode.DAWN
			skybox.configure_match_sky(config)
			if mode == "cycle":
				skybox.set_cycle_phase(0.2)
		var sky: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
		var clear_glow: float = float(sky.get_shader_parameter(&"proc_sun_glow_strength"))
		var clear_ray: float = float(sky.get_shader_parameter(&"ray_intensity"))
		assert_gt(clear_glow, 0.0, "%s: fixture has a sun glow to fade" % mode)
		assert_gt(clear_ray, 0.0, "%s: fixture has god rays to fade" % mode)
		var baseline: Dictionary = _sun_shares(skybox, clear_glow, clear_ray)
		skybox.set_weather_cloud_overcast(1.0)
		for storm: float in [0.3, 0.6, 1.0]:
			skybox.set_storm_sky(storm, storm_theme)
			var shares: Dictionary = _sun_shares(skybox, clear_glow, clear_ray)
			var label: String = "%s storm %s" % [mode, storm]
			for term: StringName in [&"halo", &"core", &"rays", &"flare"]:
				assert_lte(float(shares[term]), float(shares[&"glow"]) + EPS, "%s: %s never outlives the sun glow" % [label, term])
			if storm >= 1.0:
				assert_almost_eq(float(shares[&"glow"]), 0.0, EPS, "%s: the sun glow is gone" % label)
				assert_eq(float(shares[&"rays_absolute"]), 0.0, "%s: no rays left under a hidden sun" % label)
				assert_eq(float(shares[&"flare"]), 0.0, "%s: no flare" % label)
		skybox.set_storm_sky(0.0, storm_theme)
		skybox.set_weather_cloud_overcast(0.0)
		var cleared: Dictionary = _sun_shares(skybox, clear_glow, clear_ray)
		for term: StringName in [&"glow", &"rays", &"flare"]:
			assert_almost_eq(float(cleared[term]), float(baseline[term]), EPS, "%s: clearing the weather restores the %s unchanged" % [mode, term])
