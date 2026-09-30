class_name BreezeEffect
extends RefCounted
## Host-side Breeze (Bontago-470.2): an always-on weak wind made of short
## local GUSTS, layered independently of the weather mode and of any active
## weather (including Storm). Rules: core/BreezeField.gd; numbers:
## config/breeze.tres (BreezeTuning).
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
## along-heading speed cap: Breeze's is small), so the worst case under Storm
## is Storm's cap plus Breeze's small one; stopping the tick is a complete undo.
## DECISION (BreezeEffect): sleeping blocks are scanned on a rotating stride and
## woken only when the summed push reaches wake_accel, blocks that own their
## physics (Freeze, SpecialBehavior, GlueJoint) are skipped, as in Storm.
## DECISION (BreezeEffect): the gust list is authoritative host state; a peer
## joining mid-gust simply misses that gust's visual (transient, seconds).

var tuning: BreezeTuning = preload("res://config/breeze.tres")
var match_ref: MatchAutoload = null
var last_pushed: int = 0

var _enabled: bool = true
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _running: bool = false
var _spawn_left: float = 0.0
var _next_id: int = 1
var _tick_index: int = 0
var _gusts: Array[Dictionary] = []
var _host_check: Callable = Callable()
## Test seams (same shape as StormEffect's).
var _blocks_source: Callable = Callable()
var _surface_source: Callable = Callable()
var _force_host: bool = false


func bind(match_owner: MatchAutoload, host_check: Callable = Callable()) -> void:
	match_ref = match_owner
	_host_check = host_check


func set_test_world(blocks: Callable, surface_y: Callable) -> void:
	_blocks_source = blocks
	_surface_source = surface_y
	_force_host = true


func begin(seed_value: int) -> void:
	stop()
	_rng.seed = seed_value
	_enabled = tuning.enabled
	_spawn_left = tuning.spawn_interval_s
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


func gust_count() -> int:
	return _gusts.size()


func gusts() -> Array[Dictionary]:
	return _gusts


func tick(delta: float) -> void:
	last_pushed = 0
	if not _running or not _enabled or not _is_host():
		return
	_tick_index += 1
	_age_and_expire(delta)
	_spawn_left -= delta
	if _spawn_left <= 0.0:
		_spawn_left += maxf(tuning.spawn_interval_s, delta)
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
	return is_instance_valid(block) and block.is_inside_tree() and not block.freeze and not block.is_freeze_static()


## One seeded attempt. The random draws are always consumed in the same order so
## the sequence depends only on the seed and the block list.
func _try_spawn() -> void:
	var blocks: Array[Block] = _blocks()
	var pick: float = _rng.randf()
	var accept: float = _rng.randf()
	var jitter_x: float = _rng.randf_range(-1.0, 1.0)
	var jitter_y: float = _rng.randf_range(-1.0, 1.0)
	var jitter_z: float = _rng.randf_range(-1.0, 1.0)
	var angle: float = _rng.randf() * TAU
	var radius: float = _rng.randf_range(tuning.radius_min_m, maxf(tuning.radius_min_m, tuning.radius_max_m))
	var duration: float = _rng.randf_range(tuning.duration_min_s, maxf(tuning.duration_min_s, tuning.duration_max_s))
	if blocks.is_empty() or _gusts.size() >= tuning.max_active_gusts:
		return
	var block: Block = blocks[mini(int(pick * float(blocks.size())), blocks.size() - 1)]
	if not _eligible(block):
		return
	var surface: float = _surface_y()
	var height: float = block.global_position.y - surface
	if accept >= BreezeField.spawn_probability(height, tuning):
		return
	var jitter: float = radius * tuning.center_jitter
	var center: Vector3 = block.global_position + Vector3(jitter_x, jitter_y, jitter_z) * jitter
	var gust: Dictionary = {
		"id": _next_id, "x": center.x, "y": center.y, "z": center.z,
		"a": angle, "r": radius, "d": duration, "s": BreezeField.gust_strength(height, tuning),
	}
	_next_id += 1
	var wire: Dictionary = gust.duplicate()
	gust["age"] = 0.0
	_gusts.append(gust)
	Events.breeze_gust_started.emit(wire)


func _push(delta: float) -> void:
	var surface: float = _surface_y()
	var stride: int = maxi(tuning.sleeper_stride_ticks, 1)
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
			total += BreezeField.gust_accel(gust, float(gust["age"]), position, surface, delta, tuning)
		var accel: float = total.length()
		if accel <= 0.0:
			continue
		if StormEffect._owns_physics(block):
			continue
		var asleep: bool = block.sleeping
		if asleep and ((index + _tick_index) % stride != 0 or accel < tuning.wake_accel):
			continue
		var dir: Vector3 = total / accel
		if block.linear_velocity.dot(dir) >= tuning.max_speed_ms:
			continue
		accel = minf(accel, tuning.max_dv_per_tick / maxf(delta, 0.0001))
		block.apply_central_force(dir * accel * block.mass)
		last_pushed += 1


func _is_host() -> bool:
	if _force_host:
		return true
	if _host_check.is_valid():
		return bool(_host_check.call())
	return match_ref != null and match_ref._is_host()


func _blocks() -> Array[Block]:
	if _blocks_source.is_valid():
		var listed: Array[Block] = []
		listed.assign(_blocks_source.call() as Array)
		return listed
	var registry: BlockRegistry = match_ref.registry() if match_ref != null else null
	if registry == null:
		var none: Array[Block] = []
		return none
	return registry.all_blocks()


func _surface_y() -> float:
	if _surface_source.is_valid():
		return float(_surface_source.call())
	var field: Field = match_ref.field() if match_ref != null else null
	return field.surface_y() if field != null else 0.0
