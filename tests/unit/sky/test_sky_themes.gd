extends GutTest
## night theme resource, theme-driven light/environment,
## 3D cloud-puff sea and distant bird flocks.

const NIGHT_PATH: String = "res://config/sky/themes/night.tres"
const SUNSET_PATH: String = "res://config/sky/themes/sunset.tres"


func _make_skybox(theme: SkyThemeDef) -> Array:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "Light"
	add_child_autofree(light)
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = theme
	skybox.light_path = skybox.get_path_to(light) if skybox.is_inside_tree() else NodePath("")
	add_child_autofree(skybox)
	# a persistent CloudCeiling (the weather presenter inside MatchNet)
	# pushes a fading storm blend into every skybox in this group; an earlier script's
	# weather events leave it mid-fade, so this fixture opts out and stays isolated.
	skybox.remove_from_group(Skybox.OVERCAST_GROUP)
	skybox.light_path = skybox.get_path_to(light)
	return [skybox, environment, light]


func test_apply_theme_writes_light_and_environment() -> void:
	var night: SkyThemeDef = load(NIGHT_PATH) as SkyThemeDef
	var parts: Array = _make_skybox(load(SUNSET_PATH) as SkyThemeDef)
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var light: DirectionalLight3D = parts[2]
	skybox.apply_theme(night)
	assert_almost_eq(light.light_energy, night.light_energy, 0.0001)
	assert_eq(light.light_color, night.light_color)
	assert_almost_eq(environment.ambient_light_energy, night.ambient_energy, 0.0001)
	assert_almost_eq(environment.glow_hdr_threshold, night.glow_hdr_threshold, 0.0001)


func _ambient_child_count(skybox: Skybox) -> int:
	# Every node under the skybox plus the multimesh instance counts: repeated
	# switches must not accumulate nodes or puffs.
	var total: int = 0
	var stack: Array[Node] = [skybox]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		total += 1
		for child: Node in node.get_children():
			if not child.is_queued_for_deletion():
				stack.append(child)
	return total


func test_live_theme_switch_is_stable_and_matches_the_theme() -> void:
	var parts: Array = _make_skybox(load(SUNSET_PATH) as SkyThemeDef)
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var light: DirectionalLight3D = parts[2]
	var flare: SunFlare = SunFlare.new()
	add_child_autofree(flare)
	var night: SkyThemeDef = load(NIGHT_PATH) as SkyThemeDef
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var saved_theme_name: String = skybox.config.theme_name
	assert_true(skybox.set_theme_by_id("night"))
	await get_tree().process_frame
	var baseline: int = _ambient_child_count(skybox)
	var night_puffs: int = skybox.get_cloud_sea().puff_count()
	assert_eq(night_puffs, (night.cloud_clump_count + night.cloud_bank_count) * night.cloud_puffs_per_clump
		if Settings.current_graphics_preset() == null
		else skybox.get_cloud_sea().puff_count())
	for cycle: int in range(4):
		assert_true(skybox.set_theme_by_id("sunset"))
		assert_eq(light.light_color, sunset.light_color)
		assert_almost_eq(light.light_energy, sunset.light_energy, 0.0001)
		assert_almost_eq(environment.ambient_light_energy, sunset.ambient_energy, 0.0001)
		assert_almost_eq(environment.fog_density, sunset.fog_density, 0.000001)
		assert_true(flare.is_theme_enabled())
		assert_true(skybox.set_theme_by_id("night"))
		assert_eq(light.light_color, night.light_color)
		assert_almost_eq(light.light_energy, night.light_energy, 0.0001)
		assert_almost_eq(light.rotation_degrees.x, night.light_rotation_deg.x, 0.001)
		assert_almost_eq(environment.glow_hdr_threshold, night.glow_hdr_threshold, 0.0001)
		assert_eq(environment.sky.sky_material, night.sky_material)
		assert_false(flare.is_theme_enabled(), "night hides the sunset-aimed flare")
		var fog: FogVolume = skybox.get_fog_volume()
		assert_eq(fog.size, night.cloud_deck_size_m)
		assert_eq((fog.material as FogMaterial).albedo, night.fog_color)
		await get_tree().process_frame
		assert_eq(skybox.get_cloud_sea().puff_count(), night_puffs, "same puff count each night switch")
		assert_eq(_ambient_child_count(skybox), baseline, "no leaked or duplicated nodes")
	assert_true(skybox.set_theme_by_id("sunset"))
	assert_eq(environment.sky.sky_material, sunset.sky_material)
	assert_false(skybox.set_theme_by_id("no_such_theme"))
	skybox.config.theme_name = saved_theme_name


