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
## Every MatchWeather a test built: the autoload WeatherPresenter listens to their Events, so one
## left running keeps its rain presenting (and storm-tinting every later Skybox) for the rest of
## the process (Bontago-fca.39).
var _weathers: Array[MatchWeather] = []


func before_each() -> void:
	_bodies.clear()
	_weathers.clear()
	_disc = StaticBody3D.new()
	_disc.physics_material_override = _mat(BASE_DISC)
	_rain = load(RAIN_PATH) as RainTuning


func after_each() -> void:
	for body: RigidBody3D in _bodies:
		body.free()
	_disc.free()
	for weather: MatchWeather in _weathers:
		weather.reset()
	_weathers.clear()
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
	_weathers.append(w)
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
		"left": 10.0, "id": "rain", "phase": WeatherTuning.Phase.HOLD, "t": 1.0, "ev": 0}
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


# --- Bontago-mp0.21: stronger slip and puddles --------------------------------

const SLIDE_FRAMES: int = 150
const TILT_DEG: float = 12.0
const PUSH_SPEED: float = 3.0
## Start off the floor centre so the outward direction is well defined.
const START_OFFSET: float = 2.0
var _last_delta: Vector3 = Vector3.ZERO


## Real Jolt run: a box on a floor (tilted when tilt_deg > 0) or pushed along a
## flat one; returns the horizontal distance it travelled in SLIDE_FRAMES.
func _slide_distance(rain_on: bool, tilt_deg: float, push: float, slide_accel: float, push_dir: Vector3 = Vector3.RIGHT, offset: Vector3 = Vector3(START_OFFSET, 0.0, 0.0)) -> float:
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(80.0, 1.0, 80.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.physics_material_override = _mat(BASE_DISC)
	floor_body.rotation.z = deg_to_rad(tilt_deg)
	add_child(floor_body)
	var box: RigidBody3D = RigidBody3D.new()
	var box_shape: CollisionShape3D = CollisionShape3D.new()
	var cube: BoxShape3D = BoxShape3D.new()
	cube.size = Vector3.ONE
	box_shape.shape = cube
	box.add_child(box_shape)
	box.physics_material_override = _mat(BASE_BLOCK)
	add_child(box)
	# Rest the cube on the (rotated) top face, centred on the floor body.
	box.global_transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(tilt_deg)), floor_body.global_transform * (offset + Vector3.UP))
	box.linear_velocity = push_dir * push
	var tuning: RainTuning = _rain.duplicate() as RainTuning
	tuning.wet_slide_accel_mps2 = slide_accel
	var effect: RainEffect = RainEffect.new()
	effect.tuning = tuning
	effect.set_providers(func() -> Array: return [box], func() -> Variant: return floor_body)
	if rain_on:
		effect.apply(1.0)
	var start: Vector3 = box.global_position
	for _i: int in range(SLIDE_FRAMES):
		await get_tree().physics_frame
		if rain_on:
			effect.tick(1.0 / 60.0, 1.0)
	_last_delta = box.global_position - start
	var travelled: float = Vector2(_last_delta.x, _last_delta.z).length()
	effect.restore()
	# Free now: a later run in the same test must not collide with this box.
	box.free()
	floor_body.free()
	return travelled


func test_rain_makes_a_block_slide_further_on_a_tilted_floor() -> void:
	var dry: float = await _slide_distance(false, TILT_DEG, 0.0, 0.0)
	var wet: float = await _slide_distance(true, TILT_DEG, 0.0, 0.0)
	gut.p("SLIP tilted dry=%.3f wet(friction only)=%.3f" % [dry, wet])
	assert_lt(dry, 0.2, "dry block holds on the slope")
	assert_gt(wet, dry + 1.0, "wet block slides clearly further")


func test_slide_force_adds_distance_to_a_pushed_block() -> void:
	var friction_only: float = await _slide_distance(true, 0.0, PUSH_SPEED, 0.0)
	var with_force: float = await _slide_distance(true, 0.0, PUSH_SPEED, _rain.wet_slide_accel_mps2)
	var along: float = _last_delta.x
	var dry: float = await _slide_distance(false, 0.0, PUSH_SPEED, 0.0)
	gut.p("SLIP pushed dry=%.3f rain friction=%.3f rain+force=%.3f" % [dry, friction_only, with_force])
	assert_gt(friction_only, dry, "wet friction slides a pushed block further")
	assert_gt(with_force, friction_only, "boost adds distance along the push")
	assert_gt(along, 0.0, "and it is along the push direction")


func test_resting_block_is_not_nudged_by_the_boost() -> void:
	var moved: float = await _slide_distance(true, 0.0, 0.0, _rain.wet_slide_accel_mps2)
	assert_lt(moved, 0.02, "resting block stays put in rain")


