class_name NetCounters
extends RefCounted
## Every instrumentation counter MatchNet keeps, in one object: the per-slot intent identities
## the acceptance harness asserts on and the debug overlay shows.
## MatchNet owns one instance (MatchNet.counters); readers use its *_count(slot) accessors.

# --- Per-slot intent identities (host) ----------------------------------------

## Deliberate placement/throw intents received (host) or sent (client), per slot.
var sent: Dictionary = {}
var accepted: Dictionary = {}
var refused: Dictionary = {}
## Auto-drops are not intents (they never cross the wire), so they are counted apart.
var auto_drops: Dictionary = {}
## Cursor updates the host dropped as malformed. Not an intent, so not part of the
## sent == accepted + refused identity.
var cursors_refused: Dictionary = {}

func count_sent(slot_id: int) -> void:
	_bump(sent, slot_id)


func count_accepted(slot_id: int) -> void:
	_bump(accepted, slot_id)


func count_refused(slot_id: int) -> void:
	_bump(refused, slot_id)


func count_auto_drop(slot_id: int) -> void:
	_bump(auto_drops, slot_id)


func count_cursor_refused(slot_id: int) -> void:
	_bump(cursors_refused, slot_id)


func sent_count(slot_id: int) -> int:
	return int(sent.get(slot_id, 0))


func accepted_count(slot_id: int) -> int:
	return int(accepted.get(slot_id, 0))


func refused_count(slot_id: int) -> int:
	return int(refused.get(slot_id, 0))


func cursors_refused_count(slot_id: int) -> int:
	return int(cursors_refused.get(slot_id, 0))


## Clears the per-match counters (called when a match starts or ends).
func reset() -> void:
	sent.clear()
	accepted.clear()
	refused.clear()
	auto_drops.clear()
	cursors_refused.clear()


func _bump(counter: Dictionary, slot_id: int) -> void:
	counter[slot_id] = int(counter.get(slot_id, 0)) + 1
