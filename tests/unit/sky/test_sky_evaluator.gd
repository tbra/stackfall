extends GutTest
## core/sky/SkyEvaluator.gd and SkyVariation.value_at: the shipped cycle evaluated at the golden
## fixture's states (locked phases, the storm, the weather requests, the staged last-tick weather,
## the aurora night) equals the golden, and the pure palette/variation rules ported from the old
## test_sky_palette.gd (each as test_palette_<old name>).

const DEFAULT_WINDOW: Vector4 = Vector4(0.30, 0.46, 0.90, 0.98)
const TOLERANCE: float = 0.00001
## Phases of the golden's L group (locked cycle phases).
const SEED: int = 1234
## First match seed whose night 0 shows the aurora; the golden's aurora states use it.
const AURORA_SEED: int = 8
const NIGHT_PHASE: float = 0.75
## The cycle hour with the highest key light, and the fixed storm light energy the old overlay lerped to.
## Full-day phase (night mix 0, so the puff sea equals the sky sea) and the largest per-channel step a
## 0.001 storm may make.
const DAY_STORM_PHASES: Array[float] = [0.25]
const SMALL_STORM_STEP_TOLERANCE: float = 0.01
const BRIGHTEST_PHASE: float = 0.407
const OLD_STORM_LIGHT_ENERGY: float = 0.45
const STORM_AMOUNT: float = 0.5
const MIN_COMPARED: int = 70
## Weather requests the golden applied (test_sky_parity_live's constants).
const OVERCAST_AMOUNT: float = 0.6
const OVERCAST_LIGHT: float = 0.55
const OVERCAST_AMBIENT: float = 0.7
const OVERCAST_EXPOSURE: float = 0.8
const OVERCAST_TINT: Color = Color(0.62, 0.66, 0.72, 1.0)
const OVERCAST_TINT_STRENGTH: float = 0.6
const FOG_AMOUNT: float = 0.7
const FOG_MAX_OPACITY: float = 0.8
const FOG_BEGIN_M: float = 30.0
const FOG_END_M: float = 400.0
const FOG_TINT: Color = Color(0.7, 0.72, 0.75, 1.0)
const FOG_TINT_STRENGTH: float = 0.5
const FOG_SKY_AFFECT_ADD: float = 0.3
const SNOW_AMOUNT: float = 0.5
const SUN_SCALE: float = 0.6
## window_weight(step / 100, DEFAULT_WINDOW) for step 0..100, captured from the old dusk_weight rule
## (the rule SkyEvaluator.window_weight replaces) before the old class was retired.
const DUSK_WEIGHT_SWEEP: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.011230443047693177, 0.0429687029391167, 0.09228509197783634, 0.15624992246740124, 0.23193350671136007, 0.3164061570132628, 0.40673818567665815, 0.49999990500509534, 0.5932616273021233, 0.6835936648712915, 0.7680663300161483, 0.8437499350402439, 0.9077147922471268, 0.9570312139403465, 0.9887695124234518, 0.9999999999999919, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.9999999999997335, 0.957031098427212, 0.8437498155981883, 0.6835936137941387, 0.4999999552965414, 0.3164063023868686, 0.15625011734659822, 0.04296886245720688, 1.7053026e-13, 0.0, 0.0]
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
var _def: SkyCycleDef = null
var _overlay: SkyOverlayDef = null


func before_each() -> void:
	_original_preset_id = Settings.current_graphics_preset().id
	Settings.set_graphics_preset(&"high")
	_def = SkyTestKit.cycle()
	_overlay = SkyTestKit.storm_overlay()


func after_each() -> void:
	Settings.set_graphics_preset(_original_preset_id)


# --- golden comparison ----------------------------------------------------------------------

static func _golden_states() -> Dictionary:
	return SkyTestKit.golden().get("states", {}) as Dictionary


## A golden array value as the Color / Vector3 it encodes (other values unchanged).
static func _decode(value: Variant) -> Variant:
	if value is Array:
		var parts: Array = value as Array
		if parts.size() == 4:
			return Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))
		if parts.size() == 3:
			return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return value


static func _near(a: float, b: float) -> bool:
	return absf(a - b) <= TOLERANCE * maxf(1.0, maxf(absf(a), absf(b)))


static func _close(expected: Variant, actual: Variant) -> bool:
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


