extends GutTest
## core/sky/SkyEvaluator.gd and SkyVariation.value_at: parity with the live Skybox writers (the
## cycle at four locked phases, the storm, the staged last-tick weather requests) and the pure
## palette/variation rules ported from test_sky_palette.gd (each as test_palette_<old name>).

const DEFAULT_WINDOW: Vector4 = Vector4(0.30, 0.46, 0.90, 0.98)
const TOLERANCE: float = 0.00001
const LOCKED_PHASES: Array[float] = [0.03, 0.25, 0.47, 0.75]
const SEED: int = 1234
const MAX_AURORA_SEED_SEARCH: int = 400
const KEY_NAME: String = "Key"
const STORM_AMOUNT: float = 0.5
const RUN_START_PHASE: float = 0.40
const HALF_TICK_PHASE: float = 0.05
const VARIATION_SWEEP_STEPS: int = 500
const VARIATION_SEEDS: Array[int] = [0, 1, 7, 42, 1234, 99999, 2147483647]
const CEILING: WeatherCeilingTuning = preload("res://config/weather/ceiling.tres")

## Frame field -> sky material uniform of the same value.
const SKY_FIELDS: Dictionary[StringName, StringName] = {
	&"use_global_dirs": &"use_global_dirs", &"exposure": &"exposure",
	&"proc_sea_coverage": &"proc_sea_coverage", &"proc_zenith_color": &"proc_zenith_color",
	&"proc_mid_color": &"proc_mid_color", &"proc_horizon_color": &"proc_horizon_color",
	&"proc_horizon_glow_color": &"proc_horizon_glow_color",
	&"proc_gradient_mid_height": &"proc_gradient_mid_height", &"proc_gradient_power": &"proc_gradient_power",
	&"proc_horizon_glow_width": &"proc_horizon_glow_width", &"proc_sun_glow_strength": &"proc_sun_glow_strength",
	&"proc_sea_color_near": &"proc_sea_color_near", &"proc_sea_color_far": &"proc_sea_color_far",
	&"proc_sea_horizon_fade": &"proc_sea_horizon_fade", &"sun_direction": &"sun_direction",
	&"sun_core_color": &"sun_core_color", &"sun_halo_color": &"sun_halo_color", &"sun_ray_color": &"sun_ray_color",
	&"cloud_shadow_color": &"cloud_shadow_color", &"cloud_mid_color": &"cloud_mid_color",
	&"cloud_lit_color": &"cloud_lit_color", &"cloud_rim_color": &"cloud_rim_color",
	&"cycle_night_mix": &"cycle_night_mix", &"cycle_night_zenith": &"cycle_night_zenith",
	&"cycle_night_horizon": &"cycle_night_horizon", &"cycle_night_below": &"cycle_night_below",
	&"cycle_star_brightness": &"cycle_star_brightness", &"cycle_star_cells": &"cycle_star_cells",
	&"cycle_star_threshold": &"cycle_star_threshold", &"cycle_star_radius": &"cycle_star_radius",
	&"cycle_star_horizon_fade": &"cycle_star_horizon_fade", &"moon_direction": &"moon_direction",
	&"moon_visibility": &"moon_visibility", &"moon_angular_radius_deg": &"moon_angular_radius_deg",
	&"moon_halo_radius_deg": &"moon_halo_radius_deg", &"moon_halo_strength": &"moon_halo_strength",
	&"moon_brightness": &"moon_brightness", &"aurora_visibility": &"aurora_visibility",
}
## Aurora look uniforms, written by the live code only while the aurora is visible.
const AURORA_LOOK_FIELDS: Array[StringName] = [
	&"aurora_intensity", &"aurora_color_low", &"aurora_color_mid", &"aurora_color_top",
	&"aurora_speed", &"aurora_base_height", &"aurora_curtain_height",
]
## Frame field -> puff material uniform.
const PUFF_FIELDS: Dictionary[StringName, StringName] = {
	&"puff_shadow_color": &"shadow_color", &"puff_mid_color": &"mid_color", &"puff_lit_color": &"lit_color",
	&"puff_rim_color": &"rim_color", &"puff_cloud_shadow_color": &"cloud_shadow_color",
	&"puff_cloud_mid_color": &"cloud_mid_color", &"puff_cloud_lit_color": &"cloud_lit_color",
	&"puff_cloud_rim_color": &"cloud_rim_color", &"puff_grade_dark": &"grade_dark", &"puff_grade_mid": &"grade_mid",
	&"puff_grade_light": &"grade_light", &"puff_grade_amount": &"grade_amount",
	&"puff_sea_color_near": &"proc_sea_color_near", &"puff_sea_color_far": &"proc_sea_color_far",
	&"puff_exposure": &"exposure", &"puff_sea_coverage": &"proc_sea_coverage",
	&"puff_light_direction": &"light_direction", &"puff_sun_direction": &"sun_direction",
	&"weather_dim": &"weather_dim", &"weather_desaturate": &"weather_desaturate",
	&"floor_color": &"weather_floor", &"floor_shadow_ratio": &"floor_shadow_ratio",
	&"floor_mid_ratio": &"floor_mid_ratio",
}
## Frame field -> Environment property.
const ENVIRONMENT_FIELDS: Dictionary[StringName, StringName] = {
	&"fog_light_color": &"fog_light_color", &"fog_density": &"fog_density", &"fog_sky_affect": &"fog_sky_affect",
	&"volumetric_fog_density": &"volumetric_fog_density", &"volumetric_fog_albedo": &"volumetric_fog_albedo",
	&"ambient_light_energy": &"ambient_light_energy", &"glow_intensity": &"glow_intensity",
	&"glow_hdr_threshold": &"glow_hdr_threshold", &"fog_aerial_perspective": &"fog_aerial_perspective",
	&"fog_sun_scatter": &"fog_sun_scatter", &"fog_height": &"fog_height",
	&"fog_height_density": &"fog_height_density", &"background_energy_scale": &"background_energy_multiplier",
}
## (frame field, key field) pairs of the day palette, for the ported palette cases.
const KEY_FIELDS: Array[Array] = [
	[&"fog_light_color", &"fog_color"], [&"volumetric_fog_albedo", &"volumetric_fog_albedo"],
	[&"light_color", &"light_color"], [&"proc_zenith_color", &"proc_zenith_color"],
	[&"proc_mid_color", &"proc_mid_color"], [&"proc_horizon_color", &"proc_horizon_color"],
	[&"proc_horizon_glow_color", &"proc_horizon_glow_color"], [&"proc_sea_color_near", &"proc_sea_color_near"],
	[&"proc_sea_color_far", &"proc_sea_color_far"], [&"fog_density", &"fog_density"],
	[&"volumetric_fog_density", &"volumetric_fog_density"], [&"light_energy", &"light_energy"],
	[&"ambient_light_energy", &"ambient_energy"], [&"proc_horizon_glow_width", &"proc_horizon_glow_width"],
	[&"proc_sun_glow_strength", &"proc_sun_glow_strength"], [&"sun_core_color", &"sun_core_color"],
	[&"sun_halo_color", &"sun_halo_color"], [&"sun_ray_color", &"sun_ray_color"],
	[&"cloud_shadow_color", &"cloud_shadow_color"], [&"cloud_mid_color", &"cloud_mid_color"],
	[&"cloud_lit_color", &"cloud_lit_color"], [&"cloud_rim_color", &"cloud_rim_color"],
	[&"puff_shadow_color", &"puff_shadow_color"], [&"puff_mid_color", &"puff_mid_color"],
	[&"puff_lit_color", &"puff_lit_color"], [&"puff_rim_color", &"puff_rim_color"],
]

