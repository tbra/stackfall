extends GutTest
## Bontago-1pi.46 R1 (docs/MATCH_RESET_AUDIT.md G1, G2 and weather-fog parity): the
## sky and weather presentation owners return to what a fresh launch has when
## Events.match_scope_reset fires, so a match never starts under the previous one's
## night / cycle / storm / overcast sky or its fading ceiling.

const SUNSET_PATH: String = "res://config/sky_themes/sunset.tres"
const NIGHT_PATH: String = "res://config/sky_themes/night.tres"
const STORM_ID: StringName = &"storm"
const RAIN_ID: StringName = &"rain"
const FOG_ID: StringName = &"fog"
## The overcast / fog numbers a presentation would feed in; any non-zero request works.
const OVERCAST_LIGHT_SCALE: float = 0.5
const OVERCAST_AMBIENT_SCALE: float = 0.6
const OVERCAST_EXPOSURE_SCALE: float = 0.7
const OVERCAST_FOG_TINT: Color = Color(0.4, 0.4, 0.5)
const OVERCAST_FOG_STRENGTH: float = 0.5
const STORM_AMOUNT: float = 0.8
const WFOG_OPACITY: float = 0.6
const WFOG_BEGIN_M: float = 30.0
const WFOG_END_M: float = 120.0
const WFOG_TINT: Color = Color(0.7, 0.8, 0.9)
const WFOG_TINT_STRENGTH: float = 0.5
const WFOG_SKY_AFFECT: float = 0.3


func after_each() -> void:
	# The real WeatherNet presenter (an autoload) hears the weather signals these tests
	# emit; stop what they started, then reset it, the shared fog statics and any live
	# skybox so nothing leaks into the next test.
	for weather_id: StringName in [RAIN_ID, FOG_ID, STORM_ID]:
		Events.weather_stopped.emit(weather_id)
	Events.match_scope_reset.emit()


## A Skybox wired like Main's: own Environment/Sky/light/config (no shared state
## between rigs apart from the shipped theme resources), launching on static sunset
## unless `launch_theme_name` is "cycle".
func _rig(launch_theme_name: String = "") -> Dictionary:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	var light: DirectionalLight3D = DirectionalLight3D.new()
	add_child_autofree(light)
	var config: SkyboxConfig = SkyboxConfig.new()
	config.theme_name = launch_theme_name
	var skybox: Skybox = Skybox.new()
	skybox.config = config
	skybox.environment = environment
	skybox.theme = load(SUNSET_PATH) as SkyThemeDef
	skybox.light_path = light.get_path()
	add_child_autofree(skybox)
	return {"skybox": skybox, "environment": environment, "light": light}


func _overcast(skybox: Skybox, amount: float) -> void:
	skybox.set_overcast(amount, OVERCAST_LIGHT_SCALE, OVERCAST_AMBIENT_SCALE, OVERCAST_EXPOSURE_SCALE,
		OVERCAST_FOG_TINT, OVERCAST_FOG_STRENGTH)


func _weather_fog(skybox: Skybox, amount: float) -> void:
	skybox.set_weather_fog(amount, WFOG_OPACITY, WFOG_BEGIN_M, WFOG_END_M, WFOG_TINT, WFOG_TINT_STRENGTH, WFOG_SKY_AFFECT)


