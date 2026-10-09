class_name GiftWirePhase
extends RefCounted
## The one numbering of a gift crate's wire phase (autoload decoupling S2a,
## STARTUP_COMPILE_PLAN B0a). Pure and dependency-free so net/MatchNet.gd and
## world code can name the phases without loading autoload/match/MatchGifts.gd.
## MatchGifts re-exports these constants, so existing callers are unchanged.

const FALLING: int = 0
const LANDED: int = 1
## Client-side wire-tracking only states (net/MatchNet.gd's own GiftWirePhase
## enum aliases these). Never stored in a crate.
const WIRE_LEGACY: int = 2
const WIRE_REMOVED: int = 3


static func is_valid_wire_phase(value: int) -> bool:
	return value >= FALLING and value <= WIRE_REMOVED
