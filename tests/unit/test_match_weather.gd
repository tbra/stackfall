extends GutTest
## Weather framework (Bontago-22y.10; owner decision Bontago-22y.14): config,
## registry, the host schedule, effect apply/restore and match lifecycle.
## MatchWeather is driven standalone (host override) for the schedule, and
## through the real Match for the lifecycle. The wire is in
## test_match_weather_net.gd.

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
	Match.weather().set_schedule_tuning(load("res://config/weather_schedule.tres") as WeatherScheduleTuning)
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

func test_weather_defaults_to_changing_everywhere() -> void:
	# DECISION (470.1): Changing (calm most of the time) is the default everywhere; the three
	# sources of a default must agree with the class default, whichever mode that is.
	var class_default: int = MatchConfig.new().weather_mode
	assert_eq(class_default, MatchConfig.WeatherMode.CHANGING, "Changing is the shipped default (470.1)")
	assert_eq((load("res://config/match_defaults.tres") as MatchConfig).weather_mode, class_default, "the shipped config resource does not override it")
	assert_eq(MatchConfig.from_dict({}).weather_mode, class_default, "a missing key means the default")


func test_weather_mode_round_trips_and_sanitize_clamps() -> void:
	var c: MatchConfig = MatchConfig.new()
	c.weather_mode = MatchConfig.WeatherMode.CHANGING
	assert_eq(MatchConfig.from_dict(c.to_dict()).weather_mode, MatchConfig.WeatherMode.CHANGING)
	var hostile: MatchConfig = MatchConfig.from_dict({"weather_mode": 99})
	hostile.sanitize()
	assert_eq(hostile.weather_mode, MatchConfig.WeatherMode.CHANGING)
	var negative: MatchConfig = MatchConfig.from_dict({"weather_mode": -4})
	negative.sanitize()
	assert_eq(negative.weather_mode, MatchConfig.WeatherMode.OFF)


func test_registry_loads_storm_rain_snow_with_sane_tunables() -> void:
	var defs: Array[WeatherTuning] = WeatherTuning.load_all()
	var ids: Array[String] = []
	assert_gt(defs.size(), 0)
	for def: WeatherTuning in defs:
		ids.append(String(def.id))
		assert_between(def.intensity, 0.0, 1.0)
		assert_gt(def.ramp_in_s, 0.0)
		assert_gt(def.ramp_out_s, 0.0)
		assert_lte(def.hold_min_s, def.hold_max_s)
		assert_true(load(def.presentation_scene) is PackedScene, "%s presentation scene loads" % def.id)
	var sorted_ids: Array[String] = ids.duplicate()
	sorted_ids.sort()
	assert_eq(ids, sorted_ids, "sorted by id")
	var unique: Dictionary = {}
	for id: String in ids:
		unique[id] = true
	assert_eq(unique.size(), ids.size(), "no duplicate ids")
	for mode: int in [MatchConfig.WeatherMode.STORM, MatchConfig.WeatherMode.RAIN, MatchConfig.WeatherMode.SNOW]:
		assert_true(ids.has(String(MatchWeather.id_for_mode(mode))))


func test_schedule_tuning_resource_is_sane() -> void:
	var s: WeatherScheduleTuning = load("res://config/weather_schedule.tres") as WeatherScheduleTuning
	assert_gt(s.first_delay_s, 0.0)
	assert_lte(s.gap_min_s, s.gap_max_s)


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
	assert_eq(w.event_phase(), WeatherTuning.Phase.HOLD)
	assert_almost_eq(w.active_intensity(), 1.0, 0.001)
	assert_eq(_log.size(), 1, "one start, no stop")
	assert_eq(w.state_dict()["left"], 0.0)


func test_random_mode_draws_one_type_then_holds_it_constantly() -> void:
	var sched: WeatherScheduleTuning = _schedule()
	sched.constant_start_delay_s = 1.0
	for seed_value: int in [1, 2, 3, 4, 5]:
		var w: MatchWeather = _make(_abc(), sched)
		_log.clear()
		w.begin_match(_cfg(MatchConfig.WeatherMode.RANDOM, seed_value))
		_run(w, 400.0)
		assert_eq(_log.size(), 1, "seed %d: one weather for the whole match" % seed_value)
		assert_eq(w.event_phase(), WeatherTuning.Phase.HOLD)
		w.reset()