## Everything a player can see (or that decides it) on a Skybox, plain values.
func _snapshot(rig: Dictionary) -> Dictionary:
	var skybox: Skybox = rig["skybox"] as Skybox
	var environment: Environment = rig["environment"] as Environment
	var light: DirectionalLight3D = rig["light"] as DirectionalLight3D
	var sky_material: ShaderMaterial = environment.sky.sky_material as ShaderMaterial
	var lighting: CloudLighting = skybox.cloud_lighting()
	var fog_material: FogMaterial = skybox.get_fog_volume().material as FogMaterial
	return {
		"theme": skybox.theme.resource_path,
		"theme_name": skybox.config.theme_name,
		"set_enabled": skybox.config.enabled,
		"fallback_active": skybox.fallback_active,
		"cycle_active": skybox.is_cycle_active(),
		"locked_phase": skybox.locked_phase(),
		"cycle_phase": skybox.current_cycle_phase(),
		"process_mode": environment.sky.process_mode,
		"storm_amount": skybox.storm_sky_amount(),
		"overcast_amount": skybox.overcast_amount(),
		"cloud_overcast": skybox.cloud_overcast_amount(),
		"wfog_amount": skybox.weather_fog_amount(),
		"sky_is_theme_material": sky_material == skybox.theme.sky_material,
		"sky_exposure": sky_material.get_shader_parameter(&"exposure"),
		"sky_sea_mix": sky_material.get_shader_parameter(&"procedural_sea_mix"),
		"fog_enabled": environment.fog_enabled,
		"fog_mode": environment.fog_mode,
		"fog_density": environment.fog_density,
		"fog_color": environment.fog_light_color,
		"fog_sky_affect": environment.fog_sky_affect,
		"fog_depth_begin": environment.fog_depth_begin,
		"fog_depth_end": environment.fog_depth_end,
		"volumetric_density": environment.volumetric_fog_density,
		"volumetric_albedo": environment.volumetric_fog_albedo,
		"ambient_energy": environment.ambient_light_energy,
		"background_energy": environment.background_energy_multiplier,
		"glow_intensity": environment.glow_intensity,
		"light_basis": light.global_basis,
		"light_energy": light.light_energy,
		"light_color": light.light_color,
		"cloud_night": lighting.night_mix,
		"cloud_overcast_lit": lighting.overcast,
		"cloud_storm": lighting.storm,
		"cloud_dim": lighting.dim,
		"cloud_light_direction": lighting.light_direction,
		"cloud_deck_density": fog_material.density,
		"cloud_deck_albedo": fog_material.albedo,
	}


func _assert_same_snapshot(actual: Dictionary, expected: Dictionary, label: String) -> void:
	for key: Variant in expected.keys():
		var want: Variant = expected[key]
		var got: Variant = actual.get(key)
		var same: bool = false
		if want is float and got is float:
			same = is_equal_approx(want as float, got as float)
		elif want is Color and got is Color:
			same = (want as Color).is_equal_approx(got as Color)
		elif want is Basis and got is Basis:
			same = (want as Basis).is_equal_approx(got as Basis)
		elif want is Vector3 and got is Vector3:
			same = (want as Vector3).is_equal_approx(got as Vector3)
		else:
			same = want == got
		assert_true(same, "%s: %s is %s, a fresh Skybox has %s" % [label, key, got, want])


## The match-A sky the audit worries about: running cycle, then a locked night, then
## storm + overcast + weather fog on top.
func _dirty_with_locked_night_storm(rig: Dictionary) -> void:
	var skybox: Skybox = rig["skybox"] as Skybox
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	skybox.set_locked_phase(skybox.theme.cycle_locked_phase_night)
	skybox.set_storm_sky(STORM_AMOUNT, Skybox.load_theme("storm"))
	_overcast(skybox, 1.0)
	_weather_fog(skybox, 1.0)


# --- Skybox.reset_to_launch() -------------------------------------------------------