func test_inner_ring_block_is_not_pushed_toward_the_centre() -> void:
	# A block sitting 2 m from the centre (RING inner side) moving tangentially
	# gains no motion along the radius (the old radial push moved it outward/in).
	var moved: float = await _slide_distance(true, 0.0, PUSH_SPEED, _rain.wet_slide_accel_mps2, Vector3.BACK, Vector3(-START_OFFSET, 0.0, 0.0))
	assert_lt(absf(_last_delta.x), 0.05, "no radial drift")
	assert_gt(moved, 0.0)


func test_boost_respects_the_speed_cap() -> void:
	var tuning: RainTuning = _rain.duplicate() as RainTuning
	tuning.wet_slide_max_speed_mps = 1.0
	var effect: RainEffect = RainEffect.new()
	effect.tuning = tuning
	var fast: RigidBody3D = _block()
	add_child(fast)
	fast.linear_velocity = Vector3(3.0, 0.0, 0.0)
	effect.set_providers(func() -> Array: return [fast], func() -> Variant: return null)
	effect.tick(1.0 / 60.0, 1.0)
	assert_eq(fast.constant_force, Vector3.ZERO)
	assert_eq(fast.get_applied_force() if fast.has_method("get_applied_force") else Vector3.ZERO, Vector3.ZERO)


func test_puddle_count_follows_a_preset_change() -> void:
	var parts: Array = _puddle_field()
	var puddles: RainPuddles = parts[0]
	var full: int = puddles.patch_count()
	var low: GraphicsPreset = GraphicsPreset.new()
	low.ambient_life_enabled = false
	low.weather_density_scale = 1.0
	Settings.graphics_preset_changed.emit(low)
	assert_lt(puddles.patch_count(), full, "Low preset rebuilds with fewer patches")


func test_puddle_alpha_leaves_territory_edges_visible() -> void:
	assert_lte(_rain.puddle_alpha, 0.5)


func _puddle_field() -> Array:
	var holder: Node3D = Node3D.new()
	add_child_autofree(holder)
	var map_def: MapDef = MapDef.new()
	var puddles: RainPuddles = RainPuddles.ensure_on(holder, map_def, _rain, 1.0)
	return [puddles, map_def]


func test_puddles_fill_in_rain_and_dry_after() -> void:
	var puddles: RainPuddles = _puddle_field()[0]
	assert_gt(puddles.patch_count(), 0)
	puddles.set_rain(1.0)
	puddles.advance(_rain.puddle_fill_time_s * 0.5)
	assert_almost_eq(puddles.wetness(), 0.5, 0.001)
	puddles.advance(_rain.puddle_fill_time_s)
	assert_eq(puddles.wetness(), 1.0)
	puddles.set_rain(0.0)
	puddles.advance(_rain.puddle_dry_time_s * 0.5)
	assert_almost_eq(puddles.wetness(), 0.5, 0.001)
	puddles.advance(_rain.puddle_dry_time_s)
	assert_eq(puddles.wetness(), 0.0)


func test_puddles_stay_on_the_disc_and_low_preset_has_fewer() -> void:
	var parts: Array = _puddle_field()
	var puddles: RainPuddles = parts[0]
	var map_def: MapDef = parts[1]
	var patches: MultiMesh = puddles.get_node("Patches").multimesh
	for index: int in range(patches.instance_count):
		var origin: Vector3 = patches.get_instance_transform(index).origin
		assert_true(map_def.shape_contains(Vector2(origin.x, origin.z)))
	var low_holder: Node3D = Node3D.new()
	add_child_autofree(low_holder)
	var low: RainPuddles = RainPuddles.ensure_on(low_holder, map_def, _rain, _rain.puddle_low_preset_scale)
	assert_lt(low.patch_count(), puddles.patch_count())


func _big_patches() -> MultiMesh:
	var holder: Node3D = Node3D.new()
	add_child_autofree(holder)
	var map_def: MapDef = MapDef.new()
	map_def.field_radius = 40.0
	return RainPuddles.ensure_on(holder, map_def, _rain, 1.0).get_node("Patches").multimesh


func test_puddles_are_seeded_identically() -> void:
	# (The headless dummy renderer returns identity instance transforms, so only the
	# seeded patch count is comparable here; the layout is checked in the capture.)
	var first: MultiMesh = _big_patches()
	var second: MultiMesh = _big_patches()
	assert_gt(first.instance_count, 20)
	assert_eq(first.instance_count, second.instance_count)


func test_puddle_shader_has_no_centre_streak_or_global_pulse() -> void:
	var code: String = RainPuddles.SHADER.code
	assert_false(code.contains("float band"), "no diagonal glint band across the puddle")
	assert_false(code.contains("t * (edge"), "no ring expanding to the rim")