var _original_preset_id: StringName
var _sunset: SkyThemeDef = null
var _dawn: SkyThemeDef = null
var _night: SkyThemeDef = null
var _storm: SkyThemeDef = null
var _def: SkyCycleDef = null
var _overlay: SkyOverlayDef = null


func before_each() -> void:
	_original_preset_id = Settings.current_graphics_preset().id
	Settings.set_graphics_preset(&"high")
	_sunset = Skybox.load_theme("sunset")
	_dawn = Skybox.load_theme("dawn")
	_night = Skybox.load_theme("night")
	_storm = Skybox.load_theme("storm")
	_def = SkyThemeMigration.cycle_from_themes(_sunset, _dawn, _night)
	_overlay = SkyThemeMigration.overlay_from_theme(_storm)


func after_each() -> void:
	Settings.set_graphics_preset(_original_preset_id)


# --- live harness ---------------------------------------------------------------------------

## A wired cycle Skybox running from RUN_START_PHASE at clock 0, with a key light, a flare and
## the match seed `seed_value`.
func _live(seed_value: int) -> Skybox:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = KEY_NAME
	skybox.add_child(light)
	skybox.light_path = NodePath(KEY_NAME)
	add_child_autofree(skybox)
	var flare: SunFlare = SunFlare.new()
	add_child_autofree(flare)
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	config.rng_seed = seed_value
	config.sky_start_phase = RUN_START_PHASE
	skybox.configure_match_sky(config)
	return skybox


func _flare() -> SunFlare:
	return get_tree().get_nodes_in_group(SunFlare.GROUP)[0] as SunFlare