func test_a_dirty_sky_resets_to_a_fresh_skybox_for_cycle_locked_and_static_night_storms() -> void:
	var fresh: Dictionary = _rig()
	var expected: Dictionary = _snapshot(fresh)
	var used: Dictionary = _rig()
	var skybox: Skybox = used["skybox"] as Skybox
	_dirty_with_locked_night_storm(used)
	var stormy: Dictionary = _snapshot(used)
	assert_true(skybox.is_cycle_active(), "fixture: the cycle is running")
	assert_almost_eq(skybox.locked_phase(), skybox.theme.cycle_locked_phase_night, 0.0001, "fixture: locked at night")
	assert_gt(skybox.storm_sky_amount(), 0.0, "fixture: storm on")
	assert_gt(skybox.overcast_amount(), 0.0, "fixture: overcast on")
	assert_gt(skybox.weather_fog_amount(), 0.0, "fixture: weather fog on")
	assert_ne(stormy["fog_color"], expected["fog_color"], "fixture: the dirty sky differs from launch")
	skybox.reset_to_launch()
	_assert_same_snapshot(_snapshot(used), expected, "after reset")

	# Merged variant: a static night theme (set_theme_by_id) with storm + overcast.
	var static_used: Dictionary = _rig()
	var static_skybox: Skybox = static_used["skybox"] as Skybox
	var static_config: MatchConfig = MatchConfig.new()
	static_config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	static_skybox.configure_match_sky(static_config)
	assert_true(static_skybox.set_theme_by_id("night"))
	static_skybox.set_storm_sky(STORM_AMOUNT, Skybox.load_theme("storm"))
	_overcast(static_skybox, 1.0)
	assert_eq(static_skybox.config.theme_name, "night", "fixture: set_theme_by_id wrote the shared config")
	static_skybox.reset_to_launch()
	_assert_same_snapshot(_snapshot(static_used), expected, "static night: after reset")
	assert_eq(static_skybox.config.theme_name, "", "config.theme_name is the launch value again")
	assert_false(static_skybox.is_cycle_active())


func test_a_skybox_launched_on_the_cycle_restarts_the_running_cycle() -> void:
	var fresh: Dictionary = _rig(Skybox.CYCLE_THEME_ID)
	var fresh_skybox: Skybox = fresh["skybox"] as Skybox
	assert_true(fresh_skybox.is_cycle_active(), "fixture: the launch config starts the cycle")
	var expected: Dictionary = _snapshot(fresh)
	var used: Dictionary = _rig(Skybox.CYCLE_THEME_ID)
	var skybox: Skybox = used["skybox"] as Skybox
	_dirty_with_locked_night_storm(used)
	assert_ne(skybox.locked_phase(), -1.0, "fixture: locked")
	skybox.reset_to_launch()
	assert_true(skybox.is_cycle_active())
	assert_eq(skybox.locked_phase(), -1.0, "a running, not a locked, cycle as at launch")
	assert_eq(skybox.config.theme_name, Skybox.CYCLE_THEME_ID)
	_assert_same_snapshot(_snapshot(used), expected, "after reset")


func test_reset_is_idempotent_and_skips_the_rebuild_when_already_at_launch() -> void:
	var rig: Dictionary = _rig()
	var skybox: Skybox = rig["skybox"] as Skybox
	var launch: Dictionary = _snapshot(rig)
	var puffs: MultiMeshInstance3D = skybox.get_cloud_sea().puff_instance()
	assert_not_null(puffs, "fixture: the theme has cloud puffs")
	skybox.reset_to_launch()
	assert_same(skybox.get_cloud_sea().puff_instance(), puffs, "an untouched sky is not rebuilt")
	_dirty_with_locked_night_storm(rig)
	skybox.reset_to_launch()
	var rebuilt: MultiMeshInstance3D = skybox.get_cloud_sea().puff_instance()
	assert_not_same(rebuilt, puffs, "a dirty sky is rebuilt from the launch theme")
	_assert_same_snapshot(_snapshot(rig), launch, "after the first reset")
	skybox.reset_to_launch()
	assert_same(skybox.get_cloud_sea().puff_instance(), rebuilt, "the second reset changes nothing")
	_assert_same_snapshot(_snapshot(rig), launch, "after the second reset")


func test_reset_restores_the_sun_flare_the_cycle_hijacked() -> void:
	var flare: SunFlare = SunFlare.new()
	add_child_autofree(flare)
	var rig: Dictionary = _rig()
	var skybox: Skybox = rig["skybox"] as Skybox
	var launch_direction: Vector3 = flare.config.sun_direction
	var launch_enabled: bool = flare.is_theme_enabled()
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.NIGHT
	skybox.configure_match_sky(config)
	assert_false(flare.is_theme_enabled(), "fixture: the night cycle switched the flare off")
	skybox.reset_to_launch()
	assert_eq(flare.is_theme_enabled(), launch_enabled)
	assert_eq(flare.config.sun_direction, launch_direction, "the authored flare direction is back")


