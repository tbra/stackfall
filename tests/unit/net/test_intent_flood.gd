extends GutTest
## MatchIntentGateway's per-peer flood buckets (place, throw, cursor, cat target, gift slot, replay,
## return) with a synthetic clock and a spy Match: every bucket has an honest-client run (the real
## client send pattern, zero drops) and a flood run (3x the burst back to back: exactly `burst`
## pass, the rest are dropped, no Match call, no reply, no rebroadcast; a second peer is
## unaffected; one refill interval lets one more through). Decision: a flooder is dropped, never
## kicked.

const HOST_PEER: int = 1
const CLIENT_PEER: int = 2
const CLIENT_SLOT: int = 1
const OTHER_PEER: int = 3
const OTHER_SLOT: int = 2
const POSE_ORIGIN: Vector3 = Vector3(0.0, 1.0, 0.0)
const FLOOD_FACTOR: int = 3
const SIM_SECONDS: float = 10.0
const FRAME_S: float = 1.0 / 60.0
const EPSILON_S: float = 0.0001


## A Match stand-in that answers the gateway's port subset and records every call.
class SpyMatch extends RefCounted:
	var config: MatchConfig = null
	var phase: int = MatchPhase.State.PLAYING
	var place_reason: StringName = PlacementRules.REASON_NO_BLOCK
	var pose_ok: bool = true
	var place_calls: int = 0
	var throw_calls: int = 0
	var gift_calls: int = 0
	var cat_calls: int = 0
	var start_calls: int = 0
	var abort_calls: int = 0
	var aim_calls: int = 0
	var on_place: Callable = Callable()

	func state() -> int:
		return phase

	func request_place(_slot: int, _origin: Vector3, _orient: int, _quat: Quaternion, _auto: bool, _seq: int) -> StringName:
		place_calls += 1
		if on_place.is_valid():
			on_place.call()
		return place_reason

	func request_throw(_slot: int, _origin: Vector3, _orient: int, _quat: Quaternion, _vel: Vector3, _seq: int) -> StringName:
		throw_calls += 1
		return place_reason

	func request_use_gift_slot(_slot: int) -> bool:
		gift_calls += 1
		return true

	func set_cat_target(_slot: int, _point: Vector3) -> bool:
		cat_calls += 1
		return true

	func is_pose_well_formed(_origin: Vector3, _orient: int, _quat: Quaternion) -> bool:
		return pose_ok

	func note_aim(_slot: int, _aim: Vector3) -> void:
		aim_calls += 1

	func abort_match() -> void:
		abort_calls += 1

	func start_match(_config: MatchConfig) -> void:
		start_calls += 1


## One gateway wired to spies and a clock the test advances by hand.
class Rig extends RefCounted:
	var net: FakeNet
	var spy: SpyMatch = SpyMatch.new()
	var counters: NetCounters = NetCounters.new()
	var gateway: MatchIntentGateway
	var now: float = 0.0
	var to_peer: Array[Array] = []
	var to_host: Array[Array] = []
	var broadcasts: Array[Array] = []
	var stored_cursors: int = 0
	var cursor_events: int = 0
	var replay_pending: Dictionary = {}

	func _init(session: FakeNet, config: NetConfig) -> void:
		net = session
		spy.config = MatchConfig.new()
		var seams: MatchIntentGateway.Seams = MatchIntentGateway.Seams.new()
		seams.can_send = _can_send
		seams.send_to_host = _send_to_host
		seams.send_to_peer = _send_to_peer
		seams.broadcast = _broadcast
		seams.now_s = _now
		seams.is_replay_pending = _pending
		seams.store_cursor = _store_cursor
		gateway = MatchIntentGateway.new(net, spy, config, counters, seams)
		Events.remote_cursor_updated.connect(_on_cursor_event)

	func close() -> void:
		if Events.remote_cursor_updated.is_connected(_on_cursor_event):
			Events.remote_cursor_updated.disconnect(_on_cursor_event)

	func _on_cursor_event(_slot: int, _origin: Vector3, _orient: int, _quat: Quaternion) -> void:
		cursor_events += 1

	func _can_send() -> bool:
		return true

	func _send_to_host(method: StringName, args: Array) -> void:
		to_host.append([method, args])

	func _send_to_peer(peer_id: int, method: StringName, args: Array) -> bool:
		to_peer.append([peer_id, method, args])
		return true

	func _broadcast(method: StringName, args: Array) -> void:
		broadcasts.append([method, args])

	func _now() -> float:
		return now

	func _pending(peer_id: int) -> bool:
		return replay_pending.has(peer_id)

	func _store_cursor(_slot: int, _origin: Vector3, _orient: int, _quat: Quaternion) -> void:
		stored_cursors += 1


