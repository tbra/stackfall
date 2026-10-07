extends GutTest
## Bontago-1pi.11.37: adaptive quality governor (core/perf/QualityGovernor.gd, the
## Settings integration and game/QualityGovernorDriver.gd).

const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")
const MEDIUM_PATH: String = "res://config/graphics_presets/medium.tres"

var _cfg: QualityGovernorConfig = null
var _cfg_counter: int = 0


func before_each() -> void:
	_cfg = QualityGovernorConfig.new()


func _settings() -> Node:
	var node: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(node)
	_cfg_counter += 1
	var path: String = OS.get_user_data_dir().path_join("test_quality_governor_%d.cfg" % _cfg_counter)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	node.set_config_path_for_test(path)
	return node


func _stress(gov: QualityGovernor, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		gov.evaluate(_cfg.target_frame_ms * 2.0, 0, _cfg.sample_interval_s)
		t += _cfg.sample_interval_s


func _calm(gov: QualityGovernor, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		gov.evaluate(5.0, 0, _cfg.sample_interval_s)
		t += _cfg.sample_interval_s


func test_sustained_stress_sheds_steps_in_order() -> void:
	var gov: QualityGovernor = QualityGovernor.new(_cfg)
	var base: GraphicsPreset = load(MEDIUM_PATH) as GraphicsPreset
	_stress(gov, _cfg.shed_delay_s)
	assert_eq(gov.level, 1)
	var p1: GraphicsPreset = QualityGovernor.apply(base, 1, _cfg)
	assert_lt(p1.particle_budget_scale, 1.0)
	assert_eq(p1.weather_density_scale, 1.0, "weather is step 2")
	_stress(gov, _cfg.shed_delay_s)
	assert_eq(gov.level, 2)
	var p2: GraphicsPreset = QualityGovernor.apply(base, 2, _cfg)
	assert_lt(p2.weather_density_scale, 1.0)
	var p3: GraphicsPreset = QualityGovernor.apply(base, 3, _cfg)
	assert_lt(p3.sun_shadow_max_distance, base.sun_shadow_max_distance)
	assert_true(p3.volumetric_fog_enabled)
	assert_false(QualityGovernor.apply(base, 4, _cfg).volumetric_fog_enabled)
	assert_lt(QualityGovernor.apply(base, 5, _cfg).render_scale_3d, 1.0)
	_stress(gov, 100.0)
	assert_eq(gov.level, gov.max_level(), "stops at the last step")


func test_short_spike_does_not_shed_and_awake_count_alone_does() -> void:
	var gov: QualityGovernor = QualityGovernor.new(_cfg)
	gov.evaluate(_cfg.target_frame_ms * 3.0, 0, _cfg.shed_delay_s * 0.5)
	gov.evaluate(5.0, 0, _cfg.sample_interval_s)
	gov.evaluate(_cfg.target_frame_ms * 3.0, 0, _cfg.shed_delay_s * 0.5)
	assert_eq(gov.level, 0, "an interrupted spike restarts the timer")
	assert_true(gov.evaluate(5.0, _cfg.awake_high, _cfg.shed_delay_s), "high awake count sheds even at a good frame time")


func test_recovery_restores_with_hysteresis() -> void:
	var gov: QualityGovernor = QualityGovernor.new(_cfg)
	_stress(gov, _cfg.shed_delay_s * 3.0)
	assert_eq(gov.level, 3)
	var in_band: float = _cfg.target_frame_ms * (_cfg.recover_frame_ratio + 1.0) * 0.5
	for i: int in range(100):
		gov.evaluate(in_band, 0, _cfg.sample_interval_s)
	assert_eq(gov.level, 3, "no restore inside the hysteresis band")
	for i: int in range(100):
		gov.evaluate(5.0, _cfg.awake_settled + 1, _cfg.sample_interval_s)
	assert_eq(gov.level, 3, "no restore while the pile is unsettled")
	_calm(gov, _cfg.restore_delay_s - _cfg.sample_interval_s)
	assert_eq(gov.level, 3, "restore needs the full delay")
	_calm(gov, _cfg.sample_interval_s)
	assert_eq(gov.level, 2)
	_calm(gov, _cfg.restore_delay_s * 2.0)
	assert_eq(gov.level, 0)


func test_off_does_nothing() -> void:
	var settings: Node = _settings()
	assert_false(settings.adaptive_quality_enabled(), "defaults to OFF")
	var emitted: Array[int] = [0]
	settings.graphics_preset_changed.connect(func(_p: GraphicsPreset) -> void: emitted[0] += 1)
	settings.set_governor_level(4)
	assert_eq(settings.governor_level(), 0)
	assert_eq(emitted[0], 0)
	var driver: QualityGovernorDriver = QualityGovernorDriver.new()
	driver.settings_node = settings
	add_child_autofree(driver)
	assert_false(driver.is_processing(), "driver idles while OFF")
	for i: int in range(20):
		driver.sample(500.0, 500, 10.0)
	assert_eq(settings.governor_level(), 0)
	assert_eq(settings.current_graphics_preset().particle_budget_scale, 1.0)


func test_driver_sheds_through_settings_and_user_settings_are_untouched() -> void:
	var settings: Node = _settings()
	settings.set_graphics_preset(&"high")
	settings.set_adaptive_quality_enabled(true)
	var distance_before: float = settings.stored_graphics_preset().sun_shadow_max_distance
	var driver: QualityGovernorDriver = QualityGovernorDriver.new()
	driver.settings_node = settings
	add_child_autofree(driver)
	assert_true(driver.is_processing())
	var cfg: QualityGovernorConfig = driver.config
	for i: int in range(int(cfg.shed_delay_s / cfg.sample_interval_s) + 1):
		driver.sample(cfg.target_frame_ms * 2.0, 0, cfg.sample_interval_s)
	assert_eq(settings.governor_level(), 1)
	assert_lt(settings.current_graphics_preset().particle_budget_scale, 1.0)
	assert_eq(settings.stored_graphics_preset().particle_budget_scale, 1.0)
	settings.set_governor_level(4)
	assert_false(settings.current_graphics_preset().volumetric_fog_enabled)
	assert_true(settings.stored_graphics_preset().volumetric_fog_enabled)
	assert_eq(settings.stored_graphics_preset().sun_shadow_max_distance, distance_before)
	var cfg_file: ConfigFile = ConfigFile.new()
	cfg_file.load(settings._config_path)
	assert_eq(cfg_file.get_value("graphics", "preset"), "high", "saved preset id is the user choice")
	assert_false(cfg_file.has_section_key("graphics", "governor_level"), "level is never persisted")
	settings.set_adaptive_quality_enabled(false)
	assert_eq(settings.governor_level(), 0)
	var restored: GraphicsPreset = settings.current_graphics_preset()
	assert_eq(restored.particle_budget_scale, 1.0)
	assert_true(restored.volumetric_fog_enabled)
	assert_eq(restored.sun_shadow_max_distance, distance_before)


func test_preset_change_while_shed_resolves_on_the_new_preset() -> void:
	var settings: Node = _settings()
	settings.set_graphics_preset(&"high")
	settings.set_adaptive_quality_enabled(true)
	settings.set_governor_level(3)
	var seen: Array[GraphicsPreset] = []
	settings.graphics_preset_changed.connect(func(p: GraphicsPreset) -> void: seen.append(p))
	settings.set_graphics_preset(&"low")
	assert_eq(seen.size(), 1)
	var low: GraphicsPreset = load("res://config/graphics_presets/low.tres") as GraphicsPreset
	var effective: GraphicsPreset = seen[0]
	assert_eq(effective.id, &"low")
	assert_eq(effective.particle_budget_scale, minf(low.particle_budget_scale, _cfg.shed_particle_budget_scale), "governor override still on")
	assert_eq(effective.sun_shadow_max_distance, minf(low.sun_shadow_max_distance, _cfg.shed_shadow_max_distance_m))
	assert_eq(effective.cloud_puff_density, low.cloud_puff_density, "new preset own fields win")
	assert_eq(settings.stored_graphics_preset().id, &"low")
	assert_eq(settings.stored_graphics_preset().particle_budget_scale, low.particle_budget_scale)
	assert_eq(QualityGovernor.apply(low, 5, _cfg).sun_shadow_mode, mini(low.sun_shadow_mode, _cfg.shed_shadow_mode))