func test_id_for_mode_and_labels_derive_from_the_enum() -> void:
	assert_eq(MatchWeather.id_for_mode(MatchConfig.WeatherMode.STORM), &"storm")
	assert_eq(MatchWeather.id_for_mode(MatchConfig.WeatherMode.SNOW), &"snow")
	assert_eq(MatchWeather.id_for_mode(MatchConfig.WeatherMode.OFF), &"")
	assert_eq(MatchWeather.id_for_mode(MatchConfig.WeatherMode.RANDOM), &"")
	assert_eq(MatchWeather.id_for_mode(MatchConfig.WeatherMode.CHANGING), &"")
	assert_eq(MatchWeather.id_for_mode(99), &"")
	assert_eq(MatchWeather.mode_labels().size(), MatchConfig.WeatherMode.size())
	assert_eq(MatchWeather.mode_labels()[MatchConfig.WeatherMode.STORM], "Storm")
	for mode: int in range(MatchConfig.WeatherMode.RANDOM):
		if MatchWeather.is_type_mode(mode):
			var ids: Array[StringName] = []
			for def: WeatherTuning in WeatherTuning.load_all():
				ids.append(def.id)
			assert_true(ids.has(MatchWeather.id_for_mode(mode)), "every type mode has a config/weather resource")


# --- F4 debug override -------------------------------------------------------------

func test_debug_override_forces_a_type_swaps_cleanly_and_releases_to_the_schedule() -> void:
	var w: MatchWeather = _make(_abc(), _schedule(5.0))
	w.set_effect_factory(_probe_factory)
	w.begin_match(_cfg(MatchConfig.WeatherMode.CHANGING))
	assert_true(w.set_debug_override(&"rain"))
	assert_eq(w.active_id(), &"rain")
	assert_true(w.is_constant())
	_run(w, 200.0)
	assert_eq(w.active_id(), &"rain", "held constantly, schedule paused")
	assert_true(w.set_debug_override(&"snow"))
	assert_eq(w.active_id(), &"snow")
	assert_eq(_effects.size(), 2)
	assert_almost_eq(float(_world["friction"]), 0.8 * (1.0 - WeatherProbeEffect.FRICTION_DROP_AT_FULL * w.active_intensity()), 0.05)
	assert_true(_effects[0].restore_calls > 0, "the previous weather's physics were restored")
	assert_true(w.set_debug_override(MatchWeather.DEBUG_OFF))
	assert_eq(w.active_id(), &"")
	assert_gt(_effects[1].restore_calls, 0)
	_run(w, 300.0)
	assert_eq(w.active_id(), &"", "off stays off")
	assert_false(w.set_debug_override(&"nope"), "unknown id refused")
	assert_true(w.set_debug_override(&""))
	assert_eq(w.debug_override(), &"")
	assert_eq(w.schedule_phase(), MatchWeather.Sched.CALM)
	_run(w, 5.5)
	assert_ne(w.active_id(), &"", "lobby schedule resumed")


func test_debug_override_on_a_client_is_refused_and_from_off_returns_to_off() -> void:
	var client: MatchWeather = _make(_abc(), _schedule(), false)
	assert_false(client.set_debug_override(&"rain"))
	var w: MatchWeather = _make(_abc(), _schedule())
	assert_true(w.set_debug_override(&"storm"))
	assert_true(w.is_running())
	assert_eq(w.active_id(), &"storm")
	assert_true(w.set_debug_override(&""))
	assert_eq(w.active_id(), &"")
	assert_false(w.is_running(), "an override that started the run stops it when released")
	assert_eq(w.schedule_phase(), MatchWeather.Sched.OFF)


