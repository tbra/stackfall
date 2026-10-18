extends GutTest
## game/sky/Skybox.gd (spec 1.10): theme, cycle, fog volume, reflection probe and SSR.

var _skybox: Skybox = null

## saved/restored the same way tests/unit/test_main_graphics_
## preset.gd's own _original_preset_id does -- the real "Settings" autoload
## outlives this script, so a FogVolume-gating test that calls
## Settings.set_graphics_preset() must not leak a changed preset into whatever
## test file the runner loads next in the same process.
var _original_preset_id: StringName


func before_each() -> void:
	_original_preset_id = Settings.current_graphics_preset().id
	_skybox = Skybox.new()
	_skybox.config = SkyboxConfig.new()
	add_child_autofree(_skybox)


func after_each() -> void:
	Settings.set_graphics_preset(_original_preset_id)


## A fresh Skybox + Environment pair, independent of before_each()'s plain
## `_skybox` (which every existing test above relies on staying unwired --
## Skybox.gd's own doc: environment is optional and every sky-material write
## no-ops without it).
func _make_wired_skybox() -> Dictionary:
	var procedural: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	var sky: Sky = Sky.new()
	sky.sky_material = procedural
	var environment: Environment = Environment.new()
	environment.sky = sky

	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = SkyThemeDef.new()
	add_child_autofree(skybox)

	return {"skybox": skybox, "environment": environment, "procedural": procedural}


func test_cycle_key_light_and_flare_follow_the_sun() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "CycleKey"
	skybox.add_child(light)
	skybox.light_path = NodePath("CycleKey")
	var flare: SunFlare = SunFlare.new()
	add_child_autofree(flare)
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	for phase: float in [0.0, 0.25, 0.5, 0.75]:
		skybox.set_cycle_phase(phase)
		var material: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
		var sun: Vector3 = material.get_shader_parameter(&"sun_direction") as Vector3
		assert_true(light.light_energy >= 0.0)
		assert_true(light.global_basis.z.y >= -0.001, "key light must never shine from below")
		assert_true(flare.config.sun_direction.is_equal_approx(sun), "flare must track the sky disc")
		if sun.y < -0.01:
			assert_true(light.light_energy < 0.5, "night key must stay dim")
			assert_false(flare._theme_enabled)


## F4's "cycle" Theme entry persists as theme_name "cycle" and
## _ready() runs the cycle from boot (it is not a theme file); any other name
## still loads its static theme.
func test_ready_starts_the_cycle_for_theme_name_cycle() -> void:
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment: Environment = Environment.new()
	environment.sky = sky
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.config.theme_name = Skybox.CYCLE_THEME_ID
	skybox.environment = environment
	add_child_autofree(skybox)
	assert_true(skybox.is_cycle_active(), "the persisted cycle entry runs at boot")
	assert_eq(skybox.locked_phase(), -1.0)
	assert_almost_eq(skybox.current_cycle_phase(), (Skybox.load_theme("sunset") as SkyThemeDef).cycle_start_phase, 0.0001)
	assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_REALTIME)
	assert_not_null(skybox.get_node("CloudSea") as CloudSea, "the layers the cycle drives exist")

	# Any other launch id is the same cycle locked at that id's phase (no static theme any more).
	var locked_skybox: Skybox = Skybox.new()
	locked_skybox.config = SkyboxConfig.new()
	locked_skybox.config.theme_name = "night"
	locked_skybox.environment = Environment.new()
	locked_skybox.environment.sky = Sky.new()
	add_child_autofree(locked_skybox)
	assert_true(locked_skybox.is_cycle_active(), "boot is always the cycle")
	assert_almost_eq(locked_skybox.locked_phase(), locked_skybox.sky_def.cycle_locked_phase_night, 0.0001, "locked at the night phase")


## The one intended visual delta (Q4): the bare launch sky is the cycle locked at
## SkyboxConfig.theme_name (sunset by default), not the static sunset theme.
func test_boot_and_reset_are_the_cycle_locked_at_the_launch_sky_id() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	assert_true(skybox.is_cycle_active())
	assert_almost_eq(skybox.locked_phase(), skybox.sky_def.cycle_locked_phase_sunset, 0.0001, "default launch = sunset")
	assert_eq((wired["environment"] as Environment).sky.process_mode, Sky.PROCESS_MODE_QUALITY, "a locked sky is built once")
	skybox.set_locked_phase(0.75)
	skybox.set_storm_sky(0.5, Skybox.load_theme("storm"))
	skybox.flush_weather()
	skybox.reset_to_launch()
	assert_almost_eq(skybox.locked_phase(), skybox.sky_def.cycle_locked_phase_sunset, 0.0001, "reset returns to the launch lock")
	assert_eq(skybox.weather_state().storm_amount, 0.0, "reset clears the storm")


