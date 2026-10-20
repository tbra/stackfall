extends GutTest
## sky cycle: locked looks, cycle-driven light/environment, 3D cloud-puff sea and distant bird flocks.
## The pure phase maths (rate, continuity at a length edit or a lock, night count) is in
## test_sky_cycle_clock; the cases here drive the Skybox through the shared clock.

var _context: FakeMatchContext
var _previous_context: MatchContext


func before_each() -> void:
	_context = FakeMatchContext.new()
	_previous_context = MatchContext.installed()
	MatchContext.install(_context)


func after_each() -> void:
	MatchContext.install(_previous_context)


## Moves the shared clock to `clock_s` and runs one radiance interval of the real frame path.
func _run_to(skybox: Skybox, clock_s: float) -> void:
	SkyTestKit.run_to_clock(skybox, _context, clock_s)


func _make_skybox() -> Array:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "Light"
	add_child_autofree(light)
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.sky_def = SkyTestKit.cycle()
	skybox.light_path = skybox.get_path_to(light) if skybox.is_inside_tree() else NodePath("")
	add_child_autofree(skybox)
	# a persistent CloudCeiling (the weather presenter inside MatchNet)
	# pushes a fading storm blend into every skybox in this group; an earlier script's
	# weather events leave it mid-fade, so this fixture opts out and stays isolated.
	skybox.remove_from_group(Skybox.OVERCAST_GROUP)
	skybox.light_path = skybox.get_path_to(light)
	return [skybox, environment, light]


func test_locked_night_writes_the_night_light_and_environment() -> void:
	var parts: Array = _make_skybox()
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var light: DirectionalLight3D = parts[2]
	skybox.set_locked_phase(skybox.sky_def.cycle_locked_phase_night)
	var def: SkyCycleDef = skybox.sky_def
	var night: SkyNightKeyframe = def.night
	var moon_key: float = smoothstep(0.0, def.light_key_ramp_sin, -skybox.sun_direction().y)
	assert_almost_eq(light.light_energy, night.light_energy * night.moon_light_ratio * moon_key, 0.0001)
	assert_true(light.light_color.is_equal_approx(night.light_color))
	assert_almost_eq(environment.ambient_light_energy, night.ambient_energy, 0.0001)
	assert_almost_eq(environment.glow_hdr_threshold, skybox.sky_def.glow_hdr_threshold, 0.0001, "glow threshold is cycle structure")


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


## Puffs of the sea layers: the hull instance plus its impostor twin, when present. The overcast layer
## carries the per-instance floor_on flag and is left out (a rebuild renames nodes, so names are no guide).
func _puff_count(sea: CloudSea) -> int:
	var total: int = 0
	for child: Node in sea.get_children():
		if child is MultiMeshInstance3D and not child.is_queued_for_deletion() \
				and (child as MultiMeshInstance3D).get_instance_shader_parameter(&"floor_on") == null:
			total += (child as MultiMeshInstance3D).multimesh.instance_count
	return total


## Locks a running cycle at the phase of a lockable sky id; false for an unknown id.
func _lock_sky(skybox: Skybox, sky_id: String) -> bool:
	var phase: float = skybox.sky_def.locked_phase_for(sky_id)
	if phase < 0.0:
		return false
	skybox.set_locked_phase(phase)
	return true


func test_live_sky_switch_is_stable_and_matches_the_cycle() -> void:
	var parts: Array = _make_skybox()
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var light: DirectionalLight3D = parts[2]
	var flare: SunFlare = SunFlare.new()
	add_child_autofree(flare)
	var night: SkyNightKeyframe = skybox.sky_def.night
	assert_true(_lock_sky(skybox, "night"))
	await get_tree().process_frame
	var baseline: int = _ambient_child_count(skybox)
	var night_puffs: int = _puff_count(skybox.get_node("CloudSea") as CloudSea)
	for cycle: int in range(4):
		assert_true(_lock_sky(skybox, "sunset"))
		assert_almost_eq(skybox.locked_phase(), skybox.sky_def.cycle_locked_phase_sunset, 0.0001)
		assert_true(flare._theme_enabled, "the sunset sun is up")
		assert_true(_lock_sky(skybox, "night"))
		assert_almost_eq(skybox.locked_phase(), skybox.sky_def.cycle_locked_phase_night, 0.0001)
		assert_true(light.light_color.is_equal_approx(night.light_color))
		assert_almost_eq(light.rotation_degrees.x, night.light_rotation_deg.x, 0.001)
		assert_almost_eq(environment.glow_hdr_threshold, skybox.sky_def.glow_hdr_threshold, 0.0001, "glow threshold is cycle structure")
		assert_eq(environment.sky.sky_material, SkyTestKit.sky_material(skybox), "one live sky material")
		assert_false(flare._theme_enabled, "night hides the sunset-aimed flare")
		var fog: FogVolume = skybox.get_node_or_null("CloudDeck") as FogVolume
		assert_eq(fog.size, skybox.sky_def.cloud_deck_size_m)
		assert_true((fog.material as FogMaterial).albedo.is_equal_approx(night.fog_color), "the deck wears the night fog")
		await get_tree().process_frame
		assert_eq(_puff_count(skybox.get_node("CloudSea") as CloudSea), night_puffs, "same puff count each night switch")
		assert_eq(_ambient_child_count(skybox), baseline, "no leaked or duplicated nodes")
	assert_true(_lock_sky(skybox, "sunset"))
	assert_false(_lock_sky(skybox, "no_such_theme"))


