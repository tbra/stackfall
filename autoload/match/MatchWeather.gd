class_name MatchWeather
extends RefCounted
## Weather as a random host-scheduled EVENT (Bontago-22y.10; owner decision
## Bontago-22y.14: at most one weather at a time, calm most of the time).
##
## Timeline per match, all decided by the host from one seed:
##   calm (WeatherScheduleTuning.first_delay_s)
##   -> event: ramp-in, hold (per-weather range), ramp-out
##   -> calm gap (WeatherScheduleTuning gap range) -> event -> ...
##
## Authority: the host runs the schedule and the WeatherEffect physics hook;
## a client runs no schedule and no effect. It receives the host's state
## (net/WeatherNet.gd) and only advances presentation intensity from it, using
## the same WeatherTuning ramp curve, so the host sends state per phase change
## rather than per frame.
##
## DECISION (autoload/match/MatchWeather.gd): lobby mapping, per the owner
## decision above, revised by owner decision 470.1: a TYPE mode (STORM/RAIN/
## SNOW/...) is CONSTANT weather: after WeatherScheduleTuning.constant_start_delay_s
## the type ramps in, holds at full intensity for the whole match and never
## ramps out. RANDOM = one type drawn at match start, then constant. CHANGING =
## the random-event schedule above, each event drawing its type (avoiding the
## previous when avoid_repeat_type and another type exists). OFF = none.
##
## DECISION: the F4 debug override (set_debug_override) pauses the schedule and
## forces one type constantly (or none) on the host; clients follow through
## normal replication. Clearing it restarts the mode's own schedule.
##
## DECISION: lifecycle is tied to Events.match_state_changed rather than a
## hook in MatchLifecycle, so no lifecycle file needed editing: PLAYING starts
## the schedule (host), LOADING/LOBBY/END stop it and restore physics. Every
## teardown path (win, abort_match, restart, host leaving to the menu) passes
## through one of those transitions.

enum Sched { OFF, CALM, EVENT }

## set_debug_override() value meaning "no weather at all".
const DEBUG_OFF: StringName = &"off"

## Mixed into the match seed so Breeze's stream differs from the schedule's.
const BREEZE_SEED_SALT: int = 0x5B1EE2E

## Wire format version of state_dict(). Architecture, not a tunable.
const WIRE_VERSION: int = 1
const WIRE_KEYS: PackedStringArray = ["v", "epoch", "seed", "mode", "sched", "left", "id", "phase", "t", "ev"]

var _match: MatchAutoload = null
var _defs: Dictionary = {}
var _defs_loaded: bool = false
var _schedule: WeatherScheduleTuning = preload("res://config/weather_schedule.tres")
## Test seams. `_host_override` null means "ask Match"; the factory builds the
## WeatherEffect for a def (null = no physics effect).
var _host_override: Variant = null
var _effect_factory: Callable = Callable()

var _running: bool = false
var _mode: int = MatchConfig.WeatherMode.OFF
var _seed: int = 0
var _epoch: int = -1
## Bontago-22y.4: which event of this match is (or was last) active, 1-based;
## replicated so per-event seeded effects (wind heading) agree on every peer.
var _event_index: int = 0
var _host_epoch_counter: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _fixed_id: StringName = &""
var _last_id: StringName = &""
## The active event never ends by itself (constant modes and the F4 override).
var _constant: bool = false
## F4 override: &"" = follow the lobby mode, DEBUG_OFF = force no weather, else
## a weather id held constantly.
var _debug: StringName = &""
## The override (not a lobby mode) started the schedule; clearing it stops it.
var _debug_started_run: bool = false

var _sched: int = Sched.OFF
var _left: float = 0.0
var _active_id: StringName = &""
var _phase: int = WeatherTuning.Phase.HOLD
var _phase_t: float = 0.0
var _hold_total: float = 0.0
var _intensity: float = 0.0
var _effect: WeatherEffect = null
## Bontago-470.2: the always-on gust layer; it spawns no gusts while a Storm is
## active (Bontago-mp0.91).
## DECISION: it lives here because MatchWeather already owns the host check,
## the per-frame tick and the PLAYING/teardown lifecycle; it never touches the
## schedule or the epoch.
var _breeze: BreezeEffect = BreezeEffect.new()


func setup(match_ref: MatchAutoload) -> void:
	_match = match_ref
	_breeze.bind(match_ref, _is_host)
	Events.match_state_changed.connect(_on_match_state_changed)


# --- Test seams --------------------------------------------------------------