## Every value the live Skybox wrote that a SkyFrame field carries, keyed by field name. Values a
## writer leaves untouched (unset uniforms, aurora look while hidden) are left out.
func _live_values(skybox: Skybox, frame: SkyFrame) -> Dictionary[StringName, Variant]:
	skybox.flush_weather()
	var values: Dictionary[StringName, Variant] = {}
	var sky: ShaderMaterial = skybox.environment.sky.sky_material as ShaderMaterial
	for field: StringName in SKY_FIELDS:
		var value: Variant = sky.get_shader_parameter(SKY_FIELDS[field])
		if value != null:
			values[field] = value
	if frame.aurora_visibility > 0.0:
		for field: StringName in AURORA_LOOK_FIELDS:
			values[field] = sky.get_shader_parameter(field)
	var sun_scale: Variant = sky.get_shader_parameter(&"sun_effect_scale")
	if sun_scale is float:
		values[&"sun_effect_scale"] = sun_scale
	var environment: Environment = skybox.environment
	for field: StringName in ENVIRONMENT_FIELDS:
		values[field] = environment.get(ENVIRONMENT_FIELDS[field])
	values[&"fog_depth_mode"] = environment.fog_mode == Environment.FOG_MODE_DEPTH
	if frame.fog_depth_mode:
		values[&"fog_depth_begin"] = environment.fog_depth_begin
		values[&"fog_depth_end"] = environment.fog_depth_end
	var light: DirectionalLight3D = skybox.get_node(KEY_NAME) as DirectionalLight3D
	values[&"light_color"] = light.light_color
	values[&"light_energy"] = light.light_energy
	var deck: FogVolume = skybox.get_node("CloudDeck") as FogVolume
	var deck_material: FogMaterial = deck.material as FogMaterial
	values[&"deck_density"] = deck_material.density
	values[&"deck_albedo"] = deck_material.albedo
	var puffs: ShaderMaterial = (skybox.get_node("CloudSea") as CloudSea).puff_material()
	assert_not_null(puffs, "fixture: the cloud sea has a puff material")
	if puffs != null:
		for field: StringName in PUFF_FIELDS:
			var value: Variant = puffs.get_shader_parameter(PUFF_FIELDS[field])
			if value != null:
				values[field] = value
	values[&"lighting_light_color"] = skybox._cloud_lighting.light_color
	values[&"cloud_overcast"] = skybox._cloud_lighting.overcast
	values[&"sun_effects"] = skybox._cloud_lighting.sun_scale
	values[&"flare_weather_scale"] = _flare()._weather_scale
	if frame.storm_amount > 0.0:
		values[&"flare_enabled"] = _flare()._theme_enabled
	return values


func _close(expected: Variant, actual: Variant) -> bool:
	if expected is Color and actual is Color:
		var a: Color = expected as Color
		var b: Color = actual as Color
		return _near(a.r, b.r) and _near(a.g, b.g) and _near(a.b, b.b) and _near(a.a, b.a)
	if expected is Vector3 and actual is Vector3:
		var u: Vector3 = expected as Vector3
		var v: Vector3 = actual as Vector3
		return _near(u.x, v.x) and _near(u.y, v.y) and _near(u.z, v.z)
	if expected is bool or actual is bool:
		return bool(expected) == bool(actual)
	return _near(float(expected), float(actual))


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= TOLERANCE * maxf(1.0, maxf(absf(a), absf(b)))


## Asserts every live value equals the frame's field of the same name (`skip` names are left out).
func _assert_parity(frame: SkyFrame, skybox: Skybox, label: String, skip: Array[StringName] = []) -> void:
	var expected: Dictionary = frame.to_dict()
	var live: Dictionary[StringName, Variant] = _live_values(skybox, frame)
	var compared: int = 0
	for field: StringName in live:
		if skip.has(field):
			continue
		compared += 1
		assert_true(_close(expected[field], live[field]),
			"%s: %s frame %s vs live %s" % [label, field, expected[field], live[field]])
	assert_gt(compared, 70, "%s: the comparison covers the channels the old code writes" % label)
	if not skip.has(&"light_rotation_deg"):
		_assert_light_orientation(frame, skybox, label)


func _assert_light_orientation(frame: SkyFrame, skybox: Skybox, label: String) -> void:
	var light: DirectionalLight3D = skybox.get_node(KEY_NAME) as DirectionalLight3D
	assert_eq(frame.light_uses_sun_basis, frame.sun_direction.y >= 0.0, "%s: basis follows the sun above the horizon" % label)
	if frame.light_uses_sun_basis:
		assert_true(_close(frame.sun_direction, light.global_basis.z), "%s: key light looks along the sun" % label)
	else:
		assert_true(_close(frame.light_rotation_deg, light.rotation_degrees), "%s: night key rotation" % label)


func _weather() -> SkyWeatherState:
	var weather: SkyWeatherState = SkyWeatherState.new()
	weather.tuning = CEILING
	return weather


func _set_overcast(skybox: Skybox, weather: SkyWeatherState) -> void:
	weather.overcast_amount = 0.6
	weather.overcast_light_scale = 0.55
	weather.overcast_ambient_scale = 0.75
	weather.overcast_exposure_scale = 0.8
	weather.overcast_fog_tint = Color(0.6, 0.65, 0.7)
	weather.overcast_fog_tint_strength = 0.5
	if skybox != null:
		skybox.set_overcast(weather.overcast_amount, weather.overcast_light_scale, weather.overcast_ambient_scale,
			weather.overcast_exposure_scale, weather.overcast_fog_tint, weather.overcast_fog_tint_strength)


