extends GutTest
## The typed sky cycle contract (config/sky/Sky*Def/Keyframe, core/sky/SkyFrame, SkyWeatherState):
## the locked phase of every sky id, the weather state defaults, requests and reset, and the frame
## copy. The shipped cycle's values are pinned through the golden parity test
## (test_sky_parity_live) and the dome and ambient-life data tests (test_sky_cycle_data).

const Evaluator := preload("res://tests/unit/sky/test_sky_evaluator.gd")
const LOCKED_PHASES_BY_ID: Dictionary[String, float] = {
	"sunset": 0.47, "dawn": 0.03, "night": 0.75, "": -1.0, "cycle": -1.0, "storm": -1.0,
}
const FRAME_PROBE_COLOR: Color = Color(0.25, 0.5, 0.75, 1.0)
const FRAME_PROBE_VECTOR: Vector3 = Vector3(0.1, 0.2, 0.3)
const FRAME_PROBE_FLOAT: float = 0.37
const FRAME_PROBE_INT: int = 7


func _script_vars(object: Object) -> Array[StringName]:
	var names: Array[StringName] = []
	for property: Dictionary in object.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			names.append(StringName(str(property["name"])))
	return names


func test_contract_class_names_load() -> void:
	assert_not_null(SkyCycleDef.new())
	assert_not_null(SkyKeyframe.new())
	assert_not_null(SkyNightKeyframe.new())
	assert_not_null(SkyOverlayDef.new())
	assert_not_null(SkyFrame.new())
	assert_not_null(SkyWeatherState.new())
	assert_not_null(SkyEvaluator.new())


func test_locked_phase_for_every_id() -> void:
	var def: SkyCycleDef = SkyTestKit.cycle()
	for sky_id: String in LOCKED_PHASES_BY_ID:
		assert_almost_eq(def.locked_phase_for(sky_id), LOCKED_PHASES_BY_ID[sky_id], 0.00001, sky_id)
	assert_eq(def.locked_phase_for(""), -1.0)


func test_weather_state_defaults_are_inactive() -> void:
	var state: SkyWeatherState = SkyWeatherState.new()
	assert_false(state.any_active())
	assert_eq(state.cloud_overcast_amount(), 0.0)
	assert_eq(state.sun_cloud_scale, 1.0)


func test_weather_state_any_active_per_request() -> void:
	var state: SkyWeatherState = SkyWeatherState.new()
	for field: StringName in [&"storm_amount", &"overcast_amount", &"weather_cloud_overcast",
			&"snow_brighten", &"wfog_amount"]:
		state.clear()
		state.set(field, 0.4)
		assert_true(state.any_active(), "%s makes the weather active" % field)
	state.clear()
	state.sun_cloud_scale = 0.5
	assert_false(state.any_active(), "the sun-cloud scale alone is not a weather request")


func test_weather_state_cloud_overcast_is_the_strongest_source() -> void:
	var state: SkyWeatherState = SkyWeatherState.new()
	state.overcast_amount = 0.3
	state.weather_cloud_overcast = 0.6
	assert_almost_eq(state.cloud_overcast_amount(), 0.6, 0.00001)
	state.overcast_amount = 0.8
	assert_almost_eq(state.cloud_overcast_amount(), 0.8, 0.00001)


func test_weather_state_clear_restores_identity() -> void:
	var state: SkyWeatherState = SkyWeatherState.new()
	var fresh: SkyWeatherState = SkyWeatherState.new()
	state.storm_amount = 0.5
	state.storm_overlay = SkyOverlayDef.new()
	state.overcast_amount = 0.5
	state.overcast_light_scale = 0.4
	state.overcast_ambient_scale = 0.3
	state.overcast_exposure_scale = 0.2
	state.overcast_fog_tint = Color.RED
	state.overcast_fog_tint_strength = 0.9
	state.weather_cloud_overcast = 0.7
	state.snow_brighten = 0.6
	state.wfog_amount = 0.5
	state.wfog_max_opacity = 0.8
	state.wfog_depth_begin_m = 12.0
	state.wfog_depth_end_m = 90.0
	state.wfog_tint = Color.BLUE
	state.wfog_tint_strength = 0.5
	state.wfog_sky_affect_add = 0.3
	state.sun_cloud_scale = 0.5
	state.clear()
	for field: StringName in _script_vars(fresh):
		assert_eq(state.get(field), fresh.get(field), "clear() resets %s" % field)
	assert_false(state.any_active())


func test_frame_copy_from_round_trips_every_field() -> void:
	var source: SkyFrame = SkyFrame.new()
	var fields: Array[StringName] = _script_vars(source)
	assert_gt(fields.size(), 100)
	for field: StringName in fields:
		var current: Variant = source.get(field)
		if current is Color:
			source.set(field, FRAME_PROBE_COLOR)
		elif current is Vector3:
			source.set(field, FRAME_PROBE_VECTOR)
		elif current is bool:
			source.set(field, not (current as bool))
		elif current is int:
			source.set(field, FRAME_PROBE_INT)
		elif current is float:
			source.set(field, FRAME_PROBE_FLOAT)
	var copy: SkyFrame = SkyFrame.new()
	copy.copy_from(source)
	for field: StringName in fields:
		assert_ne(copy.get(field), SkyFrame.new().get(field), "%s was probed away from its default" % field)
		assert_eq(copy.get(field), source.get(field), "copy_from copies %s" % field)
	assert_eq(Evaluator.frame_values(copy), Evaluator.frame_values(source))
