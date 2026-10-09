class_name SettleTracker
extends RefCounted
## Pure decision logic for the awake-but-still settle freeze (owner decision
## Bontago-e7o B, spec 3.5): a block that is AWAKE (Jolt keeps it awake, e.g. a
## micro-jittering pile) but has stayed within `move_epsilon_m` (and
## `rotation_epsilon`, the same unit-basis-axis distance
## StableBlockManager already uses) of the pose its still window started in,
## for `window_s` continuous seconds, may be frozen like an asleep block.
## Any move beyond the epsilons restarts the window at the new pose. A block
## with a fast-moving body within `neighbour_radius_m` is never ready (it may be
## about to be hit), but keeps its window.
##
## No scene tree, no physics queries: the caller feeds poses and speeds it
## already has. Cost is O(blocks observed) plus O(fast bodies) per candidate.

## The five thresholds are set by the caller from PhysicsTuning (no defaults here).
var window_s: float
var move_epsilon_m: float
var rotation_epsilon: float
var fast_speed_mps: float
var neighbour_radius_m: float

## id -> Transform3D the current still window started in.
var _anchor: Dictionary = {}
## id -> continuous seconds still.
var _still_s: Dictionary = {}


## Feeds one observation. Returns the continuous still time so far (0 right
## after a move or on first sight).
func observe(id: int, pose: Transform3D, delta: float) -> float:
	if not _anchor.has(id) or moved(pose, _anchor[id]):
		_anchor[id] = pose
		_still_s[id] = 0.0
		return 0.0
	var elapsed: float = float(_still_s.get(id, 0.0)) + delta
	_still_s[id] = elapsed
	return elapsed


func still_seconds(id: int) -> float:
	return float(_still_s.get(id, 0.0))


func is_window_complete(id: int) -> bool:
	return still_seconds(id) >= window_s


## Forgets a block (it slept, froze, was released or removed).
func reset(id: int) -> void:
	_anchor.erase(id)
	_still_s.erase(id)


func tracked_count() -> int:
	return _anchor.size()


## Drops every tracked id not in `live_ids` (id -> true).
func prune(live_ids: Dictionary) -> void:
	for id: Variant in _anchor.keys():
		if not live_ids.has(id):
			reset(id as int)


func is_fast(speed_sq: float) -> bool:
	return speed_sq > fast_speed_mps * fast_speed_mps


## True when any position in `fast_positions` is within neighbour_radius_m of `pos`.
func has_fast_neighbour(pos: Vector3, fast_positions: PackedVector3Array) -> bool:
	var radius_sq: float = neighbour_radius_m * neighbour_radius_m
	for other: Vector3 in fast_positions:
		if pos.distance_squared_to(other) <= radius_sq:
			return true
	return false


func moved(current: Transform3D, anchor: Transform3D) -> bool:
	var move_sq: float = move_epsilon_m * move_epsilon_m
	var rot_sq: float = rotation_epsilon * rotation_epsilon
	return (
		current.origin.distance_squared_to(anchor.origin) > move_sq
		or current.basis.x.distance_squared_to(anchor.basis.x) > rot_sq
		or current.basis.y.distance_squared_to(anchor.basis.y) > rot_sq
		or current.basis.z.distance_squared_to(anchor.basis.z) > rot_sq
	)
