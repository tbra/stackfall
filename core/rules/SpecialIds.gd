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
