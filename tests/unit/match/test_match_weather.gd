extends GutTest
## Weather framework: host schedule, effect apply/restore and match lifecycle.

const DELTA: float = 0.25

var _log: Array = []
var _active_now: int = 0
var _max_active: int = 0
var _world: Dictionary = {}
var _effects: Array[WeatherProbeEffect] = []
var _clock: float = 0.0


func before_each() -> void:
	_log.clear()
	_active_now = 0
	_max_active = 0
	_world = {"friction": 0.8}
	_effects.clear()
	_clock = 0.0
	Events.weather_started.connect(_on_started)
	Events.weather_stopped.connect(_on_stopped)


func after_each() -> void:
	Events.weather_started.disconnect(_on_started)
	Events.weather_stopped.disconnect(_on_stopped)
	Match.abort_match()
	Match.weather().set_effect_factory(Callable())
	Match.weather().set_defs(WeatherTuning.load_all())
	Match.weather().set_schedule_tuning(load("res://config/weather/weather_schedule.tres") as WeatherScheduleTuning)
	Match.weather().set_host_override(null)
	Match.set_process(true)


func _on_started(weather_id: StringName) -> void:
	_active_now += 1
	_max_active = maxi(_max_active, _active_now)
	_log.append([snappedf(_clock, 0.01), "start", weather_id])


func _on_stopped(weather_id: StringName) -> void:
	_active_now -= 1
	_log.append([snappedf(_clock, 0.01), "stop", weather_id])


func _def(id: StringName, hold: float = 10.0) -> WeatherTuning:
	var def: WeatherTuning = WeatherTuning.new()
	def.id = id
	def.display_name = String(id)
	def.ramp_in_s = 2.0
	def.ramp_out_s = 2.0
	def.hold_min_s = hold
	def.hold_max_s = hold
	return def


func _schedule(first: float = 5.0, gap_min: float = 10.0, gap_max: float = 20.0) -> WeatherScheduleTuning:
	var s: WeatherScheduleTuning = WeatherScheduleTuning.new()
	s.first_delay_s = first
	s.constant_start_delay_s = first
	s.gap_min_s = gap_min
	s.gap_max_s = gap_max
	return s


func _make(defs: Array[WeatherTuning], schedule: WeatherScheduleTuning, host: bool = true) -> MatchWeather:
	var w: MatchWeather = MatchWeather.new()
	w.set_defs(defs)
	w.set_schedule_tuning(schedule)
	w.set_host_override(host)
	return w


func _cfg(mode: int, seed_value: int = 7) -> MatchConfig:
	var c: MatchConfig = MatchConfig.new()
	c.weather_mode = mode as MatchConfig.WeatherMode
	c.rng_seed = seed_value
	return c


func _run(w: MatchWeather, seconds: float) -> void:
	var steps: int = int(round(seconds / DELTA))
	for _i: int in range(steps):
		_clock += DELTA
		w.tick(DELTA)


func _abc() -> Array[WeatherTuning]:
	return [_def(&"storm"), _def(&"rain"), _def(&"snow")]


# --- Config ---------------------------------------------------------------------

func test_ramp_curve() -> void:
	var def: WeatherTuning = _def(&"storm")
	def.intensity = 0.8
	assert_almost_eq(def.intensity_at(WeatherTuning.Phase.RAMP_IN, 0.0), 0.0, 0.0001)
	assert_almost_eq(def.intensity_at(WeatherTuning.Phase.RAMP_IN, 1.0), 0.4, 0.0001)
	assert_almost_eq(def.intensity_at(WeatherTuning.Phase.HOLD, 5.0), 0.8, 0.0001)
	assert_almost_eq(def.intensity_at(WeatherTuning.Phase.RAMP_OUT, 1.0), 0.4, 0.0001)
	assert_almost_eq(def.intensity_at(WeatherTuning.Phase.RAMP_OUT, 9.0), 0.0, 0.0001)


# --- Schedule --------------------------------------------------------------------

func test_off_never_runs_a_schedule() -> void:
	var w: MatchWeather = _make(_abc(), _schedule())
	w.begin_match(_cfg(MatchConfig.WeatherMode.OFF))
	assert_false(w.is_running())
	_run(w, 600.0)
	assert_eq(_log.size(), 0)


