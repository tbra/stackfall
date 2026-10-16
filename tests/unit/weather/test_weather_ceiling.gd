extends GutTest
## /mp0.29: the upper puff layer (the cloud sea's own puffs) stays on; the weather fades
## with rain/snow/storm intensity, the Low preset is cheaper, rain/snow start at the ceiling and the storm sky
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


## The storm sky blend the ceiling has pushed to the Skybox, as the shared cloud lighting publishes it.
func _sky_storm(skybox: Skybox) -> float:
	return (skybox.get_node("CloudSea") as CloudSea).lighting.storm


func test_fades_in_with_rain_and_out_when_it_clears() -> void:
	var skybox: Skybox = _wired_skybox()["skybox"] as Skybox
	var ceiling: CloudCeiling = _presenter.get_node("CloudCeiling") as CloudCeiling
	assert_eq(_sky_storm(skybox), 0.0)
	Events.weather_intensity_changed.emit(&"rain", 0.6)
	_fade(ceiling, ceiling.tuning.fade_in_s + 1.0)
	assert_almost_eq(_sky_storm(skybox), 0.6 * ceiling.tuning.rain_sky_blend, 0.001, "rain uses the storm sky at its lighter blend")
	Events.weather_stopped.emit(&"rain")
	_fade(ceiling, ceiling.tuning.fade_out_s + 1.0)
	assert_eq(_sky_storm(skybox), 0.0)


func test_storm_drives_the_storm_sky_blend() -> void:
	var skybox: Skybox = _wired_skybox()["skybox"] as Skybox
	var ceiling: CloudCeiling = _presenter.get_node("CloudCeiling") as CloudCeiling
	Events.weather_intensity_changed.emit(&"storm", 1.0)
	_fade(ceiling, ceiling.tuning.fade_in_s + 1.0)
	assert_almost_eq(_sky_storm(skybox), ceiling.tuning.storm_sky_blend, 0.001)
	Events.weather_stopped.emit(&"storm")
	_fade(ceiling, ceiling.tuning.fade_out_s + 1.0)
	assert_almost_eq(_sky_storm(skybox), 0.0, 0.0001, "the storm sky is gone once the storm has faded out")


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


func test_upper_layer_is_the_sea_puff_field_and_always_present() -> void:
	Settings.set_graphics_preset(&"high")
	var skybox: Skybox = _wired_skybox()["skybox"] as Skybox
	skybox.apply_theme(skybox.theme)
	var sea: CloudSea = skybox.get_node("CloudSea") as CloudSea
	var upper: MultiMeshInstance3D = _puffs(sea, true)
	assert_not_null(upper)
	assert_true(upper.visible, "clear weather: the upper layer is already there")
	var clear_count: int = upper.multimesh.instance_count
	assert_same(upper.material_override, _puffs(sea, false).material_override, "same shader material")
	assert_same(upper.multimesh.mesh.get_class(), _puffs(sea, false).multimesh.mesh.get_class())
	assert_eq(upper.layers, _puffs(sea, false).layers)
	var ceiling: CloudCeiling = _presenter.get_node("CloudCeiling") as CloudCeiling
	Events.weather_intensity_changed.emit(&"rain", 0.5)
	_fade(ceiling, ceiling.tuning.fade_in_s + 1.0)
	assert_true(upper.visible, "weather never changes presence")
	assert_eq(upper.multimesh.instance_count, clear_count, "constant coverage")
	assert_almost_eq(float(upper.get_instance_shader_parameter(&"floor_on")), 1.0, 0.001)
	assert_null(_puffs(sea, false).get_instance_shader_parameter(&"floor_on"), "sea puffs keep the shader default (0)")
	# The layer sits above the play volume and the rain starts beneath it.
	var tuning: WeatherCeilingTuning = ceiling.tuning
	assert_gte(upper.custom_aabb.position.y, tuning.height_m - tuning.upper_clump_radius_max_m - 0.01)
	assert_gt(tuning.height_m - tuning.spawn_below_ceiling_m, 72.0, "rain spawns above the play volume, below the cloud bases")
	Events.weather_stopped.emit(&"rain")
	_fade(ceiling, ceiling.tuning.fade_out_s + 1.0)
	assert_true(upper.visible)
	sea.configure(skybox.theme, 1.0, skybox.theme.sky_material)
	assert_true(_puffs(sea, true).visible, "a rebuild keeps the layer")