## The golden values a frame field must equal, keyed by field name: every sky-material uniform,
## puff uniform, Environment property, key-light and fog-volume value, cloud-lighting and flare
## input the frame carries. Values the writers leave untouched (the aurora look while hidden,
## fog depth bounds outside depth mode) are left out.
static func _golden_values(frame: SkyFrame, state: Dictionary) -> Dictionary[StringName, Variant]:
	var values: Dictionary[StringName, Variant] = {}
	var sky: Dictionary = state.get("sky", {}) as Dictionary
	for field: StringName in SKY_FIELDS:
		var uniform_name: String = str(SKY_FIELDS[field])
		if sky.get(uniform_name) != null:
			values[field] = _decode(sky[uniform_name])
	if frame.aurora_visibility > 0.0:
		for field: StringName in AURORA_LOOK_FIELDS:
			values[field] = _decode(sky[str(field)])
	if sky.get("sun_effect_scale") is float:
		values[&"sun_effect_scale"] = sky["sun_effect_scale"]
	var env: Dictionary = state.get("env", {}) as Dictionary
	for field: StringName in ENVIRONMENT_FIELDS:
		values[field] = _decode(env[str(ENVIRONMENT_FIELDS[field])])
	values[&"fog_depth_mode"] = int(env["fog_mode"]) == Environment.FOG_MODE_DEPTH
	if frame.fog_depth_mode:
		values[&"fog_depth_begin"] = env["fog_depth_begin"]
		values[&"fog_depth_end"] = env["fog_depth_end"]
	var light: Dictionary = state.get("light", {}) as Dictionary
	values[&"light_color"] = _decode(light["color"])
	values[&"light_energy"] = light["energy"]
	var deck: Dictionary = state.get("fog_volume", {}) as Dictionary
	values[&"deck_density"] = deck["density"]
	values[&"deck_albedo"] = _decode(deck["albedo"])
	var puff: Dictionary = state.get("puff", {}) as Dictionary
	for field: StringName in PUFF_FIELDS:
		var uniform_name: String = str(PUFF_FIELDS[field])
		if puff.get(uniform_name) != null:
			values[field] = _decode(puff[uniform_name])
	var lighting: Dictionary = state.get("lighting", {}) as Dictionary
	values[&"lighting_light_color"] = _decode(lighting["light_color"])
	values[&"cloud_overcast"] = lighting["overcast"]
	values[&"sun_effects"] = lighting["sun_scale"]
	var flare: Dictionary = state.get("flare", {}) as Dictionary
	values[&"flare_weather_scale"] = flare["weather_scale"]
	if frame.storm_amount > 0.0:
		values[&"flare_enabled"] = flare["theme_enabled"]
	return values


## Every field of `frame` under its own name (the frame carries only plain typed script variables).
static func frame_values(frame: SkyFrame) -> Dictionary[StringName, Variant]:
	var values: Dictionary[StringName, Variant] = {}
	for property: Dictionary in frame.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			var field: StringName = StringName(str(property["name"]))
			values[field] = frame.get(field)
	return values


## Every way `frame` differs from the golden `state` (empty when it equals it).
static func golden_mismatches(frame: SkyFrame, state: Dictionary, label: String) -> Array[String]:
	var problems: Array[String] = []
	if state.is_empty():
		problems.append("%s: the golden has no such state" % label)
		return problems
	var expected: Dictionary = frame_values(frame)
	var golden: Dictionary[StringName, Variant] = _golden_values(frame, state)
	for field: StringName in golden:
		if not _close(golden[field], expected[field]):
			problems.append("%s: %s golden %s vs frame %s" % [label, field, golden[field], expected[field]])
	if golden.size() <= MIN_COMPARED:
		problems.append("%s: only %d channels compared" % [label, golden.size()])
	var light: Dictionary = state.get("light", {}) as Dictionary
	var parts: Array = light["basis"] as Array
	var basis: Basis = Basis(Vector3(float(parts[0]), float(parts[1]), float(parts[2])),
		Vector3(float(parts[3]), float(parts[4]), float(parts[5])), Vector3(float(parts[6]), float(parts[7]), float(parts[8])))
	if frame.light_uses_sun_basis != (frame.sun_direction.y >= 0.0):
		problems.append("%s: the light basis does not follow the sun above the horizon" % label)
	if frame.light_uses_sun_basis:
		if not _close(frame.sun_direction, basis.z):
			problems.append("%s: key light does not look along the sun" % label)
	else:
		var rotation: Vector3 = frame.light_rotation_deg
		var night_basis: Basis = Basis.from_euler(Vector3(deg_to_rad(rotation.x), deg_to_rad(rotation.y), deg_to_rad(rotation.z)))
		if not night_basis.is_equal_approx(basis):
			problems.append("%s: night key rotation %s is not the golden basis" % [label, rotation])
	return problems