func _set_weather_fog(skybox: Skybox, weather: SkyWeatherState) -> void:
	weather.wfog_amount = 0.7
	weather.wfog_max_opacity = 0.6
	weather.wfog_depth_begin_m = 12.0
	weather.wfog_depth_end_m = 140.0
	weather.wfog_tint = Color(0.7, 0.72, 0.78)
	weather.wfog_tint_strength = 0.4
	weather.wfog_sky_affect_add = 0.2
	skybox.set_weather_fog(weather.wfog_amount, weather.wfog_max_opacity, weather.wfog_depth_begin_m,
		weather.wfog_depth_end_m, weather.wfog_tint, weather.wfog_tint_strength, weather.wfog_sky_affect_add)


func _set_snow_and_sun(skybox: Skybox, weather: SkyWeatherState) -> void:
	weather.snow_brighten = 0.5
	weather.weather_cloud_overcast = 0.4
	weather.sun_cloud_scale = 0.6
	skybox.set_snow_brighten(weather.snow_brighten)
	skybox.set_weather_cloud_overcast(weather.weather_cloud_overcast)
	skybox.set_sun_cloud_scale(weather.sun_cloud_scale)


func _set_storm(skybox: Skybox, weather: SkyWeatherState) -> void:
	weather.storm_amount = STORM_AMOUNT
	weather.storm_overlay = _overlay
	skybox.set_storm_sky(STORM_AMOUNT, _overlay)


# --- parity with the live cycle -------------------------------------------------------------

func test_evaluator_matches_live_cycle_at_locked_phases() -> void:
	var clear: SkyWeatherState = _weather()
	for phase: float in LOCKED_PHASES:
		var skybox: Skybox = _live(SEED)
		skybox.set_locked_phase(phase)
		var frame: SkyFrame = SkyEvaluator.evaluate(_def, phase, SkyVariation.seed_for(SEED), 0, clear, true)
		_assert_parity(frame, skybox, "phase %s" % phase)


func test_evaluator_matches_live_storm_at_midnight() -> void:
	var skybox: Skybox = _live(SEED)
	skybox.set_locked_phase(0.75)
	var weather: SkyWeatherState = _weather()
	_set_storm(skybox, weather)
	var frame: SkyFrame = SkyEvaluator.evaluate(_def, 0.75, SkyVariation.seed_for(SEED), 0, weather, true)
	assert_eq(frame.storm_amount, STORM_AMOUNT)
	_assert_parity(frame, skybox, "storm 0.5 at 0.75")


func test_evaluator_matches_live_daytime_storms() -> void:
	for case_row: Array in [[0.25, 0.5], [0.47, 1.0]]:
		var phase: float = float(case_row[0])
		var amount: float = float(case_row[1])
		var skybox: Skybox = _live(SEED)
		skybox.set_locked_phase(phase)
		var weather: SkyWeatherState = _weather()
		weather.storm_amount = amount
		weather.storm_overlay = _overlay
		skybox.set_storm_sky(amount, _overlay)
		var frame: SkyFrame = SkyEvaluator.evaluate(_def, phase, SkyVariation.seed_for(SEED), 0, weather, true)
		assert_eq(frame.storm_amount, amount)
		_assert_parity(frame, skybox, "storm %s at %s" % [amount, phase])


func test_storm_amount_without_an_overlay_is_no_storm() -> void:
	# The live set_storm_sky() treats a null storm theme as amount 0 everywhere (blend, dim, keep).
	var skybox: Skybox = _live(SEED)
	skybox.set_locked_phase(0.25)
	skybox.set_storm_sky(STORM_AMOUNT, null)
	var weather: SkyWeatherState = _weather()
	weather.storm_amount = STORM_AMOUNT
	weather.storm_overlay = null
	var frame: SkyFrame = SkyEvaluator.evaluate(_def, 0.25, SkyVariation.seed_for(SEED), 0, weather, true)
	assert_eq(frame.storm_amount, 0.0)
	_assert_parity(frame, skybox, "storm amount with null overlay")


func test_evaluator_matches_live_aurora_night() -> void:
	var chance: float = _def.aurora_night_chance
	var seed_value: int = -1
	for candidate: int in MAX_AURORA_SEED_SEARCH:
		if SkyVariation.aurora_night_shown(SkyVariation.seed_for(candidate), 0, chance):
			seed_value = candidate
			break
	assert_ne(seed_value, -1, "fixture: a seed whose first night shows the aurora")
	var skybox: Skybox = _live(seed_value)
	skybox.set_locked_phase(0.75)
	var frame: SkyFrame = SkyEvaluator.evaluate(_def, 0.75, SkyVariation.seed_for(seed_value), 0, _weather(), true)
	assert_gt(frame.aurora_visibility, 0.0, "fixture: the aurora shows")
	_assert_parity(frame, skybox, "aurora night")
	var hidden: SkyFrame = SkyEvaluator.evaluate(_def, 0.75, SkyVariation.seed_for(seed_value), 0, _weather(), false)
	assert_eq(hidden.aurora_visibility, 0.0, "the Low preset hides the aurora")


