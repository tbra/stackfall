extends GutTest
## SkyEvaluator.evaluate over the shipped cycle (config/sky/sky_cycle.tres) reproduces the
## golden fixture's locked-phase (group L) values: every sky-material uniform the frame carries
## under the same name, plus the Environment fog/ambient and the key light colour and energy.
## The golden was captured from the old facade, so this pins the evaluator before and after the
## facade switch. Weather-owned groups are covered by test_sky_parity_live.

const Evaluator := preload("res://tests/unit/sky/test_sky_evaluator.gd")
const LOCKED_PHASES: Array[float] = [0.03, 0.10, 0.25, 0.38, 0.47, 0.52, 0.62, 0.75, 0.95]
## Sky uniforms the frame carries under a different meaning (the sky channel holds the day palette
## and the writers add constants), so they are compared by the parity test instead.
const SKIPPED_SKY_KEYS: Array[String] = ["sun_direction"]
const ENV_TO_FRAME: Dictionary = {
	"fog_light_color": "fog_light_color", "fog_density": "fog_density",
	"ambient_light_energy": "ambient_light_energy", "volumetric_fog_density": "volumetric_fog_density",
	"volumetric_fog_albedo": "volumetric_fog_albedo",
}


func _close(want: Variant, got: Variant) -> bool:
	if want is Array and got is Array:
		var a: Array = want as Array
		var b: Array = got as Array
		if a.size() != b.size():
			return false
		for i: int in a.size():
			if not _close(a[i], b[i]):
				return false
		return true
	if (want is float or want is int) and (got is float or got is int):
		return is_equal_approx(float(want), float(got))
	return want == got


func _enc(value: Variant) -> Variant:
	if value is Color:
		var c: Color = value as Color
		return [c.r, c.g, c.b, c.a]
	if value is Vector3:
		var v: Vector3 = value as Vector3
		return [v.x, v.y, v.z]
	return value


func test_locked_phase_frames_match_the_golden() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/unit/sky/fixtures/sky_cycle_golden.json"))
	var golden: Dictionary = (parsed as Dictionary).get("states", {}) as Dictionary
	var def: SkyCycleDef = load("res://config/sky/sky_cycle.tres") as SkyCycleDef
	var weather: SkyWeatherState = SkyWeatherState.new()
	weather.tuning = load("res://config/weather/ceiling.tres") as WeatherCeilingTuning
	var compared: int = 0
	for phase: float in LOCKED_PHASES:
		var state: Dictionary = golden.get("L_%.2f" % phase, {}) as Dictionary
		assert_false(state.is_empty(), "golden has L_%.2f" % phase)
		var frame: SkyFrame = SkyEvaluator.evaluate(def, phase, SkyVariation.DEFAULT_SEED, 0, weather, true)
		var values: Dictionary = Evaluator.frame_values(frame)
		var sky: Dictionary = state.get("sky", {}) as Dictionary
		for key: String in sky.keys():
			if SKIPPED_SKY_KEYS.has(key) or not values.has(StringName(key)):
				continue
			assert_true(_close(sky[key], _enc(values[StringName(key)])), "phase %.2f sky.%s: want %s got %s" % [phase, key, sky[key], _enc(values[StringName(key)])])
			compared += 1
		var env: Dictionary = state.get("env", {}) as Dictionary
		for key: String in ENV_TO_FRAME.keys():
			var want: Variant = env.get(key)
			var got: Variant = _enc(values[StringName(ENV_TO_FRAME[key] as String)])
			assert_true(_close(want, got), "phase %.2f env.%s: want %s got %s" % [phase, key, want, got])
			compared += 1
		var light: Dictionary = state.get("light", {}) as Dictionary
		assert_true(_close(light["energy"], frame.light_energy), "phase %.2f light energy" % phase)
		assert_true(_close(light["color"], _enc(frame.light_color)), "phase %.2f light colour" % phase)
	assert_gt(compared, 300, "the comparison covered the sky channel")