var _config: NetConfig = preload("res://config/net/net_config.tres")
var _rigs: Array[Rig] = []


func after_each() -> void:
	for rig: Rig in _rigs:
		rig.close()
	_rigs.clear()


func _host_rig() -> Rig:
	var net: FakeNet = FakeNet.host({HOST_PEER: 0, CLIENT_PEER: CLIENT_SLOT, OTHER_PEER: OTHER_SLOT}, [0])
	var rig: Rig = Rig.new(net, _config)
	_rigs.append(rig)
	return rig


func _client_rig() -> Rig:
	var rig: Rig = Rig.new(FakeNet.client(CLIENT_SLOT), _config)
	_rigs.append(rig)
	return rig


func _place(rig: Rig, peer: int = CLIENT_PEER, slot: int = CLIENT_SLOT) -> void:
	rig.gateway.handle_place(peer, slot, POSE_ORIGIN, 0, Quaternion.IDENTITY, 0)


func _throw(rig: Rig, peer: int = CLIENT_PEER, slot: int = CLIENT_SLOT) -> void:
	rig.gateway.handle_throw(peer, slot, POSE_ORIGIN, 0, Quaternion.IDENTITY, Vector3.FORWARD, 0)


func _cursor(rig: Rig, peer: int = CLIENT_PEER, slot: int = CLIENT_SLOT) -> void:
	rig.gateway.handle_cursor(peer, slot, POSE_ORIGIN, 0, Quaternion.IDENTITY)


func _cat(rig: Rig, peer: int = CLIENT_PEER, slot: int = CLIENT_SLOT) -> void:
	rig.gateway.handle_cat_target(peer, slot, Vector3.RIGHT)


func _gift(rig: Rig, peer: int = CLIENT_PEER, slot: int = CLIENT_SLOT) -> void:
	rig.gateway.handle_gift_slot(peer, slot)


func _replay(rig: Rig, peer: int = CLIENT_PEER, _slot: int = CLIENT_SLOT) -> void:
	rig.gateway.handle_replay_request(peer)


func _return(rig: Rig, peer: int = CLIENT_PEER, _slot: int = CLIENT_SLOT) -> void:
	rig.gateway.handle_return_request(peer)


## Row of the NetConfig-derived limits for `intent`: Vector2(burst, refill_per_s).
func _limit(intent: StringName) -> Vector2:
	return FloodLimits.from_config(_config)[intent] as Vector2


## Honest play: `per_second` calls spread evenly over SIM_SECONDS from one peer.
func _run_honest(rig: Rig, send: Callable, per_second: float) -> int:
	var sent: int = 0
	var step: float = 1.0 / per_second
	var t: float = 0.0
	while t < SIM_SECONDS:
		rig.now = t
		send.call(rig)
		sent += 1
		t += step
	return sent


## 3x burst back to back from the client, the same instant. Returns nothing; callers assert.
func _flood(rig: Rig, send: Callable, intent: StringName) -> void:
	var burst: int = roundi(_limit(intent).x)
	rig.now = 5.0
	for _i: int in range(FLOOD_FACTOR * burst):
		send.call(rig)


func _assert_isolated_and_refills(rig: Rig, send: Callable, intent: StringName, passes: Callable) -> void:
	var burst: int = roundi(_limit(intent).x)
	var refill: float = _limit(intent).y
	assert_eq(int(passes.call(rig)), burst, "%s: exactly the burst got through, the excess was dropped" % intent)
	var before: int = int(passes.call(rig))
	send.call(rig, OTHER_PEER, OTHER_SLOT)
	assert_eq(int(passes.call(rig)), before + 1, "%s: a second peer is unaffected by the flooder" % intent)
	before = int(passes.call(rig))
	send.call(rig)
	assert_eq(int(passes.call(rig)), before, "%s: still drained right after the flood" % intent)
	rig.now += 1.0 / refill + EPSILON_S
	send.call(rig)
	assert_eq(int(passes.call(rig)), before + 1, "%s: one refill interval lets one more through" % intent)
	assert_eq(rig.net.kick_peer_calls.size(), 0, "%s: a flooder is dropped, never kicked" % intent)


# --- place ------------------------------------------------------------------------------------

