extends GutTest
## Bontago-mp0.19/mp0.29: the upper puff layer (the cloud sea's own puffs) stays on; the weather fades
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


func test_fades_in_with_rain_and_out_when_it_clears() -> void:
	var ceiling: CloudCeiling = _presenter.cloud_ceiling()
	assert_eq(ceiling.amount(), 0.0)
	Events.weather_intensity_changed.emit(&"rain", 0.6)
	_fade(ceiling, ceiling.tuning.fade_in_s + 1.0)
	assert_almost_eq(ceiling.amount(), 0.6, 0.001)
	assert_eq(ceiling.storm_amount(), 0.0, "rain never touches the sky theme")
	Events.weather_stopped.emit(&"rain")
	_fade(ceiling, ceiling.tuning.fade_out_s + 1.0)
	assert_eq(ceiling.amount(), 0.0)


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


func _upper_count(preset: StringName) -> int:
	Settings.set_graphics_preset(preset)
	var skybox: Skybox = _wired_skybox()["skybox"] as Skybox
	skybox.apply_theme(skybox.theme)
	return skybox.get_cloud_sea().upper_puff_count()


func test_low_preset_uses_fewer_upper_puffs() -> void:
	var high: int = _upper_count(&"high")
	var low: int = _upper_count(&"low")
	assert_gt(low, 0)
	assert_gt(high, low)


func test_upper_layer_is_the_sea_puff_field_and_always_present() -> void:
	Settings.set_graphics_preset(&"high")
	var skybox: Skybox = _wired_skybox()["skybox"] as Skybox
	skybox.apply_theme(skybox.theme)
	var sea: CloudSea = skybox.get_cloud_sea()
	var upper: MultiMeshInstance3D = sea.upper_instance()
	assert_not_null(upper)
	assert_true(upper.visible, "clear weather: the upper layer is already there")
	var clear_count: int = upper.multimesh.instance_count
	assert_same(upper.material_override, sea.puff_instance().material_override, "same shader material")
	assert_same(upper.multimesh.mesh.get_class(), sea.puff_instance().multimesh.mesh.get_class())
	assert_eq(upper.layers, sea.puff_instance().layers)
	var ceiling: CloudCeiling = _presenter.cloud_ceiling()
	Events.weather_intensity_changed.emit(&"rain", 0.5)
	_fade(ceiling, ceiling.tuning.fade_in_s + 1.0)
	assert_true(upper.visible, "weather never changes presence")
	assert_eq(upper.multimesh.instance_count, clear_count, "constant coverage")
	assert_almost_eq(float(upper.get_instance_shader_parameter(&"floor_on")), 1.0, 0.001)
	assert_null(sea.puff_instance().get_instance_shader_parameter(&"floor_on"), "sea puffs keep the shader default (0)")
	# The layer sits above the play volume and the rain starts beneath it.
	var tuning: WeatherCeilingTuning = ceiling.tuning
	assert_gte(upper.custom_aabb.position.y, tuning.height_m - tuning.upper_clump_radius_max_m - 0.01)
	assert_gt(tuning.height_m - tuning.spawn_below_ceiling_m, 72.0, "rain spawns above the play volume, below the cloud bases")
	Events.weather_stopped.emit(&"rain")
	_fade(ceiling, ceiling.tuning.fade_out_s + 1.0)
	assert_true(upper.visible)
	sea.configure(skybox.theme, 1.0, skybox.theme.sky_material)
	assert_true(sea.upper_instance().visible, "a rebuild keeps the layer")


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


## Bontago-mp0.26: in CYCLE a partial storm tints from the cycle-mixed colours.
func test_partial_storm_tints_from_the_night_mixed_puffs_in_cycle() -> void:
	var wired: Dictionary = _wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var storm: SkyThemeDef = Skybox.load_theme("storm")
	var day: SkyThemeDef = Skybox.load_theme(MatchConfig.SKY_THEME_IDS[MatchConfig.SkyThemeMode.DAY])
	var night: SkyThemeDef = Skybox.load_theme("night")
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	var amount: float = 0.5
	var day_base: Color = (day.cloud_puff_material as ShaderMaterial).get_shader_parameter(&"mid_color") as Color
	var night_base: Color = (night.cloud_puff_material as ShaderMaterial).get_shader_parameter(&"mid_color") as Color
	var storm_color: Color = (storm.cloud_puff_material as ShaderMaterial).get_shader_parameter(&"mid_color") as Color
	skybox.set_storm_sky(amount, storm)
	skybox.set_cycle_phase(0.75)
	var material: ShaderMaterial = skybox.get_cloud_sea().puff_material()
	assert_not_null(material)
	var night_tint: Color = material.get_shader_parameter(&"mid_color") as Color
	assert_true(night_tint.is_equal_approx(night_base.lerp(storm_color, amount)), "night tint lerps from the night colours")
	assert_lt(_color_distance(night_tint, night_base), _color_distance(night_tint, day_base), "closer to night than day")
	skybox.set_cycle_phase(0.25)
	var day_tint: Color = material.get_shader_parameter(&"mid_color") as Color
	assert_true(day_tint.is_equal_approx(day_base.lerp(storm_color, amount)), "day phase unchanged")


func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


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
	ceiling._process(0.1)
	assert_eq(ceiling.amount(), 0.0)
	assert_eq(ceiling.overcast(), 0.0)


