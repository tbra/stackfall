extends GutTest
## SkyReflections: SSR rule of the plan (visuals AND preset), probe configuration, probe
## interval/retrigger and the radiance cadence, all through injected dependencies.

const VISUALS_PATH: String = "res://config/territory/territory_visuals.tres"
const PRESET_IDS: Array[String] = ["low", "medium", "high"]
const RADIANCE_PATH: String = "res://config/sky/sky_radiance_config.tres"


func _preset(preset_id: String) -> GraphicsPreset:
	return load("res://config/graphics/presets/%s.tres" % preset_id) as GraphicsPreset


func _visuals() -> TerritoryVisuals:
	return (load(VISUALS_PATH) as TerritoryVisuals).duplicate() as TerritoryVisuals


func _radiance(hz: float = 10.0) -> SkyRadianceConfig:
	var config: SkyRadianceConfig = (load(RADIANCE_PATH) as SkyRadianceConfig).duplicate() as SkyRadianceConfig
	config.radiance_hz = hz
	return config


func _registry() -> BlockRegistry:
	var registry: BlockRegistry = BlockRegistry.new()
	add_child_autofree(registry)
	return registry


func _probe() -> ReflectionProbe:
	var probe: ReflectionProbe = ReflectionProbe.new()
	add_child_autofree(probe)
	return probe


func _bound(environment: Environment, probe: ReflectionProbe, registry: BlockRegistry,
		visuals: TerritoryVisuals, hz: float = 10.0) -> SkyReflections:
	var reflections: SkyReflections = SkyReflections.new()
	reflections.bind(environment, probe, registry, visuals, _radiance(hz))
	return reflections


func test_shipped_visuals_give_the_preset_ssr_value_at_boot_preset_change_and_f4_refresh() -> void:
	var visuals: TerritoryVisuals = _visuals()
	assert_true(visuals.ssr_enabled, "the shipped dev switch is on")
	for preset_id: String in PRESET_IDS:
		var preset: GraphicsPreset = _preset(preset_id)
		var environment: Environment = Environment.new()
		var reflections: SkyReflections = _bound(environment, null, null, visuals)
		reflections.configure_ssr(preset)
		assert_eq(environment.ssr_enabled, preset.ssr_enabled, "%s at boot" % preset_id)
		for other_id: String in PRESET_IDS:
			var other: GraphicsPreset = _preset(other_id)
			reflections.configure_ssr(other)
			assert_eq(environment.ssr_enabled, other.ssr_enabled, "%s after a change from %s" % [other_id, preset_id])
		reflections.configure_ssr(preset)
		visuals.ssr_max_steps += 1
		reflections.configure_ssr(preset)
		assert_eq(environment.ssr_enabled, preset.ssr_enabled, "%s after an F4 refresh" % preset_id)
		assert_eq(environment.ssr_max_steps, visuals.ssr_max_steps, "the refresh carries the edited tunable")
		visuals.ssr_max_steps -= 1


func test_dev_switch_off_is_a_kill_switch_and_a_null_preset_defers_to_visuals() -> void:
	var visuals: TerritoryVisuals = _visuals()
	var environment: Environment = Environment.new()
	var reflections: SkyReflections = _bound(environment, null, null, visuals)
	visuals.ssr_enabled = false
	reflections.configure_ssr(_preset("high"))
	assert_false(environment.ssr_enabled, "visuals off wins over a preset with SSR")
	visuals.ssr_enabled = true
	reflections.configure_ssr(null)
	assert_true(environment.ssr_enabled, "no preset: visuals alone")
	visuals.ssr_enabled = false
	reflections.configure_ssr(null)
	assert_false(environment.ssr_enabled)


func test_ssao_follows_visuals_only() -> void:
	var visuals: TerritoryVisuals = _visuals()
	var environment: Environment = Environment.new()
	var reflections: SkyReflections = _bound(environment, null, null, visuals)
	visuals.ssao_enabled = true
	visuals.ssao_radius = 2.5
	reflections.configure_ssr(_preset("low"))
	assert_true(environment.ssao_enabled, "a Low preset does not touch SSAO")
	assert_almost_eq(environment.ssao_radius, 2.5, 0.0001)


func test_unbound_calls_are_no_ops() -> void:
	var reflections: SkyReflections = SkyReflections.new()
	reflections.configure_ssr(_preset("high"))
	reflections.configure_probe(10.0, _preset("high"))
	reflections.refresh_capture()
	reflections.retrigger_probe()
	reflections.set_running(true)
	assert_false(reflections.step(1.0), "no radiance config, no tick")


func test_effective_probe_mode_mapping() -> void:
	var visuals: TerritoryVisuals = _visuals()
	var high: GraphicsPreset = _preset("high")
	assert_eq(SkyReflections.effective_probe_mode(null, high), GraphicsPreset.ReflectionProbeMode.OFF)
	visuals.reflection_probe_enabled = false
	assert_eq(SkyReflections.effective_probe_mode(visuals, high), GraphicsPreset.ReflectionProbeMode.OFF)
	visuals.reflection_probe_enabled = true
	visuals.reflection_probe_update_always = true
	assert_eq(SkyReflections.effective_probe_mode(visuals, null), GraphicsPreset.ReflectionProbeMode.ALWAYS)
	visuals.reflection_probe_update_always = false
	assert_eq(SkyReflections.effective_probe_mode(visuals, null), GraphicsPreset.ReflectionProbeMode.INTERVAL)
	for preset_id: String in PRESET_IDS:
		assert_eq(SkyReflections.effective_probe_mode(visuals, _preset(preset_id)), _preset(preset_id).reflection_probe_mode)


