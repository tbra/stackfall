extends GutTest
## game/sky/Skybox.gd (spec 1.10): sky cycle, fog volume, reflection probe and SSR.

var _skybox: Skybox = null
var _ambient: AmbientLife = null

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
	skybox.sky_def = SkyTestKit.cycle()
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
		var material: ShaderMaterial = SkyTestKit.sky_material(skybox)
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
	assert_almost_eq(skybox.current_cycle_phase(), SkyTestKit.cycle().cycle_start_phase, 0.0001)
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
	skybox.set_storm_sky(0.5, load("res://config/sky/storm_overlay.tres") as SkyOverlayDef)
	SkyTestKit.settle(skybox)
	var lighting: CloudLighting = (skybox.get_node("CloudSea") as CloudSea).lighting
	assert_gt(lighting.storm, 0.0, "the storm shows before the reset")
	Events.match_scope_reset.emit()
	SkyTestKit.settle(skybox)
	assert_almost_eq(skybox.locked_phase(), skybox.sky_def.cycle_locked_phase_sunset, 0.0001, "reset returns to the launch lock")
	assert_eq(lighting.storm, 0.0, "reset clears the storm")


## A running cycle sky configured from `config`, advanced to the shared clock `clock`.
func _cycle_skybox(config: MatchConfig, clock: float) -> Skybox:
	var skybox: Skybox = _make_wired_skybox()["skybox"] as Skybox
	skybox.configure_match_sky(config)
	var context: FakeMatchContext = FakeMatchContext.new()
	var previous_context: MatchContext = MatchContext.installed()
	MatchContext.install(context)
	SkyTestKit.run_to_clock(skybox, context, clock)
	MatchContext.install(previous_context)
	return skybox


## [exposure, sea coverage] of the live sky material of `_cycle_skybox`.
func _cycle_look(config: MatchConfig, clock: float) -> Array[float]:
	return _look_of(_cycle_skybox(config, clock))