func test_changing_mode_repeats_events_one_at_a_time_with_calm_between() -> void:
	var w: MatchWeather = _make(_abc(), _schedule())
	w.begin_match(_cfg(MatchConfig.WeatherMode.CHANGING))
	assert_eq(w.schedule_phase(), MatchWeather.Sched.CALM)
	_run(w, 4.5)
	assert_eq(_log.size(), 0, "calm through the initial delay")
	_run(w, 1.0)
	assert_ne(w.active_id(), &"")
	assert_eq(w.schedule_phase(), MatchWeather.Sched.EVENT)
	_run(w, 200.0)
	var starts: int = 0
	for entry: Array in _log:
		if entry[1] == "start":
			starts += 1
	assert_gt(starts, 1, "events repeat on the schedule")
	assert_lte(_max_active, 1, "never two weathers at once")


func test_type_mode_is_constant_after_the_start_delay_with_no_calm_gaps() -> void:
	var sched: WeatherScheduleTuning = _schedule()
	sched.constant_start_delay_s = 3.0
	var w: MatchWeather = _make(_abc(), sched)
	w.begin_match(_cfg(MatchConfig.WeatherMode.RAIN))
	assert_true(w.is_constant())
	_run(w, 2.5)
	assert_eq(_log.size(), 0, "calm through the short start delay")
	_run(w, 1.0)
	assert_eq(w.active_id(), &"rain")
	_run(w, 3.0)
	assert_almost_eq(w.active_intensity(), 1.0, 0.001, "ramped in")
	_run(w, 900.0)
	assert_eq(w.active_id(), &"rain", "still raining, never ramps out")
	assert_almost_eq(w.active_intensity(), 1.0, 0.001)
	assert_eq(_log.size(), 1, "one start, no stop")
	assert_eq(w.state_dict()["left"], 0.0)


# --- F4 debug override -------------------------------------------------------------

func _sequence(mode: int, seed_value: int, seconds: float) -> Array:
	var w: MatchWeather = _make(_abc(), _schedule(), true)
	_log.clear()
	_clock = 0.0
	w.begin_match(_cfg(mode, seed_value))
	_run(w, seconds)
	var out: Array = _log.duplicate(true)
	w.reset()
	return out


func test_schedule_is_deterministic_for_a_seed_and_differs_across_seeds() -> void:
	var a: Array = _sequence(MatchConfig.WeatherMode.CHANGING, 1234, 1500.0)
	var b: Array = _sequence(MatchConfig.WeatherMode.CHANGING, 1234, 1500.0)
	var c: Array = _sequence(MatchConfig.WeatherMode.CHANGING, 999, 1500.0)
	assert_gt(a.size(), 6)
	assert_eq(a, b)
	assert_ne(a, c)


# --- Effect hook -------------------------------------------------------------------

func _probe_factory(_def_arg: WeatherTuning) -> WeatherEffect:
	var effect: WeatherProbeEffect = WeatherProbeEffect.new(_world)
	_effects.append(effect)
	return effect


func test_effect_scales_with_intensity_and_restores_baseline_when_the_event_ends() -> void:
	var w: MatchWeather = _make([_def(&"rain", 6.0)], _schedule(1.0))
	w.set_effect_factory(_probe_factory)
	w.begin_match(_cfg(MatchConfig.WeatherMode.CHANGING))
	_run(w, 5.0)
	assert_eq(_effects.size(), 1)
	assert_almost_eq(float(_world["friction"]), 0.4, 0.001, "full intensity halves friction")
	assert_gt(_effects[0].tick_calls, 0)
	_run(w, 12.0)
	assert_eq(w.active_id(), &"")
	assert_eq(_effects[0].restore_calls, 1)
	assert_eq(float(_world["friction"]), 0.8, "baseline restored exactly")


func test_a_client_never_starts_events_or_runs_effects() -> void:
	var w: MatchWeather = _make(_abc(), _schedule(), false)
	w.set_effect_factory(_probe_factory)
	assert_false(w.start_event(&"snow"))
	w.begin_match(_cfg(MatchConfig.WeatherMode.RAIN))
	w.tick(1000.0)
	assert_eq(_effects.size(), 0)


# --- Match lifecycle ------------------------------------------------------------------
