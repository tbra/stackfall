extends GutTest
## game/ambient/AmbientLife.gd: it subscribes to the sky's Events and swaps the day/night set with
## hysteresis thresholds read from the SkyCycleDef.

const SUNSET_PATH: String = "res://config/sky/themes/sunset.tres"
const NIGHT_PATH: String = "res://config/sky/themes/night.tres"
const DISC_RADIUS_M: float = 30.0
const MIX_FULL_NIGHT: float = 1.0
const SWEEP_STEPS: int = 400
const SWEEP_SEED: int = 7
## The sweep opens at midday (day) so it crosses dusk, the night and dawn once each.
const SWEEP_START_PHASE: float = 0.25


func _def() -> SkyCycleDef:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var night: SkyThemeDef = load(NIGHT_PATH) as SkyThemeDef
	return SkyThemeMigration.cycle_from_themes(sunset, sunset, night)


func _built() -> AmbientLife:
	var life: AmbientLife = AmbientLife.build(null, null)
	add_child_autofree(life)
	return life


func _configure_by_signal(def: SkyCycleDef) -> void:
	Events.sky_ambient_configured.emit(def, null, DISC_RADIUS_M)


func test_build_creates_the_three_named_children() -> void:
	var life: AmbientLife = _built()
	assert_true(life.get_node_or_null("DistantBirds") is DistantBirds)
	assert_true(life.get_node_or_null("PerchingBirds") is PerchingBirds)
	assert_true(life.get_node_or_null("Fireflies") is Fireflies)


func test_swap_uses_hysteresis_thresholds_from_the_def() -> void:
	var life: AmbientLife = _built()
	var def: SkyCycleDef = _def()
	_configure_by_signal(def)
	assert_false(life._is_night)
	Events.sky_time_of_day_changed.emit(0.0, def.life_night_on_mix - 0.01)
	assert_false(life._is_night, "below the on threshold stays day")
	Events.sky_time_of_day_changed.emit(0.0, def.life_night_on_mix + 0.01)
	assert_true(life._is_night)
	Events.sky_time_of_day_changed.emit(0.0, def.life_night_off_mix + 0.01)
	assert_true(life._is_night, "between the thresholds keeps night")
	Events.sky_time_of_day_changed.emit(0.0, def.life_night_off_mix - 0.01)
	assert_false(life._is_night)


func test_time_before_the_first_configure_is_ignored() -> void:
	var life: AmbientLife = _built()
	Events.sky_time_of_day_changed.emit(0.75, MIX_FULL_NIGHT)
	assert_false(life._is_night)


func test_birds_hide_at_night_and_configure_resets_to_day() -> void:
	var life: AmbientLife = _built()
	var birds: DistantBirds = life.get_node("DistantBirds") as DistantBirds
	var def: SkyCycleDef = _def()
	_configure_by_signal(def)
	assert_true(birds.visible)
	Events.sky_time_of_day_changed.emit(0.75, MIX_FULL_NIGHT)
	assert_false(birds.visible, "no distant birds at night")
	_configure_by_signal(def)
	assert_false(life._is_night, "configure restarts from the day set")
	assert_true(birds.visible)


func test_phase_sweep_swaps_exactly_once_at_dusk_and_once_at_dawn() -> void:
	var life: AmbientLife = _built()
	var def: SkyCycleDef = _def()
	_configure_by_signal(def)
	var clear: SkyWeatherState = SkyWeatherState.new()
	var swaps: Array[bool] = []
	var was_night: bool = false
	for step: int in range(SWEEP_STEPS + 1):
		var phase: float = fposmod(SWEEP_START_PHASE + float(step) / float(SWEEP_STEPS), 1.0)
		var frame: SkyFrame = SkyEvaluator.evaluate(def, phase, SkyVariation.seed_for(SWEEP_SEED), 0, clear, true)
		Events.sky_time_of_day_changed.emit(phase, frame.night)
		if life._is_night != was_night:
			was_night = life._is_night
			swaps.append(was_night)
	assert_eq(swaps, [true, false] as Array[bool], "one swap into night then one back to day")