func _cycle_skybox() -> Skybox:
	var parts: Array = _make_skybox(load(SUNSET_PATH) as SkyThemeDef)
	var skybox: Skybox = parts[0] as Skybox
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	return skybox


func test_cycle_runs_a_full_loop_in_the_authored_length() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var saved_length: float = sunset.cycle_length_seconds
	sunset.cycle_length_seconds = 300.0
	var skybox: Skybox = _cycle_skybox()
	assert_almost_eq(skybox.cycle_length_seconds(), 300.0, 0.001)
	# the cycle opens at SkyThemeDef.cycle_start_phase, not at dawn.
	var start: float = sunset.cycle_start_phase
	skybox.update_cycle_clock(75.0)
	assert_almost_eq(skybox.cycle_phase_at(75.0), fposmod(start + 0.25, 1.0), 0.0001, "a quarter of 5 min on")
	skybox.update_cycle_clock(150.0)
	assert_almost_eq(skybox.cycle_phase_at(150.0), fposmod(start + 0.5, 1.0), 0.0001)
	assert_almost_eq(skybox.cycle_phase_at(300.0), start, 0.0001, "a full cycle takes 300 s")
	sunset.cycle_length_seconds = saved_length


## a live length edit changes the speed only; the time of day
## at the moment of the edit is unchanged.
func test_cycle_length_change_keeps_the_phase_continuous() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var saved_length: float = sunset.cycle_length_seconds
	sunset.cycle_length_seconds = 300.0
	var skybox: Skybox = _cycle_skybox()
	skybox.update_cycle_clock(100.0)
	var before: float = skybox.cycle_phase_at(100.0)
	skybox.set_cycle_length_seconds(900.0)
	assert_almost_eq(skybox.cycle_length_seconds(), 900.0, 0.001)
	assert_almost_eq(skybox.cycle_phase_at(100.0), before, 0.0001, "no jump at the edit")
	skybox.update_cycle_clock(190.0)
	assert_almost_eq(skybox.cycle_phase_at(190.0), fposmod(before + 90.0 / 900.0, 1.0), 0.0001,
		"afterwards the phase advances at the new rate")
	skybox.set_cycle_length_seconds(60.0)
	assert_almost_eq(skybox.cycle_phase_at(190.0), fposmod(before + 90.0 / 900.0, 1.0), 0.0001, "shortening is continuous too")
	skybox.update_cycle_clock(220.0)
	assert_almost_eq(skybox.cycle_phase_at(220.0), fposmod(before + 90.0 / 900.0 + 30.0 / 60.0, 1.0), 0.0001)
	# A direct write to the live theme (not through the seam) is folded in on
	# the next clock update without a jump as well.
	var direct: float = skybox.cycle_phase_at(220.0)
	skybox.theme.cycle_length_seconds = 120.0
	skybox.update_cycle_clock(220.0)
	assert_almost_eq(skybox.cycle_phase_at(220.0), direct, 0.0001)
	sunset.cycle_length_seconds = saved_length


## S0: the locked phases the lobby's Sunset / Dawn / Night options
## use. Each concrete id maps to its authored phase, anything else (including the
## "" of a running cycle) is -1.0, and the shipped defaults put the sun where the
## option's name says (phase 0 dawn, 0.25 noon, 0.5 sunset, 0.75 midnight).
func test_locked_phase_for_maps_concrete_ids_and_rejects_the_rest() -> void:
	var theme: SkyThemeDef = SkyThemeDef.new()
	assert_eq(theme.locked_phase_for("sunset"), theme.cycle_locked_phase_sunset)
	assert_eq(theme.locked_phase_for("dawn"), theme.cycle_locked_phase_dawn)
	assert_eq(theme.locked_phase_for("night"), theme.cycle_locked_phase_night)
	for unknown: String in ["", "cycle", "storm", "../evil", "Sunset"]:
		assert_eq(theme.locked_phase_for(unknown), -1.0, "'%s' is not a lockable sky id" % unknown)
	for sky_id: String in MatchConfig.SKY_THEME_IDS:
		var phase: float = theme.locked_phase_for(sky_id)
		assert_between(phase, 0.0, 1.0, "%s has a lock phase in the 0..1 cycle" % sky_id)
	theme.cycle_locked_phase_night = 0.8
	assert_eq(theme.locked_phase_for("night"), 0.8, "the lock phase is tunable content")


