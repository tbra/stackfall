extends GutTest
## G1: the sky radiance refreshes at SkyRadianceConfig.radiance_hz,
## not every frame (shaders read the global sky_time, never TIME).

func _make_skybox(cycle: bool) -> Skybox:
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment: Environment = Environment.new()
	environment.sky = sky
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.config.theme_name = Skybox.CYCLE_THEME_ID if cycle else "sunset"
	skybox.environment = environment
	add_child_autofree(skybox)
	return skybox


const SENTINEL_UNIFORM: StringName = &"exposure"
const SENTINEL: float = -123.0


func test_locked_sky_is_never_written_after_its_first_frame() -> void:
	var skybox: Skybox = _make_skybox(false)
	assert_true(skybox.is_cycle_active(), "a locked sky is the cycle locked at the launch id")
	var interval: float = 1.0 / skybox.radiance_config.radiance_hz
	skybox._process(interval)
	var material: ShaderMaterial = SkyTestKit.sky_material(skybox)
	material.set_shader_parameter(SENTINEL_UNIFORM, SENTINEL)
	for i: int in 50:
		skybox._process(interval / 5.0)
	assert_eq(material.get_shader_parameter(SENTINEL_UNIFORM), SENTINEL, "no radiance re-render while locked and clear")


func test_quality_sky_is_never_ticked() -> void:
	var skybox: Skybox = _make_skybox(false)
	var material: ShaderMaterial = ShaderMaterial.new()
	skybox.environment.sky.sky_material = material
	skybox.environment.sky.process_mode = Sky.PROCESS_MODE_QUALITY
	for i: int in 20:
		skybox._process(1.0)
	assert_null(material.get_shader_parameter(&"radiance_tick"))


func test_cycle_writes_sun_only_at_cadence() -> void:
	var skybox: Skybox = _make_skybox(true)
	assert_true(skybox.is_cycle_active())
	var interval: float = 1.0 / skybox.radiance_config.radiance_hz
	var seen: Dictionary = {}
	var frame: float = interval / 4.0
	for i: int in 40:
		skybox._process(frame)
		var material: ShaderMaterial = skybox.environment.sky.sky_material as ShaderMaterial
		seen[material.get_shader_parameter(&"sun_direction")] = true
	assert_lte(seen.size(), 12, "sun direction is written at most once per interval")


func test_cycle_material_writes_stay_at_the_radiance_cadence() -> void:
	var skybox: Skybox = _make_skybox(true)
	assert_true(skybox.is_cycle_active())
	var interval: float = 1.0 / skybox.radiance_config.radiance_hz
	var frame: float = interval / 4.0
	var frames: int = 40
	var material: ShaderMaterial = SkyTestKit.sky_material(skybox)
	var context: FakeMatchContext = FakeMatchContext.new()
	var previous_context: MatchContext = MatchContext.installed()
	MatchContext.install(context)
	var material_seen: Dictionary = {}
	for i: int in frames:
		# Moving the shared clock moves the phase (0.002 of a cycle per frame).
		context.shared_clock_seconds_value = 0.1 + float(i) * 0.002 * skybox.sky_def.cycle_length_seconds
		skybox._process(frame)
		material_seen[material.get_shader_parameter(&"sun_direction")] = true
	MatchContext.install(previous_context)
	assert_lte(material_seen.size(), 12, "material/light writes stay at radiance_hz")
	assert_gt(material_seen.size(), 1, "the material still steps as the phase moves")
	assert_eq(material.get_shader_parameter(&"use_global_dirs"), 1.0)
