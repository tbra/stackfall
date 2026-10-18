extends GutTest
## Rain: wet-friction round trips, the intensity mapping, the
## framework restore paths, host-only physics and the streak presentation.

const DELTA: float = 0.25
const RAIN_PATH: String = "res://config/weather/rain.tres"
const FIELD_RADIUS_M: float = 20.0

var _blocks: Array[Block] = []
var _field: Field = null
var _root: Node3D = null
var _registry: BlockRegistry = null
var _physics: PhysicsTuning = null
var _context: FakeMatchContext = null
var _previous_context: MatchContext = null
var _rain: RainTuning = null
var _base_block: float = 0.0
var _base_disc: float = 0.0
## Every MatchWeather a test built: the autoload WeatherPresenter listens to their Events, so one
## left running keeps its rain presenting (and storm-tinting every later Skybox) for the rest of
## the process.
var _weathers: Array[MatchWeather] = []


func before_each() -> void:
	_blocks.clear()
	_weathers.clear()
	_field = Field.new()
	_field.map_def = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_field.map_def.field_radius = FIELD_RADIUS_M
	add_child_autofree(_field)
	_root = Node3D.new()
	add_child_autofree(_root)
	_physics = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	_registry = BlockRegistry.new()
	add_child_autofree(_registry)
	_registry.configure(_field, _field.map_def)
	_previous_context = MatchContext.installed()
	_context = FakeMatchContext.new()
	_context.field_value = _field
	_context.registry_value = _registry
	MatchContext.install(_context)
	_rain = load(RAIN_PATH) as RainTuning
	_base_disc = _field.physics_material_override.friction
	# PhysicsMaterial stores a 32-bit float: compare against what it holds.
	var probe: PhysicsMaterial = PhysicsMaterial.new()
	probe.friction = _physics.block_friction
	_base_block = probe.friction


func after_each() -> void:
	for weather: MatchWeather in _weathers:
		weather.reset()
	_weathers.clear()
	MatchContext.install(_previous_context)
	Match.abort_match()


## A real Block registered the way a placement does (Events.block_placed), at `at` in world space.
func _block(at: Vector3 = Vector3(0.0, 0.01, 0.0)) -> Block:
	var block: Block = BlockFactory.build(load("res://config/blocks/cube.tres") as BlockShape, _physics)
	_root.add_child(block)
	block.global_position = at
	_blocks.append(block)
	Events.block_placed.emit(block, block.shape_id)
	return block


func _effect(tuning: RainTuning = null) -> RainEffect:
	var e: RainEffect = RainEffect.new()
	e.bind(_context, tuning if tuning != null else _rain)
	return e


func _f(b: Block) -> float:
	return b.physics_material_override.friction


func _disc_f() -> float:
	return _field.physics_material_override.friction


func test_intensity_maps_linearly_and_restores_exactly() -> void:
	var a: Block = _block()
	var e: RainEffect = _effect()
	e.apply(0.0)
	assert_almost_eq(_f(a), _base_block, 0.0001)
	e.apply(0.5)
	assert_almost_eq(_f(a), _base_block * lerpf(1.0, _rain.wet_block_friction_factor, 0.5), 0.0001)
	assert_almost_eq(_disc_f(), _base_disc * lerpf(1.0, _rain.wet_disc_friction_factor, 0.5), 0.0001)
	e.apply(1.0)
	assert_almost_eq(_f(a), maxf(_base_block * _rain.wet_block_friction_factor, _rain.min_friction), 0.0001)
	e.restore()
	assert_eq(_f(a), _base_block, "exact baseline")
	assert_eq(_disc_f(), _base_disc)
	e.restore()
	assert_eq(_f(a), _base_block, "double restore is safe")


func test_block_spawned_mid_rain_gets_wet_and_restores() -> void:
	var e: RainEffect = _effect()
	e.apply(1.0)
	var late: Block = _block()
	e.tick(_rain.rescan_interval_s + 0.01, 1.0)
	assert_lt(_f(late), _base_block, "late block wet after a rescan")
	e.restore()
	assert_eq(_f(late), _base_block)


func _weather(host: bool, factory_calls: Array) -> MatchWeather:
	var w: MatchWeather = MatchWeather.new()
	w.set_defs([_rain])
	WeatherTestHost.bind_host(self, w, host)
	w.set_effect_factory(func(_def: WeatherTuning) -> WeatherEffect:
		factory_calls.append(1)
		return _effect())
	_weathers.append(w)
	return w


