extends GutTest
## Live parity: the real Skybox facade, driven through the golden's state groups, writes exactly
## the values pinned in fixtures/sky_cycle_golden.json (sky/puff material uniforms, Environment,
## key light, FogVolume, CloudLighting, SunFlare inputs, ambient-life flag). The same driver
## (`capture_all`) produced the fixture from the old facade, so a later facade must pass
## unchanged. Groups: L locked phases, W weather, P preset matrix, R running cycle.
## Facade-private reads live in the `_probe_*` helpers and the `_apply_*`/`_tick` seams so a
## replacement facade changes only those.

const GOLDEN_PATH: String = "res://tests/unit/sky/fixtures/sky_cycle_golden.json"
const PRESET_LOW: StringName = &"low"
const PRESET_MEDIUM: StringName = &"medium"
const PRESET_HIGH: StringName = &"high"
const PRESET_IDS: Array[StringName] = [PRESET_LOW, PRESET_MEDIUM, PRESET_HIGH]
## INTENDED CHANGE (boot and reset sky; the default is still to be confirmed): boot and
## reset are the cycle locked at SkyboxConfig.theme_name (default sunset = the locked Day phase 0.47),
## no longer the static sunset theme. These states therefore assert the golden's locked-Day state
## instead of their own old-facade snapshot (P_<preset>_boot compares to P_<preset>_0.47).
const BOOT_STATE_REFERENCE: Dictionary = {"W_after_reset": "L_0.47"}
const LOCKED_PHASES: Array[float] = [0.03, 0.10, 0.25, 0.38, 0.47, 0.52, 0.62, 0.75, 0.95]
const PRESET_PHASES: Array[float] = [0.25, 0.47, 0.75]
## First match seed whose night 0 shows the aurora (SkyVariation.aurora_night_shown at 0.1).
const AURORA_SEED: int = 8
## Running-cycle fixture: nonzero shared clock, rolled start phase, a 60 s cycle so half a
## radiance interval is a measurable phase step.
const RUN_CLOCK_S: float = 1234.5
const RUN_START_PHASE: float = 0.62
const RUN_CYCLE_S: float = 60.0
const RUN_EVENING_PHASE: float = 0.40
const RUN_NIGHT_PHASE: float = 0.75
const FADE_FRAMES: int = 6
const FADE_TICK_FRAME: int = 4
## RainPresentation-like overcast request (amount, light, ambient, exposure scales, fog tint).
const OVERCAST_LIGHT: float = 0.55
const OVERCAST_AMBIENT: float = 0.7
const OVERCAST_EXPOSURE: float = 0.8
const OVERCAST_TINT: Color = Color(0.62, 0.66, 0.72, 1.0)
const OVERCAST_TINT_STRENGTH: float = 0.6
const FOG_MAX_OPACITY: float = 0.8
const FOG_BEGIN_M: float = 30.0
const FOG_END_M: float = 400.0
const FOG_TINT: Color = Color(0.7, 0.72, 0.75, 1.0)
const FOG_TINT_STRENGTH: float = 0.5
const FOG_SKY_AFFECT_ADD: float = 0.3
const ENV_PROPERTIES: Array[StringName] = [
	&"background_mode", &"background_energy_multiplier", &"ambient_light_source", &"ambient_light_color",
	&"ambient_light_energy", &"fog_enabled", &"fog_mode", &"fog_light_color", &"fog_light_energy",
	&"fog_density", &"fog_sky_affect", &"fog_aerial_perspective", &"fog_sun_scatter", &"fog_height",
	&"fog_height_density", &"fog_depth_begin", &"fog_depth_end", &"fog_depth_curve",
	&"volumetric_fog_enabled", &"volumetric_fog_density", &"volumetric_fog_albedo",
	&"volumetric_fog_emission", &"glow_enabled", &"glow_intensity", &"glow_hdr_threshold",
	&"ssr_enabled", &"ssao_enabled",
]
const LIGHTING_PROPERTIES: Array[StringName] = [
	&"shadow_color", &"mid_color", &"lit_color", &"rim_color", &"light_direction", &"light_color",
	&"night_mix", &"overcast", &"storm", &"dim", &"desaturate", &"floor_color", &"floor_shadow_ratio",
	&"floor_mid_ratio", &"sun_scale",
]


## Everything one state needs: the facade under test and its scene neighbours.
class Rig extends RefCounted:
	var skybox: Skybox = null
	var ambient: AmbientLife = null
	var environment: Environment = null
	var light: DirectionalLight3D = null
	var flare: SunFlare = null
	var context: FakeMatchContext = null
	var previous_context: MatchContext = null
	var previous_preset: StringName = &""


