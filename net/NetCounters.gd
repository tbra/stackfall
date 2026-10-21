class_name NetCounters
extends RefCounted
## Every instrumentation counter MatchNet keeps, in one object: the per-slot intent identities
## the acceptance harness asserts on and the debug overlay shows, plus the test-only tallies that
## prove what the host did and did not put on the wire. Game code never reads the test-only ones.
## MatchNet owns one instance and keeps the public accessors (intents_sent(slot), ...) as
## forwarders, so NetDebugOverlay and MatchFingerprint read the same names as before.

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

# --- Per-match test tallies (cleared by reset()) -------------------------------

## to_state values replicated as EVENT_STATE_CHANGED, in order.
var replicated_state_changes: Array[int] = []
## How many times replicate_match_start() actually queued net_match_start.
var match_starts_replicated: int = 0
## net_ids the host decided to replicate a dissolve start for, in order.
var replicated_dissolve_starts: Array[int] = []

# --- Whole-session test tallies (not cleared per match) ------------------------

## Event name -> times it reached replicate_match_event() on the host.
var replicated_event_counts: Dictionary = {}
## peer_id -> placement_rejected replies addressed to it, and the latest one as
## [peer_id, slot_id, reason].
var reject_replies_by_peer: Dictionary = {}
var last_reject_reply: Array = []
## Host: replay-pending refusals.
var intents_refused_before_replay_ack: int = 0
## Impact replication: batches a client dropped as malformed, events it re-emitted, and
## events a well-formed batch carried that were not played.
var impact_batches_rejected: int = 0
var impacts_emitted: int = 0
var impact_events_dropped: int = 0


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


## Counts one event name reaching replicate_match_event().
func count_event(event: StringName) -> void:
	replicated_event_counts[event] = int(replicated_event_counts.get(event, 0)) + 1


## Notes a placement_rejected reply addressed to `peer_id`.
func note_reject_reply(peer_id: int, slot_id: int, reason: StringName) -> void:
	reject_replies_by_peer[peer_id] = int(reject_replies_by_peer.get(peer_id, 0)) + 1
	last_reject_reply = [peer_id, slot_id, reason]


## Clears the per-match counters (called when a match starts or ends). The whole-session
## tallies keep their values, as they did before the move.
func reset() -> void:
	sent.clear()
	accepted.clear()
	refused.clear()
	auto_drops.clear()
	cursors_refused.clear()
	replicated_state_changes.clear()
	match_starts_replicated = 0
	replicated_dissolve_starts.clear()


func _bump(counter: Dictionary, slot_id: int) -> void:
	counter[slot_id] = int(counter.get(slot_id, 0)) + 1
