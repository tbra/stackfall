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


func test_static_sky_ticks_at_cadence_not_every_frame() -> void:
	var skybox: Skybox = _make_skybox(false)
	skybox.environment.sky.sky_material = ShaderMaterial.new()
	skybox.environment.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	var interval: float = 1.0 / skybox.radiance_config.radiance_hz
	var writes: int = 0
	var frame: float = interval / 5.0
	for i: int in 50:
		var before: Variant = (skybox.environment.sky.sky_material as ShaderMaterial).get_shader_parameter(&"radiance_tick")
		skybox._process(frame)
		var after: Variant = (skybox.environment.sky.sky_material as ShaderMaterial).get_shader_parameter(&"radiance_tick")
		if after != before:
			writes += 1
	assert_between(writes, 9, 11, "50 frames of 1/5 interval = ~10 ticks")


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


func test_cycle_discs_move_every_frame_while_material_steps() -> void:
	var skybox: Skybox = _make_skybox(true)
	assert_true(skybox.is_cycle_active())
	var interval: float = 1.0 / skybox.radiance_config.radiance_hz
	var frame: float = interval / 4.0
	var frames: int = 40
	var material: ShaderMaterial = skybox.environment.sky.sky_material as ShaderMaterial
	var published_before: int = skybox.disc_publish_count
	var disc_seen: Dictionary = {}
	var material_seen: Dictionary = {}
	for i: int in frames:
		# The headless MatchContext clock is fixed at 0; moving the offset moves the phase.
		skybox._cycle_phase_offset = 0.1 + float(i) * 0.002
		skybox._process(frame)
		disc_seen[skybox.last_disc_sun_direction] = true
		material_seen[(skybox.environment.sky.sky_material as ShaderMaterial).get_shader_parameter(&"sun_direction")] = true
	assert_eq(skybox.disc_publish_count - published_before, frames, "discs written every frame")
	assert_gt(disc_seen.size(), material_seen.size(), "discs move more often than the throttled material")
	assert_lte(material_seen.size(), 12, "material/light writes stay at radiance_hz")
	assert_eq(material.get_shader_parameter(&"use_global_dirs"), 1.0)