func _assert_golden(frame: SkyFrame, state_name: String) -> void:
	var problems: Array[String] = golden_mismatches(frame, _golden_states().get(state_name, {}) as Dictionary, state_name)
	for problem: String in problems:
		fail_test(problem)
	assert_eq(problems.size(), 0, "%s equals the golden" % state_name)


# --- weather requests -----------------------------------------------------------------------

static func clear_weather() -> SkyWeatherState:
	var weather: SkyWeatherState = SkyWeatherState.new()
	weather.tuning = CEILING
	return weather


func _weather() -> SkyWeatherState:
	return clear_weather()


## The request the golden applied for `kind` ("overcast", "fog", "snow", "sun", "storm") at `amount`.
func _request(weather: SkyWeatherState, kind: String, amount: float) -> void:
	match kind:
		"overcast":
			weather.overcast_amount = amount
			weather.overcast_light_scale = OVERCAST_LIGHT
			weather.overcast_ambient_scale = OVERCAST_AMBIENT
			weather.overcast_exposure_scale = OVERCAST_EXPOSURE
			weather.overcast_fog_tint = OVERCAST_TINT
			weather.overcast_fog_tint_strength = OVERCAST_TINT_STRENGTH
			weather.weather_cloud_overcast = amount
		"fog":
			weather.wfog_amount = amount
			weather.wfog_max_opacity = FOG_MAX_OPACITY
			weather.wfog_depth_begin_m = FOG_BEGIN_M
			weather.wfog_depth_end_m = FOG_END_M
			weather.wfog_tint = FOG_TINT
			weather.wfog_tint_strength = FOG_TINT_STRENGTH
			weather.wfog_sky_affect_add = FOG_SKY_AFFECT_ADD
		"snow":
			weather.snow_brighten = amount
		"sun":
			weather.sun_cloud_scale = amount
		"storm":
			weather.storm_amount = amount
			weather.storm_overlay = _overlay


## The request amount the golden's single-step half-tick states used.
func _step_amount(step: String) -> float:
	match step:
		"overcast":
			return OVERCAST_AMOUNT
		"fog":
			return FOG_AMOUNT
		"sun":
			return SUN_SCALE
		"storm":
			return STORM_AMOUNT
	return SNOW_AMOUNT


## The weather request the golden's "all" step applied.
func _request_all(weather: SkyWeatherState) -> void:
	for step: String in ["overcast", "fog", "sun", "storm", "snow"]:
		_request(weather, step, _step_amount(step))


# --- golden: the cycle at the locked phases and under weather -------------------------------

func test_storm_amount_without_an_overlay_is_no_storm() -> void:
	# A storm request with no overlay is amount 0 everywhere (blend, dim, keep): the clear L_0.25 sky.
	var weather: SkyWeatherState = _weather()
	weather.storm_amount = STORM_AMOUNT
	weather.storm_overlay = null
	var clear: SkyFrame = SkyEvaluator.evaluate_tick(_def, 0.25, SkyVariation.DEFAULT_SEED, 0, true)
	var storm_frame: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_storm(clear, weather.storm_amount, weather.storm_overlay, CEILING.storm_flare_off_amount, storm_frame)
	var out: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_weather(storm_frame, weather, out)
	assert_eq(out.storm_amount, 0.0)
	assert_eq(frame_values(storm_frame), frame_values(clear), "no overlay leaves the clear L_0.25 sky")
	for field: StringName in [&"light_energy", &"ambient_light_energy", &"fog_light_color", &"fog_density", &"exposure"]:
		assert_eq(out.get(field), clear.get(field), "no storm keeps %s" % field)