## Weather requests land after the tick, with the clock half a tick on: the old code used the
## last tick's palette values, so stages B and C reading the cached tick frame must match it.
func test_staged_weather_uses_last_tick_values() -> void:
	var seed_value: int = SkyVariation.seed_for(SEED)
	var tick: SkyFrame = SkyEvaluator.evaluate_tick(_def, RUN_START_PHASE, seed_value, 0, true)
	var moved: SkyFrame = SkyEvaluator.evaluate_tick(_def, RUN_START_PHASE + HALF_TICK_PHASE, seed_value, 0, true)
	assert_false(_close(tick.light_energy, moved.light_energy), "fixture: the phase step is measurable")
	assert_false(_close(tick.fog_light_color, moved.fog_light_color), "fixture: the fog colour moves with the phase")
	var cases: Array[String] = ["overcast", "weather fog", "sun cloud scale", "snow and cloud overcast", "storm", "all"]
	for case_name: String in cases:
		var skybox: Skybox = _live(SEED)
		var weather: SkyWeatherState = _weather()
		if case_name == "overcast" or case_name == "all":
			_set_overcast(skybox, weather)
		if case_name == "weather fog" or case_name == "all":
			_set_weather_fog(skybox, weather)
		if case_name == "sun cloud scale" or case_name == "snow and cloud overcast" or case_name == "all":
			_set_snow_and_sun(skybox, weather)
		if case_name == "storm" or case_name == "all":
			_set_storm(skybox, weather)
		var storm_frame: SkyFrame = SkyFrame.new()
		SkyEvaluator.apply_storm(tick, weather.storm_amount, weather.storm_overlay, CEILING.storm_flare_off_amount, storm_frame)
		var out: SkyFrame = SkyFrame.new()
		SkyEvaluator.apply_weather(storm_frame, weather, out)
		_assert_parity(out, skybox, "staged %s" % case_name)
		var chained: SkyFrame = SkyEvaluator.evaluate(_def, RUN_START_PHASE, seed_value, 0, weather, true)
		assert_eq(chained.to_dict(), out.to_dict(), "%s: evaluate() chains the three stages" % case_name)


func test_stages_do_not_mutate_their_inputs() -> void:
	var weather: SkyWeatherState = _weather()
	_set_overcast(null, weather)
	var tick: SkyFrame = SkyEvaluator.evaluate_tick(_def, 0.6, SEED, 2, true)
	var before: Dictionary = tick.to_dict()
	var storm_frame: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_storm(tick, STORM_AMOUNT, _overlay, CEILING.storm_flare_off_amount, storm_frame)
	var out: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_weather(storm_frame, weather, out)
	assert_eq(tick.to_dict(), before, "stage A frame is untouched by B and C")
	assert_ne(storm_frame.to_dict(), before)
	var again: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_weather(storm_frame, weather, again)
	assert_eq(again.to_dict(), out.to_dict(), "stage C is repeatable from the cached frame")


func test_zero_storm_and_clear_weather_are_identity() -> void:
	var tick: SkyFrame = SkyEvaluator.evaluate_tick(_def, 0.3, SEED, 0, true)
	var storm_frame: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_storm(tick, 0.0, _overlay, CEILING.storm_flare_off_amount, storm_frame)
	assert_eq(storm_frame.to_dict(), tick.to_dict(), "amount 0 is the tick frame")
	var out: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_weather(storm_frame, _weather(), out)
	for field: StringName in [&"light_energy", &"ambient_light_energy", &"fog_light_color", &"fog_density", &"exposure"]:
		assert_eq(out.get(field), tick.get(field), "clear weather keeps %s" % field)
	assert_eq(out.background_energy_scale, 1.0)
	assert_false(out.fog_depth_mode)


func test_night_index_is_carried_and_drives_the_aurora_roll() -> void:
	var chance: float = _def.aurora_night_chance
	var shown: int = 0
	for night_index: int in 40:
		var frame: SkyFrame = SkyEvaluator.evaluate_tick(_def, 0.75, SEED, night_index, true)
		assert_eq(frame.night_index, night_index)
		var rolled: bool = SkyVariation.aurora_night_shown(SEED, night_index, chance)
		assert_eq(frame.aurora_visibility > 0.0, rolled, "night %d follows the seeded roll" % night_index)
		shown += 1 if rolled else 0
	assert_gt(shown, 0)
	assert_lt(shown, 40)