func test_event_ramps_up_holds_ramps_down_then_gap_in_range() -> void:
	var w: MatchWeather = _make([_def(&"storm", 10.0)], _schedule(1.0, 10.0, 20.0))
	w.begin_match(_cfg(MatchConfig.WeatherMode.CHANGING))
	_run(w, 1.25)
	assert_eq(w.active_id(), &"storm")
	var previous: float = -1.0
	for _i: int in range(int(2.0 / DELTA)):
		_run(w, DELTA)
		assert_gte(w.active_intensity(), previous, "ramp-in never falls")
		previous = w.active_intensity()
	_run(w, 0.5)
	assert_almost_eq(w.active_intensity(), 1.0, 0.001)
	assert_eq(w.event_phase(), WeatherTuning.Phase.HOLD)
	_run(w, 10.0)
	assert_eq(w.event_phase(), WeatherTuning.Phase.RAMP_OUT)
	_run(w, 2.5)
	assert_eq(w.active_id(), &"", "event over")
	assert_eq(w.schedule_phase(), MatchWeather.Sched.CALM)
	assert_between(w.next_event_in(), 8.0, 20.0)
	var stop_time: float = _clock
	var second_start: float = -1.0
	for _i: int in range(int(40.0 / DELTA)):
		_run(w, DELTA)
		if w.active_id() != &"":
			second_start = _clock
			break
	assert_between(second_start - stop_time, 9.0, 21.0, "calm gap within tuned range")


func test_next_event_cue_counts_down_while_calm_and_is_off_during_an_event() -> void:
	var w: MatchWeather = _make(_abc(), _schedule(5.0))
	w.begin_match(_cfg(MatchConfig.WeatherMode.CHANGING))
	assert_almost_eq(w.next_event_in(), 5.0, 0.01)
	_run(w, 2.0)
	assert_almost_eq(w.next_event_in(), 3.0, 0.01)
	_run(w, 3.5)
	assert_eq(w.next_event_in(), -1.0)


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


func test_random_mode_fixes_one_type_per_match_but_varies_by_seed() -> void:
	var seen_across: Dictionary = {}
	for seed_value: int in range(12):
		var seq: Array = _sequence(MatchConfig.WeatherMode.RANDOM, seed_value, 900.0)
		var types: Dictionary = {}
		for entry: Array in seq:
			if entry[1] == "start":
				types[entry[2]] = true
		assert_eq(types.size(), 1, "seed %d: RANDOM uses one type for every event" % seed_value)
		for id: Variant in types.keys():
			seen_across[id] = true
	assert_gt(seen_across.size(), 1, "different seeds draw different types")


func test_changing_mode_never_repeats_the_previous_type_and_uses_several() -> void:
	var seq: Array = _sequence(MatchConfig.WeatherMode.CHANGING, 55, 4000.0)
	var starts: Array[StringName] = []
	for entry: Array in seq:
		if entry[1] == "start":
			starts.append(entry[2])
	assert_gt(starts.size(), 15)
	var kinds: Dictionary = {}
	for i: int in range(starts.size()):
		kinds[starts[i]] = true
		if i > 0:
			assert_ne(starts[i], starts[i - 1], "no back-to-back repeats")
	assert_eq(kinds.size(), 3)


func test_shipped_schedule_is_calm_most_of_the_time() -> void:
	var w: MatchWeather = _make(WeatherTuning.load_all(), load("res://config/weather_schedule.tres") as WeatherScheduleTuning)
	w.begin_match(_cfg(MatchConfig.WeatherMode.CHANGING, 21))
	var calm: int = 0
	var total: int = int(3600.0 / DELTA)
	for _i: int in range(total):
		_clock += DELTA
		w.tick(DELTA)
		if w.active_id() == &"":
			calm += 1
	assert_gt(float(calm) / float(total), 0.5, "weather is an event, not the norm")
	assert_lt(calm, total, "but events do happen in an hour")


func test_a_missing_fixed_type_stays_calm_without_error() -> void:
	var w: MatchWeather = _make([_def(&"rain")], _schedule())
	w.begin_match(_cfg(MatchConfig.WeatherMode.STORM))
	_run(w, 200.0)
	assert_eq(_log.size(), 0)


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


