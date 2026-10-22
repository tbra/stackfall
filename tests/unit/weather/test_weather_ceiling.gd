extends GutTest
## /mp0.29: the upper puff layer (the cloud sea's own puffs) stays on; the weather fades
## with rain/snow/storm intensity, the Low preset is cheaper, rain/snow start at the ceiling and the storm sky
## blends in and restores the match sky.

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
	SkyTestKit.settle(skybox)
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
	skybox.refresh_sky_def()
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
	sea.configure_cycle(skybox.sky_def, SkyEvaluator.evaluate_tick(skybox.sky_def, skybox.current_cycle_phase(), skybox.variation_seed(), 0, true), 1.0)
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
	add_child_autofree(skybox)
	return {"skybox": skybox, "environment": environment}


func test_storm_sky_blends_and_restores_the_match_sky() -> void:
	var wired: Dictionary = _wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	var storm: SkyOverlayDef = load("res://config/sky/storm_overlay.tres") as SkyOverlayDef
	skybox.refresh_sky_def()
	var base_fog: Color = environment.fog_light_color
	skybox.set_storm_sky(0.5, storm)
	SkyTestKit.settle(skybox)
	var halfway: Color = environment.fog_light_color
	assert_true(halfway.is_equal_approx(base_fog.lerp(storm.fog_color, 0.5)))
	skybox.set_storm_sky(1.0, storm)
	SkyTestKit.settle(skybox)
	assert_true(environment.fog_light_color.is_equal_approx(storm.fog_color))
	skybox.set_storm_sky(0.0, storm)
	SkyTestKit.settle(skybox)
	assert_eq(environment.fog_light_color, base_fog, "match sky restored exactly")
	assert_eq(_sky_storm(skybox), 0.0)


## Scenery haze under a storm: the overlay carries no haze distances, so strength/begin/end stay the
## cycle's and only the haze tint follows the storm fog colour blend.
func test_storm_haze_keeps_distances_and_blends_the_tint() -> void:
	var wired: Dictionary = _wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var storm: SkyOverlayDef = load("res://config/sky/storm_overlay.tres") as SkyOverlayDef
	skybox.refresh_sky_def()
	SkyTestKit.settle(skybox)
	var strength: float = WeatherFogShader.ambient_strength
	var begin: float = WeatherFogShader.ambient_begin_m
	var finish: float = WeatherFogShader.ambient_end_m
	var base_tint: Color = WeatherFogShader.ambient_color
	skybox.set_storm_sky(0.5, storm)
	SkyTestKit.settle(skybox)
	assert_almost_eq(WeatherFogShader.ambient_strength, strength, 0.0001, "storm 0.5 strength")
	assert_almost_eq(WeatherFogShader.ambient_begin_m, begin, 0.0001, "storm 0.5 begin")
	assert_almost_eq(WeatherFogShader.ambient_end_m, finish, 0.0001, "storm 0.5 end")
	assert_true(WeatherFogShader.ambient_color.is_equal_approx(base_tint.lerp(storm.fog_color, 0.5)), "storm 0.5 tint")
	skybox.set_storm_sky(1.0, storm)
	SkyTestKit.settle(skybox)
	assert_almost_eq(WeatherFogShader.ambient_strength, strength, 0.0001, "storm 1.0 strength")
	assert_almost_eq(WeatherFogShader.ambient_end_m, finish, 0.0001, "storm 1.0 end")
	assert_true(WeatherFogShader.ambient_color.is_equal_approx(storm.fog_color), "storm 1.0 tint")
	skybox.set_storm_sky(0.0, storm)
	SkyTestKit.settle(skybox)
	assert_true(WeatherFogShader.ambient_color.is_equal_approx(base_tint), "storm over: tint restored")


## Review finding 3: the storm ending after a sky switch restores that sky's own values, with no
## birds/puff rebuild and the fog volume included.
func test_storm_end_restores_the_switched_sky_without_a_rebuild() -> void:
	var wired: Dictionary = _wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	var storm: SkyOverlayDef = load("res://config/sky/storm_overlay.tres") as SkyOverlayDef
	skybox.set_storm_sky(1.0, storm)
	skybox.set_locked_phase(SkyTestKit.locked_phase("night"))
	skybox.set_storm_sky(0.0, storm)
	SkyTestKit.settle(skybox)
	var chosen_fog_color: Color = environment.fog_light_color
	var chosen_fog_density: float = environment.fog_density
	var chosen_fog_sky_affect: float = environment.fog_sky_affect
	var chosen_ambient_energy: float = environment.ambient_light_energy
	var chosen_volumetric_density: float = environment.volumetric_fog_density
	var chosen_shadow_color: Color = SkyTestKit.puff_material(skybox.get_node("CloudSea") as CloudSea).get_shader_parameter(&"shadow_color") as Color
	var puffs: MultiMeshInstance3D = _puffs(skybox.get_node("CloudSea") as CloudSea, false)
	skybox.set_storm_sky(1.0, storm)
	skybox.set_storm_sky(0.0, storm)
	SkyTestKit.settle(skybox)
	assert_same(_puffs(skybox.get_node("CloudSea") as CloudSea, false), puffs, "no puff rebuild on restore")
	assert_true(environment.fog_light_color.is_equal_approx(chosen_fog_color))
	assert_almost_eq(environment.fog_density, chosen_fog_density, 0.0001)
	assert_almost_eq(environment.fog_sky_affect, chosen_fog_sky_affect, 0.0001)
	assert_almost_eq(environment.ambient_light_energy, chosen_ambient_energy, 0.0001)
	assert_almost_eq(environment.volumetric_fog_density, chosen_volumetric_density, 0.0001)
	var fog_material: FogMaterial = skybox._fog_volume.material as FogMaterial
	assert_almost_eq(fog_material.density, chosen_fog_density, 0.0001, "fog volume restored")
	assert_true((SkyTestKit.puff_material(skybox.get_node("CloudSea") as CloudSea).get_shader_parameter(&"shadow_color") as Color).is_equal_approx(chosen_shadow_color))


func test_rain_snow_and_storm_all_drive_the_shared_overcast() -> void:
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = Environment.new()
	skybox.environment.sky = Sky.new()
	skybox.environment.sky.sky_material = ProceduralSkyMaterial.new()
	add_child_autofree(skybox)
	var ceiling: CloudCeiling = _presenter.get_node("CloudCeiling") as CloudCeiling
	var lighting: CloudLighting = (skybox.get_node("CloudSea") as CloudSea).lighting
	var seen: Dictionary = {}
	for weather_id: StringName in [&"rain", &"snow", &"storm"]:
		Events.weather_intensity_changed.emit(weather_id, 1.0)
		_fade(ceiling, ceiling.tuning.fade_in_s + 1.0)
		var expected: float = ceiling.tuning.overcast_for(weather_id, 1.0)
		assert_gt(expected, 0.0, "%s sets overcast" % weather_id)
		SkyTestKit.settle(skybox)
		assert_almost_eq(lighting.overcast, expected, 0.001, "%s reaches the shared lighting" % weather_id)
		seen[weather_id] = lighting.dim
		Events.weather_stopped.emit(weather_id)
		_fade(ceiling, ceiling.tuning.fade_out_s + 1.0)
		SkyTestKit.settle(skybox)
		assert_eq(lighting.overcast, 0.0, "clear again")
	assert_lt(float(seen[&"snow"]), 0.0, "snow lifts the clouds (negative dim)")