# --- fixture ------------------------------------------------------------------------------------

static func _make_rig(host: Node, preset_id: StringName, clock_s: float = 0.0) -> Rig:
	var rig: Rig = Rig.new()
	# Process-wide weather-fog statics (what the puff and bird materials read) carry over from
	# earlier tests; a state starts from the launch values like the first capture did.
	WeatherFogShader.reset_to_launch(host.get_tree())
	rig.previous_preset = Settings.current_graphics_preset().id
	if rig.previous_preset != preset_id:
		Settings.set_graphics_preset(preset_id)
	rig.previous_context = MatchContext.installed()
	rig.context = FakeMatchContext.new()
	rig.context.shared_clock_seconds_value = clock_s
	MatchContext.install(rig.context)
	rig.environment = Environment.new()
	rig.environment.sky = Sky.new()
	rig.light = DirectionalLight3D.new()
	rig.light.name = "Light"
	host.add_child(rig.light)
	rig.flare = SunFlare.new()
	host.add_child(rig.flare)
	rig.flare.set_process(false)
	rig.ambient = AmbientLife.build(null, null)
	host.add_child(rig.ambient)
	rig.skybox = Skybox.new()
	rig.skybox.config = SkyboxConfig.new()
	rig.skybox.environment = rig.environment
	host.add_child(rig.skybox)
	# A persistent CloudCeiling pushes weather into every skybox in this group; stay isolated.
	rig.skybox.remove_from_group(Skybox.OVERCAST_GROUP)
	rig.skybox.set_process(false)
	rig.skybox.light_path = rig.skybox.get_path_to(rig.light)
	return rig


static func _free_rig(rig: Rig) -> void:
	rig.skybox.free()
	rig.ambient.free()
	rig.flare.free()
	rig.light.free()
	MatchContext.install(rig.previous_context)
	if Settings.current_graphics_preset().id != rig.previous_preset:
		Settings.set_graphics_preset(rig.previous_preset)


# --- facade seams (the only place a replacement facade changes) ---------------------------------

static func _apply_storm(rig: Rig, amount: float) -> void:
	rig.skybox.set_storm_sky(amount, load("res://config/sky/storm_overlay.tres") as SkyOverlayDef)


static func _apply_overcast(rig: Rig, amount: float) -> void:
	rig.skybox.set_overcast(amount, OVERCAST_LIGHT, OVERCAST_AMBIENT, OVERCAST_EXPOSURE,
		OVERCAST_TINT, OVERCAST_TINT_STRENGTH)
	rig.skybox.set_weather_cloud_overcast(amount)


static func _apply_fog(rig: Rig, amount: float) -> void:
	rig.skybox.set_weather_fog(amount, FOG_MAX_OPACITY, FOG_BEGIN_M, FOG_END_M, FOG_TINT,
		FOG_TINT_STRENGTH, FOG_SKY_AFFECT_ADD)


static func _apply_snow(rig: Rig, amount: float) -> void:
	rig.skybox.set_snow_brighten(amount)


static func _apply_sun_scale(rig: Rig, scale: float) -> void:
	rig.skybox.set_sun_cloud_scale(scale)


static func _flush(rig: Rig) -> void:
	SkyTestKit.settle(rig.skybox)


## One frame of the real `_process` with `delta` seconds; the radiance tick lands when the
## accumulated delta reaches the interval.
static func _tick(rig: Rig, delta: float) -> void:
	rig.skybox._process(delta)


static func _interval(rig: Rig) -> float:
	return 1.0 / rig.skybox.radiance_config.radiance_hz


static func _probe_life_is_night(rig: Rig) -> bool:
	return rig.ambient._is_night


static func _probe_lighting(rig: Rig) -> Object:
	return rig.skybox._cloud_lighting


static func _probe_puff_material(rig: Rig) -> ShaderMaterial:
	var sea: CloudSea = rig.skybox.get_node_or_null("CloudSea") as CloudSea
	return SkyTestKit.puff_material(sea) if sea != null else null


static func _probe_fog_volume(rig: Rig) -> FogVolume:
	return rig.skybox._fog_volume


# --- dump ---------------------------------------------------------------------------------------

static func _enc(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME:
			return str(value)
		TYPE_COLOR:
			var c: Color = value as Color
			return [c.r, c.g, c.b, c.a]
		TYPE_VECTOR2:
			var v2: Vector2 = value as Vector2
			return [v2.x, v2.y]
		TYPE_VECTOR3:
			var v3: Vector3 = value as Vector3
			return [v3.x, v3.y, v3.z]
		TYPE_VECTOR4:
			var v4: Vector4 = value as Vector4
			return [v4.x, v4.y, v4.z, v4.w]
		TYPE_BASIS:
			var b: Basis = value as Basis
			return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z]
		_:
			return null


