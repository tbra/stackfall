class_name StormEffect
extends WindEffect
## Host-side wind physics (Bontago-22y.4). Every physics tick pushes live
## blocks sideways with a force that is zero below StormTuning.threshold_height_m
## and rises to a maximum at cap_height_m, so tall thin stacks topple while low
## piles stay put. The push is mass-proportional (acceleration), clamped per
## tick and by along-wind speed so nothing launches.
##
## Holds no persistent physics state: forces are applied per tick through
## apply_central_force (Jolt clears them each step), so restore() only drops
## bookkeeping and stopping the tick is a complete undo.
##
## DECISION (StormEffect): sleeping blocks are scanned as a rotating subset
## (1 in sleeper_stride_ticks per tick) and woken only if the push reaches
## wake_accel; awake blocks are pushed every tick. Frozen/static blocks
## (StableBlockManager or a Freeze special) are never touched, and neither
## are blocks not yet placed (held/ghost blocks are not in the registry).
## DECISION (StormEffect): wind direction is drawn per EVENT from the schedule
## seed and the replicated event index (WindField.event_seed), plus a slow veer
## over the event; the client presentation derives the same value from the
## replicated state. The gust phase is approximate on clients (local clock).
## DECISION (StormEffect): a block carrying a SpecialBehavior child (an
## untriggered special, e.g. rocket/propeller/jumping bean, which write its
## velocity) or a GlueJoint child (glue owner, joints under stress) is skipped
## so wind cannot break those rules; no other special leaves a marker.

var _elapsed: float = 0.0
var _tick_index: int = 0
var _seed: int = 0
var last_dir: Vector2 = Vector2.ZERO
var last_gust: float = 1.0


func bind(match_context: MatchContext, weather_tuning: WeatherTuning) -> void:
	super.bind(match_context, weather_tuning)
	if match_context != null and match_context.has_weather():
		_seed = WindField.event_seed(match_context.weather_seed(), match_context.weather_event_index())


func set_seed(seed_value: int) -> void:
	_seed = seed_value


func tick(delta: float, intensity: float) -> void:
	last_pushed = 0
	last_woken = 0
	var wt: StormTuning = tuning as StormTuning
	if wt == null or intensity <= 0.0 or not _is_host():
		return
	_elapsed += delta
	_tick_index += 1
	var dir2: Vector2 = WindField.direction(_seed, _elapsed, wt)
	var gust_mult: float = WindField.gust(_seed, _elapsed, wt)
	last_dir = dir2
	last_gust = gust_mult
	var dir: Vector3 = Vector3(dir2.x, 0.0, dir2.y)
	var surface: float = _surface_y()
	var stride: int = maxi(wt.sleeper_stride_ticks, 1)
	var index: int = 0
	for block: Block in _blocks():
		index += 1
		if not is_instance_valid(block) or not block.is_inside_tree():
			continue
		var stable_frozen: bool = is_stable_frozen(block)
		if not stable_frozen and (block.freeze or block.is_freeze_static()):
			continue
		var height: float = block.global_position.y - surface
		if height <= wt.threshold_height_m:
			continue
		if _owns_physics(block):
			continue
		var asleep: bool = block.sleeping or stable_frozen
		if asleep and (index + _tick_index) % stride != 0:
			continue
		var accel: float = WindField.accel_at(height, intensity, gust_mult, delta, wt)
		if accel <= 0.0 or (asleep and accel < wt.wake_accel):
			continue
		if stable_frozen:
			if last_woken >= wt.max_wakes_per_tick or not is_exposed(block, wt.exposure_probe_m):
				continue
			if not wake_stable_frozen(block):
				continue
			last_woken += 1
		if block.linear_velocity.dot(dir) >= wt.max_speed_ms:
			continue
		block.apply_central_force(dir * accel * block.mass)
		last_pushed += 1


func restore() -> void:
	_elapsed = 0.0
	_tick_index = 0
	last_pushed = 0
