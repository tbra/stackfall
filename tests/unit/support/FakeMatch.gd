class_name FakeMatch
extends RefCounted
## Test double for the Match autoload (docs/M2_PLAN.md P4).
##
## autoload/Match.gd has since landed for real, but this fake still exists to
## isolate the P4 controller/HUD unit tests from it: the real Match drives
## territory solving and feed timing on its own clock, which would make those
## tests slow and order-dependent for no benefit, since all they need is a
## scripted answer to a handful of calls. PlayerController and HUD both read
## a `Variant` field (see their matching DECISION comments) instead of the
## global `Match` singleton so tests can swap in one of these and drive the
## documented contract (request_place, preview_placement, slot, held_shape,
## feed_progress, max_height_for_slot) directly, one call at a time.
## tests/bench/m2_acceptance.gd provides the integration coverage against the
## real Match that this fake deliberately doesn't attempt.

var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
## Where request_place() adds a Block when spawn_on_ok is true, mirroring
## what the real Match will eventually do via Match.register_world().
var spawn_parent: Node = null

## Bontago-mv0.9: mirrors the real Match's public `config` field (null until
## a match starts). ui/HUD.gd reads `match_provider.config.hot_seat` to gate
## its "Player N's turn" wording; tests that care set this to a MatchConfig
## with hot_seat true/false, everything else leaves it null (real-time
## behaviour, matching the real autoload before start_match()).
var config: MatchConfig = null

var slots_by_id: Dictionary = {}
var held_shapes: Dictionary = {}
var next_shapes: Dictionary = {}
var feed_progress_by_slot: Dictionary = {}
var max_height_by_slot: Dictionary = {}
var feed_seq_by_slot: Dictionary = {}

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


## M3a: the sequence an intent must quote. The fake hands out a fixed value
## per slot; nothing that uses this double cares what it is, only that the
## call exists.
func feed_seq(slot_id: int) -> int:
	return int(feed_seq_by_slot.get(slot_id, 0))


## Bontago-mv0.10 (spec 2.4 "[ORIGINAL target]" cadence): game/PlayerController.
## gd's _update_ghost_tint() calls this every frame regardless of which Match
## it is bound to (see its own DECISION on the Variant seam), so this fake
## needs the method to exist even though none of the P4 controller/HUD tests
## that use it are about the interval lock. Always false: nothing sets it,
## so a ghost driven by this fake is never shown locked.
var release_locked_by_slot: Dictionary = {}


func is_release_locked(slot_id: int) -> bool:
	return bool(release_locked_by_slot.get(slot_id, false))


## Bontago-1en.16: ui/HUD.gd's _process() polls these every frame regardless
## of which double it is bound to (same reasoning as is_release_locked's own
## comment above) -- test_hud.gd's other _process() tests use this fake
## without caring about specials, so both default to "nothing pending"
## rather than requiring every caller to populate them.
var pending_special_count_by_slot: Dictionary = {}
var held_special_by_slot: Dictionary = {}


func pending_special_count(slot_id: int) -> int:
	return int(pending_special_count_by_slot.get(slot_id, 0))


func held_special(slot_id: int) -> StringName:
	return held_special_by_slot.get(slot_id, &"") as StringName


## M3a adds the trailing feed_seq the real Match takes (docs/M3a_PLAN.md,
## "Never duplicated, never lost"). It is defaulted here exactly as it is
## there, so every M2 call site and every M2 test still compiles unchanged;
## the fake records it but never enforces it, since idempotence is the real
## Match's job and tests/unit/test_match_net.gd is where it is proved.
func request_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq: int = -1
) -> StringName:
	request_place_calls.append({
		"slot_id": slot_id,
		"origin": origin,
		"orientation_index": orientation_index,
		"free_quat": free_quat,
		"auto_drop": auto_drop,
		"feed_seq": feed_seq,
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