func _cycle_skybox(length_s: float = 0.0) -> Skybox:
	var parts: Array = _make_skybox()
	var skybox: Skybox = parts[0] as Skybox
	if length_s > 0.0:
		skybox.sky_def.cycle_length_seconds = length_s
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	return skybox


func test_cycle_runs_a_full_loop_in_the_authored_length() -> void:
	var skybox: Skybox = _cycle_skybox(300.0)
	assert_almost_eq(skybox.sky_def.cycle_length_seconds, 300.0, 0.001)
	# the cycle opens at SkyCycleDef.cycle_start_phase, not at dawn.
	var start: float = skybox.sky_def.cycle_start_phase
	assert_almost_eq(skybox.current_cycle_phase(), start, 0.0001, "opens at the start phase")
	_run_to(skybox, 75.0)
	assert_almost_eq(skybox.current_cycle_phase(), fposmod(start + 0.25, 1.0), 0.0001, "a quarter of 5 min on")
	_run_to(skybox, 150.0)
	assert_almost_eq(skybox.current_cycle_phase(), fposmod(start + 0.5, 1.0), 0.0001)
	_run_to(skybox, 300.0)
	assert_almost_eq(skybox.current_cycle_phase(), start, 0.0001, "a full cycle takes 300 s")


## a live length edit changes the speed only; the time of day
## at the moment of the edit is unchanged. (The clock maths itself: test_sky_cycle_clock.)
func test_cycle_length_change_keeps_the_phase_continuous() -> void:
	var skybox: Skybox = _cycle_skybox(300.0)
	_run_to(skybox, 100.0)
	var before: float = skybox.current_cycle_phase()
	skybox.set_cycle_length_seconds(900.0)
	assert_almost_eq(skybox.sky_def.cycle_length_seconds, 900.0, 0.001)
	_run_to(skybox, 100.0)
	assert_almost_eq(skybox.current_cycle_phase(), before, 0.0001, "no jump at the edit")
	_run_to(skybox, 190.0)
	assert_almost_eq(skybox.current_cycle_phase(), fposmod(before + 90.0 / 900.0, 1.0), 0.0001,
		"afterwards the phase advances at the new rate")
	skybox.set_cycle_length_seconds(60.0)
	_run_to(skybox, 190.0)
	assert_almost_eq(skybox.current_cycle_phase(), fposmod(before + 90.0 / 900.0, 1.0), 0.0001, "shortening is continuous too")
	_run_to(skybox, 220.0)
	assert_almost_eq(skybox.current_cycle_phase(), fposmod(before + 90.0 / 900.0 + 30.0 / 60.0, 1.0), 0.0001)
	# A direct write to the live definition (not through the seam) is folded in on
	# the next clock update without a jump as well.
	var direct: float = skybox.current_cycle_phase()
	skybox.sky_def.cycle_length_seconds = 120.0
	_run_to(skybox, 220.0)
	assert_almost_eq(skybox.current_cycle_phase(), direct, 0.0001)


## S0: the locked phases the lobby's Sunset / Dawn / Night options
## use. Each concrete id maps to its authored phase, anything else (including the
## "" of a running cycle) is -1.0, and the shipped defaults put the sun where the
## option's name says (phase 0 dawn, 0.25 noon, 0.5 sunset, 0.75 midnight).
func test_locked_phase_for_maps_concrete_ids_and_rejects_the_rest() -> void:
	var theme: SkyCycleDef = SkyCycleDef.new()
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
func _configured_skybox(config: MatchConfig, length_s: float = 0.0) -> Array:
	var parts: Array = _make_skybox()
	if length_s > 0.0:
		(parts[0] as Skybox).sky_def.cycle_length_seconds = length_s
	(parts[0] as Skybox).configure_match_sky(config)
	return parts


