extends GutTest
## Bontago-mp0.127: cloud shadow math, config, sun contrast, Low preset gate and the node's
## decal / sun dimming behaviour.

const CONFIG_PATH: String = "res://config/cloud_shadows.tres"


func _config() -> CloudShadowConfig:
	return load(CONFIG_PATH) as CloudShadowConfig


func test_config_drives_a_monotonic_strength_ramp_and_a_real_sun_dim() -> void:
	var config: CloudShadowConfig = _config()
	assert_not_null(config)
	assert_gt(config.full_sun_sin, config.min_sun_sin, "the ramp has a positive width")
	var previous: float = -1.0
	for step: int in range(0, 11):
		var sun_sin: float = float(step) / 10.0
		var value: float = CloudShadowMath.strength(sun_sin, 1.0, config)
		assert_gte(value, previous, "shadows never weaken as the sun climbs")
		assert_lte(value, config.max_strength + 0.0001)
		previous = value
	assert_gt(previous, 0.0, "a high sun casts visible shadows")
	assert_lt(CloudShadowMath.sun_scale(1.0, config), 1.0, "full occlusion dims the sun")


func test_strength_zero_at_night_and_horizon_full_at_noon() -> void:
	var config: CloudShadowConfig = _config()
	assert_eq(CloudShadowMath.strength(0.9, 0.0, config), 0.0, "night")
	assert_eq(CloudShadowMath.strength(0.05, 1.0, config), 0.0, "horizon")
	assert_almost_eq(CloudShadowMath.strength(1.0, 1.0, config), config.max_strength, 0.0001)
	assert_gt(CloudShadowMath.strength(0.3, 1.0, config), 0.0)
	assert_lt(CloudShadowMath.strength(0.3, 1.0, config), config.max_strength)


func test_layer_weights_cross_fade_to_one() -> void:
	for step: int in range(0, 41):
		var time_s: float = float(step) * 0.77
		var total: float = CloudShadowMath.layer_weight(CloudShadowMath.layer_phase(time_s, 30.0, 0)) \
				+ CloudShadowMath.layer_weight(CloudShadowMath.layer_phase(time_s, 30.0, 1))
		assert_almost_eq(total, 1.0, 0.0001)
	assert_eq(CloudShadowMath.layer_weight(0.0), 0.0)
	assert_almost_eq(CloudShadowMath.layer_offset(0.5, 100.0), 0.0, 0.0001)
	assert_almost_eq(CloudShadowMath.layer_offset(1.0, 100.0), 50.0, 0.0001)


func test_wind_dir_is_unit_and_follows_heading() -> void:
	assert_almost_eq(CloudShadowMath.wind_dir(0.0).x, 1.0, 0.0001)
	assert_almost_eq(CloudShadowMath.wind_dir(90.0).y, 1.0, 0.0001)
	assert_almost_eq(CloudShadowMath.wind_dir(37.0).length(), 1.0, 0.0001)


func test_sun_scale_dims_with_occlusion() -> void:
	var config: CloudShadowConfig = _config()
	assert_eq(CloudShadowMath.sun_scale(0.0, config), 1.0)
	assert_almost_eq(CloudShadowMath.sun_scale(1.0, config), 1.0 - config.sun_dim_max, 0.0001)
	assert_almost_eq(CloudShadowMath.sun_scale(5.0, config), 1.0 - config.sun_dim_max, 0.0001, "clamped")


func test_follow_converges_and_is_stable_at_zero_delta() -> void:
	assert_eq(CloudShadowMath.follow(1.0, 0.5, 3.0, 0.0), 1.0)
	var value: float = 1.0
	for i: int in range(120):
		value = CloudShadowMath.follow(value, 0.5, 3.0, 1.0 / 60.0)
	assert_almost_eq(value, 0.5, 0.01)


func test_volume_covers_field_after_sweep() -> void:
	var config: CloudShadowConfig = _config()
	var span: float = CloudShadowMath.span(50.0, config)
	var travel: float = CloudShadowMath.max_travel(50.0, config)
	assert_gte(span * 0.5 - travel * 0.5, 50.0, "field inside box at the sweep extreme")
	assert_gte(CloudShadowMath.span(500.0, config), CloudShadowMath.volume_size(500.0, 0.0, config), "huge field grows the span")
	assert_eq(CloudShadowMath.max_travel(500.0, config), 0.0, "no sweep room on a huge field")


