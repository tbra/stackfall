extends GutTest
## The host's replay-acknowledgement door (MatchWorldReplay.handle_replay_ack) under a synthetic
## clock: an honest joiner acknowledges once per replay and always gets through; a peer that
## floods acknowledgements is dropped per peer without touching anyone else, and its bucket
## refills with time. Built through the class's public constructor over the real Match, a faked
## session and a spy send seam.

const HOST_PEER: int = 1
const JOINER_PEER: int = 3
const JOINER_SLOT: int = 2
const OTHER_PEER: int = 4
const OTHER_SLOT: int = 3
const STALE_ID_BASE: int = 10000
const REFILL_MARGIN_S: float = 0.25
const SECONDS_BETWEEN_HONEST_REPLAYS: float = 60.0

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _session: FakeNet
var _replay: MatchWorldReplay
var _config: NetConfig = preload("res://config/net/net_config.tres")
var _now_s: float = 0.0
var _sent: Array[Array] = []


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_now_s = 0.0
	_sent.clear()
	var map: MapDef = MapDef.base().scaled(0.75)
	_field = Field.new()
	_field.map_def = map
	add_child_autofree(_field)
	_blocks_root = Node3D.new()
	add_child_autofree(_blocks_root)
	_registry = BlockRegistry.new()
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	_session = FakeNet.host({HOST_PEER: 0, 2: 1}, [0])
	var seams: MatchWorldReplay.Seams = MatchWorldReplay.Seams.new()
	seams.send_to_peer = func(peer_id: int, method: StringName, args: Array) -> bool:
		_sent.append([peer_id, method, args])
		return true
	seams.now_s = func() -> float: return _now_s
	_replay = MatchWorldReplay.new(_session, Match, _config, seams)
	var match_config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	match_config.disc_size_step = 1
	match_config.player_count = 4
	match_config.ai_count = 0
	match_config.hot_seat = false
	match_config.rng_seed = 4242
	match_config.allow_mid_match_join = true
	Match.start_match(match_config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the match is running")


func after_each() -> void:
	_replay = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


## Seats `peer_id` mid-match and returns the id of the replay it owes an acknowledgement for.
func _join(peer_id: int, slot_id: int) -> int:
	_session.slots_by_peer[peer_id] = slot_id
	_replay.on_peer_joined(peer_id, slot_id, "Latey")
	assert_true(_replay.is_pending(peer_id), "fixture: the joiner owes an acknowledgement")
	return _replay_id(peer_id, slot_id)


## The replay id the opening net_match_start of the peer's replay carries.
func _replay_id(peer_id: int, slot_id: int) -> int:
	var rows: Array[Array] = _replay.build_replay(peer_id, slot_id)
	assert_false(rows.is_empty(), "the replay has rows")
	if rows.is_empty():
		return -1
	assert_eq(StringName(rows[0][0]), &"net_match_start")
	var args: Array = rows[0][1]
	assert_eq(args.size(), 3, "the replay's net_match_start carries its replay id")
	return int(args[2]) if args.size() == 3 else -1


## Wrong-id acknowledgements: each is a stale ack that changes nothing but spends a token.
func _flood_stale(sender: int, count: int, id: int) -> void:
	for i: int in range(count):
		_replay.handle_replay_ack(sender, id + STALE_ID_BASE + i)


func _refill_wait_s(tokens: int) -> float:
	return float(tokens) / _config.flood_replay_ack_refill_per_s + REFILL_MARGIN_S


# --- Honest clients ------------------------------------------------------------------

func test_an_honest_ack_lifts_the_gate_and_is_never_dropped() -> void:
	var id: int = _join(JOINER_PEER, JOINER_SLOT)
	_replay.handle_replay_ack(JOINER_PEER, id)
	assert_false(_replay.is_pending(JOINER_PEER), "the right ack lifts the gate")


func test_a_peer_that_acks_every_replay_it_is_sent_is_never_throttled() -> void:
	for replay_number: int in range(_config.flood_replay_ack_burst * 3):
		var id: int = _join(JOINER_PEER, JOINER_SLOT)
		_replay.handle_replay_ack(JOINER_PEER, id)
		assert_false(_replay.is_pending(JOINER_PEER), "replay %d acknowledged" % replay_number)
		_replay.on_peer_left(JOINER_PEER)
		_now_s += SECONDS_BETWEEN_HONEST_REPLAYS


func test_one_honest_ack_survives_a_clumsy_client_that_acked_a_stale_id_first() -> void:
	var id: int = _join(JOINER_PEER, JOINER_SLOT)
	_replay.handle_replay_ack(JOINER_PEER, id + STALE_ID_BASE)
	assert_true(_replay.is_pending(JOINER_PEER), "a wrong id changes nothing")
	_replay.handle_replay_ack(JOINER_PEER, id)
	assert_false(_replay.is_pending(JOINER_PEER), "the next, right ack still lands inside the burst")


# --- Floods --------------------------------------------------------------------------

func test_a_flood_of_acks_drops_the_excess_and_the_right_ack_with_it() -> void:
	var id: int = _join(JOINER_PEER, JOINER_SLOT)
	_flood_stale(JOINER_PEER, _config.flood_replay_ack_burst * 3, id)
	assert_true(_replay.is_pending(JOINER_PEER), "stale acks never lift the gate")
	_replay.handle_replay_ack(JOINER_PEER, id)
	assert_true(_replay.is_pending(JOINER_PEER), "the bucket is empty: even the right ack is dropped")


func test_the_burst_is_exactly_the_configured_size() -> void:
	var id: int = _join(JOINER_PEER, JOINER_SLOT)
	_flood_stale(JOINER_PEER, _config.flood_replay_ack_burst - 1, id)
	_replay.handle_replay_ack(JOINER_PEER, id)
	assert_false(_replay.is_pending(JOINER_PEER), "the last token of the burst still carries a right ack")


func test_the_bucket_refills_with_time() -> void:
	var id: int = _join(JOINER_PEER, JOINER_SLOT)
	_flood_stale(JOINER_PEER, _config.flood_replay_ack_burst * 3, id)
	_replay.handle_replay_ack(JOINER_PEER, id)
	assert_true(_replay.is_pending(JOINER_PEER), "dropped while empty")
	_now_s += _refill_wait_s(1)
	_replay.handle_replay_ack(JOINER_PEER, id)
	assert_false(_replay.is_pending(JOINER_PEER), "one refilled token carries the honest ack")


func test_a_flood_from_one_peer_does_not_throttle_another() -> void:
	var flooder_id: int = _join(JOINER_PEER, JOINER_SLOT)
	var other_id: int = _join(OTHER_PEER, OTHER_SLOT)
	_flood_stale(JOINER_PEER, _config.flood_replay_ack_burst * 3, flooder_id)
	_replay.handle_replay_ack(OTHER_PEER, other_id)
	assert_false(_replay.is_pending(OTHER_PEER), "the honest peer's ack is untouched by the flooder")
	assert_true(_replay.is_pending(JOINER_PEER), "the flooder is still gated")


func test_a_peer_cannot_ack_for_another_peer() -> void:
	var id: int = _join(JOINER_PEER, JOINER_SLOT)
	_replay.handle_replay_ack(OTHER_PEER, id)
	assert_true(_replay.is_pending(JOINER_PEER), "another peer's ack does not lift this gate")
	assert_false(_replay.is_pending(OTHER_PEER), "and it owes nothing itself")


func test_an_ack_from_a_peer_with_no_replay_changes_nothing() -> void:
	_replay.handle_replay_ack(JOINER_PEER, 1)
	assert_false(_replay.is_pending(JOINER_PEER))
	_replay.handle_replay_ack(JOINER_PEER, 1)
	var id: int = _join(JOINER_PEER, JOINER_SLOT)
	_replay.handle_replay_ack(JOINER_PEER, id)
	assert_false(_replay.is_pending(JOINER_PEER), "a stray ack did not poison the joiner's later honest one")


func test_a_flooded_ack_does_not_extend_the_ack_timeout() -> void:
	var id: int = _join(JOINER_PEER, JOINER_SLOT)
	_flood_stale(JOINER_PEER, _config.flood_replay_ack_burst * 3, id)
	_now_s += _config.replay_ack_timeout
	_replay.tick_timeouts(_now_s)
	assert_eq(_session.kick_peer_calls.size(), 1, "flooding does not keep a dead replay alive")
	if _session.kick_peer_calls.size() == 1:
		assert_eq(int(_session.kick_peer_calls[0]["peer_id"]), JOINER_PEER)