func set_defs(defs: Array[WeatherTuning]) -> void:
	_defs.clear()
	for def: WeatherTuning in defs:
		_defs[def.id] = def
	_defs_loaded = true


func set_schedule_tuning(tuning: WeatherScheduleTuning) -> void:
	_schedule = tuning


func set_effect_factory(factory: Callable) -> void:
	_effect_factory = factory


func set_host_override(is_host: Variant) -> void:
	_host_override = is_host


# --- Breeze ----------------------------------------------------------------------

func breeze() -> BreezeEffect:
	return _breeze


## Host: starts the gust layer for a match (seeded from the match seed).
func begin_breeze(config: MatchConfig) -> void:
	var seed_value: int = config.rng_seed if config.rng_seed != -1 else int(randi())
	_breeze.begin(seed_value ^ BREEZE_SEED_SALT)


## F4: turns the gust layer on/off at runtime (host only; clients see gusts
## through replication). Returns false on a client.
func set_breeze_enabled(value: bool) -> bool:
	if not _is_host():
		return false
	_breeze.set_enabled(value)
	return true


func breeze_enabled() -> bool:
	return _breeze.is_enabled()


# --- Queries -------------------------------------------------------------------

func is_running() -> bool:
	return _running


func mode() -> int:
	return _mode


func schedule_phase() -> int:
	return _sched


func active_id() -> StringName:
	return _active_id


func active_intensity() -> float:
	return maxf(_intensity, 0.0) if _active_id != &"" else 0.0


func event_phase() -> int:
	return _phase


## Seconds until the next event while calm; -1.0 when not calm. The "weather
## incoming" cue reads this (approximate on a client: it counts down locally
## from the host's last announcement).
func next_event_in() -> float:
	return _left if _sched == Sched.CALM else -1.0


func seed_value() -> int:
	return _seed


## Ordinal of the current event within the match (0 before the first).
func event_index() -> int:
	return _event_index


## Which Match states a client accepts a replicated weather state in: from the
## countdown on, never after the match ended or before it started.
static func accepts_replication_in(match_state: int) -> bool:
	return match_state == MatchAutoload.State.COUNTDOWN 		or match_state == MatchAutoload.State.PLAYING 		or match_state == MatchAutoload.State.SUDDEN_DEATH


## The weather id a TYPE mode stands for (its enum name lower-cased, matching
## config/weather/<id>.tres); &"" for OFF/RANDOM/CHANGING or an out-of-range int.
static func id_for_mode(weather_mode: int) -> StringName:
	if not is_type_mode(weather_mode):
		return &""
	return DisplayNames.weather_key(weather_mode)


static func is_type_mode(weather_mode: int) -> bool:
	return weather_mode > MatchConfig.WeatherMode.OFF and weather_mode < MatchConfig.WeatherMode.RANDOM


## Lobby labels indexed by WeatherMode value ("Storm", "Random", ...).
static func mode_labels() -> Array:
	var labels: Array = []
	for index: int in MatchConfig.WeatherMode.size():
		labels.append(DisplayNames.weather(index))
	return labels


## True while the active weather never ends by itself.
func is_constant() -> bool:
	return _constant


func debug_override() -> StringName:
	return _debug


## Weather ids the F4 panel can force, sorted (all config/weather/*.tres).
func available_ids() -> Array[StringName]:
	return _sorted_ids()


func _is_host() -> bool:
	if _host_override != null:
		return bool(_host_override)
	return _match != null and _match._is_host()


func _ensure_defs() -> void:
	if _defs_loaded:
		return
	_defs_loaded = true
	_defs.clear()
	for def: WeatherTuning in WeatherTuning.load_all():
		_defs[def.id] = def


func _sorted_ids() -> Array[StringName]:
	_ensure_defs()
	var ids: Array[StringName] = []
	for key: Variant in _defs.keys():
		ids.append(key as StringName)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids


# --- Lifecycle -----------------------------------------------------------------

func _on_match_state_changed(_from_state: int, to_state: int) -> void:
	match to_state:
		MatchAutoload.State.PLAYING:
			if _is_host() and _match != null and _match.config != null:
				if not _running:
					begin_match(_match.config)
				if not _breeze.is_running():
					begin_breeze(_match.config)
		MatchAutoload.State.LOADING, MatchAutoload.State.LOBBY, MatchAutoload.State.END:
			reset()