func test_ceiling_clears_the_camera_and_rain_reaches_it() -> void:
	var tuning: WeatherCeilingTuning = CloudCeiling.TUNING
	assert_eq(tuning.ceiling_y(0.0), tuning.height_m)
	assert_eq(tuning.ceiling_y(200.0), 200.0 + tuning.min_clearance_above_camera_m)
	var rain: RainPresentation = (load("res://game/weather/rain_presentation.tscn") as PackedScene).instantiate() as RainPresentation
	add_child_autofree(rain)
	var camera_pos: Vector3 = Vector3(5.0, 30.0, 7.0)
	var center: Vector3 = rain._volume_center(camera_pos)
	var height: float = float(rain._material.get_shader_parameter(&"box_height"))
	var top: float = center.y + height * 0.5
	assert_almost_eq(top, tuning.ceiling_y(camera_pos.y) - tuning.spawn_below_ceiling_m, 0.01)
	assert_gt(height, rain._tuning.area_height_m)


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
	assert_eq(_sky_storm(skybox), 0.0)


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
	var puffs: MultiMeshInstance3D = _puffs(skybox.get_node("CloudSea") as CloudSea, false)
	skybox.set_storm_sky(0.0, storm)
	assert_same(_puffs(skybox.get_node("CloudSea") as CloudSea, false), puffs, "no puff rebuild on restore")
	assert_true(environment.fog_light_color.is_equal_approx(chosen.fog_color))
	assert_almost_eq(environment.fog_density, chosen.fog_density, 0.0001)
	assert_almost_eq(environment.fog_sky_affect, chosen.fog_sky_affect, 0.0001)
	assert_almost_eq(environment.ambient_light_energy, chosen.ambient_energy, 0.0001)
	assert_almost_eq(environment.volumetric_fog_density, chosen.volumetric_fog_density, 0.0001)
	var fog_material: FogMaterial = skybox._fog_volume.material as FogMaterial
	assert_almost_eq(fog_material.density, chosen.fog_density, 0.0001, "fog volume restored")
	var expected: Color = (chosen.cloud_puff_material as ShaderMaterial).get_shader_parameter(&"shadow_color") as Color
	assert_true(((skybox.get_node("CloudSea") as CloudSea).puff_material().get_shader_parameter(&"shadow_color") as Color).is_equal_approx(expected))


func test_rain_snow_and_storm_all_drive_the_shared_overcast() -> void:
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = Environment.new()
	skybox.environment.sky = Sky.new()
	skybox.environment.sky.sky_material = ProceduralSkyMaterial.new()
	skybox.theme = Skybox.load_theme("sunset")
	add_child_autofree(skybox)
	var ceiling: CloudCeiling = _presenter.get_node("CloudCeiling") as CloudCeiling
	var lighting: CloudLighting = (skybox.get_node("CloudSea") as CloudSea).lighting
	var seen: Dictionary = {}
	for weather_id: StringName in [&"rain", &"snow", &"storm"]:
		Events.weather_intensity_changed.emit(weather_id, 1.0)
		_fade(ceiling, ceiling.tuning.fade_in_s + 1.0)
		var expected: float = ceiling.tuning.overcast_for(weather_id, 1.0)
		assert_gt(expected, 0.0, "%s sets overcast" % weather_id)
		assert_almost_eq(lighting.overcast, expected, 0.001, "%s reaches the shared lighting" % weather_id)
		seen[weather_id] = lighting.dim
		Events.weather_stopped.emit(weather_id)
		_fade(ceiling, ceiling.tuning.fade_out_s + 1.0)
		assert_eq(lighting.overcast, 0.0, "clear again")
	assert_lt(float(seen[&"snow"]), 0.0, "snow lifts the clouds (negative dim)")

