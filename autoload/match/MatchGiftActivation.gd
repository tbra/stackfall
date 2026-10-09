class_name MatchGiftActivation
extends RefCounted
## Bontago-1pi.85.35 / 1pi.85.24 (docs/GIFT_PLAYTEST2_PLAN.md): host-side in-place gift
## activation. A gift whose SpecialDef.activates_in_place is true (Stackfall, Volcano,
## Earthquake) is activated at the release point without a falling carrier: a small
## invisible, non-colliding, frozen anchor Block carries the effect for as long as it runs
## and is freed when the SpecialBehavior completes. The anchor is never registered
## (no block_placed, no net_id, no replicate_spawn), so clients never see a body; the effect
## reaches them the same way as today, through Events.special_triggered (net_id IN_PLACE_NET_ID).

## Meta set on the anchor so an effect can tell it runs in place (StackfallEffect).
const IN_PLACE_META: StringName = SpecialIds.IN_PLACE_META
## Meta carrying a per-match activation counter (seeds Stackfall when net_id < 0).
const SEQ_META: StringName = SpecialIds.ACTIVATION_SEQ_META
## DECISION (1pi.85.24): the wire (MatchNet EVENT_SPECIAL_TRIGGERED, not owned by this package)
## drops net_id < 0, so an anchor-driven special_triggered carries this sentinel instead of -1.
## It never exists in BlockRegistry, so GiftFxPresenter resolves a null block (it tolerates one).
const IN_PLACE_NET_ID: int = 2147483647
const ANCHOR_FREEZE_REASON: StringName = &"gift_anchor"
const ANCHOR_NODE_NAME: String = "GiftAnchor"

var _match: MatchAutoload = null
var _special_tuning: SpecialTuning = null
var _anchors: Array[Block] = []
var _sequence: int = 0


func setup(match_ref: MatchAutoload) -> void:
	_match = match_ref
	# No linger after the effect ends: the anchor has no body worth showing.
	_special_tuning = (preload("res://config/special_tuning.tres") as SpecialTuning).duplicate() as SpecialTuning
	_special_tuning.gift_despawn_delay_s = 0.0


## Called by MatchPlacement.request_place after the valid-point check, only for a def with
## activates_in_place. `disk_origin` is the validated disk-local point (x, z). Returns true when
## the gift was activated (the caller then consumes the feed and returns REASON_OK); false leaves
## the normal carrier path untouched.
##
## DECISION (1pi.85.24, P0 review note): the hook skips _attach_pending_special and
## consume_glue_drop on purpose. This function pops the held gift itself (exactly once; the
## caller's _consume_and_refeed then refeeds the next piece). An in-place gift drops no block, so
## it neither bonds (a Glue charge is for a future BLOCK drop and stays banked) nor spends one.
func try_activate(slot_id: int, def: SpecialDef, disk_origin: Vector2) -> bool:
	if _match == null or def == null or not def.activates_in_place or def.effect == null:
		return false
	if not _match._is_host() or _match.state() != MatchAutoload.State.PLAYING:
		return false
	var field: Field = _match.field()
	if field == null or slot_id < 0 or slot_id >= _match.slot_count():
		return false
	if not disk_origin.is_finite() or _match.held_special(slot_id) != def.id:
		return false
	_prune_anchors()
	_match.pop_pending_special(slot_id)
	var anchor: Block = Block.new()
	anchor.name = ANCHOR_NODE_NAME
	anchor.owner_slot = slot_id
	anchor.shape_id = def.id
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	anchor.gravity_scale = 0.0
	anchor.set_meta(IN_PLACE_META, true)
	_sequence += 1
	anchor.set_meta(SEQ_META, _sequence)
	_match.add_child(anchor)
	anchor.global_position = field.world_from_disk_local(disk_origin, field.surface_y())
	# Frozen static and out of the awake set: no physics body, nothing for the settle loop.
	anchor.request_freeze_static(ANCHOR_FREEZE_REASON)
	_anchors.append(anchor)
	var behavior: SpecialBehavior = SpecialBehavior.new()
	anchor.add_child(behavior)
	behavior.bind(anchor, def, _special_tuning)
	behavior.despawn_when_done = true
	behavior.triggered.connect(_on_triggered.bind(anchor))
	behavior.completed.connect(_on_completed)
	# First tick now: arms (arm_delay 0) and lets an instant effect (Volcano) fire at once.
	behavior.advance(0.0)
	return true


## Frees every live anchor (match reset / teardown). The SpecialBehavior backstop
## (gift_max_lifetime_s) frees a stray one anyway.
func clear() -> void:
	for anchor: Block in _anchors:
		if is_instance_valid(anchor) and not anchor.is_queued_for_deletion():
			anchor.queue_free()
	_anchors.clear()
	_sequence = 0


func live_anchor_count() -> int:
	_prune_anchors()
	return _anchors.size()


func _on_triggered(def_id: StringName, position: Vector3, chain_depth: int, anchor: Block) -> void:
	Events.special_triggered.emit(IN_PLACE_NET_ID, def_id, position, chain_depth)
	# The action is over when trigger() returns (SpecialBehavior DECISION, t8x.5): free now.
	_on_completed(anchor)


## No block_removed: the anchor was never registered, so nothing else knows it.
func _on_completed(block: Block) -> void:
	_anchors.erase(block)
	if block != null and is_instance_valid(block) and not block.is_queued_for_deletion():
		block.queue_free()


func _prune_anchors() -> void:
	var live: Array[Block] = []
	for anchor: Block in _anchors:
		if is_instance_valid(anchor) and not anchor.is_queued_for_deletion():
			live.append(anchor)
	_anchors = live