## Effective value of every non-resource uniform of `material` (the set value, else the shader default).
static func _uniforms(material: ShaderMaterial) -> Dictionary:
	var out: Dictionary = {}
	if material == null or material.shader == null:
		return out
	for entry: Dictionary in material.shader.get_shader_uniform_list():
		var uniform_name: StringName = StringName(str(entry["name"]))
		var value: Variant = material.get_shader_parameter(uniform_name)
		if value == null:
			value = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), uniform_name)
		var encoded: Variant = _enc(value)
		if encoded != null:
			out[str(uniform_name)] = encoded
	return out


static func _props(object: Object, names: Array[StringName]) -> Dictionary:
	var out: Dictionary = {}
	for property_name: StringName in names:
		var encoded: Variant = _enc(object.get(property_name))
		if encoded != null:
			out[str(property_name)] = encoded
	return out


static func dump(rig: Rig) -> Dictionary:
	var sky: ShaderMaterial = rig.environment.sky.sky_material as ShaderMaterial
	var out: Dictionary = {}
	out["sky"] = _uniforms(sky)
	out["puff"] = _uniforms(_probe_puff_material(rig))
	var env: Dictionary = _props(rig.environment, ENV_PROPERTIES)
	env["sky_process_mode"] = int(rig.environment.sky.process_mode)
	out["env"] = env
	out["light"] = {
		"color": _enc(rig.light.light_color), "energy": rig.light.light_energy,
		"basis": _enc(rig.light.global_basis), "visible": rig.light.visible,
	}
	var volume: FogVolume = _probe_fog_volume(rig)
	var fog: Dictionary = {}
	if volume != null:
		fog["visible"] = volume.visible
		fog["size"] = _enc(volume.size)
		fog["y"] = volume.position.y
		var material: FogMaterial = volume.material as FogMaterial
		if material != null:
			fog["density"] = material.density
			fog["albedo"] = _enc(material.albedo)
	out["fog_volume"] = fog
	out["lighting"] = _props(_probe_lighting(rig), LIGHTING_PROPERTIES)
	out["flare"] = {
		"theme_enabled": rig.flare._theme_enabled, "weather_scale": rig.flare._weather_scale,
		"sun_direction": _enc(rig.flare.config.sun_direction),
	}
	out["life_is_night"] = _probe_life_is_night(rig)
	out["globals"] = {
		"sky_sun_dir": _enc(RenderingServer.global_shader_parameter_get(Skybox.SKY_SUN_DIR_GLOBAL)),
		"sky_moon_dir": _enc(RenderingServer.global_shader_parameter_get(Skybox.SKY_MOON_DIR_GLOBAL)),
	}
	out["facade"] = {
		"phase": rig.skybox.current_cycle_phase(), "locked": rig.skybox.locked_phase(),
		"sun_direction": _enc(rig.skybox.sun_direction()), "daylight": rig.skybox.daylight(),
		"cloud_overcast": (_probe_lighting(rig) as CloudLighting).overcast,
	}
	return out


# --- scenarios ----------------------------------------------------------------------------------

static func _match_config(mode: MatchConfig.SkyThemeMode, variation_seed: int) -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = mode
	config.sky_variation_seed = variation_seed
	config.sky_start_phase = RUN_START_PHASE
	return config


## A running cycle opened at `clock_s`, 60 s long, then moved by whole radiance ticks to `phase`.
static func _running_rig(host: Node, preset_id: StringName, clock_s: float, variation_seed: int,
		phase: float) -> Rig:
	var rig: Rig = _make_rig(host, preset_id, clock_s)
	if clock_s == 0.0:
		rig.skybox.configure_match_sky(_match_config(MatchConfig.SkyThemeMode.CYCLE, variation_seed))
	else:
		rig.skybox.start_cycle(-1.0, RUN_START_PHASE)
	rig.skybox.set_cycle_length_seconds(RUN_CYCLE_S)
	var interval: float = _interval(rig)
	var ticks: int = int(round(fposmod(phase - RUN_START_PHASE, 1.0) * RUN_CYCLE_S / interval))
	rig.context.shared_clock_seconds_value = clock_s + float(ticks) * interval
	_tick(rig, interval)
	return rig


static func _locked_rig(host: Node, preset_id: StringName, phase: float) -> Rig:
	var rig: Rig = _make_rig(host, preset_id)
	rig.skybox.start_cycle(phase)
	return rig