func _look_of(skybox: Skybox) -> Array[float]:
	var material: ShaderMaterial = SkyTestKit.sky_material(skybox)
	return [
		float(material.get_shader_parameter(&"exposure")),
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
	var def: SkyCycleDef = SkyTestKit.cycle()
	assert_eq(host_config.effective_sky_variation_seed(), 5551)
	var at_start: Skybox = _cycle_skybox(host_config, 0.0)
	var expected_exposure: float = SkyVariation.value_at(def.variation_exposure_min, def.variation_exposure_max,
		def.variation_knots_per_cycle, at_start.current_cycle_phase(), 5551, SkyVariation.CHANNEL_EXPOSURE)
	assert_eq(_look_of(at_start)[0], expected_exposure, "it is SkyVariation's function of that seed")


## F4 refresh: an edit of the live sky definition reaches the next evaluation after
## refresh_sky_def(), in a locked and in a running cycle.
func _bridge_case(running: bool) -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	var original: float = skybox.sky_def.day_keyframes[1].fog_density
	if running:
		skybox.start_cycle(-1.0, 0.47)
	else:
		skybox.set_locked_phase(0.47)
	SkyTestKit.settle(skybox)
	var before: float = environment.fog_density
	skybox.sky_def.day_keyframes[1].fog_density = original * 3.0
	skybox.refresh_sky_def()
	SkyTestKit.settle(skybox)
	var after: float = environment.fog_density
	assert_ne(after, before, "the edited fog density shows (running=%s)" % running)
	assert_almost_eq(skybox.sky_def.day_keyframes[1].fog_density, original * 3.0, 0.00001, "the keyframe carries the edit")


func test_f4_bridge_edit_reaches_a_locked_cycle() -> void:
	_bridge_case(false)


func test_f4_bridge_edit_reaches_a_running_cycle() -> void:
	_bridge_case(true)


const SENTINEL_UNIFORM: StringName = &"exposure"
const SENTINEL: float = -123.0


## Writes the sentinel into the live dome material and returns the material. The dome writer
## writes only the uniforms whose value changed, so a sentinel survives exactly while the sky
## output does not change.
func _plant_sentinel(skybox: Skybox) -> ShaderMaterial:
	var material: ShaderMaterial = SkyTestKit.sky_material(skybox)
	material.set_shader_parameter(SENTINEL_UNIFORM, SENTINEL)
	return material


class TimeOfDayCounter extends RefCounted:
	var count: int = 0

	func hit(_phase: float, _night_mix: float) -> void:
		count += 1


## Weather setters only queue requests: N requests in one frame show nothing until the frame's
## one flush, which then shows the stormed result and never re-runs the time-of-day stage.
func test_weather_requests_in_one_frame_flush_once() -> void:
	var skybox: Skybox = _make_wired_skybox()["skybox"] as Skybox
	SkyTestKit.settle(skybox)
	var lighting: CloudLighting = (skybox.get_node("CloudSea") as CloudSea).lighting
	assert_eq(lighting.storm, 0.0)
	var material: ShaderMaterial = _plant_sentinel(skybox)
	var counter: TimeOfDayCounter = TimeOfDayCounter.new()
	Events.sky_time_of_day_changed.connect(counter.hit)
	skybox.set_storm_sky(0.3, load("res://config/sky/storm_overlay.tres") as SkyOverlayDef)
	skybox.set_overcast(0.4, 0.6, 0.7, 0.8, Color(0.6, 0.6, 0.7), 0.5)
	skybox.set_weather_fog(0.5, 0.8, 30.0, 400.0, Color(0.7, 0.7, 0.75), 0.5, 0.2)
	skybox.set_snow_brighten(0.4)
	skybox.set_sun_cloud_scale(0.7)
	skybox.set_weather_cloud_overcast(0.3)
	assert_eq(material.get_shader_parameter(SENTINEL_UNIFORM), SENTINEL, "setters do not evaluate")
	assert_eq(lighting.storm, 0.0, "nothing shows before the frame's flush")
	SkyTestKit.settle(skybox)
	Events.sky_time_of_day_changed.disconnect(counter.hit)
	assert_ne(material.get_shader_parameter(SENTINEL_UNIFORM), SENTINEL, "the flush wrote the stormed sky")
	assert_gt(lighting.storm, 0.0, "the stormed result shows")
	assert_eq(counter.count, 0, "weather never reruns the time-of-day stage")
	material.set_shader_parameter(SENTINEL_UNIFORM, SENTINEL)
	SkyTestKit.settle(skybox)
	assert_eq(material.get_shader_parameter(SENTINEL_UNIFORM), SENTINEL, "a clean flush does nothing")


## A locked sky with no weather writes nothing to the sky material after its first frame (the
## radiance is never re-rendered).
func test_locked_sky_without_weather_writes_nothing_per_frame() -> void:
	var skybox: Skybox = _make_wired_skybox()["skybox"] as Skybox
	skybox._process(0.016)
	var material: ShaderMaterial = _plant_sentinel(skybox)
	for i: int in 30:
		skybox._process(0.016)
	assert_eq(material.get_shader_parameter(SENTINEL_UNIFORM), SENTINEL, "no sky-material writes while locked and clear")


func test_sun_cloud_scale_changes_only_the_light() -> void:
	var skybox: Skybox = _make_wired_skybox()["skybox"] as Skybox
	SkyTestKit.settle(skybox)
	var material: ShaderMaterial = _plant_sentinel(skybox)
	skybox.set_sun_cloud_scale(0.6)
	SkyTestKit.settle(skybox)
	assert_eq(material.get_shader_parameter(SENTINEL_UNIFORM), SENTINEL, "a sun dim leaves the sky material alone")


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
	_ambient = AmbientLife.build(null, null)
	add_child_autofree(_ambient)
	var skybox: Skybox = _make_wired_skybox()["skybox"] as Skybox
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.NIGHT
	config.resolve_sky_theme(0)
	skybox.configure_match_sky(config)
	return skybox


## Asserts the cloud puffs and ambient life of a sky locked at full night.
func _assert_locked_night_dressing(skybox: Skybox, label: String) -> void:
	var night_key: SkyNightKeyframe = skybox.sky_def.night
	var night_tones: Dictionary = {
		&"shadow_color": night_key.puff_shadow_color, &"mid_color": night_key.puff_mid_color,
		&"lit_color": night_key.puff_lit_color, &"rim_color": night_key.puff_rim_color,
	}
	var puffs: ShaderMaterial = SkyTestKit.puff_material(skybox.get_node("CloudSea") as CloudSea)
	assert_not_null(puffs, "%s: the cloud sea has puffs" % label)
	if puffs == null:
		return
	assert_true(skybox.locked_phase() >= 0.0, "%s: the sky stays locked" % label)
	var grade: Variant = puffs.get_shader_parameter(&"grade_amount")
	assert_true(grade is float and is_equal_approx(grade as float, 1.0), "%s: puff grade is the night value (got %s)" % [label, grade])
	for parameter: StringName in [&"shadow_color", &"mid_color", &"lit_color", &"rim_color"]:
		var colour: Color = puffs.get_shader_parameter(parameter) as Color
		assert_true(colour.is_equal_approx(night_tones[parameter] as Color), "%s: puff %s is the night mix" % [label, parameter])
	var sun: Vector3 = SkyTestKit.sky_material(skybox).get_shader_parameter(&"sun_direction") as Vector3
	assert_true((puffs.get_shader_parameter(&"light_direction") as Vector3).is_equal_approx(sun), "%s: puffs are lit from the cycle sun, not the authored one" % label)
	assert_false((_ambient.get_node("DistantBirds") as DistantBirds).visible, "%s: no distant day birds at night" % label)
	assert_false((_ambient.get_node("PerchingBirds") as PerchingBirds).visible, "%s: the night life config has no perching birds" % label)
	assert_true((_ambient.get_node("Fireflies") as Fireflies).visible, "%s: fireflies swarm at night" % label)


func test_graphics_preset_change_keeps_a_locked_night_dressed_as_night() -> void:
	var skybox: Skybox = _make_locked_night_skybox()
	_assert_locked_night_dressing(skybox, "before the change")

	# The real signal path: Settings emits graphics_preset_changed to the live Skybox.
	Settings.set_graphics_preset(&"medium")
	_assert_locked_night_dressing(skybox, "after the preset change")

	# The handler itself (what the adaptive governor's level change ends up calling).
	skybox._on_graphics_preset_changed(Settings.current_graphics_preset())
	_assert_locked_night_dressing(skybox, "after the handler")


func test_storm_request_between_ticks_recaptures_an_update_once_probe() -> void:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.sky_def = SkyTestKit.cycle()
	var probe: ReflectionProbe = ReflectionProbe.new()
	probe.name = "Probe"
	skybox.add_child(probe)
	skybox.reflection_probe_path = NodePath("Probe")
	add_child_autofree(skybox)
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	skybox.set_locked_phase(0.25)
	SkyTestKit.settle(skybox)
	probe.visible = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	var before: float = probe.position.y
	skybox.set_storm_sky(0.5, load("res://config/sky/storm_overlay.tres") as SkyOverlayDef)
	SkyTestKit.settle(skybox)
	assert_ne(probe.position.y, before, "the probe was nudged to re-capture the stormed sky")


func _make_probe_skybox() -> Array:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.sky_def = SkyTestKit.cycle()
	var probe: ReflectionProbe = ReflectionProbe.new()
	probe.name = "Probe"
	skybox.add_child(probe)
	skybox.reflection_probe_path = NodePath("Probe")
	add_child_autofree(skybox)
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	skybox.set_locked_phase(0.25)
	SkyTestKit.settle(skybox)
	probe.visible = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	return [skybox, probe]


func test_storm_fade_retriggers_the_probe_at_most_once_per_radiance_interval() -> void:
	var made: Array = _make_probe_skybox()
	var skybox: Skybox = made[0] as Skybox
	var probe: ReflectionProbe = made[1] as ReflectionProbe
	var storm: SkyOverlayDef = load("res://config/sky/storm_overlay.tres") as SkyOverlayDef
	var frames: int = 60
	var delta: float = 1.0 / 60.0
	var retriggers: int = 0
	var last_y: float = probe.position.y
	for frame: int in frames:
		skybox.set_storm_sky(float(frame + 1) / float(frames), storm)
		skybox._process(delta)
		if not is_equal_approx(probe.position.y, last_y):
			retriggers += 1
			last_y = probe.position.y
	var fade_s: float = float(frames) * delta
	var limit: int = ceili(fade_s * skybox.radiance_config.radiance_hz) + 1
	assert_gt(retriggers, 0, "the fade re-captured the probe")
	assert_lte(retriggers, limit, "bounded by the radiance cadence")
	# Settled: one trailing capture within an interval, then none.
	var settled: int = 0
	for frame: int in frames:
		skybox._process(delta)
		if not is_equal_approx(probe.position.y, last_y):
			settled += 1
			last_y = probe.position.y
	assert_lte(settled, 1, "at most one settle capture")
	var stable: float = probe.position.y
	skybox._process(delta)
	assert_eq(probe.position.y, stable, "no further retriggers once settled")


func test_set_storm_sky_without_overlay_is_a_no_op() -> void:
	var skybox: Skybox = _make_probe_skybox()[0] as Skybox
	skybox.set_storm_sky(0.0, null)
	SkyTestKit.settle(skybox)
	var lighting: CloudLighting = (skybox.get_node("CloudSea") as CloudSea).lighting
	var material: ShaderMaterial = _plant_sentinel(skybox)
	skybox.set_storm_sky(0.7, null)
	skybox.set_storm_sky(0.7, null)
	SkyTestKit.settle(skybox)
	assert_eq(material.get_shader_parameter(SENTINEL_UNIFORM), SENTINEL, "a stormless request with no overlay changes nothing")
	assert_eq(lighting.storm, 0.0, "no overlay, no storm")