func test_place_honest_client_is_never_dropped() -> void:
	var rig: Rig = _host_rig()
	var sent: int = _run_honest(rig, _place, 2.0)
	assert_eq(rig.spy.place_calls, sent)


func test_place_flood_passes_exactly_the_burst_and_sends_no_reply_for_the_rest() -> void:
	var rig: Rig = _host_rig()
	var burst: int = roundi(_limit(FloodLimits.INTENT_PLACE).x)
	_flood(rig, _place, FloodLimits.INTENT_PLACE)
	assert_eq(rig.spy.place_calls, burst, "exactly the burst reaches Match")
	# Every passing call is refused by the spy (REASON_NO_BLOCK) and answered once; a dropped call
	# is not answered at all, so replies == burst rather than 3 * burst.
	assert_eq(rig.to_peer.size(), burst, "no refusal reply for a flooded call")
	assert_eq(rig.counters.sent_count(CLIENT_SLOT), burst, "a flooded call is not counted as an intent")
	_assert_isolated_and_refills(rig, _place, FloodLimits.INTENT_PLACE, func(r: Rig) -> int: return r.spy.place_calls)


# --- throw ------------------------------------------------------------------------------------

func test_throw_honest_client_is_never_dropped() -> void:
	var rig: Rig = _host_rig()
	var sent: int = _run_honest(rig, _throw, 2.0)
	assert_eq(rig.spy.throw_calls, sent)


func test_throw_flood_passes_exactly_the_burst_and_sends_no_reply_for_the_rest() -> void:
	var rig: Rig = _host_rig()
	var burst: int = roundi(_limit(FloodLimits.INTENT_THROW).x)
	_flood(rig, _throw, FloodLimits.INTENT_THROW)
	assert_eq(rig.spy.throw_calls, burst)
	assert_eq(rig.to_peer.size(), burst, "no refusal reply for a flooded call")
	_assert_isolated_and_refills(rig, _throw, FloodLimits.INTENT_THROW, func(r: Rig) -> int: return r.spy.throw_calls)


# --- gift slot --------------------------------------------------------------------------------

func test_gift_slot_honest_client_is_never_dropped() -> void:
	var rig: Rig = _host_rig()
	var sent: int = _run_honest(rig, _gift, 1.0)
	assert_eq(rig.spy.gift_calls, sent)


func test_gift_slot_flood_passes_exactly_the_burst() -> void:
	var rig: Rig = _host_rig()
	var burst: int = roundi(_limit(FloodLimits.INTENT_GIFT_SLOT).x)
	_flood(rig, _gift, FloodLimits.INTENT_GIFT_SLOT)
	assert_eq(rig.spy.gift_calls, burst)
	assert_eq(rig.to_peer.size(), 0)
	_assert_isolated_and_refills(rig, _gift, FloodLimits.INTENT_GIFT_SLOT, func(r: Rig) -> int: return r.spy.gift_calls)


# --- cursor -----------------------------------------------------------------------------------

func test_cursor_honest_client_with_the_real_throttle_is_never_dropped() -> void:
	var host: Rig = _host_rig()
	var client: Rig = _client_rig()
	var frames: int = int(SIM_SECONDS / FRAME_S)
	var delivered: int = 0
	for frame: int in range(frames):
		client.now = float(frame) * FRAME_S + 1.0
		client.gateway.submit_cursor(CLIENT_SLOT, POSE_ORIGIN, 0, Quaternion.IDENTITY)
		host.now = client.now
		for sent: Array in client.to_host:
			assert_eq(sent[0], MatchIntentGateway.RPC_CURSOR)
			var args: Array = sent[1]
			host.gateway.handle_cursor(CLIENT_PEER, args[0], args[1], args[2], args[3], args[4])
			delivered += 1
		client.to_host.clear()
	var expected: int = int(SIM_SECONDS * _config.cursor_hz)
	assert_gte(host.stored_cursors, int(float(expected) * 0.8), "the client really sent at cursor_hz")
	assert_eq(host.stored_cursors, delivered, "an honest client loses no cursor")
	assert_eq(host.cursor_events, delivered, "and the ghost saw every one")
	assert_eq(host.broadcasts.size(), host.stored_cursors, "every accepted cursor is rebroadcast once")