## Host: starts the schedule for a match played with `config`. A repeated call
## while running is ignored.
func begin_match(config: MatchConfig) -> void:
	if _running:
		return
	reset()
	_mode = clampi(config.weather_mode, MatchConfig.WeatherMode.OFF, MatchConfig.WeatherMode.CHANGING)
	if _mode == MatchConfig.WeatherMode.OFF:
		return
	_constant = _mode != MatchConfig.WeatherMode.CHANGING
	_seed = config.rng_seed if config.rng_seed != -1 else int(randi())
	_rng.seed = _seed
	_host_epoch_counter += 1
	_epoch = _host_epoch_counter
	_last_id = &""
	_fixed_id = id_for_mode(_mode)
	if _mode == MatchConfig.WeatherMode.RANDOM:
		var ids: Array[StringName] = _sorted_ids()
		if not ids.is_empty():
			_fixed_id = ids[_rng.randi_range(0, ids.size() - 1)]
	_running = true
	_enter_calm(_schedule.constant_start_delay_s if _constant else _schedule.first_delay_s)


## Ends any event (restoring physics) and clears the schedule. Safe from any
## state, on host and client, and idempotent.
func reset() -> void:
	_breeze.stop()
	if _active_id != &"":
		_end_event()
	_running = false
	_mode = MatchConfig.WeatherMode.OFF
	_sched = Sched.OFF
	_left = 0.0
	_epoch = -1
	_event_index = 0
	_fixed_id = &""
	_last_id = &""
	_constant = false
	_debug = &""
	_debug_started_run = false
	_intensity = 0.0
	_phase_t = 0.0


func tick(delta: float) -> void:
	_breeze.tick(delta)
	if not _running:
		return
	if _is_host():
		_tick_host(delta)
	else:
		_tick_client(delta)


func _tick_host(delta: float) -> void:
	if _sched == Sched.CALM:
		if _debug == &"":  # the F4 override pauses the schedule
			_left -= delta
			if _left <= 0.0:
				var carry: float = -_left
				var next_id: StringName = _draw_type()
				if next_id == &"":
					_enter_calm(_draw_gap())
				else:
					_begin_event(next_id)
					_advance_event(carry)
	elif _sched == Sched.EVENT:
		_advance_event(delta)
	if _active_id != &"":
		_present_intensity()
		if _effect != null:
			_effect.tick(delta, _intensity)


func _tick_client(delta: float) -> void:
	_left = maxf(_left - delta, 0.0)
	if _active_id != &"":
		_phase_t = minf(_phase_t + delta, _schedule.wire_max_time_s)
		_present_intensity()


# --- Host schedule ---------------------------------------------------------------

func _draw_gap() -> float:
	return _rng.randf_range(_schedule.gap_min_s, maxf(_schedule.gap_min_s, _schedule.gap_max_s))


func _draw_type() -> StringName:
	var ids: Array[StringName] = _sorted_ids()
	if _mode != MatchConfig.WeatherMode.CHANGING:
		return _fixed_id if _defs.has(_fixed_id) else &""
	if ids.is_empty():
		return &""
	var candidates: Array[StringName] = []
	for id: StringName in ids:
		if not (_schedule.avoid_repeat_type and ids.size() > 1 and id == _last_id):
			candidates.append(id)
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _enter_calm(seconds: float) -> void:
	_sched = Sched.CALM
	_left = seconds
	_announce()


## Starts an event of `weather_id` now. Host schedule internals call this;
## tests and debug tooling may too. No-op for an unknown id or on a client.
func start_event(weather_id: StringName) -> bool:
	if not _is_host() or not _defs_ready_for(weather_id):
		return false
	if not _running:
		_running = true
		_host_epoch_counter += 1
		_epoch = _host_epoch_counter
		if _mode == MatchConfig.WeatherMode.OFF:
			_mode = MatchConfig.WeatherMode.CHANGING
	if _active_id != &"":
		_end_event()
	_begin_event(weather_id)
	return true


## Host, F4 debug: `value` is &"" (follow the lobby mode again), DEBUG_OFF (no
## weather) or a weather id (held constantly). The previous weather's physics
## are restored before anything new starts. Returns false on a client or for an
## unknown id.
func set_debug_override(value: StringName) -> bool:
	if not _is_host():
		return false
	if value != &"" and value != DEBUG_OFF and not _defs_ready_for(value):
		return false
	if value != &"" and not _running:
		_debug_started_run = true
	_debug = value
	if value == &"":
		if _debug_started_run:
			# Back to "no weather": end the event and announce Sched.OFF (keeping
			# the epoch, so clients accept it) instead of a silent reset().
			if _active_id != &"":
				_end_event()
			_debug_started_run = false
			_running = false
			_mode = MatchConfig.WeatherMode.OFF
			_constant = false
			_sched = Sched.OFF
			_left = 0.0
			_announce()
		elif _running:
			if _active_id != &"":
				_end_event()
			_constant = _mode != MatchConfig.WeatherMode.CHANGING
			_enter_calm(_schedule.constant_start_delay_s if _constant else _schedule.first_delay_s)
		return true
	if value == DEBUG_OFF:
		if _active_id != &"":
			_end_event()
		if _running:
			_enter_calm(0.0)
		return true
	_constant = true
	return start_event(value)