func _sun_elevation(skybox: Skybox) -> float:
	return (SkyTestKit.sky_material(skybox).get_shader_parameter(&"sun_direction") as Vector3).y


func _night_mix(skybox: Skybox) -> float:
	return float(SkyTestKit.sky_material(skybox).get_shader_parameter(&"cycle_night_mix"))


func test_each_sky_mode_locks_the_right_phase() -> void:
	var source: SkyCycleDef = SkyTestKit.cycle()
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
			_run_to(skybox, clock)
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
			_run_to(host, clock)
			_run_to(client, clock)
			assert_almost_eq(client.current_cycle_phase(), host.current_cycle_phase(), 0.00001,
				"mode %s at clock %s" % [mode, clock])
			assert_eq(client.current_cycle_phase(), host.current_cycle_phase(), "mode %s exact phase at %s" % [mode, clock])


func test_lock_and_unlock_a_running_cycle_keep_the_phase_continuous() -> void:
	var parts: Array = _configured_skybox(MatchConfig.new(), 300.0)
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	_run_to(skybox, 30.0)
	skybox.set_locked_phase(0.75)
	assert_almost_eq(skybox.locked_phase(), 0.75, 0.0001)
	assert_almost_eq(skybox.current_cycle_phase(), 0.75, 0.0001, "the lock applies at once")
	assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_QUALITY)
	assert_gt(_night_mix(skybox), 0.99)
	# A moving shared clock plus the frame path leaves a locked phase unchanged.
	_run_to(skybox, 45.0)
	assert_almost_eq(skybox.current_cycle_phase(), 0.75, 0.0001, "the clock does not move a locked sky")
	skybox.set_locked_phase(1.25)
	assert_almost_eq(skybox.locked_phase(), 0.25, 0.0001, "a lock wraps into 0..1")
	skybox.set_locked_phase(-1.0)
	assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_REALTIME, "running again")
	assert_eq(skybox.locked_phase(), -1.0)
	assert_almost_eq(skybox.current_cycle_phase(), 0.25, 0.0001, "no jump at the unlock")
	skybox.set_locked_phase(-1.0)
	assert_almost_eq(skybox.current_cycle_phase(), 0.25, 0.0001, "unlocking a running cycle is a no-op")


## The cycle's day half is the
## dawn palette by morning and noon, fading into the sunset palette on the setting
## side (the day keyframes), and the night mix on top is unchanged.
func _day_palette_skybox(mode: MatchConfig.SkyThemeMode) -> Array:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = mode
	config.resolve_sky_theme(0)
	return _configured_skybox(config)


func _live_sky(skybox: Skybox) -> ShaderMaterial:
	return SkyTestKit.sky_material(skybox)


func _sky_color(material: ShaderMaterial, uniform: StringName) -> Color:
	return material.get_shader_parameter(uniform) as Color


func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## Sky uniform -> SkyKeyframe field for the sun and cloud colour uniforms the day palette owns.
const SKY_UNIFORM_COLORS: Array[StringName] = [
	&"sun_core_color", &"sun_halo_color", &"sun_ray_color",
	&"cloud_shadow_color", &"cloud_mid_color", &"cloud_lit_color", &"cloud_rim_color",
]
## Puff material uniform -> SkyKeyframe field of the four cel tones.
const PUFF_KEY_FIELDS: Dictionary = {
	&"shadow_color": &"puff_shadow_color", &"mid_color": &"puff_mid_color",
	&"lit_color": &"puff_lit_color", &"rim_color": &"puff_rim_color",
}


func _assert_day_palette(skybox: Skybox, expected: SkyKeyframe, label: String) -> void:
	var live: ShaderMaterial = _live_sky(skybox)
	for field: StringName in [&"proc_zenith_color", &"proc_mid_color", &"proc_horizon_color", &"proc_horizon_glow_color",
			&"proc_sea_color_near", &"proc_sea_color_far"]:
		assert_true(_sky_color(live, field).is_equal_approx(expected.get(field) as Color), "%s: sky uniform %s" % [label, field])
	for uniform: StringName in SKY_UNIFORM_COLORS:
		assert_true(_sky_color(live, uniform).is_equal_approx(expected.get(uniform) as Color), "%s: sky %s" % [label, uniform])
	assert_almost_eq(float(live.get_shader_parameter(&"proc_horizon_glow_width")), expected.proc_horizon_glow_width, 0.0001, "%s: glow width" % label)
	assert_almost_eq(float(live.get_shader_parameter(&"proc_sun_glow_strength")), expected.proc_sun_glow_strength, 0.0001, "%s: sun glow" % label)