func test_puff_snapshot_copies_the_sky_values_the_puffs_share() -> void:
	var frame: SkyFrame = SkyEvaluator.evaluate_tick(_def, 0.25, SEED, 0, true)
	var target: SkyFrame = SkyFrame.new()
	SkyEvaluator.puff_snapshot(_def, frame, target)
	assert_eq(target.puff_shared.size(), SkyEvaluator.PUFF_SHARED_KEYS.size())
	assert_eq(target.puff_shared[&"proc_zenith_color"], frame.proc_zenith_color)
	assert_eq(target.puff_shared[&"exposure"], frame.exposure)
	var evening: SkyFrame = SkyEvaluator.evening_frame(_def)
	assert_eq(evening.proc_zenith_color, _def.evening_keyframe().proc_zenith_color, "cycle start seeds the puffs from the evening key")
	assert_eq(evening.sun_direction, _def.sun_base_direction)


# --- SkyVariation.value_at ------------------------------------------------------------------

func test_value_at_is_bit_identical_to_the_base_formula() -> void:
	# The base (pre-value_at) formula, written out: clamp(lerp(min, max, clamp(weight))) per channel.
	var theme: SkyThemeDef = _sunset
	var ranges: Array[Array] = [
		[theme.variation_exposure_min, theme.variation_exposure_max, SkyVariation.CHANNEL_EXPOSURE],
		[theme.variation_sea_coverage_min, theme.variation_sea_coverage_max, SkyVariation.CHANNEL_SEA_COVERAGE],
		[0.9, 0.3, SkyVariation.CHANNEL_CLOUD_COVERAGE],
	]
	for seed_value: int in VARIATION_SEEDS:
		for step: int in range(VARIATION_SWEEP_STEPS + 1):
			var phase: float = float(step) / float(VARIATION_SWEEP_STEPS)
			for range_row: Array in ranges:
				var low: float = minf(float(range_row[0]), float(range_row[1]))
				var high: float = maxf(float(range_row[0]), float(range_row[1]))
				var weight: float = SkyVariation.weight(phase, theme.variation_knots_per_cycle, seed_value, int(range_row[2]))
				var base: float = clampf(lerpf(low, high, clampf(weight, 0.0, 1.0)), low, high)
				assert_eq(SkyVariation.value_at(float(range_row[0]), float(range_row[1]), theme.variation_knots_per_cycle,
					phase, seed_value, int(range_row[2])), base, "seed %d phase %s channel %d" % [seed_value, phase, int(range_row[2])])
	assert_eq(SkyVariation.in_range(0.8, 0.95, 0.0), 0.8)
	assert_eq(SkyVariation.in_range(0.8, 0.95, 1.0), 0.95)
	assert_eq(SkyVariation.in_range(0.95, 0.8, 1.0), 0.95, "a swapped pair is a range")
	assert_almost_eq(SkyVariation.in_range(0.8, 0.95, 0.5), 0.875, 0.0000001)


func test_evaluator_variation_equals_the_theme_helpers() -> void:
	var frame: SkyFrame = SkyFrame.new()
	for seed_value: int in VARIATION_SEEDS:
		for phase: float in [0.0, 0.13, 0.5, 0.77, 0.999]:
			SkyEvaluator.apply_variation(_def, phase, seed_value, frame)
			assert_eq(frame.exposure, SkyVariation.exposure_at(_sunset, phase, seed_value))
			assert_eq(frame.puff_exposure, frame.exposure)
			assert_eq(frame.proc_sea_coverage, SkyVariation.sea_coverage_at(_sunset, phase, seed_value))
			assert_eq(frame.puff_sea_coverage, frame.proc_sea_coverage)


# --- ported from test_sky_palette.gd (SKY-15 deletes that file once this mapping exists) -----

func _keyed(seed_value: float) -> SkyKeyframe:
	# A key whose every palette field is a distinct value derived from seed_value.
	var key: SkyKeyframe = SkyKeyframe.new()
	for pair: Array in KEY_FIELDS:
		var field: StringName = pair[1] as StringName
		if key.get(field) is Color:
			key.set(field, Color(seed_value, seed_value * 0.5 + float(KEY_FIELDS.find(pair)) * 0.01, 1.0 - seed_value, 1.0))
		else:
			key.set(field, seed_value * 2.0 + 0.25 + float(KEY_FIELDS.find(pair)) * 0.01)
	return key


func _two_key_def(a: SkyKeyframe, b: SkyKeyframe) -> SkyCycleDef:
	var def: SkyCycleDef = SkyCycleDef.new()
	b.phase_window = DEFAULT_WINDOW
	var keys: Array[SkyKeyframe] = [a, b]
	def.day_keyframes = keys
	return def


func _assert_palette(frame: SkyFrame, key: SkyKeyframe, label: String) -> void:
	for pair: Array in KEY_FIELDS:
		assert_eq(frame.get(pair[0] as StringName), key.get(pair[1] as StringName), "%s: %s" % [label, pair[0]])


