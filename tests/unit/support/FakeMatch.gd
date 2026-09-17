class_name FakeMatch
extends RefCounted
## Test double for the Match autoload (docs/M2_PLAN.md P4).
##
## P2 owns autoload/Match.gd and hasn't landed its real implementation on
## this branch yet — it's still the M2-plan's typed stub, which always
## returns REASON_NO_BLOCK / Result.EMPTY and spawns nothing. PlayerController
## and HUD both read a `Variant` field (see their matching DECISION comments)
## instead of the global `Match` singleton so tests can swap in one of these
## and drive the documented contract (request_place, preview_placement, slot,
## held_shape, feed_progress, max_height_for_slot) exactly as P2's finished
## Match will answer it, without waiting on that package to land.

var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
## Where request_place() adds a Block when spawn_on_ok is true, mirroring
## what the real Match will eventually do via Match.register_world().
var spawn_parent: Node = null

var slots_by_id: Dictionary = {}
var held_shapes: Dictionary = {}
var next_shapes: Dictionary = {}
var feed_progress_by_slot: Dictionary = {}
var max_height_by_slot: Dictionary = {}

## What request_place() / preview_placement() return next; tests set these to
## drive VALID / OUTSIDE_TERRITORY / CONTESTED / HOLE / etc. scenarios.
var next_request_result: StringName = PlacementRules.REASON_OK
var next_preview_result: PlacementRules.Result = PlacementRules.Result.VALID
## Whether a REASON_OK request_place() should actually build and spawn a
## Block into spawn_parent. Tests that only care about call-counting (e.g.
## "exactly one request_place per ghost_place press") can leave this false.
var spawn_on_ok: bool = false

## Every call PlayerController/HUD made, in order, for assertions like
## "exactly one request_place per press".
var request_place_calls: Array[Dictionary] = []
var preview_placement_calls: Array[Dictionary] = []


func slot(slot_id: int) -> PlayerSlot:
	return slots_by_id.get(slot_id) as PlayerSlot


func held_shape(slot_id: int) -> BlockShape:
	return held_shapes.get(slot_id) as BlockShape


func next_shape(slot_id: int) -> BlockShape:
	return next_shapes.get(slot_id) as BlockShape


func feed_progress(slot_id: int) -> float:
	return float(feed_progress_by_slot.get(slot_id, 1.0))


func max_height_for_slot(slot_id: int) -> float:
	return float(max_height_by_slot.get(slot_id, 0.0))


func request_place(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion, auto_drop: bool
) -> StringName:
	request_place_calls.append({
		"slot_id": slot_id,
		"origin": origin,
		"orientation_index": orientation_index,
		"free_quat": free_quat,
		"auto_drop": auto_drop,
	})
	if next_request_result == PlacementRules.REASON_OK:
		if spawn_on_ok:
			_spawn(slot_id, origin, orientation_index, free_quat)
	else:
		Events.placement_rejected.emit(slot_id, next_request_result)
	return next_request_result


func preview_placement(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion
) -> PlacementRules.Result:
	preview_placement_calls.append({
		"slot_id": slot_id,
		"origin": origin,
		"orientation_index": orientation_index,
		"free_quat": free_quat,
	})
	return next_preview_result


func _spawn(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion) -> void:
	var shape: BlockShape = held_shape(slot_id)
	if shape == null or spawn_parent == null:
		return
	var block: Block = BlockFactory.build(shape, tuning)
	spawn_parent.add_child(block)
	block.global_position = origin
	block.global_transform.basis = Basis(free_quat) * BlockOrientations.get_basis(orientation_index)
	Events.block_placed.emit(block, shape.id)