func test_the_sunset_lock_wears_exactly_the_sunset_palette() -> void:
	var parts: Array = _day_palette_skybox(MatchConfig.SkyThemeMode.DAY)
	var skybox: Skybox = parts[0]
	var def: SkyCycleDef = skybox.sky_def
	var sunset: SkyKeyframe = def.day_keyframes[1]
	assert_almost_eq(skybox.locked_phase(), def.cycle_locked_phase_sunset, 0.0001)
	assert_eq(SkyEvaluator.window_weight(skybox.locked_phase(), sunset.phase_window), 1.0)
	assert_eq(_sky_color(_live_sky(skybox), &"proc_zenith_color"), sunset.proc_zenith_color, "bit-exact sunset zenith")
	assert_eq(_sky_color(_live_sky(skybox), &"proc_horizon_color"), sunset.proc_horizon_color)
	_assert_day_palette(skybox, sunset, "locked Sunset")
	var puffs: ShaderMaterial = SkyTestKit.puff_material(skybox.get_node("CloudSea") as CloudSea)
	var night: float = _night_mix(skybox)
	assert_lt(night, 0.01, "locked Sunset is a day sky")
	for uniform: StringName in PUFF_KEY_FIELDS:
		var want: Color = sunset.get(PUFF_KEY_FIELDS[uniform]) as Color
		var night_tone: Color = def.night.get(PUFF_KEY_FIELDS[uniform]) as Color
		assert_true(_sky_color(puffs, uniform).is_equal_approx(want.lerp(night_tone, night)), "puff %s: sunset tone, then the (tiny) night mix" % uniform)


func test_the_palette_fades_from_dawn_to_sunset_across_the_dusk_window() -> void:
	var skybox: Skybox = _day_palette_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	var dawn: SkyKeyframe = skybox.sky_def.day_keyframes[0]
	var sunset: SkyKeyframe = skybox.sky_def.day_keyframes[1]
	var window: Vector4 = sunset.phase_window
	var middle: float = (window.x + window.y) * 0.5
	skybox.set_cycle_phase(middle)
	var halfway: Color = dawn.proc_zenith_color.lerp(sunset.proc_zenith_color, 0.5)
	assert_true(_sky_color(_live_sky(skybox), &"proc_zenith_color").is_equal_approx(halfway), "half dawn, half sunset at the window middle")
	var previous: float = -1.0
	for step: int in range(0, 17):
		skybox.set_cycle_phase(window.x + (window.y - window.x) * float(step) / 16.0)
		var progress: float = _color_distance(_sky_color(_live_sky(skybox), &"proc_zenith_color"), dawn.proc_zenith_color)
		assert_gte(progress, previous - 0.00001, "the zenith drifts monotonically toward sunset (step %d)" % step)
		previous = progress
	skybox.set_cycle_phase(window.y)
	assert_eq(_sky_color(_live_sky(skybox), &"proc_zenith_color"), sunset.proc_zenith_color, "the sunset palette is complete at the window end")


## C1b variation, "lets add some variation and just set
## a range so it can vary": the cycle's sky exposure and cloud coverage wander inside
## the SkyCycleDef.variation_* ranges as a smooth function of the match seed and the
## cycle phase (core/sky/SkyVariation.gd); storm and overcast compose on top.
const VARIATION_SEED: int = 4242
const OVERCAST_EXPOSURE_SCALE: float = 0.4
const SWEEP_CLOCKS: Array[float] = [0.0, 13.0, 41.0, 77.5, 120.0, 133.3, 187.0, 224.0, 262.0, 299.0]


func _exposure_at(def: SkyCycleDef, phase: float, seed_value: int) -> float:
	return SkyVariation.value_at(def.variation_exposure_min, def.variation_exposure_max,
		def.variation_knots_per_cycle, phase, seed_value, SkyVariation.CHANNEL_EXPOSURE)


func _sea_coverage_at(def: SkyCycleDef, phase: float, seed_value: int) -> float:
	return SkyVariation.value_at(def.variation_sea_coverage_min, def.variation_sea_coverage_max,
		def.variation_knots_per_cycle, phase, seed_value, SkyVariation.CHANNEL_SEA_COVERAGE)