## Ramps the current event out early (host). The calm gap follows.
func end_event() -> void:
	if _active_id != &"" and _is_host() and _phase != WeatherTuning.Phase.RAMP_OUT:
		_phase = WeatherTuning.Phase.RAMP_OUT
		_phase_t = 0.0
		_left = _current_def().ramp_out_s
		_announce()


func _defs_ready_for(weather_id: StringName) -> bool:
	_ensure_defs()
	return _defs.has(weather_id)


func _current_def() -> WeatherTuning:
	return _defs.get(_active_id) as WeatherTuning


func _begin_event(weather_id: StringName) -> void:
	_active_id = weather_id
	_event_index += 1
	var def: WeatherTuning = _current_def()
	_phase = WeatherTuning.Phase.RAMP_IN
	_phase_t = 0.0
	_hold_total = _rng.randf_range(def.hold_min_s, maxf(def.hold_min_s, def.hold_max_s))
	_sched = Sched.EVENT
	_intensity = -1.0
	_effect = null
	if _effect_factory.is_valid():
		_effect = _effect_factory.call(def) as WeatherEffect
	elif def.effect_script != "":
		var script: Script = load(def.effect_script) as Script
		if script != null:
			_effect = script.new() as WeatherEffect
	if _effect != null:
		_effect.bind(_match, def)
	_left = _event_remaining()
	Events.weather_started.emit(weather_id)
	_announce()
	_present_intensity()


## Walks phase transitions for `delta` more seconds (host).
func _advance_event(delta: float) -> void:
	if _active_id == &"":
		return
	var def: WeatherTuning = _current_def()
	_phase_t += delta
	var guard: int = 0
	while guard < WeatherTuning.Phase.size():
		guard += 1
		if _phase == WeatherTuning.Phase.RAMP_IN and _phase_t >= def.ramp_in_s:
			_phase_t -= def.ramp_in_s
			_phase = WeatherTuning.Phase.HOLD
			_announce_phase()
		elif _phase == WeatherTuning.Phase.HOLD and _constant:
			_phase_t = minf(_phase_t, _schedule.wire_max_time_s)
			break
		elif _phase == WeatherTuning.Phase.HOLD and _phase_t >= _hold_total:
			_phase_t -= _hold_total
			_phase = WeatherTuning.Phase.RAMP_OUT
			_announce_phase()
		elif _phase == WeatherTuning.Phase.RAMP_OUT and _phase_t >= def.ramp_out_s:
			var carry: float = _phase_t - def.ramp_out_s
			_end_event()
			_enter_calm(_draw_gap())
			_left = maxf(_left - carry, 0.0)
			return
		else:
			break
	_left = _event_remaining()


func _announce_phase() -> void:
	_left = _event_remaining()
	_announce()


func _event_remaining() -> float:
	var def: WeatherTuning = _current_def()
	if def == null:
		return 0.0
	match _phase:
		WeatherTuning.Phase.RAMP_IN:
			if _constant:
				return maxf(def.ramp_in_s - _phase_t, 0.0)
			return maxf(def.ramp_in_s - _phase_t, 0.0) + _hold_total + def.ramp_out_s
		WeatherTuning.Phase.HOLD:
			if _constant:
				return 0.0
			return maxf(_hold_total - _phase_t, 0.0) + def.ramp_out_s
	return maxf(def.ramp_out_s - _phase_t, 0.0)


## Finishes the active event: baseline physics first, then the signals.
func _end_event() -> void:
	var finished: StringName = _active_id
	if finished == &"":
		return
	if _effect != null:
		_effect.restore()
		_effect = null
	if _intensity != 0.0:
		_intensity = 0.0
		Events.weather_intensity_changed.emit(finished, 0.0)
	_active_id = &""
	_last_id = finished
	_phase_t = 0.0
	Events.weather_stopped.emit(finished)