## Cycle is the default sky
## and Sunset / Night / Dawn / Random are the same cycle locked at a phase.
func _configured_skybox(config: MatchConfig) -> Array:
	var parts: Array = _make_skybox(load(SUNSET_PATH) as SkyThemeDef)
	(parts[0] as Skybox).configure_match_sky(config)
	return parts


func _sun_elevation(skybox: Skybox) -> float:
	return ((skybox.theme.sky_material as ShaderMaterial).get_shader_parameter(&"sun_direction") as Vector3).y


func _night_mix(skybox: Skybox) -> float:
	return float((skybox.theme.sky_material as ShaderMaterial).get_shader_parameter(&"cycle_night_mix"))


func test_each_sky_mode_locks_the_right_phase() -> void:
	var source: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var cases: Array[Array] = [
		[MatchConfig.SkyThemeMode.DAY, "sunset", source.cycle_locked_phase_sunset],
		[MatchConfig.SkyThemeMode.NIGHT, "night", source.cycle_locked_phase_night],
		[MatchConfig.SkyThemeMode.DAWN, "dawn", source.cycle_locked_phase_dawn],
	]
	for roll: int in range(MatchConfig.SKY_THEME_IDS.size()):
		var random_config: MatchConfig = MatchConfig.new()
		random_config.sky_theme_mode = MatchConfig.SkyThemeMode.RANDOM
		random_config.resolve_sky_theme(roll)
		cases.append([MatchConfig.SkyThemeMode.RANDOM, random_config.sky_theme_resolved, source.locked_phase_for(random_config.sky_theme_resolved)])
	for entry: Array in cases:
		var config: MatchConfig = MatchConfig.new()
		config.sky_theme_mode = entry[0] as MatchConfig.SkyThemeMode
		config.resolve_sky_theme(MatchConfig.SKY_THEME_IDS.find(entry[1] as String))
		var label: String = "mode %s -> %s" % [entry[0], entry[1]]
		var expected: float = entry[2] as float
		var parts: Array = _configured_skybox(config)
		var skybox: Skybox = parts[0]
		var environment: Environment = parts[1]
		assert_true(skybox.is_cycle_active(), label)
		assert_almost_eq(skybox.locked_phase(), expected, 0.0001, "%s: locked phase" % label)
		assert_almost_eq(skybox.current_cycle_phase(), expected, 0.0001, "%s: applied phase" % label)
		for clock: float in [0.0, 41.0, 987654.0]:
			skybox.update_cycle_clock(clock)
			assert_almost_eq(skybox.current_cycle_phase(), expected, 0.0001, "%s: the clock is ignored at %s s" % [label, clock])
		assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_QUALITY, "%s: a locked sky stops radiance updates" % label)
		if entry[1] == "night":
			assert_gt(_night_mix(skybox), 0.99, "%s: midnight" % label)
			assert_lt(_sun_elevation(skybox), 0.0, "%s: sun below the horizon" % label)
		else:
			assert_lt(_night_mix(skybox), 0.05, "%s: still daylight" % label)
			assert_gt(_sun_elevation(skybox), 0.0, "%s: sun above the horizon" % label)


func test_host_and_client_configs_give_the_same_phase_at_the_same_clock() -> void:
	var modes: Array[MatchConfig.SkyThemeMode] = [
		MatchConfig.SkyThemeMode.CYCLE, MatchConfig.SkyThemeMode.DAY, MatchConfig.SkyThemeMode.NIGHT,
		MatchConfig.SkyThemeMode.DAWN, MatchConfig.SkyThemeMode.RANDOM]
	for mode: MatchConfig.SkyThemeMode in modes:
		var host_config: MatchConfig = MatchConfig.new()
		host_config.sky_theme_mode = mode
		host_config.resolve_sky_theme(2)
		# The client only ever sees the wire form of the host's resolved config.
		var client_config: MatchConfig = MatchConfig.from_dict(host_config.to_dict())
		var host: Skybox = _configured_skybox(host_config)[0] as Skybox
		var client: Skybox = _configured_skybox(client_config)[0] as Skybox
		assert_eq(client.locked_phase(), host.locked_phase(), "mode %s: same lock" % mode)
		for clock: float in [0.0, 37.5, 123.4, 299.0, 301.0, 12345.6]:
			host.update_cycle_clock(clock)
			client.update_cycle_clock(clock)
			assert_almost_eq(client.current_cycle_phase(), host.current_cycle_phase(), 0.00001,
				"mode %s at clock %s" % [mode, clock])
			assert_eq(client.cycle_phase_at(clock), host.cycle_phase_at(clock), "mode %s pure phase at %s" % [mode, clock])