func _variation_skybox(mode: MatchConfig.SkyThemeMode, rng_seed: int = VARIATION_SEED) -> Array:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = mode
	config.rng_seed = rng_seed
	config.resolve_sky_theme(0)
	return _configured_skybox(config)


## The live sky's three varying uniforms and the puff material's two, in one dictionary.
func _look(skybox: Skybox) -> Dictionary:
	var sky: ShaderMaterial = _live_sky(skybox)
	var puffs: ShaderMaterial = SkyTestKit.puff_material(skybox.get_node("CloudSea") as CloudSea)
	return {
		"exposure": float(sky.get_shader_parameter(&"exposure")),
		"sea_coverage": float(sky.get_shader_parameter(&"proc_sea_coverage")),
		"puff_exposure": float(puffs.get_shader_parameter(&"exposure")),
		"puff_sea_coverage": float(puffs.get_shader_parameter(&"proc_sea_coverage")),
	}


func test_the_running_cycle_varies_exposure_and_coverage_inside_the_configured_ranges() -> void:
	var skybox: Skybox = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	var def: SkyCycleDef = skybox.sky_def
	assert_true(def.variation_enabled, "fixture: the shipped cycle varies")
	var lowest: float = INF
	var highest: float = -INF
	for second: int in range(0, 300, 2):
		_run_to(skybox, float(second))
		var look: Dictionary = _look(skybox)
		assert_between(look["exposure"], def.variation_exposure_min, def.variation_exposure_max, "exposure at %s s" % second)
		assert_between(look["sea_coverage"], def.variation_sea_coverage_min, def.variation_sea_coverage_max, "sea coverage at %s s" % second)
		var phase: float = skybox.current_cycle_phase()
		assert_eq(look["exposure"], _exposure_at(def, phase, VARIATION_SEED), "exposure is the pure function at %s s" % second)
		assert_eq(look["sea_coverage"], _sea_coverage_at(def, phase, VARIATION_SEED), "sea is the pure function at %s s" % second)
		assert_eq(look["puff_exposure"], look["exposure"], "the puffs' far fade shares the sky exposure at %s s" % second)
		assert_eq(look["puff_sea_coverage"], look["sea_coverage"], "and the sea coverage at %s s" % second)
		lowest = minf(lowest, look["exposure"])
		highest = maxf(highest, look["exposure"])
	assert_gt(highest - lowest, 0.4 * (def.variation_exposure_max - def.variation_exposure_min), "the exposure really moves over a cycle")


func test_the_variation_never_writes_the_shipped_sky_material_and_reset_restores_the_launch_sky() -> void:
	var shipped: ShaderMaterial = SkyTestKit.cycle().sky_material as ShaderMaterial
	var launch_exposure: float = float(shipped.get_shader_parameter(&"exposure"))
	var launch_sea: float = float(shipped.get_shader_parameter(&"proc_sea_coverage"))
	var parts: Array = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE)
	var skybox: Skybox = parts[0] as Skybox
	var source: ShaderMaterial = skybox.sky_def.sky_material as ShaderMaterial
	var environment: Environment = parts[1] as Environment
	for clock: float in SWEEP_CLOCKS:
		_run_to(skybox, clock)
	skybox.set_overcast(1.0, 0.5, 0.6, OVERCAST_EXPOSURE_SCALE, Color(0.4, 0.4, 0.5), 0.5)
	assert_eq(float(source.get_shader_parameter(&"exposure")), launch_exposure, "the cycle varies its own duplicate, not the definition's material")
	assert_eq(float(source.get_shader_parameter(&"proc_sea_coverage")), launch_sea)
	Events.match_scope_reset.emit()
	assert_almost_eq(skybox.locked_phase(), skybox.sky_def.cycle_locked_phase_sunset, 0.0001, "reset: the cycle locked at the launch sky")
	var restored: ShaderMaterial = environment.sky.sky_material as ShaderMaterial
	var sunset_exposure: float = _exposure_at(skybox.sky_def, skybox.locked_phase(), SkyVariation.DEFAULT_SEED)
	assert_almost_eq(float(restored.get_shader_parameter(&"exposure")), sunset_exposure, 0.00001, "reset: the default-seed exposure, no overcast")
	# And a new match after the reset draws its own seed's sky, not the previous one's.
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.DAY
	config.rng_seed = VARIATION_SEED + 9
	config.resolve_sky_theme(0)
	skybox.configure_match_sky(config)
	assert_eq(_look(skybox)["exposure"], _exposure_at(skybox.sky_def, skybox.locked_phase(), VARIATION_SEED + 9))
