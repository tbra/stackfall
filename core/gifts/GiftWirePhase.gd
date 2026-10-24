class_name GiftWirePhase
extends RefCounted
## The one numbering of a gift crate's wire phase. Pure and dependency-free so net/MatchNet.gd and
## world code can name the phases without loading autoload/match/MatchGifts.gd.
## MatchGifts re-exports these constants, so existing callers are unchanged.

const FALLING: int = 0
const LANDED: int = 1
## Client-side wire-tracking only states (net/match/GiftWireGuard.gd). Never stored in a crate.
const WIRE_SPAWN_ONLY: int = 2
const WIRE_REMOVED: int = 3