func test_changing_weather_fades_the_ceiling_with_the_new_intensity() -> void:
	var ceiling: CloudCeiling = _presenter.cloud_ceiling()
	Events.weather_intensity_changed.emit(&"rain", 0.8)
	_fade(ceiling, ceiling.tuning.fade_in_s + 1.0)
	Events.weather_stopped.emit(&"rain")
	Events.weather_intensity_changed.emit(&"snow", 0.4)
	_fade(ceiling, ceiling.tuning.fade_out_s + 1.0)
	assert_almost_eq(ceiling.amount(), 0.4, 0.001, "settles on the incoming weather, never full")
	Events.weather_stopped.emit(&"snow")
	_fade(ceiling, ceiling.tuning.fade_out_s + 1.0)
	assert_eq(ceiling.amount(), 0.0)


func test_rain_snow_and_storm_all_drive_the_shared_overcast() -> void:
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = Environment.new()
	skybox.environment.sky = Sky.new()
	skybox.environment.sky.sky_material = ProceduralSkyMaterial.new()
	skybox.theme = Skybox.load_theme("sunset")
	add_child_autofree(skybox)
	var ceiling: CloudCeiling = _presenter.cloud_ceiling()
	var seen: Dictionary = {}
	for weather_id: StringName in [&"rain", &"snow", &"storm"]:
		Events.weather_intensity_changed.emit(weather_id, 1.0)
		_fade(ceiling, ceiling.tuning.fade_in_s + 1.0)
		var expected: float = ceiling.tuning.overcast_for(weather_id, 1.0)
		assert_gt(expected, 0.0, "%s sets overcast" % weather_id)
		assert_almost_eq(ceiling.overcast(), expected, 0.001)
		assert_almost_eq(skybox.cloud_lighting().overcast, expected, 0.001, "%s reaches the shared lighting" % weather_id)
		seen[weather_id] = skybox.cloud_lighting().dim
		Events.weather_stopped.emit(weather_id)
		_fade(ceiling, ceiling.tuning.fade_out_s + 1.0)
		assert_eq(skybox.cloud_lighting().overcast, 0.0, "clear again")
	assert_gt(float(seen[&"snow"]), 0.0)



## Bontago-mp0.93 (owner playtest "bottom of clouds has some issues"): the upper
## layer is seen from below, where the flat base is the whole visible face. The
## puff shader's base used to keep a radial (side-facing) normal almost
## everywhere and a triplanar dome map with a constant y, so the cel bands cut
## the underside into sun-side wedges and lit slivers, and the coplanar bases of
## a clump z-fought into stripes. A shader cannot be evaluated headless: these
## pin the source that carries the fix (the captures in the Bead show the look).
func _puff_shader_code() -> String:
	var shader: Shader = load("res://shaders/cloud_puffs.gdshader") as Shader
	var code_lines: PackedStringArray = PackedStringArray()
	for line: String in shader.code.split("\n"):
		var stripped: String = line.strip_edges()
		if not stripped.begins_with("//"):
			code_lines.append(line.split("//")[0])
	return "\n".join(code_lines)


func test_puff_base_normal_eases_to_straight_down_inside_the_rim() -> void:
	var code: String = _puff_shader_code()
	assert_true(code.contains("n = normalize(mix(vec3(0.0, -1.0, 0.0), n, base_ramp));"),
		"base fragments face down in the middle and join the side normal at the rim")
	assert_false(code.contains("rim_ratio"), "the old |xz|/|unit| ratio left the base radial almost everywhere")
	assert_true(code.contains("base_ramp = smoothstep(min(base_rim_start, 0.99), 1.0, sqrt(base_sq) / max(radius, 0.0001));"),
		"the ramp is measured against the lumpy rim radius, so base and sides meet without a step")
	assert_true(code.contains("shade += base_bounce * (1.0 - base_ramp);"), "the underbelly's soft lift fades out at the rim")
	assert_true(code.contains("float base_ramp = 1.0;"), "every non-base fragment keeps the side shading unchanged")


func test_puff_base_uses_a_top_down_dome_map_and_staggered_planes() -> void:
	var code: String = _puff_shader_code()
	assert_true(code.contains("vec2 top_down = mix(under_xz, u.xz, to_sides);"), "base noise is sampled over the base's own plane")
	assert_true(code.contains("w = mix(vec3(0.0, 1.0, 0.0), w, to_sides);"), "triplanar weights move to the top-down map on the base")
	assert_true(code.contains("lumps(unit_dir, puff_seed, t_boil, 1.0, base_ramp, unit.xz)"), "shading domes pass the base ramp")
	assert_true(code.contains("VERTEX.y += base_stagger_m * INSTANCE_CUSTOM.y / TAU;"), "coplanar bases of one clump are staggered")
	for silhouette_call: String in ["lumps(dir, puff_seed, t_boil, lump_vertex_scale, 1.0, dir.xz)"]:
		assert_true(code.contains(silhouette_call), "the silhouette radius keeps the plain triplanar map (side and base share one rim)")


func test_puff_base_uniform_defaults() -> void:
	var code: String = _puff_shader_code()
	assert_true(code.contains("uniform float base_rim_start = 0.55;"))
	assert_true(code.contains("uniform float base_bounce = 0.5;"))
	assert_true(code.contains("uniform float base_stagger_m = 0.4;"))


func test_upper_layer_draws_with_the_shader_that_carries_the_base_fix() -> void:
	Settings.set_graphics_preset(&"high")
	var skybox: Skybox = _wired_skybox()["skybox"] as Skybox
	skybox.apply_theme(skybox.theme)
	var sea: CloudSea = skybox.get_cloud_sea()
	var material: ShaderMaterial = sea.upper_instance().material_override as ShaderMaterial
	assert_not_null(material)
	assert_eq(material.shader.resource_path, "res://shaders/cloud_puffs.gdshader")
	assert_true(material.shader.code.contains("base_bounce"), "the upper puffs share the underside shading")