func test_cursor_flood_drops_the_excess_without_a_rebroadcast() -> void:
	var rig: Rig = _host_rig()
	var burst: int = roundi(_limit(FloodLimits.INTENT_CURSOR).x)
	_flood(rig, _cursor, FloodLimits.INTENT_CURSOR)
	assert_eq(rig.stored_cursors, burst, "exactly the burst is stored")
	assert_eq(rig.cursor_events, burst, "and only the burst reaches the ghost")
	assert_eq(rig.broadcasts.size(), burst, "the host rebroadcasts only what it accepted")
	assert_eq(rig.to_peer.size(), 0, "a cursor never gets a reply")
	_assert_isolated_and_refills(rig, _cursor, FloodLimits.INTENT_CURSOR, func(r: Rig) -> int: return r.stored_cursors)


func test_cursor_lag_bunching_one_second_of_honest_cursors_all_pass_then_a_flood_is_clipped() -> void:
	var host: Rig = _host_rig()
	var client: Rig = _client_rig()
	# A steady honest second first, delivered live, so the bucket is in its steady state.
	var steady_end: float = 1.0
	var frame: int = 0
	while float(frame) * FRAME_S < steady_end:
		client.now = float(frame) * FRAME_S + 1.0
		client.gateway.submit_cursor(CLIENT_SLOT, POSE_ORIGIN, 0, Quaternion.IDENTITY)
		host.now = client.now
		for sent: Array in client.to_host:
			var a: Array = sent[1]
			host.gateway.handle_cursor(CLIENT_PEER, a[0], a[1], a[2], a[3], a[4])
		client.to_host.clear()
		frame += 1
	var live_stored: int = host.stored_cursors
	# The link stalls for one second: the client keeps sending, nothing is delivered.
	var stall_start: int = frame
	while float(frame - stall_start) * FRAME_S < 1.0:
		client.now = float(frame) * FRAME_S + 1.0
		client.gateway.submit_cursor(CLIENT_SLOT, POSE_ORIGIN, 0, Quaternion.IDENTITY)
		frame += 1
	var bunched: Array[Array] = client.to_host.duplicate()
	assert_gte(bunched.size(), int(_config.cursor_hz * 0.7), "a second of honest cursors queued behind the stall")
	assert_lt(bunched.size(), roundi(_limit(FloodLimits.INTENT_CURSOR).x), "and it fits the default burst")
	# The stall ends: all of it arrives in the same frame.
	host.now = float(frame) * FRAME_S + 1.0
	for sent: Array in bunched:
		var b: Array = sent[1]
		host.gateway.handle_cursor(CLIENT_PEER, b[0], b[1], b[2], b[3], b[4])
	assert_eq(host.stored_cursors, live_stored + bunched.size(), "every bunched honest cursor passes")
	# A 3x-burst flood in the same frame then loses the excess.
	var burst: int = roundi(_limit(FloodLimits.INTENT_CURSOR).x)
	var before: int = host.stored_cursors
	for _i: int in range(FLOOD_FACTOR * burst):
		_cursor(host)
	assert_lte(host.stored_cursors - before, burst, "no more than a bucket's worth gets through")
	assert_eq(host.cursor_events, host.stored_cursors, "the ghost saw exactly what was stored")


# --- cat target -------------------------------------------------------------------------------

func test_cat_target_honest_client_with_the_real_throttle_is_never_dropped() -> void:
	var host: Rig = _host_rig()
	var client: Rig = _client_rig()
	var frames: int = int(SIM_SECONDS / FRAME_S)
	var delivered: int = 0
	for frame: int in range(frames):
		client.now = float(frame) * FRAME_S + 1.0
		client.gateway.submit_cat_target(CLIENT_SLOT, Vector3(float(frame), 0.0, 0.0))
		host.now = client.now
		for sent: Array in client.to_host:
			assert_eq(sent[0], MatchIntentGateway.RPC_CAT_TARGET)
			var args: Array = sent[1]
			host.gateway.handle_cat_target(CLIENT_PEER, args[0], args[1])
			delivered += 1
		client.to_host.clear()
	assert_gte(host.spy.cat_calls, int(SIM_SECONDS * _config.cursor_hz * 0.8), "the client really sent at cursor_hz")
	assert_eq(host.spy.cat_calls, delivered, "an honest client loses no cat target")


func test_cat_target_flood_passes_exactly_the_burst() -> void:
	var rig: Rig = _host_rig()
	var burst: int = roundi(_limit(FloodLimits.INTENT_CAT_TARGET).x)
	_flood(rig, _cat, FloodLimits.INTENT_CAT_TARGET)
	assert_eq(rig.spy.cat_calls, burst)
	assert_eq(rig.to_peer.size(), 0)
	_assert_isolated_and_refills(rig, _cat, FloodLimits.INTENT_CAT_TARGET, func(r: Rig) -> int: return r.spy.cat_calls)


