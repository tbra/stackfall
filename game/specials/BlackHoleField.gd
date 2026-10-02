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
	var hits: Array[RigidBody3D] = SpecialPhysics.query_bodies_in_range(
		world.direct_space_state, global_position, _effect.pull_radius_m, _exclude,
		_block_filter
	)
	for body: RigidBody3D in hits:
		var offset: Vector3 = global_position - body.global_position
		var distance: float = offset.length()
		if _effect.consume_blocks and distance <= _effect.core_radius_m:
			_consume(body as Block)
			continue
		if distance <= 0.0001:
			continue
		var ratio: float = clampf(distance / _effect.pull_radius_m, 0.0, 1.0)
		var falloff: float = pow(1.0 - ratio, _effect.falloff_exponent)
		var force: float = minf(_effect.pull_acceleration * body.mass * falloff, _effect.max_pull_force)
		SpecialPhysics.wake_and_impulse(body, offset / distance * force * delta)


## Same removal path as a completed gift (autoload/match/MatchPlacement.gd
## _on_gift_completed): the bus drops it from the registry and replicates.
func _consume(block: Block) -> void:
	if block == null or block.is_queued_for_deletion():
		return
	Events.block_removed.emit(block, String(Events.REASON_GIFT_DESPAWN))
	block.queue_free()