func test_configure_probe_sizes_and_enables_it_per_preset() -> void:
	var visuals: TerritoryVisuals = _visuals()
	for preset_id: String in PRESET_IDS:
		var preset: GraphicsPreset = _preset(preset_id)
		var probe: ReflectionProbe = _probe()
		var reflections: SkyReflections = _bound(null, probe, null, visuals)
		reflections.configure_probe(30.0, preset)
		var mode: int = SkyReflections.effective_probe_mode(visuals, preset)
		assert_eq(probe.visible, mode != GraphicsPreset.ReflectionProbeMode.OFF, "%s visibility" % preset_id)
		var expected_update: int = (
			ReflectionProbe.UPDATE_ALWAYS if mode == GraphicsPreset.ReflectionProbeMode.ALWAYS
			else ReflectionProbe.UPDATE_ONCE)
		assert_eq(probe.update_mode, expected_update, "%s update mode" % preset_id)
		var half: float = 30.0 + visuals.reflection_probe_margin_m
		assert_eq(probe.size, Vector3(half * 2.0, visuals.reflection_probe_height_m, half * 2.0))
		assert_almost_eq(probe.position.y, visuals.reflection_probe_height_m * 0.5 - SkyReflections.PROBE_GROUND_CLEARANCE_M, 0.0001)
		assert_true(probe.box_projection)
		assert_eq(probe.cull_mask, SkyReflections.PROBE_CULL_MASK)
		assert_eq(probe.cull_mask & TerritoryOverlay.DISC_LAYER_BIT, 0, "the disc is never captured")


func _interval_preset() -> GraphicsPreset:
	var preset: GraphicsPreset = _preset("medium").duplicate() as GraphicsPreset
	preset.reflection_probe_mode = GraphicsPreset.ReflectionProbeMode.INTERVAL
	preset.reflection_probe_interval_s = 0.5
	return preset


func test_interval_mode_retriggers_only_when_the_layout_changed() -> void:
	var visuals: TerritoryVisuals = _visuals()
	visuals.reflection_probe_update_always = false
	var probe: ReflectionProbe = _probe()
	var registry: BlockRegistry = _registry()
	var reflections: SkyReflections = _bound(null, probe, registry, visuals)
	reflections.configure_probe(30.0, _interval_preset())
	var base_y: float = probe.position.y
	reflections.step(0.4)
	assert_eq(probe.position.y, base_y, "before the interval nothing happens")
	reflections.step(0.2)
	assert_almost_eq(probe.position.y, base_y + SkyReflections.PROBE_RETRIGGER_NUDGE_M, 0.000001,
		"first due step sees a new revision and nudges up")
	reflections.step(0.6)
	assert_almost_eq(probe.position.y, base_y + SkyReflections.PROBE_RETRIGGER_NUDGE_M, 0.000001,
		"layout unchanged: no retrigger")
	registry.reset()
	reflections.step(0.6)
	assert_almost_eq(probe.position.y, base_y, 0.000001, "a changed layout nudges back down")


func test_other_modes_never_step_the_interval() -> void:
	var visuals: TerritoryVisuals = _visuals()
	visuals.reflection_probe_update_always = true
	var probe: ReflectionProbe = _probe()
	var reflections: SkyReflections = _bound(null, probe, _registry(), visuals)
	reflections.configure_probe(30.0, _interval_preset())
	var base_y: float = probe.position.y
	reflections.step(5.0)
	assert_eq(probe.position.y, base_y, "ALWAYS probes update themselves")


func test_retrigger_needs_a_visible_update_once_probe() -> void:
	var probe: ReflectionProbe = _probe()
	var reflections: SkyReflections = _bound(null, probe, null, _visuals())
	probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	var base_y: float = probe.position.y
	reflections.retrigger_probe()
	assert_eq(probe.position.y, base_y, "UPDATE_ALWAYS is left alone")
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.visible = false
	reflections.retrigger_probe()
	assert_eq(probe.position.y, base_y, "a hidden probe is left alone")
	probe.visible = true
	reflections.retrigger_probe()
	reflections.retrigger_probe()
	assert_almost_eq(probe.position.y, base_y, 0.000001, "two nudges cancel")


func test_refresh_capture_reconfigures_with_the_last_arguments_and_keeps_it_visible() -> void:
	var visuals: TerritoryVisuals = _visuals()
	visuals.reflection_probe_update_always = false
	var probe: ReflectionProbe = _probe()
	var reflections: SkyReflections = _bound(null, probe, null, visuals)
	reflections.configure_probe(40.0, _interval_preset())
	probe.size = Vector3.ONE
	reflections.refresh_capture()
	var half: float = 40.0 + visuals.reflection_probe_margin_m
	assert_eq(probe.size.x, half * 2.0, "the remembered disc radius is reused")
	assert_true(probe.visible, "toggled off and on again")


func test_set_running_picks_the_radiance_mode() -> void:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	var reflections: SkyReflections = _bound(environment, null, null, _visuals())
	reflections.set_running(true)
	assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_REALTIME)
	reflections.set_running(false)
	assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_QUALITY)


func test_step_reports_a_radiance_tick_at_radiance_hz() -> void:
	var reflections: SkyReflections = _bound(null, null, null, _visuals(), 10.0)
	assert_false(reflections.step(0.05))
	assert_true(reflections.step(0.06), "0.11 s >= 0.1 s interval")
	assert_false(reflections.step(0.05), "the remainder (0.01) carries over")
