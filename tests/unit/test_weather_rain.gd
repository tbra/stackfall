extends GutTest
## Rain (Bontago-22y.5): wet-friction round trips, the intensity mapping, the
## framework restore paths, host-only physics and the streak presentation.

const DELTA: float = 0.25
const BASE_BLOCK: float = 0.8
const BASE_DISC: float = 0.9
const RAIN_PATH: String = "res://config/weather/rain.tres"

var _bodies: Array[RigidBody3D] = []
var _disc: StaticBody3D = null
var _rain: RainTuning = null


func before_each() -> void:
	_bodies.clear()
	_disc = StaticBody3D.new()
	_disc.physics_material_override = _mat(BASE_DISC)
	_rain = load(RAIN_PATH) as RainTuning


func after_each() -> void:
	for body: RigidBody3D in _bodies:
		body.free()
	_disc.free()
	Match.abort_match()


func _mat(friction: float) -> PhysicsMaterial:
	var m: PhysicsMaterial = PhysicsMaterial.new()
	m.friction = friction
	return m


func _block(friction: float = BASE_BLOCK) -> RigidBody3D:
	var b: RigidBody3D = RigidBody3D.new()
	b.physics_material_override = _mat(friction)
	_bodies.append(b)
	return b


func _effect() -> RainEffect:
	var e: RainEffect = RainEffect.new()
	e.tuning = _rain
	e.set_providers(
		func() -> Array: return _bodies.filter(func(b: RigidBody3D) -> bool: return is_instance_valid(b)),
		func() -> Variant: return _disc)
	return e


func _f(b: RigidBody3D) -> float:
	return b.physics_material_override.friction


func test_shipped_rain_resource_is_a_rain_tuning_with_effect() -> void:
	assert_not_null(_rain)
	assert_eq(_rain.id, &"rain")
	assert_eq(_rain.effect_script, "res://autoload/match/weather/RainEffect.gd")
	assert_true(load(_rain.effect_script) is Script)
	assert_true(load(_rain.presentation_scene) is PackedScene)
	assert_lt(_rain.wet_block_friction_factor, 1.0)


func test_intensity_maps_linearly_and_restores_exactly() -> void:
	var a: RigidBody3D = _block()
	var e: RainEffect = _effect()
	e.apply(0.0)
	assert_almost_eq(_f(a), BASE_BLOCK, 0.0001)
	e.apply(0.5)
	assert_almost_eq(_f(a), BASE_BLOCK * lerpf(1.0, _rain.wet_block_friction_factor, 0.5), 0.0001)
	assert_almost_eq(_disc.physics_material_override.friction, BASE_DISC * lerpf(1.0, _rain.wet_disc_friction_factor, 0.5), 0.0001)
	e.apply(1.0)
	assert_almost_eq(_f(a), maxf(BASE_BLOCK * _rain.wet_block_friction_factor, _rain.min_friction), 0.0001)
	e.restore()
	assert_eq(_f(a), _mat(BASE_BLOCK).friction, "exact baseline")
	assert_eq(_disc.physics_material_override.friction, _mat(BASE_DISC).friction)
	e.restore()
	assert_eq(_f(a), _mat(BASE_BLOCK).friction, "double restore is safe")


func test_block_spawned_mid_rain_gets_wet_and_restores() -> void:
	var e: RainEffect = _effect()
	e.apply(1.0)
	var late: RigidBody3D = _block(0.6)
	e.tick(_rain.rescan_interval_s + 0.01, 1.0)
	assert_lt(_f(late), 0.6, "late block wet after a rescan")
	e.restore()
	assert_eq(_f(late), _mat(0.6).friction)


func test_despawned_block_does_not_break_restore() -> void:
	var a: RigidBody3D = _block()
	var b: RigidBody3D = _block()
	var e: RainEffect = _effect()
	e.apply(1.0)
	_bodies.erase(a)
	a.free()
	e.tick(_rain.rescan_interval_s + 0.01, 1.0)
	e.restore()
	assert_eq(_f(b), _mat(BASE_BLOCK).friction)


func test_other_effects_friction_is_rebased_not_overwritten() -> void:
	var a: RigidBody3D = _block()
	var e: RainEffect = _effect()
	e.apply(1.0)
	# Freeze-like effect writes a new baseline while it rains.
	a.physics_material_override.friction = 2.0
	e.apply(0.5)
	assert_almost_eq(_f(a), 2.0 * lerpf(1.0, _rain.wet_block_friction_factor, 0.5), 0.0001)
	# It rewrites again just before rain ends: rain must leave that value alone.
	a.physics_material_override.friction = 3.0
	e.restore()
	assert_almost_eq(_f(a), 3.0, 0.0001)


func test_small_intensity_change_is_skipped() -> void:
	var a: RigidBody3D = _block()
	var e: RainEffect = _effect()
	e.apply(0.5)
	var before: float = _f(a)
	e.apply(0.5 + _rain.apply_epsilon * 0.5)
	assert_eq(_f(a), before)


func _weather(host: bool, factory_calls: Array) -> MatchWeather:
	var w: MatchWeather = MatchWeather.new()
	w.set_defs([_rain])
	w.set_host_override(host)
	w.set_effect_factory(func(_def: WeatherTuning) -> WeatherEffect:
		factory_calls.append(1)
		return _effect())
	return w