func test_lock_and_unlock_a_running_cycle_keep_the_phase_continuous() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var saved_length: float = sunset.cycle_length_seconds
	sunset.cycle_length_seconds = 300.0
	var parts: Array = _configured_skybox(MatchConfig.new())
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	skybox.update_cycle_clock(30.0)
	skybox.set_locked_phase(0.75)
	assert_almost_eq(skybox.locked_phase(), 0.75, 0.0001)
	assert_almost_eq(skybox.current_cycle_phase(), 0.75, 0.0001, "the lock applies at once")
	assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_QUALITY)
	assert_gt(_night_mix(skybox), 0.99)
	skybox.update_cycle_clock(60.0)
	assert_almost_eq(skybox.current_cycle_phase(), 0.75, 0.0001, "the clock does not move a locked sky")
	skybox.set_locked_phase(1.25)
	assert_almost_eq(skybox.locked_phase(), 0.25, 0.0001, "a lock wraps into 0..1")
	skybox.set_locked_phase(-1.0)
	assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_REALTIME, "running again")
	assert_almost_eq(skybox.cycle_phase_at(60.0), 0.25, 0.0001, "no jump at the unlock")
	skybox.update_cycle_clock(90.0)
	assert_almost_eq(skybox.current_cycle_phase(), 0.35, 0.0001, "and it carries on at the cycle rate")
	skybox.set_locked_phase(-1.0)
	assert_almost_eq(skybox.current_cycle_phase(), 0.35, 0.0001, "unlocking a running cycle is a no-op")
	sunset.cycle_length_seconds = saved_length


## The cycle's day half is the
## dawn palette by morning and noon, fading into the sunset palette on the setting
## side (SkyPalette), and the night mix on top is unchanged.
func _day_palette_skybox(mode: MatchConfig.SkyThemeMode) -> Array:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = mode
	config.resolve_sky_theme(0)
	return _configured_skybox(config)


func _live_sky(skybox: Skybox) -> ShaderMaterial:
	return skybox.theme.sky_material as ShaderMaterial


func _sky_color(material: ShaderMaterial, uniform: StringName) -> Color:
	return material.get_shader_parameter(uniform) as Color


func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _assert_day_palette(skybox: Skybox, expected: SkyThemeDef, label: String) -> void:
	var live: ShaderMaterial = _live_sky(skybox)
	var source: ShaderMaterial = expected.sky_material as ShaderMaterial
	for field: StringName in [&"proc_zenith_color", &"proc_mid_color", &"proc_horizon_color", &"proc_horizon_glow_color",
			&"proc_sea_color_near", &"proc_sea_color_far"]:
		assert_true((skybox.theme.get(field) as Color).is_equal_approx(expected.get(field) as Color), "%s: theme %s" % [label, field])
		assert_true(_sky_color(live, field).is_equal_approx(expected.get(field) as Color), "%s: sky uniform %s" % [label, field])
	for uniform: StringName in SkyPalette.SKY_UNIFORM_COLORS:
		assert_true(_sky_color(live, uniform).is_equal_approx(_sky_color(source, uniform)), "%s: sky %s" % [label, uniform])
	assert_almost_eq(float(live.get_shader_parameter(&"proc_horizon_glow_width")), expected.proc_horizon_glow_width, 0.0001, "%s: glow width" % label)
	assert_almost_eq(float(live.get_shader_parameter(&"proc_sun_glow_strength")), expected.proc_sun_glow_strength, 0.0001, "%s: sun glow" % label)


