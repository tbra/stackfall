class_name WindEffect
extends WeatherEffect
## Shared base of the two host-side wind effects, StormEffect and BreezeEffect:
## the block/surface/host lookups, the per-tick wake counter and the
## stable-freeze helpers both use to push (and wake) blocks the same way.

## Six world axes probed by is_exposed().
const EXPOSURE_AXES: Array[Vector3] = [Vector3.UP, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.DOWN]

## Stable-frozen blocks woken on the most recent tick (capped by tuning).
var last_woken: int = 0

## Optional host check (MatchWeather passes its own for Breeze); unset = ask context.
var _host_check: Callable = Callable()


## True when StableBlockManager's auto-freeze (20 s asleep) holds `block`. A
## settled tower is in this state in real play, so wind must wake it.
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


## True when the block carries a SpecialBehavior child that owns its
## physics, so wind must not touch it. A FusedBody and every member of one
## ignore wind (the group is one heavy body; nudging a follower is moot).
static func _owns_physics(block: Block) -> bool:
	# Duck-typed carrier test (members_in_sphere is FusedBody's): a FusedBody type reference here
	# would pull the group into the autoload layer closure.
	if block.has_method(&"members_in_sphere") or block.is_fused_member():
		return true
	for child: Node in block.get_children():
		if child is SpecialBehavior:
			return true
	return false


func _is_host() -> bool:
	if _host_check.is_valid():
		return bool(_host_check.call())
	return context != null and context.has_authority()


func _blocks() -> Array[Block]:
	var registry: BlockRegistry = context.registry() as BlockRegistry if context != null else null
	if registry == null:
		var none: Array[Block] = []
		return none
	return registry.all_blocks()


## World Y of the live disc under `world`'s XZ (0.0 without a field), so a tilted disc measures each block's
## height from the ground beneath it.
func _surface_y_at(world: Vector3) -> float:
	var field: Field = context.field() as Field if context != null else null
	return field.surface_height_at(world) if field != null else 0.0
