extends GutTest
## R1 (docs/MATCH_RESET_AUDIT.md G1, G2 and weather-fog parity): the
## sky and weather presentation owners return to what a fresh launch has when
## Events.match_scope_reset fires, so a match never starts under the previous one's
## night / cycle / storm / overcast sky or its fading ceiling.

const SUNSET_PATH: String = "res://config/sky/themes/sunset.tres"
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
	var fog_material: FogMaterial = (skybox.get_node_or_null("CloudDeck") as FogVolume).material as FogMaterial
	return {
		"theme": skybox.theme.resource_path,
		"theme_name": skybox.config.theme_name,
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


# --- CloudCeiling.snap_clear() / WeatherPresenter.clear_now() ------------------------


func _presenter() -> WeatherPresenter:
	var presenter: WeatherPresenter = WeatherPresenter.new()
	add_child_autofree(presenter)
	return presenter


func _storm_to_full(presenter: WeatherPresenter) -> CloudCeiling:
	var ceiling: CloudCeiling = presenter.get_node("CloudCeiling") as CloudCeiling
	Events.weather_intensity_changed.emit(STORM_ID, 1.0)
	for _i: int in range(int((ceiling.tuning.fade_in_s + 1.0) * 10.0)):
		ceiling.step(0.1)
	return ceiling


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
	assert_gt(_live_presentations(presenter), 0, "fixture: presentations live")
	for weather_id: StringName in [RAIN_ID, FOG_ID, STORM_ID]:
		Events.weather_stopped.emit(weather_id)
	assert_eq(ceiling.target_amount(), 0.0, "fixture: stopped weather has no target, only fades in flight")
	assert_gt(ceiling.storm_amount(), 0.0, "fixture: the ceiling is still fading out")
	Events.match_scope_reset.emit()
	assert_eq(_live_presentations(presenter), 0, "presentations")
	assert_eq(ceiling.amount(), 0.0, "ceiling amount")
	assert_eq(ceiling.storm_amount(), 0.0, "ceiling storm")
	assert_eq(ceiling.overcast(), 0.0, "ceiling overcast")
	assert_eq(ceiling.target_amount(), 0.0, "ceiling targets")
	assert_eq(WeatherFogShader.strength, 0.0, "scenery fog")
	assert_eq(WeatherFogShader.begin_m, WeatherFogShader.DEFAULT_BEGIN_M)
	_assert_same_snapshot(_snapshot(rig), expected, "skybox after match_scope_reset")
	assert_eq(skybox.storm_sky_amount(), 0.0)


## Weather presentation scenes the presenter currently holds (the ceiling is not one).
func _live_presentations(presenter: WeatherPresenter) -> int:
	var count: int = 0
	for child: Node in presenter.get_children():
		if child is WeatherPresentation and not child.is_queued_for_deletion():
			count += 1
	return count