func test_palette_dusk_weight_is_zero_by_day_and_one_from_sunset_through_the_night() -> void:
	# The window is a Vector4 (32-bit components), so the literal edge phases are
	# compared with a tolerance; the window's own edge values are exact.
	for phase: float in [0.0, 0.03, 0.10, 0.25, 0.30]:
		assert_almost_eq(SkyEvaluator.window_weight(phase, DEFAULT_WINDOW), 0.0, 0.000001, "morning/noon phase %s is the dawn palette" % phase)
	for phase: float in [0.46, 0.47, 0.5, 0.75, 0.90]:
		assert_almost_eq(SkyEvaluator.window_weight(phase, DEFAULT_WINDOW), 1.0, 0.000001, "phase %s is the sunset palette" % phase)
	for phase: float in [0.98, 0.99, 1.0]:
		assert_almost_eq(SkyEvaluator.window_weight(phase, DEFAULT_WINDOW), 0.0, 0.000001, "phase %s is back to the dawn palette" % phase)
	assert_eq(SkyEvaluator.window_weight(DEFAULT_WINDOW.x, DEFAULT_WINDOW), 0.0, "exactly dawn at the window start")
	assert_eq(SkyEvaluator.window_weight(DEFAULT_WINDOW.y, DEFAULT_WINDOW), 1.0, "exactly sunset at the rise end")
	assert_eq(SkyEvaluator.window_weight(DEFAULT_WINDOW.z, DEFAULT_WINDOW), 1.0, "still sunset at the fall start")
	assert_eq(SkyEvaluator.window_weight(DEFAULT_WINDOW.w, DEFAULT_WINDOW), 0.0, "exactly dawn again at the fall end")
	assert_eq(SkyEvaluator.window_weight(0.47, DEFAULT_WINDOW), 1.0, "the Sunset lock phase is exactly the sunset palette")
	assert_eq(SkyEvaluator.window_weight(0.03, DEFAULT_WINDOW), 0.0, "the Dawn lock phase is exactly the dawn palette")
	assert_almost_eq(SkyEvaluator.window_weight(1.03, DEFAULT_WINDOW), SkyEvaluator.window_weight(0.03, DEFAULT_WINDOW), 0.000001, "wraps 1 -> 0")
	assert_eq(SkyEvaluator.window_weight(0.5, DEFAULT_WINDOW), SkyPalette.dusk_weight(0.5, DEFAULT_WINDOW), "same rule as the old SkyPalette")
	for step: int in 101:
		var phase: float = float(step) / 100.0
		assert_eq(SkyEvaluator.window_weight(phase, DEFAULT_WINDOW), SkyPalette.dusk_weight(phase, DEFAULT_WINDOW), "phase %s" % phase)


func test_palette_blend_endpoints_are_exactly_the_two_palettes() -> void:
	var a: SkyKeyframe = _keyed(0.2)
	var b: SkyKeyframe = _keyed(0.9)
	var def: SkyCycleDef = _two_key_def(a, b)
	var frame: SkyFrame = SkyFrame.new()
	SkyEvaluator.day_palette(def, 0.0, frame)
	_assert_palette(frame, a, "weight 0")
	SkyEvaluator.day_palette(def, 0.5, frame)
	_assert_palette(frame, b, "weight 1")
	var color_a: Color = Color(0.1, 0.2, 0.3)
	var color_b: Color = Color(0.9, 0.8, 0.7)
	assert_eq(SkyEvaluator.mix_color(color_a, color_b, -3.0), color_a, "weight below 0 is exactly a")
	assert_eq(SkyEvaluator.mix_color(color_a, color_b, 7.0), color_b, "weight above 1 is exactly b")
	assert_eq(SkyEvaluator.mix_scalar(0.25, 1.75, 0.0), 0.25)
	assert_eq(SkyEvaluator.mix_scalar(0.25, 1.75, 1.0), 1.75)
	assert_eq(SkyEvaluator.mix_scalar(0.25, 1.75, -3.0), 0.25)
	assert_eq(SkyEvaluator.mix_scalar(0.25, 1.75, 7.0), 1.75)


func test_palette_blend_midpoint_is_the_linear_mix_of_every_field() -> void:
	var a: SkyKeyframe = _keyed(0.2)
	var b: SkyKeyframe = _keyed(0.8)
	var def: SkyCycleDef = _two_key_def(a, b)
	var phase: float = 0.38
	var weight: float = SkyEvaluator.window_weight(phase, b.phase_window)
	assert_between(weight, 0.01, 0.99, "fixture: inside the window")
	var frame: SkyFrame = SkyFrame.new()
	SkyEvaluator.day_palette(def, phase, frame)
	for pair: Array in KEY_FIELDS:
		var from_value: Variant = a.get(pair[1] as StringName)
		var to_value: Variant = b.get(pair[1] as StringName)
		var actual: Variant = frame.get(pair[0] as StringName)
		if from_value is Color:
			assert_true((actual as Color).is_equal_approx((from_value as Color).lerp(to_value as Color, weight)), "colour %s" % pair[0])
		else:
			assert_almost_eq(float(actual), lerpf(float(from_value), float(to_value), weight), 0.00001, "scalar %s" % pair[0])