func _present_intensity() -> void:
	var def: WeatherTuning = _current_def()
	if def == null:
		return
	var value: float = def.intensity_at(_phase, _phase_t)
	if _intensity >= 0.0 and absf(value - _intensity) < _schedule.intensity_epsilon:
		return
	_intensity = value
	if _effect != null:
		_effect.apply(value)
	Events.weather_intensity_changed.emit(_active_id, value)


func _announce() -> void:
	Events.weather_state_changed.emit(state_dict())


# --- Replication -------------------------------------------------------------------

## The full host state for the wire and for the HUD cue. Small enough to
## resend whole on every phase change and to a late joiner.
func state_dict() -> Dictionary:
	return {
		"v": WIRE_VERSION,
		"epoch": _epoch,
		"seed": _seed,
		"mode": _mode,
		"sched": _sched,
		"left": _left,
		"id": String(_active_id),
		"phase": _phase,
		"t": _phase_t,
		"ev": _event_index,
	}


## Returns the sanitized state or {} when `raw` is malformed in any way: wrong
## type, missing/extra key, out-of-range enum, unknown weather id, non-finite
## or absurd time, or an id/phase that contradicts the schedule phase.
func sanitize_wire_state(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var data: Dictionary = raw
	if data.size() != WIRE_KEYS.size():
		return {}
	for key: String in WIRE_KEYS:
		if not data.has(key):
			return {}
	if not _is_int(data["v"]) or int(data["v"]) != WIRE_VERSION:
		return {}
	if not _is_int(data["epoch"]) or int(data["epoch"]) < 0:
		return {}
	if not _is_int(data["seed"]) or not _is_int(data["mode"]) or not _is_int(data["sched"]) or not _is_int(data["phase"]):
		return {}
	var mode_value: int = int(data["mode"])
	var sched_value: int = int(data["sched"])
	var phase_value: int = int(data["phase"])
	if mode_value < MatchConfig.WeatherMode.OFF or mode_value > MatchConfig.WeatherMode.CHANGING:
		return {}
	if sched_value < Sched.OFF or sched_value > Sched.EVENT:
		return {}
	if phase_value < WeatherTuning.Phase.RAMP_IN or phase_value > WeatherTuning.Phase.RAMP_OUT:
		return {}
	if not _is_int(data["ev"]) or int(data["ev"]) < 0:
		return {}
	if not _is_number(data["left"]) or not _is_number(data["t"]):
		return {}
	var left_value: float = float(data["left"])
	var t_value: float = float(data["t"])
	if not is_finite(left_value) or not is_finite(t_value):
		return {}
	if left_value < 0.0 or t_value < 0.0 or left_value > _schedule.wire_max_time_s or t_value > _schedule.wire_max_time_s:
		return {}
	var id_type: int = typeof(data["id"])
	if id_type != TYPE_STRING and id_type != TYPE_STRING_NAME:
		return {}
	var id_value: StringName = StringName(String(data["id"]))
	_ensure_defs()
	if sched_value == Sched.EVENT:
		if not _defs.has(id_value):
			return {}
	elif id_value != &"":
		return {}
	if sched_value != Sched.OFF and mode_value == MatchConfig.WeatherMode.OFF:
		return {}
	return {
		"v": WIRE_VERSION, "epoch": int(data["epoch"]), "seed": int(data["seed"]),
		"mode": mode_value, "sched": sched_value, "left": left_value,
		"id": id_value, "phase": phase_value, "t": t_value,
		"ev": int(data["ev"]),
	}


static func _is_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


## Client: adopts the host's state. Returns false (and changes nothing) for a
## malformed or stale message, on the host, or outside a live match.
## `match_live` is the caller's check of the match state (net/WeatherNet.gd).
func apply_replicated_state(raw: Variant, match_live: bool) -> bool:
	if _is_host() or not match_live:
		return false
	var data: Dictionary = sanitize_wire_state(raw)
	if data.is_empty():
		return false
	if int(data["epoch"]) < _epoch:
		return false
	_epoch = int(data["epoch"])
	_seed = int(data["seed"])
	_event_index = int(data["ev"])
	_mode = int(data["mode"])
	_running = int(data["sched"]) != Sched.OFF
	_sched = int(data["sched"])
	_left = float(data["left"])
	var new_id: StringName = data["id"]
	if new_id != _active_id:
		if _active_id != &"":
			_end_event()
		if new_id != &"":
			_active_id = new_id
			_intensity = -1.0
			Events.weather_started.emit(new_id)
	_phase = int(data["phase"])
	_phase_t = float(data["t"])
	_announce()
	if _active_id != &"":
		_present_intensity()
	return true