func test_framework_ramp_and_end_restore_friction() -> void:
	var a: RigidBody3D = _block()
	var calls: Array = []
	var w: MatchWeather = _weather(true, calls)
	assert_true(w.start_event(&"rain"))
	for _i: int in range(int(_rain.ramp_in_s / DELTA) + 4):
		w.tick(DELTA)
	assert_almost_eq(_f(a), BASE_BLOCK * _rain.wet_block_friction_factor, 0.0001, "full wet at hold")
	w.reset()
	assert_eq(_f(a), _mat(BASE_BLOCK).friction, "reset (match end/abort/teardown) restores")
	assert_eq(_disc.physics_material_override.friction, _mat(BASE_DISC).friction)


func test_natural_end_restores() -> void:
	var a: RigidBody3D = _block()
	var calls: Array = []
	var w: MatchWeather = _weather(true, calls)
	w.start_event(&"rain")
	w.end_event()
	for _i: int in range(int(_rain.ramp_out_s / DELTA) + 4):
		w.tick(DELTA)
	assert_eq(w.active_id(), &"")
	assert_eq(_f(a), _mat(BASE_BLOCK).friction)


func test_client_never_builds_physics_effect() -> void:
	var a: RigidBody3D = _block()
	var calls: Array = []
	var w: MatchWeather = _weather(false, calls)
	var state: Dictionary = {"v": 1, "epoch": 1, "seed": 1, "mode": MatchConfig.WeatherMode.RAIN, "sched": MatchWeather.Sched.EVENT,
		"left": 10.0, "id": "rain", "phase": WeatherTuning.Phase.HOLD, "t": 1.0}
	assert_true(w.apply_replicated_state(state, true))
	w.tick(DELTA)
	assert_eq(w.active_id(), &"rain")
	assert_gt(w.active_intensity(), 0.0, "presentation intensity advances")
	assert_eq(calls.size(), 0, "no effect built on a client")
	assert_eq(_f(a), _mat(BASE_BLOCK).friction)


func test_presentation_density_follows_intensity_and_low_preset_thins() -> void:
	var p: RainPresentation = RainPresentation.new()
	add_child_autofree(p)
	p.configure(_rain, 1.0)
	var full_count: int = p.streak_instance().multimesh.instance_count
	p.set_intensity(0.0)
	assert_false(p.visible)
	p.set_intensity(0.6)
	assert_true(p.visible)
	assert_almost_eq(p.shader_density(), 0.6, 0.0001)
	p.configure(_rain, 0.5)
	assert_lt(p.streak_instance().multimesh.instance_count, full_count)


const NIGHT_PATH: String = "res://config/sky_themes/night.tres"
const SUNSET_PATH: String = "res://config/sky_themes/sunset.tres"


func _overcast_skybox() -> Array:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	var light: DirectionalLight3D = DirectionalLight3D.new()
	add_child_autofree(light)
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = load(SUNSET_PATH) as SkyThemeDef
	add_child_autofree(skybox)
	skybox.light_path = skybox.get_path_to(light)
	skybox.apply_theme(skybox.theme)
	return [skybox, environment, light]


func _overcast(skybox: Skybox, amount: float) -> void:
	skybox.set_overcast(amount, _rain.overcast_light_scale, _rain.overcast_ambient_scale,
		_rain.overcast_sky_exposure_scale, _rain.overcast_fog_color, _rain.overcast_fog_strength)


func test_overcast_dims_and_restores_and_survives_theme_switch() -> void:
	var parts: Array = _overcast_skybox()
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var light: DirectionalLight3D = parts[2]
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var night: SkyThemeDef = load(NIGHT_PATH) as SkyThemeDef
	var base_bg: float = environment.background_energy_multiplier
	var sunset_sky: ShaderMaterial = sunset.sky_material as ShaderMaterial
	var sunset_exposure: float = float(sunset_sky.get_shader_parameter(&"exposure"))
	_overcast(skybox, 1.0)
	assert_almost_eq(float(sunset_sky.get_shader_parameter(&"exposure")), sunset_exposure * _rain.overcast_sky_exposure_scale, 0.0001, "sky shader exposure dims")
	assert_almost_eq(light.light_energy, sunset.light_energy * _rain.overcast_light_scale, 0.0001)
	assert_almost_eq(environment.background_energy_multiplier, base_bg * _rain.overcast_sky_exposure_scale, 0.0001)
	skybox.apply_theme(night)
	assert_almost_eq(light.light_energy, night.light_energy * _rain.overcast_light_scale, 0.0001, "theme switch re-bases")
	_overcast(skybox, 0.0)
	assert_almost_eq(float(sunset_sky.get_shader_parameter(&"exposure")), sunset_exposure, 0.0001, "sky exposure restored")
	assert_almost_eq(light.light_energy, night.light_energy, 0.0001)
	assert_almost_eq(environment.ambient_light_energy, night.ambient_energy, 0.0001)
	assert_almost_eq(environment.background_energy_multiplier, base_bg, 0.0001)
	assert_eq(environment.fog_light_color, night.fog_color)


func test_presentation_frees_overcast_when_removed() -> void:
	var parts: Array = _overcast_skybox()
	var skybox: Skybox = parts[0]
	var light: DirectionalLight3D = parts[2]
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var p: RainPresentation = RainPresentation.new()
	add_child(p)
	p.set_intensity(1.0)
	assert_lt(light.light_energy, sunset.light_energy)
	p.free()
	assert_almost_eq(light.light_energy, sunset.light_energy, 0.0001)
	assert_eq(skybox.overcast_amount(), 0.0)
