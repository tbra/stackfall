class_name BlackHoleField
extends Node3D
## Host-only physics for one active black hole (see BlackHoleEffect). Pulls
## every Block in range, all teams, toward its centre for lifetime_s, then
## frees itself. No visuals: BlackHoleVisual is built on every peer.

var _effect: BlackHoleEffect
var _exclude: Array[RID] = []
var _age: float = 0.0
## Cached once: tick() runs every physics frame.
var _block_filter: Callable = _is_block
## Seconds each body (instance id) has spent inside the capture volume.
var _hold_s: Dictionary = {}
## Set when spawned into a match world: the field then frees itself as soon as
## the match is no longer live (ended or restarted).
var bind_to_match: bool = false


func configure(effect: BlackHoleEffect, exclude: Array[RID]) -> void:
	_effect = effect
	_exclude = exclude


func age() -> float:
	return _age


func is_expired() -> bool:
	return _effect == null or _age >= _effect.lifetime_s


func _physics_process(delta: float) -> void:
	tick(delta)


func _is_block(body: RigidBody3D) -> bool:
	return body is Block


func _match_is_live() -> bool:
	var current: Match.State = Match.state()
	return current == Match.State.PLAYING or current == Match.State.SUDDEN_DEATH


## One simulation step; public so tests drive it without the physics loop.
func tick(delta: float) -> void:
	if _effect == null:
		queue_free()
		return
	if bind_to_match and not _match_is_live():
		queue_free()
		return
	_age += delta
	if is_expired():
		queue_free()
		return
	var world: World3D = get_world_3d()
	if world == null:
		return
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	# No capture callback: RadialPull's 3D core is too small for a pile (85.26).
	RadialPull.pull(space, global_position, _effect.pull, _exclude, _block_filter, delta)
	_sweep_capture(space, delta)


## Bontago-1pi.85.26: capture volume = horizontal radius + vertical band around the
## centre, so blocks piled in or above the core are removed, not only the first
## one touching a 0.8 m sphere. A body must stay inside capture_hold_s.
func _sweep_capture(space: PhysicsDirectSpaceState3D, delta: float) -> void:
	var reach: float = Vector2(_effect.capture_radius_m, _effect.capture_height_m).length()
	var inside: Dictionary = {}
	for body: RigidBody3D in ExplosionFx.query_bodies(space, global_position, reach, _exclude):
		if not _block_filter.call(body) or body.has_meta(RadialPull.CAPTURED_META):
			continue
		var offset: Vector3 = body.global_position - global_position
		if Vector2(offset.x, offset.z).length() > _effect.capture_radius_m:
			continue
		if absf(offset.y) > _effect.capture_height_m:
			continue
		var id: int = body.get_instance_id()
		inside[id] = true
		var held: float = float(_hold_s.get(id, 0.0)) + delta
		_hold_s[id] = held
		# A refused dissolve (no registry) leaves the block unmarked: retried next tick.
		if held >= _effect.capture_hold_s and _capture(body):
			body.set_meta(RadialPull.CAPTURED_META, true)
	# Forget bodies that left the volume or were freed.
	for id: int in _hold_s.keys():
		if not inside.has(id):
			_hold_s.erase(id)


## Captured blocks go through the territory holes' removal (shared entry, no
## duplicate removal code). DECISION: with no live registry (an isolated unit test)
## the block simply stays at the core.
func _capture(body: RigidBody3D) -> bool:
	return HoleDissolver.request_dissolve(body as Block)