static func _snap(states: Dictionary, name: String, rig: Rig) -> void:
	states[name] = dump(rig)


static func _weather_step(rig: Rig, step: String) -> void:
	if step == "overcast" or step == "all":
		_apply_overcast(rig, 0.6)
	if step == "fog" or step == "all":
		_apply_fog(rig, 0.7)
	if step == "sun" or step == "all":
		_apply_sun_scale(rig, 0.6)
	if step == "storm" or step == "all":
		_apply_storm(rig, 0.5)
	if step == "snow" or step == "all":
		_apply_snow(rig, 0.5)
	_flush(rig)


## Captures every state of every group. `host` is a Node in the tree.
static func capture_all(host: Node) -> Dictionary:
	var states: Dictionary = {}
	# L: locked phases
	for phase: float in LOCKED_PHASES:
		var rig: Rig = _locked_rig(host, PRESET_HIGH, phase)
		_snap(states, "L_%.2f" % phase, rig)
		_free_rig(rig)
	# W: weather on locked phases
	var weather: Array[Array] = [
		["W_storm0.5_0.25", 0.25, "storm", 0.5], ["W_storm0.5_0.75", 0.75, "storm", 0.5],
		["W_storm1.0_0.47", 0.47, "storm", 1.0], ["W_overcast0.6_0.25", 0.25, "overcast", 0.6],
		["W_fog0.7_0.47", 0.47, "fog", 0.7], ["W_snow0.5_0.25", 0.25, "snow", 0.5],
		["W_sun0.6_0.25", 0.25, "sun", 0.6],
	]
	for entry: Array in weather:
		var rig: Rig = _locked_rig(host, PRESET_HIGH, entry[1] as float)
		var amount: float = entry[3] as float
		match entry[2] as String:
			"storm": _apply_storm(rig, amount)
			"overcast": _apply_overcast(rig, amount)
			"fog": _apply_fog(rig, amount)
			"snow": _apply_snow(rig, amount)
			"sun": _apply_sun_scale(rig, amount)
		_flush(rig)
		_snap(states, entry[0] as String, rig)
		_free_rig(rig)
	# W: graphics-preset change at 0.25 (the puff snapshot)
	var preset_rig: Rig = _locked_rig(host, PRESET_HIGH, 0.25)
	Settings.set_graphics_preset(PRESET_LOW)
	_snap(states, "W_preset_high_to_low_0.25", preset_rig)
	Settings.set_graphics_preset(PRESET_HIGH)
	_snap(states, "W_preset_low_to_high_0.25", preset_rig)
	_free_rig(preset_rig)
	# W: a storm match, the match-scope reset, then a new match locked at sunset
	var match_rig: Rig = _make_rig(host, PRESET_HIGH)
	match_rig.skybox.configure_match_sky(_match_config(MatchConfig.SkyThemeMode.NIGHT, AURORA_SEED))
	_snap(states, "W_match_night_aurora_seed", match_rig)
	_apply_storm(match_rig, 0.5)
	_flush(match_rig)
	_snap(states, "W_match_night_storm", match_rig)
	Events.match_scope_reset.emit()
	_snap(states, "W_after_reset", match_rig)
	match_rig.skybox.configure_match_sky(_match_config(MatchConfig.SkyThemeMode.DAY, SkyVariation.DEFAULT_SEED))
	_snap(states, "W_after_reset_sunset_match", match_rig)
	_free_rig(match_rig)
	# P: preset matrix
	for preset_id: StringName in PRESET_IDS:
		var boot: Rig = _make_rig(host, preset_id)
		_snap(states, "P_%s_boot" % preset_id, boot)
		_free_rig(boot)
		for phase: float in PRESET_PHASES:
			var rig: Rig = _locked_rig(host, preset_id, phase)
			_snap(states, "P_%s_%.2f" % [preset_id, phase], rig)
			if phase == 0.75:
				_apply_storm(rig, 0.5)
				_flush(rig)
				_snap(states, "P_%s_storm0.5_0.75" % preset_id, rig)
			if phase == 0.47:
				_apply_fog(rig, 0.7)
				_flush(rig)
				_snap(states, "P_%s_fog0.7_0.47" % preset_id, rig)
			_free_rig(rig)
		var refreshed: Rig = _locked_rig(host, preset_id, 0.25)
		refreshed.skybox.refresh_sky_def()
		_snap(states, "P_%s_refresh_0.25" % preset_id, refreshed)
		_free_rig(refreshed)
	# R: running cycle at a nonzero clock and at clock 0, half a tick of clock advance per step
	var steps: Array[String] = ["overcast", "fog", "sun", "storm", "snow", "all"]
	for clock_s: float in [RUN_CLOCK_S, 0.0]:
		var tag: String = "R%d" % int(clock_s)
		var evening: Rig = _running_rig(host, PRESET_HIGH, clock_s, SkyVariation.DEFAULT_SEED, RUN_EVENING_PHASE)
		_snap(states, "%s_evening_tick" % tag, evening)
		_free_rig(evening)
		for step: String in steps:
			var rig: Rig = _running_rig(host, PRESET_HIGH, clock_s, SkyVariation.DEFAULT_SEED, RUN_EVENING_PHASE)
			var interval: float = _interval(rig)
			rig.context.shared_clock_seconds_value += interval * 0.5
			_tick(rig, interval * 0.5)
			_weather_step(rig, step)
			_snap(states, "%s_half_tick_%s" % [tag, step], rig)
			_free_rig(rig)
		var night: Rig = _running_rig(host, PRESET_HIGH, clock_s, AURORA_SEED, RUN_NIGHT_PHASE)
		_snap(states, "%s_night_aurora_seed" % tag, night)
		_free_rig(night)
	# R: storm-fade sequence (storm, overcast and sun scale change every frame, tick in frame 4)
	var fade: Rig = _running_rig(host, PRESET_HIGH, RUN_CLOCK_S, SkyVariation.DEFAULT_SEED, RUN_EVENING_PHASE)
	var frame_s: float = _interval(fade) / float(FADE_TICK_FRAME)
	for frame: int in range(1, FADE_FRAMES + 1):
		var level: float = float(frame) / float(FADE_FRAMES)
		fade.context.shared_clock_seconds_value += frame_s
		_apply_storm(fade, level)
		_apply_overcast(fade, level)
		_apply_sun_scale(fade, 1.0 - 0.5 * level)
		_tick(fade, frame_s)
		_flush(fade)
		_snap(states, "R_fade_f%d" % frame, fade)
	_free_rig(fade)
	return states