## C1b follow-up: a running cycle sky configured from `config`, with
## the clock at `clock`; returns [exposure, cloud coverage, sea coverage] of its live
## sky material.
func _cycle_look(config: MatchConfig, clock: float) -> Array[float]:
	var skybox: Skybox = _make_wired_skybox()["skybox"] as Skybox
	skybox.configure_match_sky(config)
	skybox.update_cycle_clock(clock)
	var material: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
	return [
		float(material.get_shader_parameter(&"exposure")),
		float(material.get_shader_parameter(&"cloud_coverage")),
		float(material.get_shader_parameter(&"proc_sea_coverage")),
	]


func _resolved_config(variation_seed: int) -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	config.resolve_sky_variation_seed(variation_seed)
	return config


## C1b follow-up: the host-rolled MatchConfig.sky_variation_seed drives
## the sky. Two skyboxes with the same resolved seed (the host's, and a client built from
## its wire dict) draw the same sky; a different seed draws a different one; the seed the
## skybox reports is the config's.
func test_skyboxes_with_the_same_resolved_sky_variation_seed_match_and_different_seeds_differ() -> void:
	var host_config: MatchConfig = _resolved_config(5551)
	var client_config: MatchConfig = MatchConfig.from_dict(host_config.to_dict())
	var other_config: MatchConfig = _resolved_config(5552)
	var host: Skybox = _make_wired_skybox()["skybox"] as Skybox
	host.configure_match_sky(host_config)
	assert_eq(host.variation_seed(), 5551, "the skybox draws from the host's resolved seed")
	var differs: bool = false
	for clock: float in [0.0, 40.0, 95.0, 150.0, 210.0, 280.0]:
		var host_look: Array[float] = _cycle_look(host_config, clock)
		assert_eq(_cycle_look(client_config, clock), host_look, "same seed, same sky at clock %s" % clock)
		if not is_equal_approx(_cycle_look(other_config, clock)[0], host_look[0]):
			differs = true
	assert_true(differs, "a different resolved seed draws a different curve")
	var theme: SkyThemeDef = Skybox.load_theme(Skybox.DEFAULT_THEME_ID)
	assert_eq(host_config.effective_sky_variation_seed(), 5551)
	assert_eq(_cycle_look(host_config, 0.0)[0], SkyVariation.exposure_at(theme, host.cycle_phase_at(0.0), 5551), "it is SkyVariation's function of that seed")


## F4 bridge: an edit of the live sunset theme reaches the next evaluation after
## refresh_cycle_sources(), in a locked and in a running cycle.
func _bridge_case(running: bool) -> void:
	var skybox: Skybox = _make_wired_skybox()["skybox"] as Skybox
	var sunset: SkyThemeDef = Skybox.load_theme(Skybox.DEFAULT_THEME_ID)
	var original: float = sunset.fog_density
	if running:
		skybox.start_cycle(-1.0, 0.47)
	else:
		skybox.set_locked_phase(0.47)
	var before: float = skybox.current_frame().fog_density
	sunset.fog_density = original * 3.0
	skybox.refresh_cycle_sources()
	var after: float = skybox.current_frame().fog_density
	sunset.fog_density = original
	assert_ne(after, before, "the edited fog density shows (running=%s)" % running)
	assert_almost_eq(skybox.sky_def.day_keyframes[1].fog_density, original * 3.0, 0.00001, "the keyframe carries the edit")


func test_f4_bridge_edit_reaches_a_locked_cycle() -> void:
	_bridge_case(false)


func test_f4_bridge_edit_reaches_a_running_cycle() -> void:
	_bridge_case(true)


## Weather setters only mark stages dirty: N requests in one frame run stage A zero times and
## stages B and C once.
func test_weather_requests_in_one_frame_flush_once() -> void:
	var skybox: Skybox = _make_wired_skybox()["skybox"] as Skybox
	skybox.flush_weather()
	var ticks: int = skybox.tick_runs
	var storms: int = skybox.storm_runs
	var weathers: int = skybox.weather_runs
	skybox.set_storm_sky(0.3, Skybox.load_theme("storm"))
	skybox.set_overcast(0.4, 0.6, 0.7, 0.8, Color(0.6, 0.6, 0.7), 0.5)
	skybox.set_weather_fog(0.5, 0.8, 30.0, 400.0, Color(0.7, 0.7, 0.75), 0.5, 0.2)
	skybox.set_snow_brighten(0.4)
	skybox.set_sun_cloud_scale(0.7)
	skybox.set_weather_cloud_overcast(0.3)
	assert_eq(skybox.tick_runs, ticks, "setters never run stage A")
	assert_eq(skybox.weather_runs, weathers, "setters do not evaluate")
	skybox.flush_weather()
	assert_eq(skybox.tick_runs, ticks, "weather never reruns stage A")
	assert_eq(skybox.storm_runs, storms + 1, "stage B once")
	assert_eq(skybox.weather_runs, weathers + 1, "stage C once")
	skybox.flush_weather()
	assert_eq(skybox.weather_runs, weathers + 1, "a clean flush does nothing")


