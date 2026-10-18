class_name SpecialIds
extends RefCounted
## Gift/special ids shared by core rules and the match autoloads, so core/ need
## not name autoload/match/MatchGifts.

## Placeholder gift id handed out until a real weighted SpecialDef pick is
## installed; MatchGifts.PENDING_SPECIAL_ID aliases it.
const PENDING: StringName = &"special_pending"

## Meta set on an in-place activation anchor so an effect can tell it runs in place;
## MatchGiftActivation.IN_PLACE_META aliases it.
# DECISION: both meta ids live here so StackfallEffect reads them without naming
# the MatchGiftActivation autoload script.
const IN_PLACE_META: StringName = &"gift_in_place"
## Meta carrying a per-match activation counter (seeds Stackfall when net_id < 0);
## MatchGiftActivation.SEQ_META aliases it.
const ACTIVATION_SEQ_META: StringName = &"gift_in_place_seq"

## An in-place activation has no carrier block, so its special_triggered net id is this
## sentinel (the wire drops net_id < 0). It never exists in BlockRegistry.
## MatchGiftActivation.IN_PLACE_NET_ID aliases it.
const IN_PLACE_NET_ID: int = 2147483647
## The owner slot rides in the net id so clients can tint the effect without a wire change:
## slot n sends IN_PLACE_NET_ID - n (slot 0 is the plain sentinel).
const MAX_ENCODED_SLOTS: int = 64


## The special_triggered net id of an in-place activation by `slot_id`.
# DECISION: slot -1 clamps to slot 0 (plain sentinel); owner_slot is always valid today.
static func in_place_net_id(slot_id: int) -> int:
	return IN_PLACE_NET_ID - clampi(slot_id, 0, MAX_ENCODED_SLOTS - 1)


## The owner slot encoded in an in-place net id, or -1 when `net_id` is not one.
static func in_place_slot(net_id: int) -> int:
	var slot_id: int = IN_PLACE_NET_ID - net_id
	return slot_id if slot_id >= 0 and slot_id < MAX_ENCODED_SLOTS else -1