func test_cat_target_lag_bunching_one_second_passes_then_a_flood_is_clipped() -> void:
	var host: Rig = _host_rig()
	var client: Rig = _client_rig()
	var frame: int = 0
	while float(frame) * FRAME_S < 1.0:
		client.now = float(frame) * FRAME_S + 1.0
		client.gateway.submit_cat_target(CLIENT_SLOT, Vector3.RIGHT)
		host.now = client.now
		for sent: Array in client.to_host:
			var a: Array = sent[1]
			host.gateway.handle_cat_target(CLIENT_PEER, a[0], a[1])
		client.to_host.clear()
		frame += 1
	var live_calls: int = host.spy.cat_calls
	var stall_start: int = frame
	while float(frame - stall_start) * FRAME_S < 1.0:
		client.now = float(frame) * FRAME_S + 1.0
		client.gateway.submit_cat_target(CLIENT_SLOT, Vector3.RIGHT)
		frame += 1
	var bunched: Array[Array] = client.to_host.duplicate()
	assert_gte(bunched.size(), int(_config.cursor_hz * 0.7))
	assert_lt(bunched.size(), roundi(_limit(FloodLimits.INTENT_CAT_TARGET).x))
	host.now = float(frame) * FRAME_S + 1.0
	for sent: Array in bunched:
		var b: Array = sent[1]
		host.gateway.handle_cat_target(CLIENT_PEER, b[0], b[1])
	assert_eq(host.spy.cat_calls, live_calls + bunched.size(), "every bunched honest cat target passes")
	var burst: int = roundi(_limit(FloodLimits.INTENT_CAT_TARGET).x)
	var before: int = host.spy.cat_calls
	for _i: int in range(FLOOD_FACTOR * burst):
		_cat(host)
	assert_lte(host.spy.cat_calls - before, burst)


# --- replay / return to lobby -------------------------------------------------------------------

func test_replay_request_honest_client_is_never_dropped() -> void:
	var rig: Rig = _host_rig()
	rig.spy.phase = MatchPhase.State.END
	var sent: int = _run_honest(rig, _replay, 0.5)
	assert_eq(rig.spy.start_calls, sent)


func test_replay_request_flood_passes_exactly_the_burst() -> void:
	var rig: Rig = _host_rig()
	rig.spy.phase = MatchPhase.State.END
	var burst: int = roundi(_limit(FloodLimits.INTENT_REPLAY_REQUEST).x)
	_flood(rig, _replay, FloodLimits.INTENT_REPLAY_REQUEST)
	assert_eq(rig.spy.start_calls, burst)
	assert_eq(rig.to_peer.size(), 0)
	_assert_isolated_and_refills(rig, _replay, FloodLimits.INTENT_REPLAY_REQUEST, func(r: Rig) -> int: return r.spy.start_calls)


func test_return_request_honest_client_is_never_dropped() -> void:
	var rig: Rig = _host_rig()
	rig.spy.phase = MatchPhase.State.END
	var sent: int = _run_honest(rig, _return, 0.5)
	assert_eq(rig.spy.abort_calls, sent)


func test_return_request_flood_passes_exactly_the_burst() -> void:
	var rig: Rig = _host_rig()
	rig.spy.phase = MatchPhase.State.END
	var burst: int = roundi(_limit(FloodLimits.INTENT_RETURN_LOBBY).x)
	_flood(rig, _return, FloodLimits.INTENT_RETURN_LOBBY)
	assert_eq(rig.spy.abort_calls, burst)
	assert_eq(rig.to_peer.size(), 0)
	_assert_isolated_and_refills(rig, _return, FloodLimits.INTENT_RETURN_LOBBY, func(r: Rig) -> int: return r.spy.abort_calls)


# --- buckets are independent, peers rejoin clean, normal refusals still answer -------------------

func test_each_intent_has_its_own_bucket_per_peer() -> void:
	var rig: Rig = _host_rig()
	_flood(rig, _place, FloodLimits.INTENT_PLACE)
	var calls_before: int = rig.spy.throw_calls
	_throw(rig)
	assert_eq(rig.spy.throw_calls, calls_before + 1, "an exhausted place bucket does not limit throws")
	var cursors_before: int = rig.stored_cursors
	_cursor(rig)
	assert_eq(rig.stored_cursors, cursors_before + 1, "nor cursors")