## A locked sky with no weather writes nothing to the sky material after its first frame (the
## radiance is never re-rendered).
func test_locked_sky_without_weather_writes_nothing_per_frame() -> void:
	var skybox: Skybox = _make_wired_skybox()["skybox"] as Skybox
	skybox._process(0.016)
	var writes: int = skybox.sky_material_writes
	for i: int in 30:
		skybox._process(0.016)
	assert_eq(skybox.sky_material_writes, writes, "no sky-material writes while locked and clear")


func test_sun_cloud_scale_changes_only_the_light() -> void:
	var skybox: Skybox = _make_wired_skybox()["skybox"] as Skybox
	skybox.flush_weather()
	var writes: int = skybox.sky_material_writes
	skybox.set_sun_cloud_scale(0.6)
	skybox.flush_weather()
	assert_eq(skybox.sky_material_writes, writes, "a sun dim leaves the sky material alone")


func test_fog_volume_is_created_but_hidden_on_low_preset() -> void:
	Settings.set_graphics_preset(&"low")
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	add_child_autofree(skybox)

	var fog_volume: FogVolume = skybox.get_node_or_null("CloudDeck") as FogVolume
	assert_not_null(fog_volume, "a FogVolume child must always be created, only its visibility is gated")
	assert_false(fog_volume.visible, "low preset must hide the cloud-deck FogVolume")


## C1a review fix: a graphics-preset change (the settings menu or the
## adaptive governor) rebuilds the cloud puffs and ambient life from the DAY
## palette. A running cycle heals on its next frame, but a locked cycle never
## re-runs set_cycle_phase() on its own, so the match stayed dressed as day inside
## a locked Night until the lock changed.
func _make_locked_night_skybox() -> Skybox:
	Settings.set_graphics_preset(&"high")
	var skybox: Skybox = _make_wired_skybox()["skybox"] as Skybox
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.NIGHT
	config.resolve_sky_theme(0)
	skybox.configure_match_sky(config)
	return skybox


## Asserts the cloud puffs and ambient life of a sky locked at full night.
func _assert_locked_night_dressing(skybox: Skybox, label: String) -> void:
	var night: SkyThemeDef = Skybox.load_theme(Skybox.CYCLE_NIGHT_THEME_ID)
	var night_puffs: ShaderMaterial = night.cloud_puff_material as ShaderMaterial
	var puffs: ShaderMaterial = (skybox.get_node("CloudSea") as CloudSea).puff_material()
	assert_not_null(puffs, "%s: the cloud sea has puffs" % label)
	if puffs == null:
		return
	assert_true(skybox.locked_phase() >= 0.0, "%s: the sky stays locked" % label)
	var grade: Variant = puffs.get_shader_parameter(&"grade_amount")
	assert_true(grade is float and is_equal_approx(grade as float, 1.0), "%s: puff grade is the night value (got %s)" % [label, grade])
	for parameter: StringName in [&"shadow_color", &"mid_color", &"lit_color", &"rim_color"]:
		var colour: Color = puffs.get_shader_parameter(parameter) as Color
		assert_true(colour.is_equal_approx(night_puffs.get_shader_parameter(parameter) as Color), "%s: puff %s is the night mix" % [label, parameter])
	var sun: Vector3 = (skybox.theme.sky_material as ShaderMaterial).get_shader_parameter(&"sun_direction") as Vector3
	assert_true((puffs.get_shader_parameter(&"light_direction") as Vector3).is_equal_approx(sun), "%s: puffs are lit from the cycle sun, not the authored one" % label)
	assert_false((skybox.get_node("DistantBirds") as DistantBirds).visible, "%s: no distant day birds at night" % label)
	assert_false((skybox.get_node("PerchingBirds") as PerchingBirds).visible, "%s: the night life config has no perching birds" % label)
	assert_true((skybox.get_node("Fireflies") as Fireflies).visible, "%s: fireflies swarm at night" % label)


func test_graphics_preset_change_keeps_a_locked_night_dressed_as_night() -> void:
	var skybox: Skybox = _make_locked_night_skybox()
	_assert_locked_night_dressing(skybox, "before the change")

	# The real signal path: Settings emits graphics_preset_changed to the live Skybox.
	Settings.set_graphics_preset(&"medium")
	_assert_locked_night_dressing(skybox, "after the preset change")

	# The handler itself (what the adaptive governor's level change ends up calling).
	skybox._on_graphics_preset_changed(Settings.current_graphics_preset())
	_assert_locked_night_dressing(skybox, "after the handler")

