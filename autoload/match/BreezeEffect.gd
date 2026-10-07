class_name BreezeEffect
extends WindEffect
## Host-side Breeze (Bontago-470.2): an always-on weak wind made of short
## local GUSTS, layered independently of the weather mode and of any active
## weather, except Storm: no NEW gust spawns while a Storm event is active
## (Bontago-mp0.91, owner playtest "gust shouldn't occur during storm"); they
## resume when it ends. Rules: core/BreezeField.gd; numbers: config/breeze.tres
## (BreezeTuning).
##
## Every spawn_interval_s the host picks one live block from its seeded RNG and
## accepts it with a chance that rises with the block's height above the disc
## (rare low, common high); an accepted gust is a sphere around that block that
## pushes only blocks inside it along one heading for a few seconds. Gusts are
## replicated compactly as one Events.breeze_gust_started per gust
## (net/BreezeNet.gd) so clients can draw them; the host is the only one that
## simulates.
##
## DECISION (BreezeEffect): forces are applied per tick with
## apply_central_force, exactly like StormEffect, so they SUM with a Storm's
## push in the physics step. Each is clamped on its own (per-tick dv and an
## along-heading speed cap: Breeze's is small). Since Bontago-mp0.91 no new
## gust spawns while a Storm is active, so the overlap is limited to a gust
## already in flight at storm start; stopping the tick is a complete undo.
## DECISION (BreezeEffect): sleeping blocks are scanned on a rotating stride and
## woken only when the summed push reaches wake_accel, blocks that own their
## physics (Freeze, SpecialBehavior, GlueJoint) are skipped, as in Storm.
## DECISION (BreezeEffect): the gust list is authoritative host state; a peer
## joining mid-gust simply misses that gust's visual (transient, seconds).
## DECISION (BreezeEffect, Bontago-mp0.91): the host scheduler skips the spawn
## attempt while the active weather id is Storm (any phase: ramp-in, hold,
## ramp-out; the F4 forced storm too). Clients need no logic: they only draw the
## gusts the host announces, so no announcement means no gust. A gust already in
## flight when a Storm starts is left to finish: the host has no "gust ended
## early" wire message (net/BreezeNet.gd announces each gust once, with its
## duration), so cancelling only the host list would leave clients drawing a
## gust that no longer pushes. The overlap is at most one gust life
## (duration_max_s, mostly inside the Storm's ramp-in, where its wind is still
## weak). Suppressed attempts consume no seeded random draws, so a seed's gust
## sequence still depends only on the seed, the block list and the weather
## schedule. The Storm's own wind is untouched.

## The weather id (config/weather/storm.tres) that quiets the Breeze.
const QUIET_WEATHER_ID: StringName = WeatherIds.STORM

## The base class's `tuning`, typed as this effect's own BreezeTuning.
var _bt: BreezeTuning:
	get:
		return tuning as BreezeTuning

var _enabled: bool = true
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _running: bool = false
var _spawn_left: float = 0.0
var _next_id: int = 1
var _tick_index: int = 0
var _gusts: Array[Dictionary] = []
## Optional override for the active weather id (returns a StringName/String);
## unset = ask match_ref.weather().
var _weather_id_source: Callable = Callable()


func _init() -> void:
	tuning = preload("res://config/breeze.tres")


## `weather_tuning` null keeps the current (default breeze.tres) tuning.
func bind(
	match_owner: MatchAutoload, weather_tuning: WeatherTuning = null, host_check: Callable = Callable()
) -> void:
	match_ref = match_owner
	if weather_tuning != null:
		tuning = weather_tuning
	_host_check = host_check


## Test seam: replaces the lookup of the active weather id.
func set_weather_source(source: Callable) -> void:
	_weather_id_source = source


func begin(seed_value: int) -> void:
	stop()
	_rng.seed = seed_value
	_enabled = _bt.enabled
	_spawn_left = _bt.spawn_interval_s
	_next_id = 1
	_running = true


## Ends the layer and drops every gust. Idempotent, safe from any state.
func stop() -> void:
	_running = false
	_gusts.clear()
	_spawn_left = 0.0
	_tick_index = 0
	last_pushed = 0


func is_running() -> bool:
	return _running


func is_enabled() -> bool:
	return _enabled


## F4 toggle: off ends every live gust at once.
func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		_gusts.clear()


## True while a Storm event is active (host weather state), i.e. while no new
## gust may spawn. Resolved on demand: it is only asked once per spawn attempt.
func is_quieted_by_weather() -> bool:
	return _active_weather_id() == QUIET_WEATHER_ID


func gust_count() -> int:
	return _gusts.size()


func gusts() -> Array[Dictionary]:
	return _gusts


func tick(delta: float, _intensity: float = 1.0) -> void:
	last_pushed = 0
	last_woken = 0
	if not _running or not _enabled or not _is_host():
		return
	_tick_index += 1
	_age_and_expire(delta)
	_spawn_left -= delta
	if _spawn_left <= 0.0:
		_spawn_left += maxf(_bt.spawn_interval_s, delta)
		if not is_quieted_by_weather():
			_try_spawn()
	if not _gusts.is_empty():
		_push(delta)