func test_client_never_builds_physics_effect() -> void:
	var a: Block = _block()
	var calls: Array = []
	var w: MatchWeather = _weather(false, calls)
	var state: Dictionary = {"v": 1, "epoch": 1, "seed": 1, "mode": MatchConfig.WeatherMode.RAIN, "sched": MatchWeather.Sched.EVENT,
		"left": 10.0, "id": "rain", "phase": WeatherTuning.Phase.HOLD, "t": 1.0, "ev": 0}
	assert_true(w.apply_replicated_state(state, true))
	w.tick(DELTA)
	assert_eq(w.active_id(), &"rain")
	assert_gt(w.active_intensity(), 0.0, "presentation intensity advances")
	assert_eq(calls.size(), 0, "no effect built on a client")
	assert_eq(_f(a), _base_block)


func _streaks(p: RainPresentation) -> MultiMeshInstance3D:
	return p.get_node("Streaks") as MultiMeshInstance3D


## Streaks drawn (visible_instance_count is -1 while everything is shown).
func _shown(streaks: MultiMeshInstance3D) -> int:
	var shown: int = streaks.multimesh.visible_instance_count
	return shown if shown >= 0 else streaks.multimesh.instance_count


func test_presentation_density_follows_intensity_and_governor_thins() -> void:
	var p: RainPresentation = RainPresentation.new()
	add_child_autofree(p)
	var streaks: MultiMeshInstance3D = _streaks(p)
	var full_count: int = _shown(streaks)
	p.set_intensity(0.0)
	assert_false(p.visible)
	p.set_intensity(0.6)
	assert_true(p.visible)
	assert_almost_eq(float((streaks.material_override as ShaderMaterial).get_shader_parameter(&"density")), 0.6, 0.0001)
	var thin: GraphicsPreset = GraphicsPreset.new()
	thin.weather_density_scale = 0.5
	Settings.graphics_preset_changed.emit(thin)
	assert_lt(_shown(streaks), full_count)


func _overcast_skybox() -> Array:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	var light: DirectionalLight3D = DirectionalLight3D.new()
	add_child_autofree(light)
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	add_child_autofree(skybox)
	skybox.light_path = skybox.get_path_to(light)
	skybox.set_locked_phase(skybox.sky_def.locked_phase_for("sunset"))
	return [skybox, environment, light]


func _overcast(skybox: Skybox, amount: float) -> void:
	skybox.set_overcast(amount, _rain.overcast_light_scale, _rain.overcast_ambient_scale,
		_rain.overcast_sky_exposure_scale, _rain.overcast_fog_color, _rain.overcast_fog_strength)


## The clear-weather values of the cycle locked at `sky_id`: what the static theme resources used
## to supply, read from a fresh facade with no weather request.
func _clear_reference(sky_id: String) -> Dictionary:
	var parts: Array = _overcast_skybox()
	var skybox: Skybox = parts[0]
	skybox.set_locked_phase(skybox.sky_def.locked_phase_for(sky_id))
	skybox.flush_weather()
	var environment: Environment = parts[1]
	var light: DirectionalLight3D = parts[2]
	return {
		&"light": light.light_energy,
		&"ambient": environment.ambient_light_energy,
		&"exposure": float((environment.sky.sky_material as ShaderMaterial).get_shader_parameter(&"exposure")),
		&"fog_color": environment.fog_light_color,
	}


func test_overcast_dims_and_restores_and_survives_sky_switch() -> void:
	var parts: Array = _overcast_skybox()
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var light: DirectionalLight3D = parts[2]
	var sunset: Dictionary = _clear_reference("sunset")
	var night: Dictionary = _clear_reference("night")
	var base_bg: float = environment.background_energy_multiplier
	var sunset_exposure: float = float(sunset[&"exposure"])
	_overcast(skybox, 1.0)
	skybox.flush_weather()
	var sky: ShaderMaterial = environment.sky.sky_material as ShaderMaterial
	assert_almost_eq(float(sky.get_shader_parameter(&"exposure")), sunset_exposure * _rain.overcast_sky_exposure_scale, 0.0001, "sky shader exposure dims")
	assert_almost_eq(light.light_energy, float(sunset[&"light"]) * _rain.overcast_light_scale, 0.0001)
	assert_almost_eq(environment.background_energy_multiplier, base_bg * _rain.overcast_sky_exposure_scale, 0.0001)
	skybox.set_locked_phase(skybox.sky_def.locked_phase_for("night"))
	skybox.flush_weather()
	assert_almost_eq(light.light_energy, float(night[&"light"]) * _rain.overcast_light_scale, 0.0001, "theme switch re-bases")
	_overcast(skybox, 0.0)
	skybox.flush_weather()
	sky = environment.sky.sky_material as ShaderMaterial
	assert_almost_eq(float(sky.get_shader_parameter(&"exposure")), float(night[&"exposure"]), 0.0001, "sky exposure restored")
	assert_almost_eq(light.light_energy, float(night[&"light"]), 0.0001)
	assert_almost_eq(environment.ambient_light_energy, float(night[&"ambient"]), 0.0001)
	assert_almost_eq(environment.background_energy_multiplier, base_bg, 0.0001)
	assert_true(environment.fog_light_color.is_equal_approx(night[&"fog_color"] as Color))


