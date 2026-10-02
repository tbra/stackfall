extends GutTest
## Bontago-mp0.19: cloud ceiling fades with rain/snow/storm intensity, the
## Low preset is cheaper, rain/snow start at the ceiling and the storm sky
## blends in and restores the match theme.

var _presenter: WeatherPresenter = null


func before_each() -> void:
	_presenter = WeatherPresenter.new()
	add_child_autofree(_presenter)


func after_each() -> void:
	Settings.set_graphics_preset(&"high")


func _fade(ceiling: CloudCeiling, seconds: float) -> void:
	for _i: int in range(int(seconds * 10.0)):
		ceiling.step(0.1)


func test_fades_in_with_rain_and_out_when_it_clears() -> void:
	var ceiling: CloudCeiling = _presenter.cloud_ceiling()
	assert_false(ceiling.visible)
	Events.weather_intensity_changed.emit(&"rain", 0.6)
	_fade(ceiling, ceiling.tuning.fade_in_s + 1.0)
	assert_almost_eq(ceiling.amount(), 0.6, 0.001)
	assert_true(ceiling.visible)
	assert_eq(ceiling.storm_amount(), 0.0, "rain never touches the sky theme")
	Events.weather_stopped.emit(&"rain")
	_fade(ceiling, ceiling.tuning.fade_out_s + 1.0)
	assert_eq(ceiling.amount(), 0.0)
	assert_false(ceiling.visible)


func test_changing_transition_follows_the_strongest_weather() -> void:
	var ceiling: CloudCeiling = _presenter.cloud_ceiling()
	Events.weather_intensity_changed.emit(&"snow", 0.3)
	Events.weather_intensity_changed.emit(&"rain", 0.8)
	assert_almost_eq(ceiling.target_amount(), 0.8, 0.001)
	Events.weather_stopped.emit(&"rain")
	assert_almost_eq(ceiling.target_amount(), 0.3, 0.001)
	Events.weather_intensity_changed.emit(&"fog", 1.0)
	assert_almost_eq(ceiling.target_amount(), 0.3, 0.001, "fog has no ceiling")


func test_storm_drives_the_storm_sky_blend() -> void:
	var ceiling: CloudCeiling = _presenter.cloud_ceiling()
	Events.weather_intensity_changed.emit(&"storm", 1.0)
	_fade(ceiling, ceiling.tuning.fade_in_s + 1.0)
	assert_almost_eq(ceiling.storm_amount(), ceiling.tuning.storm_sky_blend, 0.001)
	Events.weather_stopped.emit(&"storm")
	_fade(ceiling, ceiling.tuning.fade_out_s + 1.0)
	assert_eq(ceiling.storm_amount(), 0.0)


func test_low_preset_uses_fewer_layers() -> void:
	Settings.set_graphics_preset(&"high")
	var high: CloudCeiling = CloudCeiling.new()
	add_child_autofree(high)
	var high_count: int = high.layer_count()
	Settings.set_graphics_preset(&"low")
	var low: CloudCeiling = CloudCeiling.new()
	add_child_autofree(low)
	assert_gt(high_count, low.layer_count())
	assert_eq(high.layer_count(), low.layer_count(), "a live preset change rebuilds")
	assert_eq(low.layer_count(), low.tuning.layer_count_low)
	for layer: Node in high.get_children():
		assert_eq((layer as MeshInstance3D).layers, RainPresentation.RENDER_LAYER_BIT)


func test_ceiling_clears_the_camera_and_rain_reaches_it() -> void:
	var tuning: WeatherCeilingTuning = CloudCeiling.TUNING
	assert_eq(tuning.ceiling_y(0.0), tuning.height_m)
	assert_eq(tuning.ceiling_y(200.0), 200.0 + tuning.min_clearance_above_camera_m)
	var rain: RainPresentation = (load("res://vfx/weather/rain_presentation.tscn") as PackedScene).instantiate() as RainPresentation
	add_child_autofree(rain)
	var camera_pos: Vector3 = Vector3(5.0, 30.0, 7.0)
	var center: Vector3 = rain._volume_center(camera_pos)
	var height: float = float(rain._material.get_shader_parameter(&"box_height"))
	var top: float = center.y + height * 0.5
	assert_almost_eq(top, tuning.ceiling_y(camera_pos.y) - tuning.spawn_below_ceiling_m, 0.01)
	assert_gt(height, rain._tuning.area_height_m)


func test_snow_falls_from_the_ceiling_with_more_lifetime() -> void:
	var snow: SnowPresentation = (load("res://vfx/weather/snow_presentation.tscn") as PackedScene).instantiate() as SnowPresentation
	add_child_autofree(snow)
	var base_lifetime: float = snow.tuning.flake_lifetime_s
	var ceiling: WeatherCeilingTuning = CloudCeiling.TUNING
	snow._apply_fall(ceiling.height_m - 30.0, ceiling.snow_fall_step_m)
	assert_gt(snow.particles().lifetime, base_lifetime)
	var amount: int = snow.particles().amount
	snow._apply_fall(ceiling.height_m - 30.0, ceiling.snow_fall_step_m)
	assert_eq(snow.particles().amount, amount, "quantised: no rewrite while unchanged")


func _wired_skybox() -> Dictionary:
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment: Environment = Environment.new()
	environment.sky = sky
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = Skybox.load_theme("sunset")
	add_child_autofree(skybox)
	return {"skybox": skybox, "environment": environment}