func test_low_preset_hides_the_aurora() -> void:
	var seed_value: int = SkyVariation.seed_for(AURORA_SEED)
	var shown: SkyFrame = SkyEvaluator.evaluate_tick(_def, NIGHT_PHASE, seed_value, 0, true)
	assert_gt(shown.aurora_visibility, 0.0, "fixture: the aurora seed shows the aurora")
	var hidden: SkyFrame = SkyEvaluator.evaluate_tick(_def, NIGHT_PHASE, seed_value, 0, false)
	assert_eq(hidden.aurora_visibility, 0.0, "the Low preset hides the aurora")


## Weather requests land after the tick, with the clock half a tick on: the old code used the
## last tick's palette values, so stages B and C reading the cached tick frame must match the
## golden's half-tick states (clock 0, running from RUN_START_PHASE).
func test_staged_weather_uses_last_tick_values() -> void:
	var seed_value: int = SkyVariation.DEFAULT_SEED
	var tick: SkyFrame = SkyEvaluator.evaluate_tick(_def, RUN_START_PHASE, seed_value, 0, true)
	var moved: SkyFrame = SkyEvaluator.evaluate_tick(_def, RUN_START_PHASE + HALF_TICK_PHASE, seed_value, 0, true)
	assert_false(_close(tick.light_energy, moved.light_energy), "fixture: the phase step is measurable")
	assert_false(_close(tick.fog_light_color, moved.fog_light_color), "fixture: the fog colour moves with the phase")
	for step: String in ["overcast", "fog", "sun", "storm", "snow", "all"]:
		var weather: SkyWeatherState = _weather()
		if step == "all":
			_request_all(weather)
		else:
			_request(weather, step, _step_amount(step))
		var storm_frame: SkyFrame = SkyFrame.new()
		SkyEvaluator.apply_storm(tick, weather.storm_amount, weather.storm_overlay, CEILING.storm_flare_off_amount, storm_frame)
		var out: SkyFrame = SkyFrame.new()
		SkyEvaluator.apply_weather(storm_frame, weather, out)
		_assert_golden(out, "R0_half_tick_%s" % step)


func test_weather_stage_reads_the_weather_tuning_and_falls_back_to_the_default_without_one() -> void:
	var tick: SkyFrame = SkyEvaluator.evaluate_tick(_def, 0.3, SEED, 0, true)
	var custom: WeatherCeilingTuning = CEILING.duplicate() as WeatherCeilingTuning
	custom.puff_floor_shadow_ratio = CEILING.puff_floor_shadow_ratio + 0.17
	var weather: SkyWeatherState = _weather()
	weather.tuning = custom
	var out: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_weather(tick, weather, out)
	assert_eq(out.floor_shadow_ratio, custom.puff_floor_shadow_ratio, "the weather's own tuning is used")
	weather.tuning = null
	SkyEvaluator.apply_weather(tick, weather, out)
	assert_eq(out.floor_shadow_ratio, WeatherCeilingTuning.new().puff_floor_shadow_ratio, "no tuning falls back to the defaults")


func test_stages_do_not_mutate_their_inputs() -> void:
	var weather: SkyWeatherState = _weather()
	_request(weather, "overcast", OVERCAST_AMOUNT)
	var tick: SkyFrame = SkyEvaluator.evaluate_tick(_def, 0.6, SEED, 2, true)
	var before: Dictionary = frame_values(tick)
	var storm_frame: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_storm(tick, STORM_AMOUNT, _overlay, CEILING.storm_flare_off_amount, storm_frame)
	var out: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_weather(storm_frame, weather, out)
	assert_eq(frame_values(tick), before, "stage A frame is untouched by B and C")
	assert_ne(frame_values(storm_frame), before)
	var again: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_weather(storm_frame, weather, again)
	assert_eq(frame_values(again), frame_values(out), "stage C is repeatable from the cached frame")


func test_zero_storm_and_clear_weather_are_identity() -> void:
	var tick: SkyFrame = SkyEvaluator.evaluate_tick(_def, 0.3, SEED, 0, true)
	var storm_frame: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_storm(tick, 0.0, _overlay, CEILING.storm_flare_off_amount, storm_frame)
	assert_eq(frame_values(storm_frame), frame_values(tick), "amount 0 is the tick frame")
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