func test_forget_peer_gives_a_rejoin_full_buckets() -> void:
	var rig: Rig = _host_rig()
	var burst: int = roundi(_limit(FloodLimits.INTENT_PLACE).x)
	_flood(rig, _place, FloodLimits.INTENT_PLACE)
	assert_eq(rig.spy.place_calls, burst)
	rig.gateway.forget_peer(CLIENT_PEER)
	for _i: int in range(burst):
		_place(rig)
	assert_eq(rig.spy.place_calls, 2 * burst, "a rejoin starts with a full bucket")


func test_normal_refusals_still_answer_the_sender() -> void:
	var rig: Rig = _host_rig()
	# Wrong slot: the claimed slot is never trusted.
	_place(rig, CLIENT_PEER, OTHER_SLOT)
	assert_eq(rig.to_peer.size(), 1)
	assert_eq(rig.to_peer[0][0], CLIENT_PEER)
	assert_eq(rig.to_peer[0][1], &"net_match_event")
	assert_eq(rig.to_peer[0][2], [MatchWireEvents.PLACEMENT_REJECTED, [CLIENT_SLOT, PlacementRules.REASON_NOT_YOUR_TURN]])
	assert_eq(rig.spy.place_calls, 0)
	# A refusal Match applies but does not announce itself is answered once.
	_place(rig)
	assert_eq(rig.to_peer.size(), 2)
	assert_eq(rig.to_peer[1][2], [MatchWireEvents.PLACEMENT_REJECTED, [CLIENT_SLOT, PlacementRules.REASON_NO_BLOCK]])
	assert_eq(rig.counters.refused_count(CLIENT_SLOT), 2)


func test_a_refusal_match_already_announced_is_not_answered_twice() -> void:
	var rig: Rig = _host_rig()
	# Match's placement_rejected listener runs while the intent is applied.
	rig.spy.on_place = func() -> void: rig.gateway.note_rejection_sent(CLIENT_SLOT)
	_place(rig)
	assert_eq(rig.to_peer.size(), 0, "the handler's own tail reply is suppressed for that intent")
	rig.spy.on_place = Callable()
	_place(rig)
	assert_eq(rig.to_peer.size(), 1, "the suppression does not leak into the next intent")


func test_a_peer_that_is_replaying_is_refused_not_flooded() -> void:
	var rig: Rig = _host_rig()
	rig.replay_pending[CLIENT_PEER] = 1
	_place(rig)
	assert_eq(rig.spy.place_calls, 0)
	assert_eq(rig.counters.refused_count(CLIENT_SLOT), 1, "counted once against the sender's own slot")
	assert_eq(rig.to_peer.size(), 1, "the replay-pending refusal is an ordinary refusal reply")


# --- the remote release chain: the place and throw doors refuse identically ----------------------

const UNSEATED_PEER: int = 9
const BAD_FEED_SEQS: Array[int] = [-1, -7]
const DOORS: Array[StringName] = [&"place", &"throw"]


## What a caller can see after one remote release at a door: how many requests Match saw, the
## replies addressed to peers, the broadcasts, and the sender slot's refused / sent counts.
func _knock(
	door: StringName,
	setup: Callable = Callable(),
	peer: int = CLIENT_PEER,
	slot: int = CLIENT_SLOT,
	feed_seq: int = 0,
	origin: Vector3 = POSE_ORIGIN,
	velocity: Vector3 = Vector3.FORWARD,
) -> Dictionary:
	var rig: Rig = _host_rig()
	if setup.is_valid():
		setup.call(rig)
	if door == &"place":
		rig.gateway.handle_place(peer, slot, origin, 0, Quaternion.IDENTITY, feed_seq)
	else:
		rig.gateway.handle_throw(peer, slot, origin, 0, Quaternion.IDENTITY, velocity, feed_seq)
	return {
		"requests": _requests_at(rig, door),
		"replies": rig.to_peer,
		"broadcasts": rig.broadcasts.size(),
		"refused": rig.counters.refused_count(CLIENT_SLOT),
		"sent": rig.counters.sent_count(CLIENT_SLOT),
		"kicks": rig.net.kick_peer_calls.size(),
	}


func _requests_at(rig: Rig, door: StringName) -> int:
	return rig.spy.place_calls if door == &"place" else rig.spy.throw_calls