const SLIDE_FRAMES: int = 150
const TILT_DEG: float = 12.0
## Start off the floor centre so the outward direction is well defined.
const START_OFFSET: float = 2.0
const FIELD_MOVE_FRAMES: int = 2


## Real Jolt run: a cube on the field tilted by `tilt_deg`; returns the horizontal distance it
## travelled in SLIDE_FRAMES, with friction-only rain (no slide force) when `rain_on`.
func _slide_distance(rain_on: bool, tilt_deg: float) -> float:
	_field.rotation.z = deg_to_rad(tilt_deg)
	# The field is kinematic: let its move be processed before a body rests on it.
	for _i: int in range(FIELD_MOVE_FRAMES):
		await get_tree().physics_frame
	var box: Block = _block(_field.to_global(Vector3(START_OFFSET, 0.01, 0.0)))
	box.global_transform = Transform3D(_field.global_transform.basis, box.global_position)
	var tuning: RainTuning = _rain.duplicate() as RainTuning
	tuning.wet_slide_accel_mps2 = 0.0
	var effect: RainEffect = _effect(tuning)
	if rain_on:
		effect.apply(1.0)
	var start: Vector3 = box.global_position
	for _i: int in range(SLIDE_FRAMES):
		await get_tree().physics_frame
		if rain_on:
			effect.tick(1.0 / 60.0, 1.0)
	var delta: Vector3 = box.global_position - start
	effect.restore()
	return Vector2(delta.x, delta.z).length()


func test_rain_makes_a_block_slide_further_on_a_tilted_floor() -> void:
	var dry: float = await _slide_distance(false, TILT_DEG)
	for block: Block in _blocks:
		block.free()
	_blocks.clear()
	var wet: float = await _slide_distance(true, TILT_DEG)
	gut.p("SLIP tilted dry=%.3f wet(friction only)=%.3f" % [dry, wet])
	assert_lt(dry, 0.2, "dry block holds on the slope")
	assert_gt(wet, dry + 1.0, "wet block slides clearly further")


func _puddle_field() -> Array:
	var holder: Node3D = Node3D.new()
	add_child_autofree(holder)
	var map_def: MapDef = MapDef.new()
	var puddles: RainPuddles = RainPuddles.ensure_on(holder, map_def, _rain, 1.0)
	return [puddles, map_def]


func test_puddles_fill_in_rain_and_dry_after() -> void:
	var puddles: RainPuddles = _puddle_field()[0]
	assert_gt((puddles.get_node("Patches") as MultiMeshInstance3D).multimesh.instance_count, 0)
	puddles.set_rain(1.0)
	puddles.advance(_rain.puddle_fill_time_s * 0.5)
	assert_almost_eq(_wetness(puddles), 0.5, 0.001)
	puddles.advance(_rain.puddle_fill_time_s)
	assert_eq(_wetness(puddles), 1.0)
	puddles.set_rain(0.0)
	puddles.advance(_rain.puddle_dry_time_s * 0.5)
	assert_almost_eq(_wetness(puddles), 0.5, 0.001)
	puddles.advance(_rain.puddle_dry_time_s)
	assert_eq(_wetness(puddles), 0.0)


## The wetness the puddle shader is fed (0 when no layer or no patches exist).
func _wetness(puddles: RainPuddles) -> float:
	var patches: MultiMeshInstance3D = puddles.get_node_or_null("Patches") as MultiMeshInstance3D if puddles != null else null
	if patches == null:
		return 0.0
	var value: Variant = (patches.material_override as ShaderMaterial).get_shader_parameter(&"wetness")
	return float(value) if value != null else 0.0
