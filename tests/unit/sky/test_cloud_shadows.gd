extends GutTest
## cloud shadow math, config, sun contrast, Low preset gate and the node's
## decal / sun dimming behaviour.

const CONFIG_PATH: String = "res://config/sky/cloud_shadows.tres"


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


func _decals(node: CloudShadows) -> Array[Decal]:
	var result: Array[Decal] = []
	for child: Node in node.get_children():
		if child is Decal:
			result.append(child as Decal)
	return result


func test_low_preset_disables_cloud_shadows() -> void:
	var low: GraphicsPreset = load("res://config/graphics/presets/low.tres") as GraphicsPreset
	var high: GraphicsPreset = load("res://config/graphics/presets/high.tres") as GraphicsPreset
	assert_false(low.cloud_shadows_enabled)
	assert_true(high.cloud_shadows_enabled)


func test_node_shows_decals_by_day_and_hides_at_night_and_low() -> void:
	var node: CloudShadows = CloudShadows.new()
	add_child_autofree(node)
	assert_eq(_decals(node).size(), 2)
	var noon: Vector3 = Vector3(0.3, 0.9, 0.2).normalized()
	node.step(0.016, noon, 1.0, 1.3)
	var visible_count: int = 0
	for decal: Decal in _decals(node):
		if decal.visible:
			visible_count += 1
			assert_gt(decal.modulate.a, 0.0)
			assert_lte(decal.modulate.a, node.config.max_strength + 0.0001)
	assert_gt(visible_count, 0, "a layer is visible at noon")
	node.step(0.016, Vector3(0.3, 0.9, 0.2).normalized(), 0.0, 1.3)
	for decal: Decal in _decals(node):
		assert_false(decal.visible, "night")
	node.step(0.016, noon, 1.0, 1.3)
	node._on_graphics_preset_changed(load("res://config/graphics/presets/low.tres") as GraphicsPreset)
	for decal: Decal in _decals(node):
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
	add_child_autofree(skybox)
	skybox.light_path = skybox.get_path_to(light)
	var match_config: MatchConfig = MatchConfig.new()
	match_config.resolve_sky_theme(0)
	skybox.configure_match_sky(match_config)
	skybox.set_cycle_phase(0.25)
	var clear: float = light.light_energy
	assert_gt(clear, 0.0)
	skybox.set_sun_cloud_scale(0.5)
	skybox.flush_weather()
	assert_almost_eq(light.light_energy, clear * 0.5, 0.0001)
	skybox.set_sun_cloud_scale(1.0)
	skybox.flush_weather()
	assert_almost_eq(light.light_energy, clear, 0.0001)