func _rejected(reason: StringName) -> Array:
	return [[CLIENT_PEER, &"net_match_event", [MatchWireEvents.PLACEMENT_REJECTED, [CLIENT_SLOT, reason]]]]


func _both_doors(
	setup: Callable = Callable(),
	peer: int = CLIENT_PEER,
	slot: int = CLIENT_SLOT,
	feed_seq: int = 0,
	origin: Vector3 = POSE_ORIGIN
) -> Dictionary:
	var outcomes: Dictionary = {}
	for door: StringName in DOORS:
		outcomes[door] = _knock(door, setup, peer, slot, feed_seq, origin)
	return outcomes


func _assert_refused_with_reply(outcomes: Dictionary, reason: StringName, what: String) -> void:
	for door: StringName in DOORS:
		var seen: Dictionary = outcomes[door]
		assert_eq(seen["requests"], 0, "%s: %s never reaches Match" % [what, door])
		assert_eq(seen["replies"], _rejected(reason), "%s: %s answers the sender once" % [what, door])
		assert_eq(seen["refused"], 1, "%s: %s counts one refusal against the sender" % [what, door])
		assert_eq(seen["sent"], 1, "%s: %s counts the intent as sent" % [what, door])
		assert_eq(seen["kicks"], 0, "%s: %s never kicks" % [what, door])
	assert_eq(outcomes[&"place"], outcomes[&"throw"], "%s: both doors refuse identically" % what)


func test_trust_boundary_a_seated_well_formed_release_is_the_control_that_passes() -> void:
	var accept: Callable = func(rig: Rig) -> void: rig.spy.place_reason = PlacementRules.REASON_OK
	for door: StringName in DOORS:
		var seen: Dictionary = _knock(door, accept)
		assert_eq(seen["requests"], 1, "%s reaches Match" % door)
		assert_eq(seen["replies"], [], "%s: an accepted release needs no refusal reply" % door)
		assert_eq(seen["refused"], 0, "%s" % door)
		assert_eq(seen["sent"], 1, "%s" % door)


func test_trust_boundary_an_unseated_sender_is_ignored_by_both_doors() -> void:
	var outcomes: Dictionary = _both_doors(Callable(), UNSEATED_PEER, CLIENT_SLOT)
	for door: StringName in DOORS:
		var seen: Dictionary = outcomes[door]
		assert_eq(seen["requests"], 0, "%s: no Match call" % door)
		assert_eq(seen["replies"], [], "%s: an unseated peer gets no reply" % door)
		assert_eq(seen["broadcasts"], 0, "%s" % door)
		assert_eq(seen["sent"], 0, "%s: it has no slot to count against" % door)
		assert_eq(seen["refused"], 0, "%s" % door)
		assert_eq(seen["kicks"], 0, "%s" % door)
	assert_eq(outcomes[&"place"], outcomes[&"throw"])


func test_trust_boundary_an_unacknowledged_sender_is_refused_by_both_doors() -> void:
	var pending: Callable = func(rig: Rig) -> void: rig.replay_pending[CLIENT_PEER] = 1
	_assert_refused_with_reply(_both_doors(pending), PlacementRules.REASON_NO_BLOCK, "replay pending")


func test_trust_boundary_a_claimed_slot_that_is_not_the_senders_is_refused_by_both_doors() -> void:
	for claimed: int in [OTHER_SLOT, 0, -1]:
		_assert_refused_with_reply(
			_both_doors(Callable(), CLIENT_PEER, claimed),
			PlacementRules.REASON_NOT_YOUR_TURN,
			"claimed slot %d" % claimed
		)


func test_trust_boundary_a_negative_feed_seq_is_refused_by_both_doors() -> void:
	for bad_seq: int in BAD_FEED_SEQS:
		_assert_refused_with_reply(
			_both_doors(Callable(), CLIENT_PEER, CLIENT_SLOT, bad_seq),
			PlacementRules.REASON_NO_BLOCK,
			"feed_seq %d" % bad_seq
		)


func test_trust_boundary_a_malformed_pose_is_refused_by_both_doors() -> void:
	var malformed: Callable = func(rig: Rig) -> void: rig.spy.pose_ok = false
	_assert_refused_with_reply(_both_doors(malformed), PlacementRules.REASON_NO_BLOCK, "pose rejected by Match")