func test_reset_drops_the_cycle_sky_materials_it_no_longer_uses() -> void:
	var rig: Dictionary = _rig()
	var skybox: Skybox = rig["skybox"] as Skybox
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	for _match: int in range(3):
		skybox.configure_match_sky(config)
		_overcast(skybox, 1.0)
		skybox.reset_to_launch()
	assert_lte(skybox._overcast_sky_bases.size(), 1, "only the live material keeps a baseline exposure")


func test_a_textured_set_override_does_not_survive_the_reset() -> void:
	var rig: Dictionary = _rig()
	var skybox: Skybox = rig["skybox"] as Skybox
	var launch: Dictionary = _snapshot(rig)
	var launch_enabled: bool = skybox.config.enabled
	var launch_set: String = skybox.config.default_set
	skybox.config.enabled = not launch_enabled
	skybox.config.default_set = "elsewhere"
	skybox.fallback_active = false
	skybox.reset_to_launch()
	assert_eq(skybox.config.enabled, launch_enabled)
	assert_eq(skybox.config.default_set, launch_set)
	assert_true(skybox.fallback_active)
	_assert_same_snapshot(_snapshot(rig), launch, "after reset")


func test_match_scope_reset_resets_every_skybox_and_leaving_the_tree_unhooks_it() -> void:
	var rig: Dictionary = _rig()
	var skybox: Skybox = rig["skybox"] as Skybox
	var launch: Dictionary = _snapshot(rig)
	_dirty_with_locked_night_storm(rig)
	assert_true(Events.match_scope_reset.is_connected(skybox.reset_to_launch))
	Events.match_scope_reset.emit()
	_assert_same_snapshot(_snapshot(rig), launch, "after match_scope_reset")
	remove_child(skybox)
	assert_false(Events.match_scope_reset.is_connected(skybox.reset_to_launch), "no listener left on Events")


# --- CloudCeiling.snap_clear() / WeatherPresenter.clear_now() ------------------------


func _presenter() -> WeatherPresenter:
	var presenter: WeatherPresenter = WeatherPresenter.new()
	add_child_autofree(presenter)
	return presenter


func _storm_to_full(presenter: WeatherPresenter) -> CloudCeiling:
	var ceiling: CloudCeiling = presenter.cloud_ceiling()
	Events.weather_intensity_changed.emit(STORM_ID, 1.0)
	for _i: int in range(int((ceiling.tuning.fade_in_s + 1.0) * 10.0)):
		ceiling.step(0.1)
	return ceiling


func test_ceiling_snap_clear_zeroes_the_ceiling_and_skybox_after_a_storm_ends_and_while_one_runs() -> void:
	var rig: Dictionary = _rig()
	var skybox: Skybox = rig["skybox"] as Skybox
	var presenter: WeatherPresenter = _presenter()
	var ceiling: CloudCeiling = _storm_to_full(presenter)
	assert_gt(ceiling.storm_amount(), 0.0, "fixture: stormed up")
	assert_gt(skybox.storm_sky_amount(), 0.0, "fixture: the skybox got the storm")
	Events.weather_stopped.emit(STORM_ID)
	ceiling.step(0.1)
	assert_gt(ceiling.storm_amount(), 0.0, "without a reset the storm fades over fade_out_s into the next match")
	ceiling.snap_clear()
	assert_eq(ceiling.amount(), 0.0)
	assert_eq(ceiling.storm_amount(), 0.0)
	assert_eq(ceiling.overcast(), 0.0)
	assert_eq(ceiling.target_amount(), 0.0)
	assert_eq(skybox.storm_sky_amount(), 0.0, "the skybox received 0 storm")
	assert_eq(skybox.cloud_overcast_amount(), 0.0, "the skybox received 0 overcast")
	ceiling._process(1.0)
	assert_eq(ceiling.storm_amount(), 0.0, "nothing refills it afterwards")

	# Merged variant: snap_clear also drops a weather that is still running.
	var running_rig: Dictionary = _rig()
	var running_skybox: Skybox = running_rig["skybox"] as Skybox
	var running_ceiling: CloudCeiling = _storm_to_full(_presenter())
	running_ceiling.snap_clear()
	assert_eq(running_ceiling.target_amount(), 0.0, "the old match's requests are gone")
	assert_eq(running_ceiling.storm_amount(), 0.0)
	assert_eq(running_skybox.storm_sky_amount(), 0.0)
	# The next match's weather ramps in from zero as in a fresh launch.
	Events.weather_intensity_changed.emit(RAIN_ID, 0.5)
	assert_almost_eq(running_ceiling.target_amount(), 0.5, 0.001)
	assert_eq(running_ceiling.amount(), 0.0)