func test_the_sunset_lock_wears_exactly_the_sunset_palette() -> void:
	var sunset: SkyThemeDef = Skybox.load_theme("sunset")
	var parts: Array = _day_palette_skybox(MatchConfig.SkyThemeMode.DAY)
	var skybox: Skybox = parts[0]
	assert_almost_eq(skybox.locked_phase(), sunset.cycle_locked_phase_sunset, 0.0001)
	assert_eq(SkyPalette.dusk_weight(skybox.locked_phase(), sunset.cycle_dusk_weight_phases), 1.0)
	assert_eq(skybox.theme.proc_zenith_color, sunset.proc_zenith_color, "bit-exact sunset zenith")
	assert_eq(skybox.theme.proc_horizon_color, sunset.proc_horizon_color)
	assert_eq(skybox.theme.sky_top_color, sunset.sky_top_color)
	_assert_day_palette(skybox, sunset, "locked Sunset")
	var puffs: ShaderMaterial = skybox.get_cloud_sea().puff_material()
	var night: float = _night_mix(skybox)
	assert_lt(night, 0.01, "locked Sunset is a day sky")
	var night_puffs: ShaderMaterial = Skybox.load_theme("night").cloud_puff_material as ShaderMaterial
	for uniform: StringName in SkyPalette.PUFF_UNIFORM_COLORS:
		var want: Color = (sunset.cloud_puff_material as ShaderMaterial).get_shader_parameter(uniform) as Color
		var night_tone: Color = night_puffs.get_shader_parameter(uniform) as Color
		assert_true(_sky_color(puffs, uniform).is_equal_approx(want.lerp(night_tone, night)), "puff %s: sunset tone, then the (tiny) night mix" % uniform)


func test_the_palette_fades_from_dawn_to_sunset_across_the_dusk_window() -> void:
	var dawn: SkyThemeDef = Skybox.load_theme("dawn")
	var sunset: SkyThemeDef = Skybox.load_theme("sunset")
	var skybox: Skybox = _day_palette_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	var window: Vector4 = sunset.cycle_dusk_weight_phases
	var middle: float = (window.x + window.y) * 0.5
	skybox.set_cycle_phase(middle)
	var halfway: Color = dawn.proc_zenith_color.lerp(sunset.proc_zenith_color, 0.5)
	assert_true(skybox.theme.proc_zenith_color.is_equal_approx(halfway), "half dawn, half sunset at the window middle")
	assert_true(_sky_color(_live_sky(skybox), &"proc_zenith_color").is_equal_approx(halfway), "and on the live sky")
	var previous: float = -1.0
	for step: int in range(0, 17):
		skybox.set_cycle_phase(window.x + (window.y - window.x) * float(step) / 16.0)
		var progress: float = _color_distance(skybox.theme.proc_zenith_color, dawn.proc_zenith_color)
		assert_gte(progress, previous - 0.00001, "the zenith drifts monotonically toward sunset (step %d)" % step)
		previous = progress
	skybox.set_cycle_phase(window.y)
	assert_eq(skybox.theme.proc_zenith_color, sunset.proc_zenith_color, "the sunset palette is complete at the window end")


## C1b variation, "lets add some variation and just set
## a range so it can vary": the cycle's sky exposure and cloud coverage wander inside
## the SkyThemeDef.variation_* ranges as a smooth function of the match seed and the
## cycle phase (core/sky/SkyVariation.gd); storm and overcast compose on top.
const VARIATION_SEED: int = 4242
const OVERCAST_EXPOSURE_SCALE: float = 0.4
const SWEEP_CLOCKS: Array[float] = [0.0, 13.0, 41.0, 77.5, 120.0, 133.3, 187.0, 224.0, 262.0, 299.0]


func _variation_skybox(mode: MatchConfig.SkyThemeMode, rng_seed: int = VARIATION_SEED) -> Array:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = mode
	config.rng_seed = rng_seed
	config.resolve_sky_theme(0)
	return _configured_skybox(config)


## The live sky's three varying uniforms and the puff material's two, in one dictionary.
func _look(skybox: Skybox) -> Dictionary:
	var sky: ShaderMaterial = _live_sky(skybox)
	var puffs: ShaderMaterial = skybox.get_cloud_sea().puff_material()
	return {
		"exposure": float(sky.get_shader_parameter(&"exposure")),
		"cloud_coverage": float(sky.get_shader_parameter(&"cloud_coverage")),
		"sea_coverage": float(sky.get_shader_parameter(&"proc_sea_coverage")),
		"puff_exposure": float(puffs.get_shader_parameter(&"exposure")),
		"puff_sea_coverage": float(puffs.get_shader_parameter(&"proc_sea_coverage")),
	}