func test_a_night_storm_keeps_the_night_mixed_puff_far_fade() -> void:
	# Q1 fixed: the storm does not re-copy the sky's day-only sea colours or the overcast-scaled
	# exposure onto the puff channel; the puff sea colours lerp from the night-mixed tick values.
	var tick: SkyFrame = SkyEvaluator.evaluate_tick(_def, NIGHT_PHASE, SEED, 0, true)
	assert_gt(tick.night, 0.9, "fixture: deep night")
	var storm_frame: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_storm(tick, 0.001, _overlay, CEILING.storm_flare_off_amount, storm_frame)
	var jump: Color = storm_frame.puff_sea_color_near - tick.puff_sea_color_near
	assert_lt(maxf(absf(jump.r), maxf(absf(jump.g), absf(jump.b))), SMALL_STORM_STEP_TOLERANCE, "a storm starting at night does not jump")
	assert_ne(storm_frame.puff_sea_color_near, storm_frame.proc_sea_color_near, "starts from the night-mixed colour, not the day sea")
	SkyEvaluator.apply_storm(tick, STORM_AMOUNT, _overlay, CEILING.storm_flare_off_amount, storm_frame)
	assert_eq(storm_frame.puff_sea_color_near, tick.puff_sea_color_near.lerp(_overlay.proc_sea_color_near, STORM_AMOUNT))
	assert_eq(storm_frame.puff_sea_color_far, tick.puff_sea_color_far.lerp(_overlay.proc_sea_color_far, STORM_AMOUNT))
	SkyEvaluator.apply_storm(tick, 1.0, _overlay, CEILING.storm_flare_off_amount, storm_frame)
	assert_eq(storm_frame.puff_sea_color_near, _overlay.proc_sea_color_near)
	var weather: SkyWeatherState = _weather()
	weather.storm_amount = 1.0
	weather.storm_overlay = _overlay
	weather.overcast_amount = OVERCAST_AMOUNT
	weather.overcast_exposure_scale = OVERCAST_EXPOSURE
	var out: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_weather(storm_frame, weather, out)
	assert_eq(out.puff_exposure, tick.puff_exposure, "baseline exposure, not the overcast-scaled one")
	assert_ne(out.exposure, out.puff_exposure, "fixture: the sky exposure itself is overcast-scaled")


func test_a_day_storm_puff_sea_follows_the_sky_sea() -> void:
	for phase: float in DAY_STORM_PHASES:
		var tick: SkyFrame = SkyEvaluator.evaluate_tick(_def, phase, SEED, 0, true)
		var storm_frame: SkyFrame = SkyFrame.new()
		SkyEvaluator.apply_storm(tick, STORM_AMOUNT, _overlay, CEILING.storm_flare_off_amount, storm_frame)
		assert_true(storm_frame.puff_sea_color_near.is_equal_approx(storm_frame.proc_sea_color_near), "near at %s" % phase)
		assert_true(storm_frame.puff_sea_color_far.is_equal_approx(storm_frame.proc_sea_color_far), "far at %s" % phase)


func test_a_storm_scales_the_current_light_energy_by_the_overlay_share() -> void:
	for phase: float in [0.25, 0.47, NIGHT_PHASE]:
		var tick: SkyFrame = SkyEvaluator.evaluate_tick(_def, phase, SEED, 0, true)
		var storm_frame: SkyFrame = SkyFrame.new()
		SkyEvaluator.apply_storm(tick, 1.0, _overlay, CEILING.storm_flare_off_amount, storm_frame)
		assert_almost_eq(storm_frame.light_energy, tick.light_energy * _overlay.light_energy_share, TOLERANCE, "full storm at %s" % phase)
		SkyEvaluator.apply_storm(tick, STORM_AMOUNT, _overlay, CEILING.storm_flare_off_amount, storm_frame)
		assert_almost_eq(storm_frame.light_energy, tick.light_energy * lerpf(1.0, _overlay.light_energy_share, STORM_AMOUNT),
			TOLERANCE, "half storm at %s" % phase)
	var night: SkyFrame = SkyEvaluator.evaluate_tick(_def, NIGHT_PHASE, SEED, 0, true)
	var night_storm: SkyFrame = SkyFrame.new()
	SkyEvaluator.apply_storm(night, 1.0, _overlay, CEILING.storm_flare_off_amount, night_storm)
	assert_lte(night_storm.light_energy, night.light_energy, "a night storm is never brighter than the night")
	var brightest: SkyFrame = SkyEvaluator.evaluate_tick(_def, BRIGHTEST_PHASE, SEED, 0, true)
	SkyEvaluator.apply_storm(brightest, 1.0, _overlay, CEILING.storm_flare_off_amount, night_storm)
	assert_almost_eq(night_storm.light_energy, OLD_STORM_LIGHT_ENERGY, 0.001, "the brightest hour's full storm equals the old fixed storm energy")
	_overlay.light_energy_share = 1.0
	SkyEvaluator.apply_storm(night, 1.0, _overlay, CEILING.storm_flare_off_amount, night_storm)
	assert_eq(night_storm.light_energy, night.light_energy, "share 1 leaves the light unchanged")