func test_presenter_clear_now_keeps_a_weather_that_is_still_running() -> void:
	var presenter: WeatherPresenter = _presenter()
	Events.weather_started.emit(RAIN_ID)
	Events.weather_intensity_changed.emit(RAIN_ID, 1.0)
	var rain: WeatherPresentation = presenter.presentation_for(RAIN_ID)
	assert_not_null(rain, "fixture: rain presentation live")
	presenter.clear_now()
	assert_eq(presenter.active_count(), 1, "a running weather keeps presenting")
	assert_true(is_instance_valid(rain) and rain.is_inside_tree())
	assert_eq(presenter.cloud_ceiling().target_amount(), 0.0, "only its ceiling target is dropped")
	Events.weather_intensity_changed.emit(RAIN_ID, 0.5)
	assert_almost_eq(presenter.cloud_ceiling().target_amount(), 0.5, 0.001, "and comes back with its next intensity change")


func test_a_stopped_weather_leaves_the_presenter_and_the_skybox_fresh_after_a_reset() -> void:
	var rig: Dictionary = _rig()
	var skybox: Skybox = rig["skybox"] as Skybox
	var presenter: WeatherPresenter = _presenter()
	Events.weather_started.emit(RAIN_ID)
	Events.weather_started.emit(FOG_ID)
	Events.weather_intensity_changed.emit(RAIN_ID, 1.0)
	Events.weather_intensity_changed.emit(FOG_ID, 1.0)
	assert_gt(skybox.overcast_amount(), 0.0, "fixture: rain overcast")
	assert_gt(skybox.weather_fog_amount(), 0.0, "fixture: fog")
	assert_gt(WeatherFogShader.strength, 0.0, "fixture: the scenery fog statics")
	# What MatchWeather.reset() does at LOBBY / LOADING / END, then Main's scope reset.
	Events.weather_stopped.emit(RAIN_ID)
	Events.weather_stopped.emit(FOG_ID)
	assert_eq(presenter.active_count(), 0)
	await get_tree().process_frame
	Events.match_scope_reset.emit()
	assert_eq(skybox.overcast_amount(), 0.0)
	assert_eq(skybox.weather_fog_amount(), 0.0)
	assert_eq(skybox.cloud_overcast_amount(), 0.0)
	assert_eq(WeatherFogShader.strength, 0.0)
	assert_eq(WeatherFogShader.begin_m, WeatherFogShader.DEFAULT_BEGIN_M, "the fog presentation's tuning does not linger")
	assert_eq(WeatherFogShader.end_m, WeatherFogShader.DEFAULT_END_M)
	assert_eq(WeatherFogShader.color, WeatherFogShader.DEFAULT_COLOR)