func test_reset_mid_event_restores_baseline_and_emits_stopped() -> void:
	var w: MatchWeather = _make([_def(&"rain", 60.0)], _schedule(1.0))
	w.set_effect_factory(_probe_factory)
	w.begin_match(_cfg(MatchConfig.WeatherMode.RAIN))
	_run(w, 10.0)
	assert_ne(float(_world["friction"]), 0.8)
	w.reset()
	assert_eq(float(_world["friction"]), 0.8)
	assert_eq(_active_now, 0)
	assert_false(w.is_running())
	w.reset()
	assert_eq(_effects[0].restore_calls, 1, "reset is idempotent")


func test_forced_event_and_early_end_use_the_ramp_out() -> void:
	var w: MatchWeather = _make(_abc(), _schedule())
	assert_true(w.start_event(&"snow"))
	assert_false(w.start_event(&"hail"), "unknown id refused")
	_run(w, 3.0)
	assert_eq(w.active_id(), &"snow")
	w.end_event()
	assert_eq(w.event_phase(), WeatherTuning.Phase.RAMP_OUT)
	_run(w, 2.5)
	assert_eq(w.active_id(), &"")


func test_a_client_never_starts_events_or_runs_effects() -> void:
	var w: MatchWeather = _make(_abc(), _schedule(), false)
	w.set_effect_factory(_probe_factory)
	assert_false(w.start_event(&"snow"))
	w.begin_match(_cfg(MatchConfig.WeatherMode.RAIN))
	w.tick(1000.0)
	assert_eq(_effects.size(), 0)


# --- Match lifecycle ------------------------------------------------------------------

func _start_real_match(mode: int) -> void:
	Match.set_process(false)
	var config: MatchConfig = MatchConfig.new()
	config.hot_seat = false
	config.player_count = 2
	config.rng_seed = 31
	config.weather_mode = mode as MatchConfig.WeatherMode
	Match.weather().set_defs([_def(&"rain", 30.0)])
	Match.weather().set_schedule_tuning(_schedule(1.0, 5.0, 5.0))
	Match.weather().set_effect_factory(_probe_factory)
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.PLAYING)


func _drive_into_event() -> void:
	for _i: int in range(int(6.0 / DELTA)):
		_clock += DELTA
		Match.weather().tick(DELTA)


func test_weather_starts_with_playing_and_restores_on_abort() -> void:
	_start_real_match(MatchConfig.WeatherMode.RAIN)
	assert_true(Match.weather().is_running())
	_drive_into_event()
	assert_eq(Match.weather().active_id(), &"rain")
	assert_ne(float(_world["friction"]), 0.8)
	Match.abort_match()
	assert_false(Match.weather().is_running())
	assert_eq(Match.weather().active_id(), &"")
	assert_eq(float(_world["friction"]), 0.8, "abort returns physics to baseline")
	assert_eq(_active_now, 0)


func test_weather_restores_when_the_match_ends() -> void:
	_start_real_match(MatchConfig.WeatherMode.RAIN)
	_drive_into_event()
	assert_ne(float(_world["friction"]), 0.8)
	Match._finish_match(0)
	assert_eq(Match.state(), Match.State.END)
	assert_false(Match.weather().is_running())
	assert_eq(float(_world["friction"]), 0.8)


func test_restarting_a_match_restores_then_starts_a_fresh_schedule() -> void:
	_start_real_match(MatchConfig.WeatherMode.RAIN)
	_drive_into_event()
	var config: MatchConfig = Match.config.duplicate(true) as MatchConfig
	Match.start_match(config)
	assert_eq(float(_world["friction"]), 0.8)
	assert_false(Match.weather().is_running(), "no weather during loading/countdown")
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_true(Match.weather().is_running())
	assert_eq(Match.weather().schedule_phase(), MatchWeather.Sched.CALM)


func test_off_mode_match_has_no_weather() -> void:
	_start_real_match(MatchConfig.WeatherMode.OFF)
	assert_false(Match.weather().is_running())
	_drive_into_event()
	assert_eq(_effects.size(), 0)