# --- SkyVariation.value_at ------------------------------------------------------------------

func test_value_at_is_bit_identical_to_the_base_formula() -> void:
	# The base (pre-value_at) formula, written out: clamp(lerp(min, max, clamp(weight))) per channel.
	var theme: SkyCycleDef = _def
	var ranges: Array[Array] = [
		[theme.variation_exposure_min, theme.variation_exposure_max, SkyVariation.CHANNEL_EXPOSURE],
		[theme.variation_sea_coverage_min, theme.variation_sea_coverage_max, SkyVariation.CHANNEL_SEA_COVERAGE],
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


func test_evaluator_variation_equals_value_at_over_the_cycle_ranges() -> void:
	var frame: SkyFrame = SkyFrame.new()
	for seed_value: int in VARIATION_SEEDS:
		for phase: float in [0.0, 0.13, 0.5, 0.77, 0.999]:
			SkyEvaluator.apply_variation(_def, phase, seed_value, frame)
			assert_eq(frame.exposure, SkyVariation.value_at(_def.variation_exposure_min, _def.variation_exposure_max,
				_def.variation_knots_per_cycle, phase, seed_value, SkyVariation.CHANNEL_EXPOSURE))
			assert_eq(frame.puff_exposure, frame.exposure)
			assert_eq(frame.proc_sea_coverage, SkyVariation.value_at(_def.variation_sea_coverage_min, _def.variation_sea_coverage_max,
				_def.variation_knots_per_cycle, phase, seed_value, SkyVariation.CHANNEL_SEA_COVERAGE))
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
	assert_eq(SkyEvaluator.window_weight(0.5, DEFAULT_WINDOW), 1.0, "mid-night is the sunset palette")
	for step: int in DUSK_WEIGHT_SWEEP.size():
		var phase: float = float(step) / 100.0
		assert_almost_eq(SkyEvaluator.window_weight(phase, DEFAULT_WINDOW), DUSK_WEIGHT_SWEEP[step], 0.000000000001, "phase %s" % phase)


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
		for channel: int in [SkyVariation.CHANNEL_EXPOSURE, SkyVariation.CHANNEL_SEA_COVERAGE]:
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
		assert_eq(frame_values(first), frame_values(second), "the whole tick frame repeats at %s" % phase)


func test_palette_variation_seed_for_uses_the_match_seed_and_a_default_for_random() -> void:
	assert_eq(SkyVariation.seed_for(1234), 1234)
	assert_eq(SkyVariation.seed_for(0), 0)
	assert_eq(SkyVariation.seed_for(-1), SkyVariation.DEFAULT_SEED)


func test_palette_variation_values_stay_inside_the_theme_ranges_whatever_the_seed() -> void:
	var def: SkyCycleDef = SkyCycleDef.new()
	var frame: SkyFrame = SkyFrame.new()
	for seed_value: int in VARIATION_SEEDS:
		for step: int in range(VARIATION_SWEEP_STEPS + 1):
			var phase: float = float(step) / float(VARIATION_SWEEP_STEPS)
			SkyEvaluator.apply_variation(def, phase, seed_value, frame)
			assert_between(frame.exposure, def.variation_exposure_min, def.variation_exposure_max)
			assert_between(frame.proc_sea_coverage, def.variation_sea_coverage_min, def.variation_sea_coverage_max)
	def.variation_exposure_min = 1.2
	def.variation_exposure_max = 1.2
	SkyEvaluator.apply_variation(def, 0.3, 5, frame)
	assert_eq(frame.exposure, 1.2, "a collapsed range is a fixed exposure")
