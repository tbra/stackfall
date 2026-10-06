class_name MatchGiftActivation
extends RefCounted
## Bontago-1pi.85.35 (docs/GIFT_PLAYTEST2_PLAN.md, P0 contract): host-side in-place gift
## activation. A gift whose SpecialDef.activates_in_place is true is activated at the cursor
## surface point on release, without a physical carrier body. Package PB implements it; this
## stub activates nothing so every gift keeps its falling carrier.

var _match: MatchAutoload = null


func setup(match_ref: MatchAutoload) -> void:
	_match = match_ref


## Called by MatchPlacement.request_place after the valid-point check, only for a def with
## activates_in_place. `disk_origin` is the validated disk-local point (x, z). Returns true when
## the gift was activated (the caller then consumes the feed and returns REASON_OK); false leaves
## the normal carrier path untouched. Stub: returns false.
func try_activate(_slot_id: int, _def: SpecialDef, _disk_origin: Vector2) -> bool:
	return false
