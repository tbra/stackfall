class_name PeerFloodGate
extends RefCounted
## One TokenBucket per peer per intent. Over-limit calls are dropped silently and
## counted: no refusal reply (a reply is itself an amplification) and no kick.
## An intent with no entry in the limits table is never limited.

var _limits: Dictionary = {}
## peer_id -> { intent: StringName -> TokenBucket }
var _buckets: Dictionary = {}
## peer_id -> { intent: StringName -> int }
var _dropped: Dictionary = {}


## `limits`: StringName intent -> Vector2(burst, refill_per_s).
func _init(limits: Dictionary) -> void:
	_limits = limits.duplicate()


## True when `peer_id` may send `intent` at `now_s`; a false result is counted in dropped().
func allow(peer_id: int, intent: StringName, now_s: float) -> bool:
	var limit: Variant = _limits.get(intent)
	if typeof(limit) != TYPE_VECTOR2:
		return true
	var burst_and_refill: Vector2 = limit as Vector2
	var by_intent: Dictionary = _buckets.get(peer_id, {}) as Dictionary
	var bucket: TokenBucket = by_intent.get(intent) as TokenBucket
	if bucket == null:
		bucket = TokenBucket.new()
		by_intent[intent] = bucket
		_buckets[peer_id] = by_intent
	if bucket.take(now_s, roundi(burst_and_refill.x), burst_and_refill.y):
		return true
	var counts: Dictionary = _dropped.get(peer_id, {}) as Dictionary
	counts[intent] = int(counts.get(intent, 0)) + 1
	_dropped[peer_id] = counts
	return false


## Called on leave/kick so a rejoin starts with full buckets.
# DECISION: the peer's drop counters go with its buckets, so the table cannot grow
# without bound over a long session and a reused peer id starts clean.
func forget_peer(peer_id: int) -> void:
	_buckets.erase(peer_id)
	_dropped.erase(peer_id)


## Calls dropped for `peer_id` on `intent` since it joined (tests, NetDebugOverlay).
func dropped(peer_id: int, intent: StringName) -> int:
	var counts: Dictionary = _dropped.get(peer_id, {}) as Dictionary
	return int(counts.get(intent, 0))