# --- comparison ---------------------------------------------------------------------------------

static func _is_close(a: Variant, b: Variant) -> bool:
	if a is Array and b is Array:
		var left: Array = a as Array
		var right: Array = b as Array
		if left.size() != right.size():
			return false
		for i: int in left.size():
			if not _is_close(left[i], right[i]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return a == b


## Differences between `expected` and `actual` (one state); names in `retired` are not compared
## in the sky-material group.
static func diff_state(expected: Dictionary, actual: Dictionary, retired: Array) -> Array[String]:
	var problems: Array[String] = []
	for group: String in expected.keys():
		var want: Variant = expected[group]
		var got: Variant = actual.get(group)
		if want is Dictionary:
			var want_dict: Dictionary = want as Dictionary
			var got_dict: Dictionary = got as Dictionary if got is Dictionary else {}
			for key: String in want_dict.keys():
				if group == "sky" and retired.has(key):
					continue
				if not got_dict.has(key):
					problems.append("%s.%s missing" % [group, key])
				elif not _is_close(want_dict[key], got_dict[key]):
					problems.append("%s.%s expected %s got %s" % [group, key, want_dict[key], got_dict[key]])
			for key: String in got_dict.keys():
				if not want_dict.has(key) and not (group == "sky" and retired.has(key)):
					problems.append("%s.%s unexpected" % [group, key])
		elif not _is_close(want, got):
			problems.append("%s expected %s got %s" % [group, want, got])
	return problems


static func load_golden() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	return parsed as Dictionary if parsed is Dictionary else {}


func test_live_facade_matches_the_golden() -> void:
	var golden: Dictionary = load_golden()
	assert_false(golden.is_empty(), "golden fixture loads")
	var want: Dictionary = golden.get("states", {}) as Dictionary
	var retired: Array = golden.get("retired_uniforms", []) as Array
	var got: Dictionary = capture_all(self)
	assert_eq(got.size(), want.size(), "same state names")
	var checked: int = 0
	for state: String in want.keys():
		assert_true(got.has(state), "state %s captured" % state)
		if not got.has(state):
			continue
		var reference: String = BOOT_STATE_REFERENCE.get(state, state) as String
		if state.ends_with("_boot"):
			reference = "P_%s_0.47" % state.trim_prefix("P_").trim_suffix("_boot")
		var problems: Array[String] = diff_state(want[reference] as Dictionary, got[state] as Dictionary, retired)
		assert_eq(problems.size(), 0, "state %s: %s" % [state, str(problems.slice(0, 6))])
		checked += 1
	assert_gt(checked, 60, "the golden covers every group")