func _age_and_expire(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for gust: Dictionary in _gusts:
		gust["age"] = float(gust["age"]) + delta
		if float(gust["age"]) < float(gust["d"]):
			keep.append(gust)
	_gusts = keep


func _eligible(block: Block) -> bool:
	if not is_instance_valid(block) or not block.is_inside_tree():
		return false
	# A settled tower is stable-frozen STATIC after 20 s asleep; gusts wake it
	# (Bontago-mp0.36). Any other freeze (Freeze special) still blocks the push.
	if WindEffect.is_stable_frozen(block):
		return true
	return not block.freeze and not block.is_freeze_static()


## One seeded attempt. The random draws are always consumed in the same order so
## the sequence depends only on the seed and the block list (no draws are made
## while a Storm suppresses spawning, Bontago-mp0.91).
func _try_spawn() -> void:
	var blocks: Array[Block] = _blocks()
	var pick: float = _rng.randf()
	var accept: float = _rng.randf()
	var jitter_x: float = _rng.randf_range(-1.0, 1.0)
	var jitter_y: float = _rng.randf_range(-1.0, 1.0)
	var jitter_z: float = _rng.randf_range(-1.0, 1.0)
	var angle: float = _rng.randf() * TAU
	var radius: float = _rng.randf_range(_bt.radius_min_m, maxf(_bt.radius_min_m, _bt.radius_max_m))
	var duration: float = _rng.randf_range(_bt.duration_min_s, maxf(_bt.duration_min_s, _bt.duration_max_s))
	# Bontago-1pi.76: at most ONE gust alive at a time (a sporadic single gust).
	if blocks.is_empty() or not _gusts.is_empty():
		return
	var block: Block = blocks[mini(int(pick * float(blocks.size())), blocks.size() - 1)]
	if not _eligible(block):
		return
	var surface: float = _surface_y()
	var height: float = block.global_position.y - surface
	if accept >= BreezeField.spawn_probability(height, _bt):
		return
	var jitter: float = radius * _bt.center_jitter
	var center: Vector3 = block.global_position + Vector3(jitter_x, jitter_y, jitter_z) * jitter
	var gust: Dictionary = {
		"id": _next_id, "x": center.x, "y": center.y, "z": center.z,
		"a": angle, "r": radius, "d": duration, "s": BreezeField.gust_strength(height, _bt),
	}
	_next_id += 1
	var wire: Dictionary = gust.duplicate()
	gust["age"] = 0.0
	_gusts.append(gust)
	Events.breeze_gust_started.emit(wire)


func _push(delta: float) -> void:
	var surface: float = _surface_y()
	var stride: int = maxi(_bt.sleeper_stride_ticks, 1)
	# Cheap sphere data first: most blocks are outside every gust, and the
	# full checks (tree, freeze, children) only run for the few inside one.
	var centers: Array[Vector3] = []
	var radii_sq: Array[float] = []
	for gust: Dictionary in _gusts:
		centers.append(Vector3(float(gust["x"]), float(gust["y"]), float(gust["z"])))
		radii_sq.append(float(gust["r"]) * float(gust["r"]))
	var index: int = 0
	for block: Block in _blocks():
		index += 1
		if not is_instance_valid(block):
			continue
		var position: Vector3 = block.global_position
		var inside: bool = false
		for gi: int in range(centers.size()):
			if position.distance_squared_to(centers[gi]) < radii_sq[gi]:
				inside = true
				break
		if not inside or not _eligible(block):
			continue
		var total: Vector3 = Vector3.ZERO
		for gust: Dictionary in _gusts:
			total += BreezeField.gust_accel(gust, float(gust["age"]), position, surface, delta, _bt)
		var accel: float = total.length()
		if accel <= 0.0:
			continue
		if WindEffect._owns_physics(block):
			continue
		var stable_frozen: bool = WindEffect.is_stable_frozen(block)
		var asleep: bool = block.sleeping or stable_frozen
		if asleep and ((index + _tick_index) % stride != 0 or accel < _bt.wake_accel):
			continue
		var dir: Vector3 = total / accel
		if stable_frozen:
			if last_woken >= _bt.max_wakes_per_tick or not WindEffect.is_exposed(block, _bt.exposure_probe_m):
				continue
			if not WindEffect.wake_stable_frozen(block):
				continue
			last_woken += 1
		if block.linear_velocity.dot(dir) >= _bt.max_speed_ms:
			continue
		accel = minf(accel, _bt.max_dv_per_tick / maxf(delta, 0.0001))
		block.apply_central_force(dir * accel * block.mass)
		last_pushed += 1


func _active_weather_id() -> StringName:
	if _weather_id_source.is_valid():
		return StringName(String(_weather_id_source.call()))
	var weather: MatchWeather = match_ref.weather() if match_ref != null else null
	return weather.active_id() if weather != null else &""
