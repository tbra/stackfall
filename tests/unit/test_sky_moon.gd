extends GutTest
## Bontago-mp0.122: the moon_v1 disc + halo in the procedural cycle sky.

const MOON_DISC: String = "res://assets/sky/moon_v1/moon_disc.png"


func _cycle_skybox() -> Skybox:
	Settings.set_graphics_preset(&"high")
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = SkyThemeDef.new()
	add_child_autofree(skybox)
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	return skybox


func _sky(skybox: Skybox) -> ShaderMaterial:
	return skybox.environment.sky.sky_material as ShaderMaterial


func _param(skybox: Skybox, name: StringName) -> Variant:
	return _sky(skybox).get_shader_parameter(name)


func test_moon_textures_and_config_uniforms_are_set() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(0.75)
	var disc: Texture2D = _param(skybox, &"moon_disc_tex") as Texture2D
	assert_not_null(disc, "disc texture set")
	assert_eq(disc.resource_path, MOON_DISC)
	assert_not_null(_param(skybox, &"moon_halo_tex"), "halo texture set")
	var def: SkyThemeDef = SkyThemeDef.new()
	assert_almost_eq(_param(skybox, &"moon_angular_radius_deg") as float, def.cycle_moon_angular_radius_deg, 0.0001)
	assert_almost_eq(_param(skybox, &"moon_halo_strength") as float, def.cycle_moon_halo_strength, 0.0001)


func test_moon_opposes_the_sun() -> void:
	var skybox: Skybox = _cycle_skybox()
	for phase: float in [0.1, 0.3, 0.6, 0.75, 0.9]:
		skybox.set_cycle_phase(phase)
		var sun: Vector3 = (_param(skybox, &"sun_direction") as Vector3).normalized()
		var moon: Vector3 = (_param(skybox, &"moon_direction") as Vector3).normalized()
		assert_almost_eq(sun.dot(moon), -1.0, 0.001, "moon opposite the sun at phase %s" % phase)


func test_moon_visibility_follows_time_of_day() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(0.25)
	assert_almost_eq(_param(skybox, &"moon_visibility") as float, 0.0, 0.0001, "hidden at noon")
	skybox.set_cycle_phase(0.75)
	assert_almost_eq(_param(skybox, &"moon_visibility") as float, 1.0, 0.0001, "full at midnight")
	skybox.set_cycle_phase(0.505)
	var dusk: float = _param(skybox, &"moon_visibility") as float
	assert_true(dusk > 0.0 and dusk < 1.0, "fading in at dusk (got %s)" % dusk)
	skybox.set_cycle_phase(0.995)
	var dawn: float = _param(skybox, &"moon_visibility") as float
	assert_true(dawn < 1.0, "fading out toward dawn (got %s)" % dawn)
	skybox.set_cycle_phase(0.05)
	assert_almost_eq(_param(skybox, &"moon_visibility") as float, 0.0, 0.0001, "gone after dawn")


func test_storm_hides_the_moon() -> void:
	var skybox: Skybox = _cycle_skybox()
	skybox.set_cycle_phase(0.75)
	var storm: SkyThemeDef = Skybox.load_theme("storm")
	skybox.set_storm_sky(1.0, storm)
	assert_almost_eq(_param(skybox, &"moon_visibility") as float, 0.0, 0.0001, "full storm hides the moon like the sun")
	skybox.set_storm_sky(0.0, null)
	assert_almost_eq(_param(skybox, &"moon_visibility") as float, 1.0, 0.0001, "clear again")


func test_locked_night_shows_the_moon() -> void:
	Settings.set_graphics_preset(&"high")
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = SkyThemeDef.new()
	add_child_autofree(skybox)
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.NIGHT
	config.resolve_sky_theme(0)
	skybox.configure_match_sky(config)
	assert_almost_eq(_param(skybox, &"moon_visibility") as float, 1.0, 0.0001)