func test_fog_statics_return_to_launch_defaults_and_refresh_the_scenery() -> void:
	var rig: Dictionary = _rig()
	var sea: CloudSea = (rig["skybox"] as Skybox).get_cloud_sea()
	WeatherFogShader.set_state(1.0, WFOG_OPACITY, WFOG_BEGIN_M, WFOG_END_M, WFOG_TINT, get_tree())
	var material: ShaderMaterial = sea.puff_instance().material_override as ShaderMaterial
	assert_almost_eq(float(material.get_shader_parameter(&"wfog_strength")), WFOG_OPACITY, 0.0001, "fixture: puffs fogged")
	WeatherFogShader.reset_to_launch(get_tree())
	assert_eq(WeatherFogShader.strength, 0.0)
	assert_eq(WeatherFogShader.begin_m, WeatherFogShader.DEFAULT_BEGIN_M)
	assert_eq(WeatherFogShader.end_m, WeatherFogShader.DEFAULT_END_M)
	assert_eq(WeatherFogShader.color, WeatherFogShader.DEFAULT_COLOR)
	assert_eq(float(material.get_shader_parameter(&"wfog_strength")), 0.0, "the scenery shaders were refreshed")
	assert_eq(material.get_shader_parameter(&"wfog_begin"), WeatherFogShader.DEFAULT_BEGIN_M)
	WeatherFogShader.reset_to_launch(null)
	assert_eq(WeatherFogShader.strength, 0.0, "a null tree only resets the statics")


func test_match_scope_reset_clears_the_whole_weather_and_sky_presentation() -> void:
	var fresh: Dictionary = _rig()
	var expected: Dictionary = _snapshot(fresh)
	var rig: Dictionary = _rig()
	var skybox: Skybox = rig["skybox"] as Skybox
	var presenter: WeatherPresenter = _presenter()
	_dirty_with_locked_night_storm(rig)
	Events.weather_started.emit(RAIN_ID)
	Events.weather_started.emit(FOG_ID)
	Events.weather_intensity_changed.emit(RAIN_ID, 1.0)
	Events.weather_intensity_changed.emit(FOG_ID, 1.0)
	var ceiling: CloudCeiling = _storm_to_full(presenter)
	assert_gt(ceiling.storm_amount(), 0.0, "fixture: ceiling stormed up")
	assert_gt(presenter.active_count(), 0, "fixture: presentations live")
	for weather_id: StringName in [RAIN_ID, FOG_ID, STORM_ID]:
		Events.weather_stopped.emit(weather_id)
	assert_eq(ceiling.target_amount(), 0.0, "fixture: stopped weather has no target, only fades in flight")
	assert_gt(ceiling.storm_amount(), 0.0, "fixture: the ceiling is still fading out")
	Events.match_scope_reset.emit()
	assert_eq(presenter.active_count(), 0, "presentations")
	assert_eq(ceiling.amount(), 0.0, "ceiling amount")
	assert_eq(ceiling.storm_amount(), 0.0, "ceiling storm")
	assert_eq(ceiling.overcast(), 0.0, "ceiling overcast")
	assert_eq(ceiling.target_amount(), 0.0, "ceiling targets")
	assert_eq(WeatherFogShader.strength, 0.0, "scenery fog")
	assert_eq(WeatherFogShader.begin_m, WeatherFogShader.DEFAULT_BEGIN_M)
	_assert_same_snapshot(_snapshot(rig), expected, "skybox after match_scope_reset")
	assert_eq(skybox.storm_sky_amount(), 0.0)


func test_ceiling_and_presenter_unhook_from_the_reset_signal_when_freed() -> void:
	var presenter: WeatherPresenter = WeatherPresenter.new()
	add_child(presenter)
	var ceiling: CloudCeiling = presenter.cloud_ceiling()
	assert_true(Events.match_scope_reset.is_connected(presenter.clear_now))
	assert_true(Events.match_scope_reset.is_connected(ceiling.snap_clear))
	remove_child(presenter)
	assert_false(Events.match_scope_reset.is_connected(presenter.clear_now))
	assert_false(Events.match_scope_reset.is_connected(ceiling.snap_clear))
	presenter.free()