func test_palette_blend_writes_only_the_palette_and_never_the_sources() -> void:
	var a: SkyKeyframe = _keyed(0.2)
	var b: SkyKeyframe = _keyed(0.9)
	var def: SkyCycleDef = _two_key_def(a, b)
	var frame: SkyFrame = SkyFrame.new()
	frame.light_rotation_deg = Vector3(-33.0, 12.0, 0.0)
	frame.sun_direction = Vector3(0.0, 1.0, 0.0)
	frame.cycle_night_mix = 0.6
	frame.exposure = 1.5
	frame.proc_gradient_power = 2.5
	frame.puff_exposure = 1.4
	var a_zenith: Color = a.proc_zenith_color
	var b_lit: Color = b.puff_lit_color
	SkyEvaluator.day_palette(def, 0.38, frame)
	assert_eq(frame.light_rotation_deg, Vector3(-33.0, 12.0, 0.0), "the cycle owns the light direction")
	assert_eq(frame.sun_direction, Vector3(0.0, 1.0, 0.0), "sun direction is not palette")
	assert_eq(frame.cycle_night_mix, 0.6, "the night mix is not palette")
	assert_eq(frame.exposure, 1.5, "exposure is structure, not palette")
	assert_eq(frame.proc_gradient_power, 2.5, "gradient shape is structure")
	assert_eq(frame.puff_exposure, 1.4)
	assert_eq(a.proc_zenith_color, a_zenith, "sources are read-only")
	assert_eq(b.puff_lit_color, b_lit)
	assert_eq(b.phase_window, DEFAULT_WINDOW)


func test_palette_variation_weight_stays_in_unit_range_for_any_seed_channel_and_phase() -> void:
	for seed_value: int in VARIATION_SEEDS:
		for channel: int in [SkyVariation.CHANNEL_EXPOSURE, SkyVariation.CHANNEL_CLOUD_COVERAGE, SkyVariation.CHANNEL_SEA_COVERAGE]:
			for step: int in range(VARIATION_SWEEP_STEPS + 1):
				var value: float = SkyVariation.weight(float(step) / float(VARIATION_SWEEP_STEPS), 3, seed_value, channel)
				assert_between(value, 0.0, 1.0, "seed %s channel %s step %s" % [seed_value, channel, step])
				assert_between(SkyVariation.value_at(0.0, 1.0, 3, float(step) / float(VARIATION_SWEEP_STEPS), seed_value, channel), 0.0, 1.0)


func test_palette_variation_is_a_pure_function_of_seed_and_phase() -> void:
	for step: int in range(0, VARIATION_SWEEP_STEPS, 7):
		var phase: float = float(step) / float(VARIATION_SWEEP_STEPS)
		assert_eq(SkyVariation.value_at(0.8, 0.95, 3, phase, 1234, SkyVariation.CHANNEL_EXPOSURE),
			SkyVariation.value_at(0.8, 0.95, 3, phase, 1234, SkyVariation.CHANNEL_EXPOSURE), "repeatable at %s" % phase)
		var first: SkyFrame = SkyEvaluator.evaluate_tick(_def, phase, 1234, 0, true)
		var second: SkyFrame = SkyEvaluator.evaluate_tick(_def, phase, 1234, 0, true)
		assert_eq(first.to_dict(), second.to_dict(), "the whole tick frame repeats at %s" % phase)


func test_palette_variation_seed_for_uses_the_match_seed_and_a_default_for_random() -> void:
	assert_eq(SkyVariation.seed_for(1234), 1234)
	assert_eq(SkyVariation.seed_for(0), 0)
	assert_eq(SkyVariation.seed_for(-1), SkyVariation.DEFAULT_SEED)


func test_palette_variation_values_stay_inside_the_theme_ranges_whatever_the_seed() -> void:
	var def: SkyCycleDef = SkyCycleDef.new()
	var theme: SkyThemeDef = SkyThemeDef.new()
	var frame: SkyFrame = SkyFrame.new()
	for seed_value: int in VARIATION_SEEDS:
		for step: int in range(VARIATION_SWEEP_STEPS + 1):
			var phase: float = float(step) / float(VARIATION_SWEEP_STEPS)
			SkyEvaluator.apply_variation(def, phase, seed_value, frame)
			assert_between(frame.exposure, def.variation_exposure_min, def.variation_exposure_max)
			assert_between(frame.proc_sea_coverage, def.variation_sea_coverage_min, def.variation_sea_coverage_max)
			assert_between(SkyVariation.value_at(theme.variation_cloud_coverage_min, theme.variation_cloud_coverage_max,
				theme.variation_knots_per_cycle, phase, seed_value, SkyVariation.CHANNEL_CLOUD_COVERAGE),
				theme.variation_cloud_coverage_min, theme.variation_cloud_coverage_max)
	def.variation_exposure_min = 1.2
	def.variation_exposure_max = 1.2
	SkyEvaluator.apply_variation(def, 0.3, 5, frame)
	assert_eq(frame.exposure, 1.2, "a collapsed range is a fixed exposure")
