class_name CatSession
extends RefCounted
## The one running Cat activation (host simulation or client replica) for a match.

var _match: MatchAutoload = null
var _parent: Node = null
var _cat: RigidBody3D = null  # a CatController, loaded late (LateScripts)
var _serial: int = 0


## `parent` is where the cat body is added.
func setup(match_ref: MatchAutoload, parent: Node) -> void:
	_match = match_ref
	_parent = parent


## The running cat body, or null.
func active() -> RigidBody3D:
	return _cat if is_instance_valid(_cat) else null


## Host: starts a cat for `owner_slot` at `position`; false when refused.
func start(owner_slot: int, position: Vector3, effect: Resource) -> bool:
	if not _match._is_host() or _match.state() != MatchAutoload.State.PLAYING 			or effect == null or _match.field() == null:
		return false
	if owner_slot < 0 or owner_slot >= _match.slot_count() or not position.is_finite():
		return false
	var blocks: Node3D = _match.blocks_parent()
	if blocks == null or blocks.get_child_count() >= effect.max_active_blocks:
		return false
	var field: FieldBody = _match.field()
	var point: Vector2 = field.disk_local_from_world(position)
	if not field.map_def.shape_contains(point):
		return false
	if active() != null:
		end(_cat.activation_id)
	_serial += 1
	_cat = LateScripts.script(LateScripts.CAT_CONTROLLER).new()
	_cat.configure(_serial, owner_slot,
		field.world_from_disk_local(point, effect.body_radius_m),
		effect.duration_s, effect.speed_mps, effect.target_range_m,
		effect.body_radius_m, effect.push_impulse, true)
	_parent.add_child(_cat)
	Events.cat_started.emit(_serial, owner_slot, _cat.global_position, effect.duration_s)
	return true


## Host: points the cat of `slot_id` at `point`; false when refused.
func set_target(slot_id: int, point: Vector3) -> bool:
	var cat: RigidBody3D = active()
	if not _match._is_host() or cat == null or cat.owner_slot != slot_id 			or not MatchAutoload.is_live(_match.state()):
		return false
	return cat.set_target(point)


## Client: starts the replica of activation `id`; false when refused.
func apply_replicated_start(id: int, slot_id: int, position: Vector3, duration: float) -> bool:
	if _match._is_host() or id <= _serial or slot_id < 0 or slot_id >= _match.slot_count():
		return false
	if not position.is_finite() or not is_finite(duration) or duration <= 0.0:
		return false
	if active() != null:
		_cat.queue_free()
	_serial = id
	# DECISION: the cat's SpecialDef is read dynamically so Match does not name SpecialDef/CatEffect.
	var cat_def: Resource = load(LateScripts.CAT_RESOURCE) as Resource
	var effect: Resource = cat_def.get(&"effect") as Resource
	_cat = LateScripts.script(LateScripts.CAT_CONTROLLER).new()
	_cat.configure(id, slot_id, position, duration, effect.speed_mps,
		effect.target_range_m, effect.body_radius_m, effect.push_impulse, false)
	_parent.add_child(_cat)
	Events.cat_started.emit(id, slot_id, position, duration)
	return true


## Client: applies a snapshot of activation `id`.
func apply_replicated_state(
	id: int, position: Vector3, velocity: Vector3, point: Vector3, remaining: float
) -> void:
	var cat: RigidBody3D = active()
	if not _match._is_host() and cat != null and cat.activation_id == id and is_finite(remaining):
		cat.apply_snapshot(position, velocity, point, remaining)


## Ends activation `id`; a different id is a no-op.
func end(id: int) -> void:
	var cat: RigidBody3D = active()
	if cat == null or cat.activation_id != id:
		return
	cat.queue_free()
	_cat = null
	Events.cat_ended.emit(id)


## Ends the active cat and restarts the activation serial.
func reset() -> void:
	var cat: RigidBody3D = active()
	if cat != null:
		end(cat.activation_id)
	_serial = 0