func test_sun_contrast_identity_at_horizon_and_stronger_high() -> void:
	assert_eq(SunContrast.light_scale(0.0, 1.7, 0.6), 1.0)
	assert_eq(SunContrast.ambient_scale(-0.4, 0.7, 0.6), 1.0, "night unchanged")
	assert_almost_eq(SunContrast.light_scale(0.9, 1.7, 0.6), 1.7, 0.0001)
	assert_almost_eq(SunContrast.ambient_scale(0.9, 0.7, 0.6), 0.7, 0.0001)
	assert_lt(SunContrast.light_scale(0.15, 1.7, 0.6), SunContrast.light_scale(0.5, 1.7, 0.6), "dusk softer")


func test_theme_defaults_boost_sun_over_ambient() -> void:
	var theme: SkyThemeDef = Skybox.load_theme("sunset")
	var high_sun: float = 1.0
	assert_gt(SunContrast.light_scale(high_sun, theme.cycle_sun_energy_gain, theme.cycle_sun_contrast_full_sin), 1.0,
		"the day sun is brighter than the base light")
	assert_lt(SunContrast.ambient_scale(high_sun, theme.cycle_day_ambient_scale, theme.cycle_sun_contrast_full_sin), 1.0,
		"the day ambient is dimmer than the base, so shadows read")


func test_low_preset_disables_cloud_shadows() -> void:
	var low: GraphicsPreset = load("res://config/graphics_presets/low.tres") as GraphicsPreset
	var high: GraphicsPreset = load("res://config/graphics_presets/high.tres") as GraphicsPreset
	assert_false(low.cloud_shadows_enabled)
	assert_true(high.cloud_shadows_enabled)


func test_decals_do_not_touch_cloud_puffs_or_disc() -> void:
	# Bontago-mp0.136: the decal box covers the cloud sea; it must skip the puff render layer.
	var node: CloudShadows = CloudShadows.new()
	add_child_autofree(node)
	for decal: Decal in node.decals():
		assert_eq(decal.cull_mask & CloudSea.RENDER_LAYER_BIT, 0, "puff layer excluded")
		assert_eq(decal.cull_mask & TerritoryOverlay.DISC_LAYER_BIT, 0, "disc layer excluded")
		assert_ne(decal.cull_mask & 1, 0, "default layer (blocks) still shadowed")


func test_node_shows_decals_by_day_and_hides_at_night_and_low() -> void:
	var node: CloudShadows = CloudShadows.new()
	add_child_autofree(node)
	assert_eq(node.decals().size(), 2)
	var noon: Vector3 = Vector3(0.3, 0.9, 0.2).normalized()
	node.step(0.016, noon, 1.0, 1.3)
	var visible_count: int = 0
	for decal: Decal in node.decals():
		if decal.visible:
			visible_count += 1
			assert_gt(decal.modulate.a, 0.0)
			assert_lte(decal.modulate.a, node.config.max_strength + 0.0001)
	assert_gt(visible_count, 0, "a layer is visible at noon")
	node.step(0.016, Vector3(0.3, 0.9, 0.2).normalized(), 0.0, 1.3)
	for decal: Decal in node.decals():
		assert_false(decal.visible, "night")
	node.step(0.016, noon, 1.0, 1.3)
	node._on_graphics_preset_changed(load("res://config/graphics_presets/low.tres") as GraphicsPreset)
	assert_false(node.is_enabled())
	for decal: Decal in node.decals():
		assert_false(decal.visible, "Low preset")
	node._on_graphics_preset_changed(null)


func test_skybox_cloud_scale_dims_light_and_resets() -> void:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	var light: DirectionalLight3D = DirectionalLight3D.new()
	add_child_autofree(light)
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = Skybox.load_theme("sunset")
	add_child_autofree(skybox)
	skybox.light_path = skybox.get_path_to(light)
	var match_config: MatchConfig = MatchConfig.new()
	match_config.resolve_sky_theme(0)
	skybox.configure_match_sky(match_config)
	skybox.set_cycle_phase(0.25)
	var clear: float = light.light_energy
	assert_gt(clear, 0.0)
	skybox.set_sun_cloud_scale(0.5)
	assert_almost_eq(light.light_energy, clear * 0.5, 0.0001)
	skybox.set_sun_cloud_scale(1.0)
	assert_almost_eq(light.light_energy, clear, 0.0001)


func test_low_preset_builds_no_decals_until_enabled() -> void:
	var fresh: CloudShadows = CloudShadows.new()
	add_child_autofree(fresh)
	for decal: Decal in fresh.decals():
		decal.free()
	fresh._decals.clear()
	fresh._on_graphics_preset_changed(load("res://config/graphics_presets/low.tres") as GraphicsPreset)
	assert_false(fresh.is_enabled())
	fresh._on_graphics_preset_changed(load("res://config/graphics_presets/high.tres") as GraphicsPreset)
	assert_eq(fresh.decals().size(), 2, "built lazily when enabled")
