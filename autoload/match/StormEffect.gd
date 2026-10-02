class_name StormEffect
extends WeatherEffect
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

const EXPOSURE_AXES: Array[Vector3] = [Vector3.UP, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.DOWN]

var _elapsed: float = 0.0
var _tick_index: int = 0
var _seed: int = 0
## Test seams: replace the registry/field lookups and the host check.
var _blocks_source: Callable = Callable()
var _surface_source: Callable = Callable()
var _force_host: bool = false
var last_pushed: int = 0
## Stable-frozen blocks woken on the most recent tick (capped by tuning).
var last_woken: int = 0
var last_dir: Vector2 = Vector2.ZERO
var last_gust: float = 1.0


func set_test_world(blocks: Callable, surface_y: Callable) -> void:
	_blocks_source = blocks
	_surface_source = surface_y
	_force_host = true


func bind(match_owner: MatchAutoload, weather_tuning: WeatherTuning) -> void:
	super.bind(match_owner, weather_tuning)
	if match_owner != null and match_owner.weather() != null:
		_seed = WindField.event_seed(match_owner.weather().seed_value(), match_owner.weather().event_index())


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


## True when StableBlockManager's auto-freeze (20 s asleep) holds `block`. A
## settled tower is in this state in real play; wind used to skip it
## (Bontago-mp0.36).
static func is_stable_frozen(block: Block) -> bool:
	var manager: StableBlockManager = StableBlockManager.active
	return manager != null and is_instance_valid(manager) and manager.is_stable_frozen(block)


## Releases the stable freeze through the manager (which also restarts the
## sleep -> freeze cycle) and wakes the body. False when nothing was frozen.
static func wake_stable_frozen(block: Block) -> bool:
	var manager: StableBlockManager = StableBlockManager.active
	return manager != null and is_instance_valid(manager) and manager.wake_for_external_force(block)


## Cheap exposure test: a block is exposed when a short probe from its centre
## along any of the six world axes reaches open air (an open top or side face).
## A block enclosed on all sides, e.g. the core of a big stack, stays frozen.
## The six rays only run for frozen blocks that already passed the stride,
## accel and per-tick cap checks.
static func is_exposed(block: Block, probe_m: float) -> bool:
	var world: World3D = block.get_world_3d()
	if world == null:
		return true
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return true
	var origin: Vector3 = block.global_position
	for axis: Vector3 in EXPOSURE_AXES:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + axis * probe_m, block.collision_layer)
		query.exclude = [block.get_rid()]
		if space.intersect_ray(query).is_empty():
			return true
	return false


static func _owns_physics(block: Block) -> bool:
	for child: Node in block.get_children():
		if child is SpecialBehavior or child is GlueJoint:
			return true
	return false


func restore() -> void:
	_elapsed = 0.0
	_tick_index = 0
	last_pushed = 0


func _is_host() -> bool:
	if _force_host:
		return true
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