func test_the_running_cycle_varies_exposure_and_coverage_inside_the_configured_ranges() -> void:
	var skybox: Skybox = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	var theme: SkyThemeDef = skybox.theme
	assert_true(theme.variation_enabled, "fixture: the shipped sunset varies the cycle")
	var lowest: float = INF
	var highest: float = -INF
	for second: int in range(0, 300, 2):
		skybox.update_cycle_clock(float(second))
		var look: Dictionary = _look(skybox)
		assert_between(look["exposure"], theme.variation_exposure_min, theme.variation_exposure_max, "exposure at %s s" % second)
		assert_between(look["cloud_coverage"], theme.variation_cloud_coverage_min, theme.variation_cloud_coverage_max, "cloud coverage at %s s" % second)
		assert_between(look["sea_coverage"], theme.variation_sea_coverage_min, theme.variation_sea_coverage_max, "sea coverage at %s s" % second)
		var phase: float = skybox.current_cycle_phase()
		assert_eq(look["exposure"], SkyVariation.exposure_at(theme, phase, VARIATION_SEED), "exposure is the pure function at %s s" % second)
		assert_eq(look["cloud_coverage"], SkyVariation.cloud_coverage_at(theme, phase, VARIATION_SEED), "coverage is the pure function at %s s" % second)
		assert_eq(look["sea_coverage"], SkyVariation.sea_coverage_at(theme, phase, VARIATION_SEED), "sea is the pure function at %s s" % second)
		assert_eq(look["puff_exposure"], look["exposure"], "the puffs' far fade shares the sky exposure at %s s" % second)
		assert_eq(look["puff_sea_coverage"], look["sea_coverage"], "and the sea coverage at %s s" % second)
		lowest = minf(lowest, look["exposure"])
		highest = maxf(highest, look["exposure"])
	assert_gt(highest - lowest, 0.4 * (theme.variation_exposure_max - theme.variation_exposure_min), "the exposure really moves over a cycle")


func test_the_variation_never_writes_the_shipped_theme_materials_and_reset_restores_the_launch_sky() -> void:
	var sunset: SkyThemeDef = Skybox.load_theme("sunset")
	var source: ShaderMaterial = sunset.sky_material as ShaderMaterial
	var launch_exposure: float = float(source.get_shader_parameter(&"exposure"))
	var launch_coverage: float = float(source.get_shader_parameter(&"cloud_coverage"))
	var launch_sea: float = float(source.get_shader_parameter(&"proc_sea_coverage"))
	var parts: Array = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE)
	var skybox: Skybox = parts[0] as Skybox
	var environment: Environment = parts[1] as Environment
	for clock: float in SWEEP_CLOCKS:
		skybox.update_cycle_clock(clock)
	skybox.set_overcast(1.0, 0.5, 0.6, OVERCAST_EXPOSURE_SCALE, Color(0.4, 0.4, 0.5), 0.5)
	assert_eq(float(source.get_shader_parameter(&"exposure")), launch_exposure, "the cycle varies its own duplicate, not sunset.tres")
	assert_eq(float(source.get_shader_parameter(&"cloud_coverage")), launch_coverage)
	assert_eq(float(source.get_shader_parameter(&"proc_sea_coverage")), launch_sea)
	skybox.reset_to_launch()
	assert_false(skybox.is_cycle_active(), "reset: back on the static launch theme")
	var restored: ShaderMaterial = environment.sky.sky_material as ShaderMaterial
	assert_eq(float(restored.get_shader_parameter(&"exposure")), launch_exposure, "reset: the launch exposure, no overcast, no variation")
	assert_eq(float(restored.get_shader_parameter(&"cloud_coverage")), launch_coverage)
	assert_eq(float(restored.get_shader_parameter(&"proc_sea_coverage")), launch_sea)
	# And a new match after the reset draws its own seed's sky, not the previous one's.
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.DAY
	config.rng_seed = VARIATION_SEED + 9
	config.resolve_sky_theme(0)
	skybox.configure_match_sky(config)
	assert_eq(_look(skybox)["exposure"], SkyVariation.exposure_at(skybox.theme, skybox.locked_phase(), VARIATION_SEED + 9))
