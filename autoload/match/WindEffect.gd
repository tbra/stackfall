class_name WindEffect
extends WeatherEffect
## Shared base of the two host-side wind effects, StormEffect (Bontago-22y.4)
## and BreezeEffect (Bontago-470.2): the block/surface/host lookups with their
## test seams, the per-tick push counters and the stable-freeze helpers both
## use to push (and wake) blocks the same way.

## Six world axes probed by is_exposed().
const EXPOSURE_AXES: Array[Vector3] = [Vector3.UP, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.DOWN]

## Blocks pushed on the most recent tick.
var last_pushed: int = 0
## Stable-frozen blocks woken on the most recent tick (capped by tuning).
var last_woken: int = 0

## Test seams: replace the registry/field lookups and the host check.
var _blocks_source: Callable = Callable()
var _surface_source: Callable = Callable()
var _force_host: bool = false
## Optional host check (MatchWeather passes its own for Breeze); unset = ask match_ref.
var _host_check: Callable = Callable()


func set_test_world(blocks: Callable, surface_y: Callable) -> void:
	_blocks_source = blocks
	_surface_source = surface_y
	_force_host = true


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


## True when the block carries a SpecialBehavior or GlueJoint child that owns
## its physics, so wind must not touch it.
static func _owns_physics(block: Block) -> bool:
	for child: Node in block.get_children():
		if child is SpecialBehavior or child is GlueJoint:
			return true
	return false


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