func test_trust_boundary_a_height_outside_the_replicable_band_is_refused_by_both_doors() -> void:
	for y: float in [_config.pos_max_y + 1.0, _config.pos_min_y - 1.0]:
		_assert_refused_with_reply(
			_both_doors(Callable(), CLIENT_PEER, CLIENT_SLOT, 0, Vector3(0.0, y, 0.0)),
			PlacementRules.REASON_NO_BLOCK,
			"height %f" % y
		)


func test_trust_boundary_a_non_finite_throw_velocity_is_refused() -> void:
	for bad: Vector3 in [Vector3(NAN, 0.0, 0.0), Vector3(0.0, INF, 0.0), Vector3(0.0, 0.0, -INF)]:
		var seen: Dictionary = _knock(&"throw", Callable(), CLIENT_PEER, CLIENT_SLOT, 0, POSE_ORIGIN, bad)
		assert_eq(seen["requests"], 0, "velocity %s never reaches Match" % bad)
		assert_eq(seen["replies"], _rejected(PlacementRules.REASON_NO_BLOCK), "velocity %s: one refusal reply" % bad)
		assert_eq(seen["refused"], 1, "velocity %s" % bad)


func test_trust_boundary_a_flooding_sender_is_dropped_silently_by_both_doors() -> void:
	for door: StringName in DOORS:
		var intent: StringName = FloodLimits.INTENT_PLACE if door == &"place" else FloodLimits.INTENT_THROW
		var burst: int = roundi(_limit(intent).x)
		var rig: Rig = _host_rig()
		rig.now = 5.0
		for _i: int in range(burst):
			_knock_rig(rig, door)
		var replies_at_burst: int = rig.to_peer.size()
		var sent_at_burst: int = rig.counters.sent_count(CLIENT_SLOT)
		assert_eq(_requests_at(rig, door), burst, "%s: the burst reached Match" % door)
		for _i: int in range(FLOOD_FACTOR):
			_knock_rig(rig, door)
		assert_eq(_requests_at(rig, door), burst, "%s: nothing past the burst reaches Match" % door)
		assert_eq(rig.to_peer.size(), replies_at_burst, "%s: a dropped call is not answered" % door)
		assert_eq(rig.counters.sent_count(CLIENT_SLOT), sent_at_burst, "%s: nor counted as sent" % door)
		assert_eq(rig.broadcasts.size(), 0, "%s: nor rebroadcast" % door)
		assert_eq(rig.net.kick_peer_calls.size(), 0, "%s: never kicked" % door)


func _knock_rig(rig: Rig, door: StringName) -> void:
	if door == &"place":
		_place(rig)
	else:
		_throw(rig)


func test_trust_boundary_cat_target_and_gift_slot_refuse_an_unseated_or_foreign_sender() -> void:
	var senders: Array[Array] = [
		[UNSEATED_PEER, CLIENT_SLOT, "an unseated sender"],
		[CLIENT_PEER, OTHER_SLOT, "a claim on another seat"],
		[CLIENT_PEER, 0, "a claim on the host seat"],
		[OTHER_PEER, CLIENT_SLOT, "a seated peer naming the client slot"],
	]
	for who: Array in senders:
		var rig: Rig = _host_rig()
		var peer: int = who[0]
		var slot: int = who[1]
		rig.gateway.handle_cat_target(peer, slot, Vector3.RIGHT)
		assert_eq(rig.spy.cat_calls, 0, "cat target: %s" % who[2])
		assert_false(rig.gateway.handle_gift_slot(peer, slot), "gift slot: %s is refused" % who[2])
		assert_eq(rig.spy.gift_calls, 0, "gift slot: %s never reaches Match" % who[2])
		assert_eq(rig.to_peer.size(), 0, "%s: no reply" % who[2])
		assert_eq(rig.net.kick_peer_calls.size(), 0, "%s: never kicked" % who[2])


func test_trust_boundary_cat_target_and_gift_slot_refuse_an_unacknowledged_sender() -> void:
	var rig: Rig = _host_rig()
	rig.replay_pending[CLIENT_PEER] = 1
	_cat(rig)
	assert_false(rig.gateway.handle_gift_slot(CLIENT_PEER, CLIENT_SLOT))
	assert_eq(rig.spy.cat_calls, 0)
	assert_eq(rig.spy.gift_calls, 0)
	rig.replay_pending.erase(CLIENT_PEER)
	_cat(rig)
	assert_true(rig.gateway.handle_gift_slot(CLIENT_PEER, CLIENT_SLOT), "once it acknowledged, the same intents apply")
	assert_eq(rig.spy.cat_calls, 1)
	assert_eq(rig.spy.gift_calls, 1)
