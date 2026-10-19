extends GutTest
## The host handler behind the net_cat_target RPC, driven through the real MatchNet, gateway and
## Match with a faked session: only the cat's owner may steer it, a peer that has not
## acknowledged its world replay is ignored, a non-finite point never reaches the cat, a far point
## is clamped to the cat's range, and the per-peer flood bucket bounds the rate.

const MatchNetScript := preload("res://net/MatchNet.gd")

const HOST_PEER: int = 1
const REMOTE_PEER: int = 2
const REMOTE_SLOT: int = 1
const STRANGER_PEER: int = 9
const TARGET_RANGE_M: float = 3.0
const FAR_M: float = 60.0
const NEAR_M: float = 1.0
const RANGE_TOLERANCE_M: float = 0.05
const FLOOD_FACTOR: int = 3

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _net: MatchNetScript
var _fake_net: FakeNet
var _cat: CatController


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	var map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	_fake_net = FakeNet.host({HOST_PEER: 0, REMOTE_PEER: REMOTE_SLOT}, [0])
	Match._net_provider = _fake_net
	_net = MatchNetScript.new()
	_net.set_process(false)
	add_child_autofree(_net)
	_net.set_providers(_fake_net, Match)
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.player_count = 2
	config.hot_seat = false
	config.gifts_enabled = false
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	var effect: CatEffect = CatEffect.new()
	effect.target_range_m = TARGET_RANGE_M
	var origin: Vector3 = _field.world_from_disk_local(Match.slot(REMOTE_SLOT).home_position, 1.0)
	assert_true(Match.start_cat(REMOTE_SLOT, origin, effect), "fixture: the remote slot's cat is running")
	_cat = Match.active_cat()
	_cat.set_physics_process(false)


func after_each() -> void:
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Match._net_provider = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _point_near(offset: Vector3) -> Vector3:
	return _cat.global_position + offset


func _send(sender: int, slot_id: int, point: Vector3) -> void:
	_net._intents().handle_cat_target(sender, slot_id, point)


func test_the_owner_steers_its_cat() -> void:
	var point: Vector3 = _point_near(Vector3.RIGHT * NEAR_M)
	_send(REMOTE_PEER, REMOTE_SLOT, point)
	assert_almost_eq(_cat.target.x, point.x, RANGE_TOLERANCE_M)
	assert_almost_eq(_cat.target.z, point.z, RANGE_TOLERANCE_M)


func test_only_the_slot_owner_may_steer_the_cat() -> void:
	var before: Vector3 = _cat.target
	var point: Vector3 = _point_near(Vector3.RIGHT * NEAR_M)
	# The host's own seat (slot 0) names the remote slot: a peer acts only for its own slot.
	_send(HOST_PEER, REMOTE_SLOT, point)
	assert_eq(_cat.target, before, "a peer cannot steer another seat's cat")
	# The owner names someone else's slot: the claimed slot is never trusted.
	_send(REMOTE_PEER, 0, point)
	assert_eq(_cat.target, before, "a mismatched slot is dropped")
	# A peer with no seat at all.
	_send(STRANGER_PEER, REMOTE_SLOT, point)
	_send(STRANGER_PEER, -1, point)
	assert_eq(_cat.target, before, "an unseated peer has no say")


func test_the_host_seat_cannot_steer_a_cat_it_does_not_own() -> void:
	# Slot 0 is seated and names itself, but Match knows the cat belongs to slot 1.
	var before: Vector3 = _cat.target
	_send(HOST_PEER, 0, _point_near(Vector3.RIGHT * NEAR_M))
	assert_eq(_cat.target, before, "Match refuses a target from a non-owner")


func test_a_peer_waiting_for_its_world_replay_is_ignored() -> void:
	var before: Vector3 = _cat.target
	_net._replay_pending[REMOTE_PEER] = 1
	_send(REMOTE_PEER, REMOTE_SLOT, _point_near(Vector3.RIGHT * NEAR_M))
	assert_eq(_cat.target, before, "an unreplayed peer's target is dropped")
	_net._replay_pending.erase(REMOTE_PEER)
	_send(REMOTE_PEER, REMOTE_SLOT, _point_near(Vector3.RIGHT * NEAR_M))
	assert_ne(_cat.target, before, "once it acknowledged its replay the same target applies")


func test_a_non_finite_point_never_moves_the_cat() -> void:
	var before: Vector3 = _cat.target
	for bad: Vector3 in [Vector3.INF, Vector3(NAN, 0.0, 0.0), Vector3(0.0, 0.0, -INF), Vector3(NAN, NAN, NAN)]:
		_send(REMOTE_PEER, REMOTE_SLOT, bad)
		assert_eq(_cat.target, before, "target unchanged by %s" % bad)
	assert_eq(_net._intents().flood_dropped(REMOTE_PEER, FloodLimits.INTENT_CAT_TARGET), 0)


func test_a_far_point_is_clamped_to_the_cats_range() -> void:
	_send(REMOTE_PEER, REMOTE_SLOT, _point_near(Vector3.RIGHT * FAR_M))
	var offset: Vector2 = Vector2(_cat.target.x - _cat.global_position.x, _cat.target.z - _cat.global_position.z)
	assert_lte(offset.length(), TARGET_RANGE_M + RANGE_TOLERANCE_M, "the laser stays within target_range_m")
	assert_gt(offset.x, 0.0, "and still points where the player aimed")


func test_a_flooding_peer_is_bounded_and_the_cat_stays_controllable_by_its_owner_alone() -> void:
	var burst: int = _net.config.flood_cat_target_burst
	for _i: int in range(FLOOD_FACTOR * burst):
		_send(REMOTE_PEER, REMOTE_SLOT, _point_near(Vector3.RIGHT * NEAR_M))
	var dropped: int = _net._intents().flood_dropped(REMOTE_PEER, FloodLimits.INTENT_CAT_TARGET)
	# Real time passes between the calls (a fraction of a refill token), so allow one token of slack.
	assert_gte(dropped, (FLOOD_FACTOR - 1) * burst - 1, "the excess over the bucket is dropped")
	assert_lte(dropped, (FLOOD_FACTOR - 1) * burst)
	assert_eq(_fake_net.kick_peer_calls.size(), 0, "a flooder is never kicked")
