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
## Cached once: passed to RadialPull every tick.
var _capture_callable: Callable = _capture
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
	RadialPull.pull(
		world.direct_space_state, global_position, _effect.pull, _exclude, _block_filter, delta,
		_capture_callable
	)


## Captured blocks go through the territory holes' removal (shared entry, no
## duplicate removal code). DECISION: with no live registry (an isolated unit test)
## the block simply stays at the core.
func _capture(body: RigidBody3D) -> bool:
	return HoleDissolver.request_dissolve(body as Block)