func test_storm_sky_blends_and_restores_the_match_theme() -> void:
	var wired: Dictionary = _wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	var storm: SkyThemeDef = Skybox.load_theme("storm")
	skybox.apply_theme(skybox.theme)
	var base_fog: Color = environment.fog_light_color
	skybox.set_storm_sky(0.5, storm)
	var halfway: Color = environment.fog_light_color
	assert_true(halfway.is_equal_approx(skybox.theme.fog_color.lerp(storm.fog_color, 0.5)))
	skybox.set_storm_sky(1.0, storm)
	assert_true(environment.fog_light_color.is_equal_approx(storm.fog_color))
	skybox.set_storm_sky(0.0, storm)
	assert_eq(environment.fog_light_color, base_fog, "match theme restored exactly")
	assert_eq(skybox.storm_sky_amount(), 0.0)


func _assert_stormed(environment: Environment, storm: SkyThemeDef, label: String) -> void:
	assert_true(environment.fog_light_color.is_equal_approx(storm.fog_color), "%s fog colour" % label)
	assert_almost_eq(environment.ambient_light_energy, storm.ambient_energy, 0.001, "%s ambient" % label)
	assert_almost_eq(environment.volumetric_fog_density, storm.volumetric_fog_density, 0.0001, "%s volumetric fog" % label)


## Review finding 1: in CYCLE mode the per-phase writers must not overwrite the storm.
func test_storm_persists_while_the_cycle_advances() -> void:
	var wired: Dictionary = _wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	var storm: SkyThemeDef = Skybox.load_theme("storm")
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	skybox.set_storm_sky(1.0, storm)
	_assert_stormed(environment, storm, "at start")
	for phase: float in [0.1, 0.2, 0.3, 0.6, 0.8]:
		skybox.set_cycle_phase(phase)
		_assert_stormed(environment, storm, "phase %s" % phase)
	skybox.set_storm_sky(0.0, storm)
	skybox.set_cycle_phase(0.9)
	assert_false(environment.fog_light_color.is_equal_approx(storm.fog_color), "storm gone after it ends")


## Review finding 2: a preset change during a storm keeps the puff tint.
func test_preset_change_keeps_the_storm_puff_tint() -> void:
	var wired: Dictionary = _wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var storm: SkyThemeDef = Skybox.load_theme("storm")
	skybox.set_storm_sky(1.0, storm)
	var expected: Color = (storm.cloud_puff_material as ShaderMaterial).get_shader_parameter(&"shadow_color") as Color
	var material: ShaderMaterial = skybox.get_cloud_sea().puff_material()
	assert_not_null(material)
	assert_true((material.get_shader_parameter(&"shadow_color") as Color).is_equal_approx(expected), "tinted before")
	skybox._on_graphics_preset_changed(Settings.current_graphics_preset())
	material = skybox.get_cloud_sea().puff_material()
	assert_true((material.get_shader_parameter(&"shadow_color") as Color).is_equal_approx(expected), "tinted after the rebuild")


## Review finding 3: restore after a theme switch equals the chosen theme, with
## no birds/puff rebuild and the fog volume included.
func test_storm_end_restores_the_switched_theme_without_a_rebuild() -> void:
	var wired: Dictionary = _wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	var storm: SkyThemeDef = Skybox.load_theme("storm")
	skybox.set_storm_sky(1.0, storm)
	assert_true(skybox.set_theme_by_id("night"))
	var chosen: SkyThemeDef = Skybox.load_theme("night")
	var puffs: MultiMeshInstance3D = skybox.get_cloud_sea().puff_instance()
	skybox.set_storm_sky(0.0, storm)
	assert_same(skybox.get_cloud_sea().puff_instance(), puffs, "no puff rebuild on restore")
	assert_true(environment.fog_light_color.is_equal_approx(chosen.fog_color))
	assert_almost_eq(environment.fog_density, chosen.fog_density, 0.0001)
	assert_almost_eq(environment.fog_sky_affect, chosen.fog_sky_affect, 0.0001)
	assert_almost_eq(environment.ambient_light_energy, chosen.ambient_energy, 0.0001)
	assert_almost_eq(environment.volumetric_fog_density, chosen.volumetric_fog_density, 0.0001)
	var fog_material: FogMaterial = skybox._fog_volume.material as FogMaterial
	assert_almost_eq(fog_material.density, chosen.fog_density, 0.0001, "fog volume restored")
	var expected: Color = (chosen.cloud_puff_material as ShaderMaterial).get_shader_parameter(&"shadow_color") as Color
	assert_true((skybox.get_cloud_sea().puff_material().get_shader_parameter(&"shadow_color") as Color).is_equal_approx(expected))


## Review finding 5: lifting the rain volume keeps the streaks per cubic metre.
func test_rain_density_per_volume_is_unchanged_by_the_taller_volume() -> void:
	var rain: RainPresentation = (load("res://vfx/weather/rain_presentation.tscn") as PackedScene).instantiate() as RainPresentation
	add_child_autofree(rain)
	rain._volume_center(Vector3(0.0, 30.0, 0.0))
	var height: float = float(rain._material.get_shader_parameter(&"box_height"))
	var visible: int = rain.streak_instance().multimesh.visible_instance_count
	var expected: float = float(rain._tuning.streak_count) * rain._preset_scale() / rain._tuning.area_height_m
	assert_gt(height, rain._tuning.area_height_m)
	assert_almost_eq(float(visible) / height, expected, expected * 0.02)


func test_idle_ceiling_skips_the_per_frame_work() -> void:
	var ceiling: CloudCeiling = CloudCeiling.new()
	add_child_autofree(ceiling)
	ceiling.global_position = Vector3(1.0, 2.0, 3.0)
	ceiling._process(0.1)
	assert_eq(ceiling.global_position, Vector3(1.0, 2.0, 3.0), "idle: no placement work")
	assert_false(ceiling.visible)
