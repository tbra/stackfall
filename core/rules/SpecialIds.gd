class_name SpecialIds
extends RefCounted
## Gift/special ids shared by core rules and the match autoloads, so core/ need
## not name autoload/match/MatchGifts (layer audit, Bontago-1pi.11.75).

## Placeholder gift id handed out until a real weighted SpecialDef pick is
## installed; MatchGifts.PENDING_SPECIAL_ID aliases it.
const PENDING: StringName = &"special_pending"
