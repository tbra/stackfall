extends GutTest
## net/SnapshotSync.gd's host -> client disk-state apply path (
## spec 2.6 "Disk state: tilt quaternion and position offset, sent every
## snapshot"). Before this fix, the client half of that sentence was never
## true: client_tick() decoded a snapshot's disk pose into private fields
## and stopped there -- nothing ever wrote it into a client's
## Field -- so the host's disc tilted under Anvil/Propeller/Earthquake while
## every client saw a level one.
##
## SnapshotSync has no class_name (it is an autoload), so these tests
## instantiate the script directly, the same way test_snapshot_wire.gd's own
## `_sync` does. No real peer or FakeNet is needed: build_snapshot() (host
## encode) and receive_packet() (client decode + apply) are already exactly
## the host -> wire -> client path a real RPC would carry, so feeding one
## instance's encoded bytes straight into a second instance's receive_packet()
## is a genuine two-peer round trip of the wire format itself.

const TICK: float = 1.0 / 60.0


## PhysicsCallDriver (tests/support/PhysicsCallDriver.gd) gets a call
## into a genuine physics step. Needed both for tilting the host (Field's own
## _physics_process(), driven for real via wait_physics_frames() below,
## already does this) and for driving the client's SnapshotSync.client_tick():
## apply_replicated_pose() writes global_transform on an AnimatableBody3D with
## sync_to_physics = true (spec 2.7), which game/field/Field.gd's set_tilt_enabled()
## DECISION documents as only accepting writes made through an actual physics
## step -- calling client_tick() as a bare synchronous test call silently
## reverts the write, which would make this file's assertions compare two
## untilted (identity) transforms and pass for the wrong reason. Review NIT
## : this used to be a private inner class identical to
## tests/unit/field/test_field_tilt.gd's own.

var _config: NetConfig = preload("res://config/net/net_config.tres")
var _map: MapDef = null
var _host_field: Field = null
var _client_field: Field = null
var _client_sync: Node = null
var _client_registry: BlockRegistry = null
var _session_port: FakeSessionPort = null


func _small_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_snapshot_sync_tilt"
	map_def.field_radius = 6.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	return map_def


func before_each() -> void:
	_map = _small_map()

	_host_field = Field.new()
	_host_field.map_def = _map
	add_child_autofree(_host_field)
	_host_field.set_tilt_enabled(true)

	_client_field = Field.new()
	_client_field.map_def = _map
	add_child_autofree(_client_field)
	# autoload/match/MatchLifecycle.gd's _apply_tilt_mode() runs on the host
	# and on a client alike (it cannot tell them apart) -- a client's own
	# Field spring is "enabled" too, which is exactly the state
	# apply_replicated_pose() has to suppress.
	_client_field.set_tilt_enabled(true)

	_client_registry = autofree(BlockRegistry.new())
	add_child_autofree(_client_registry)
	_client_sync = (load("res://net/SnapshotSync.gd") as GDScript).new() as Node
	add_child_autofree(_client_sync)
	_client_sync.call("set_disk", _client_field)
	_client_sync.call("begin_match", _client_registry, _map)

	# client_tick() no-ops unless the bound session says is_client(): bind a narrow
	# client session through the production seam instead of poking the live autoload.
	_session_port = FakeSessionPort.new(FakeNet.client(0))
	assert_true(_client_sync.call("bind_session", _session_port))


func after_each() -> void:
	if _client_sync != null and is_instance_valid(_client_sync):
		_client_sync.call("end_match")
	_host_field = null
	_client_field = null
	_client_sync = null
	_client_registry = null
	_session_port = null


func _bounds() -> AABB:
	return _config.position_bounds(_map)


## One host -> client fragment carrying `disk_transform` and no bodies, the
## same shape host_tick() sends once FLAG_DISK_STATE is set (every snapshot).
func _snapshot_packet(sequence: int, host_time_ms: int, disk_transform: Transform3D) -> PackedByteArray:
	var packets: Array[PackedByteArray] = SnapshotWire.build_snapshot(
		sequence, host_time_ms, SnapshotWire.FLAG_DISK_STATE, [], disk_transform, _bounds(), _config
	)
	return packets[0]


## Ticks the host's own real _physics_process() -- a genuine engine physics
## step, since _host_field is a live child of the test's tree -- so its
## spring-driven global_transform (not just its internal tilt_vector()) is
## trustworthy to read afterwards.
func _tilt_host(direction: Vector2, magnitude: float, ticks: int) -> void:
	_host_field.apply_tilt_impulse(direction, magnitude)
	await wait_physics_frames(ticks)


## Feeds `packet` to the client SnapshotSync and runs exactly one client_tick()
## through a genuine physics step (see PhysicsCallDriver's own doc comment).
func _deliver_to_client(packet: PackedByteArray) -> void:
	var driver: PhysicsCallDriver = PhysicsCallDriver.new()
	driver.callable = func() -> void:
		_client_sync.call("receive_packet", packet)
		_client_sync.call("client_tick", TICK)
	add_child_autofree(driver)
	await wait_physics_frames(1)


# --- The apply path -----------------------------------------------------

func test_the_client_field_tilts_to_match_the_hosts_tilt_after_a_snapshot() -> void:
	await _tilt_host(Vector2(1.0, 0.0), 0.5, 30)
	assert_gt(_host_field.tilt_vector().length(), 0.0, "fixture: the host actually tilted")
	assert_gt(
		_host_field.global_transform.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY),
		deg_to_rad(0.1),
		"fixture: the host's transform genuinely reflects the tilt, not just tilt_vector()"
	)
	assert_eq(_client_field.tilt_vector(), Vector2.ZERO, "fixture: the client starts level")

	var packet: PackedByteArray = _snapshot_packet(1, 1000, _host_field.global_transform)
	await _deliver_to_client(packet)

	assert_lt(
		_client_field.global_transform.basis.get_rotation_quaternion().angle_to(
			_host_field.global_transform.basis.get_rotation_quaternion()
		),
		deg_to_rad(0.1),
		"the client Field's rotation matches the host's after one snapshot"
	)
	assert_gt(
		_client_field.tilt_vector().length(), 0.0,
		"tilt_vector() on the client reflects the replicated tilt"
	)


# --- fix round (review MAJOR): a client's own "contributing" --
# --- glow must follow the wire, not this body's own (inert on a client) -----
# --- sleeping_state_changed ---------------------------------------------------

# --- The disk smoothing itself ---------------------------------------------
#
# The 2-sample bracket, the late/duplicate rule, the extrapolation cap and the
# convergence offset live in game/net/DiskPoseSmoother.gd and are covered by
# test_disk_pose_smoother.gd. What stays here is the wiring: a snapshot reaches
# the smoother through receive_packet() and its pose reaches the Field.

func test_a_received_snapshot_feeds_the_disk_smoother() -> void:
	var smoother: DiskPoseSmoother = _client_sync.get("_disk_smoother") as DiskPoseSmoother
	assert_not_null(smoother, "begin_match builds the smoother")
	assert_false(bool(smoother.pose_at(1000.0)["ok"]), "nothing buffered before a snapshot")
	_client_sync.call("receive_packet", _snapshot_packet(1, 1000, Transform3D(Basis(), Vector3(1.0, 0.0, 0.0))))
	assert_true(bool(smoother.pose_at(1000.0)["ok"]), "the snapshot's disk pose was buffered")
	_client_sync.call("end_match")
	assert_null(_client_sync.get("_disk_smoother"), "end_match drops the smoother")


# --- The typed session seam -------------------------------------------------

## A spy session port whose is_valid() is false: the bind SnapshotSync must refuse.
class InvalidSessionPort:
	extends FakeSessionPort

	func is_valid() -> bool:
		return false


func test_bind_session_routes_mode_checks_through_the_port() -> void:
	assert_true(_client_sync.call("bind_session", FakeSessionPort.new(FakeNet.host())))
	_client_sync.call("client_tick", TICK)
	assert_eq(float(_client_sync.get("_stats_accumulator")), 0.0, "fixture: a session that is not a client gates client_tick out")
	var port: SessionPort = FakeSessionPort.new(FakeNet.client(0))
	assert_true(port.is_valid(), "a client session port is valid")
	assert_true(_client_sync.call("bind_session", port), "a valid port rebinds")
	_client_sync.call("client_tick", TICK)
	assert_gt(float(_client_sync.get("_stats_accumulator")), 0.0, "the bound session's is_client() opened the gate")


func test_bind_session_refuses_an_invalid_port() -> void:
	var port: SessionPort = InvalidSessionPort.new()
	assert_false(port.is_valid(), "a spy port that reports invalid is invalid")
	var before: Variant = _client_sync.call("_session")
	assert_false(_client_sync.call("bind_session", port), "an invalid port is refused")
	assert_push_error("SnapshotSync.bind_session")
	assert_same(_client_sync.call("_session"), before, "the previous binding is kept")
	assert_false(_client_sync.call("bind_session", null), "null is refused")
	assert_push_error("SnapshotSync.bind_session")


# --- Host peer gating and the resend memory ----------------------------------

## Test seam: overriding _remote_peers() replaces the live multiplayer peer
## list, and _send_packet() (the one network send) collects what would go out.
class PeerStubSync:
	extends "res://net/SnapshotSync.gd"
	var peers: PackedInt32Array = PackedInt32Array()
	var sent: Array[PackedByteArray] = []

	func _remote_peers() -> PackedInt32Array:
		return peers

	func _send_packet(packet: PackedByteArray) -> void:
		sent.append(packet)


const HOST_PEER: int = 2
const OTHER_PEER: int = 3
const FIRST_NET_ID: int = 600
const BODY_COUNT: int = 12
## Ticks that always cover at least one snapshot interval (30 Hz at 60 Hz ticks).
const TICKS_PER_SNAPSHOT: int = 2

var _host_bodies: Array[Block] = []
var _host_disk: Node3D = null


func _host_stub() -> PeerStubSync:
	var stub: PeerStubSync = PeerStubSync.new()
	add_child_autofree(stub)
	stub.bind_session(FakeSessionPort.new(FakeNet.host()))
	stub.begin_match(_client_registry, _map)
	_host_disk = Node3D.new()
	add_child_autofree(_host_disk)
	stub.set_disk(_host_disk)
	return stub


func _make_block(net_id: int, sleeping: bool, at: Vector3) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var physics: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	var block: Block = BlockFactory.build(shape, physics, 0)
	block.net_id = net_id
	add_child_autofree(block)
	block.global_position = at
	block.sleeping = sleeping
	return block


func _track_block(block: Block) -> void:
	Events.block_replicated.emit(block, block.net_id)


## BODY_COUNT sleepers, tracked by the stub the way a replicated body is.
func _sleepers() -> void:
	_host_bodies.clear()
	for index: int in range(BODY_COUNT):
		var block: Block = _make_block(FIRST_NET_ID + index, true, Vector3(float(index) * 1.5, 1.0, 0.0))
		assert_true(block.net_sleeping(), "fixture: body %d sleeps" % index)
		_host_bodies.append(block)
		_track_block(block)


func _tick_for(stub: PeerStubSync, seconds: float) -> void:
	for _i: int in int(seconds / TICK):
		stub.host_tick(TICK)


## Ticks until a snapshot goes out and returns the net_ids it carried.
func _next_snapshot_ids(stub: PeerStubSync) -> Array[int]:
	stub.sent.clear()
	for _i: int in range(TICKS_PER_SNAPSHOT + 1):
		stub.host_tick(TICK)
		if not stub.sent.is_empty():
			break
	assert_false(stub.sent.is_empty(), "fixture: a snapshot was sent")
	var ids: Array[int] = []
	for packet: PackedByteArray in stub.sent:
		var fragment: Dictionary = SnapshotWire.decode_fragment(packet, _bounds())
		for entry: Variant in fragment["bodies"] as Array:
			ids.append(int((entry as Dictionary)["net_id"]))
	return ids


## Ticks until a snapshot goes out and returns net_id -> sleeping for its bodies.
func _next_snapshot_sleeping(stub: PeerStubSync) -> Dictionary:
	stub.sent.clear()
	for _i: int in range(TICKS_PER_SNAPSHOT + 1):
		stub.host_tick(TICK)
		if not stub.sent.is_empty():
			break
	var flags: Dictionary = {}
	for packet: PackedByteArray in stub.sent:
		var fragment: Dictionary = SnapshotWire.decode_fragment(packet, _bounds())
		for entry: Variant in fragment["bodies"] as Array:
			flags[int((entry as Dictionary)["net_id"])] = bool((entry as Dictionary)["sleeping"])
	return flags


func _all_ids() -> Array[int]:
	var ids: Array[int] = []
	for block: Block in _host_bodies:
		ids.append(block.net_id)
	return ids


## Quiet snapshots until the stream settles: only the keyframe slice goes out.
func _settle_to_quiet(stub: PeerStubSync) -> void:
	for _i: int in range(3):
		_next_snapshot_ids(stub)
	assert_lt(_next_snapshot_ids(stub).size(), BODY_COUNT, "fixture: unmoved sleepers are not all resent")


func test_gating_zero_peers_sends_nothing() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	_tick_for(stub, 1.0)
	assert_eq(stub.sent.size(), 0, "no packet with nobody to send to")


func test_the_first_snapshot_to_a_peer_carries_every_body() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	stub.peers = PackedInt32Array([HOST_PEER])
	var ids: Array[int] = _next_snapshot_ids(stub)
	ids.sort()
	assert_eq(ids, _all_ids(), "never-sent sleepers all go out")


func test_unmoved_sleepers_are_not_all_resent_once_sent() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	_settle_to_quiet(stub)


func test_a_peer_leaving_to_zero_then_one_joining_gets_every_body_again() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	_settle_to_quiet(stub)

	stub.peers = PackedInt32Array()
	_tick_for(stub, 0.5)
	stub.peers = PackedInt32Array([HOST_PEER])
	var ids: Array[int] = _next_snapshot_ids(stub)
	ids.sort()
	assert_eq(ids, _all_ids(), "the no-peers site forgot what was sent")


func test_a_new_peer_makes_the_next_snapshot_carry_every_body() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	_settle_to_quiet(stub)

	stub.peers = PackedInt32Array([HOST_PEER, OTHER_PEER])
	var ids: Array[int] = _next_snapshot_ids(stub)
	ids.sort()
	assert_eq(ids, _all_ids(), "the new-peer site forgot what was sent")


func test_request_full_snapshot_makes_the_next_snapshot_carry_every_body() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	_settle_to_quiet(stub)

	stub.request_full_snapshot()
	var ids: Array[int] = _next_snapshot_ids(stub)
	ids.sort()
	assert_eq(ids, _all_ids(), "request_full_snapshot forgot what was sent")
	assert_lt(_next_snapshot_ids(stub).size(), BODY_COUNT, "and only once")


func test_a_new_match_makes_the_next_snapshot_carry_every_body() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	_settle_to_quiet(stub)

	stub.begin_match(_client_registry, _map) # ends the old match first
	for block: Block in _host_bodies:
		_track_block(block)
	var ids: Array[int] = _next_snapshot_ids(stub)
	ids.sort()
	assert_eq(ids, _all_ids(), "the end-of-match site forgot what was sent")


func test_a_moving_disc_resends_a_sleeper_that_drifted() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	_settle_to_quiet(stub)

	var drifted: Block = _host_bodies[BODY_COUNT - 1]
	drifted.global_position += Vector3(0.0, 0.0, 1.0)
	_host_disk.global_position += Vector3(0.0, 0.2, 0.0)
	var ids: Array[int] = _next_snapshot_ids(stub)
	assert_true(ids.has(drifted.net_id), "the disc moved, so the drifted sleeper is drift-tested and resent")
	assert_lt(ids.size(), BODY_COUNT, "bodies that did not move past the epsilon stay out")


func test_a_body_that_falls_asleep_in_place_is_resent_with_its_sleep_flag() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	var settling: Block = _make_block(FIRST_NET_ID + BODY_COUNT, false, Vector3(0.0, 1.0, 5.0))
	_host_bodies.append(settling)
	_track_block(settling)
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	_settle_to_quiet(stub)
	assert_true(_next_snapshot_ids(stub).has(settling.net_id), "fixture: the awake body is sent every snapshot")

	settling.sleeping = true # no movement at all: well inside the resend epsilon
	assert_true(settling.net_sleeping(), "fixture: it now sleeps")
	var flags: Dictionary = _next_snapshot_sleeping(stub)
	assert_true(flags.get(settling.net_id, false), "the flip is resent carrying sleeping=true")
	assert_false(_next_snapshot_sleeping(stub).has(settling.net_id), "and once sent it is not resent the next snapshot")


func test_an_awake_body_goes_out_every_snapshot() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	var awake: Block = _make_block(FIRST_NET_ID + BODY_COUNT, false, Vector3(0.0, 3.0, 0.0))
	_host_bodies.append(awake)
	_track_block(awake)
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	for _i: int in range(4):
		assert_true(_next_snapshot_ids(stub).has(awake.net_id), "the awake body is in every snapshot")


func test_a_removed_body_that_returns_is_sent_in_full_again() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	_settle_to_quiet(stub)

	var gone: Block = _host_bodies[0]
	Events.block_removed.emit(gone, "test")
	assert_false(_next_snapshot_ids(stub).has(gone.net_id), "a removed body is not sent")
	_track_block(gone)
	assert_true(_next_snapshot_ids(stub).has(gone.net_id), "a body re-tracked under the same id counts as never sent")


func test_fused_carrier_is_never_selected_only_its_followers() -> void:
	var tuning: GlueDropTuning = load("res://config/gifts/glue_drop_tuning.tres")
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var physics: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	var stub: PeerStubSync = _host_stub()
	var root: Node3D = autofree(Node3D.new())
	add_child_autofree(root)
	var blocks: Array[Block] = []
	for index: int in range(2):
		var block: Block = BlockFactory.build(shape, physics, 0)
		block.net_id = 500 + index
		root.add_child(block)
		block.global_position = _host_field.to_global(Vector3(float(index) * 1.2, 4.0, 0.0))
		blocks.append(block)
	var carrier: FusedBody = GlueFusion.fuse(blocks[0], blocks[1], tuning)
	assert_not_null(carrier)
	assert_lte(carrier.net_id, 0, "the carrier never gets a net_id")
	for body: Block in [carrier, blocks[0], blocks[1]]:
		_track_block(body)
	stub.peers = PackedInt32Array([HOST_PEER])
	var ids: Array[int] = _next_snapshot_ids(stub)
	assert_false(ids.has(carrier.net_id) or ids.has(-1) or ids.has(0), "carrier is not replicated as its own body")
	assert_true(ids.has(500) and ids.has(501), "followers are")


# --- Only awake or changed bodies are looked at, and the keyframe still reaches every sleeper ---

## Union of the net_ids over `count` consecutive snapshots.
func _ids_over_snapshots(stub: PeerStubSync, count: int) -> Array[int]:
	var seen: Dictionary = {}
	for _i: int in range(count):
		for id: int in _next_snapshot_ids(stub):
			seen[id] = true
	var ids: Array[int] = []
	for id: Variant in seen.keys():
		ids.append(int(id))
	ids.sort()
	return ids


func test_a_script_woken_sleeper_is_sent_every_snapshot_until_it_sleeps_again() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	_settle_to_quiet(stub)

	var woken: Block = _host_bodies[3]
	woken.wake()
	for _i: int in range(3):
		assert_true(_next_snapshot_ids(stub).has(woken.net_id), "a woken body is in every snapshot")
	woken.sleeping = true
	var flags: Dictionary = _next_snapshot_sleeping(stub)
	assert_true(flags.get(woken.net_id, false), "falling asleep is resent carrying sleeping=true")
	assert_false(_next_snapshot_sleeping(stub).has(woken.net_id), "and once sent it is not resent")


func test_an_engine_woken_sleeper_is_sent_after_its_sleeping_state_changed_signal() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	var body: BlockBody = BlockBody.new()
	body.net_id = FIRST_NET_ID + BODY_COUNT
	add_child_autofree(body)
	body.sleeping = true
	_track_block_body(body)
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	_settle_to_quiet(stub)
	assert_false(_next_snapshot_ids(stub).has(body.net_id) and _next_snapshot_ids(stub).has(body.net_id), "fixture: a sleeper is not sent every snapshot")

	body.sleeping = false
	body.sleeping_state_changed.emit()
	assert_true(_next_snapshot_ids(stub).has(body.net_id), "the signal puts the woken body back in the snapshot")
	assert_true(_next_snapshot_ids(stub).has(body.net_id), "and it stays in while awake")


func _track_block_body(body: BlockBody) -> void:
	Events.block_replicated.emit(body, body.net_id)


func test_the_keyframe_slice_reaches_every_sleeper_within_the_keyframe_interval() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	_settle_to_quiet(stub)

	var snapshots: int = int(ceil(_config.keyframe_interval * _config.snapshot_hz))
	assert_eq(_ids_over_snapshots(stub, snapshots), _all_ids(), "every sleeper is refreshed once per keyframe_interval")


func test_the_keyframe_slice_skips_a_sleeper_removed_or_freed_and_still_covers_the_rest() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	_settle_to_quiet(stub)

	var removed: Block = _host_bodies[2]
	Events.block_removed.emit(removed, "test")
	var freed: Block = _host_bodies[5]
	var expected: Array[int] = _all_ids()
	expected.erase(removed.net_id)
	expected.erase(freed.net_id)
	freed.free() # gone with no block_removed
	var snapshots: int = int(ceil(_config.keyframe_interval * _config.snapshot_hz))
	assert_eq(_ids_over_snapshots(stub, snapshots), expected, "the others are all still refreshed")


func test_a_body_without_a_net_id_yet_is_sent_once_it_gets_one() -> void:
	var stub: PeerStubSync = _host_stub()
	_sleepers()
	var late: Block = _make_block(-1, true, Vector3(0.0, 1.0, 6.0))
	_track_block(late)
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	_settle_to_quiet(stub)

	late.net_id = FIRST_NET_ID + BODY_COUNT
	assert_true(_next_snapshot_ids(stub).has(late.net_id), "a sleeper that was never sent goes out as soon as it has an id")


func test_the_followers_of_a_woken_carrier_are_sent() -> void:
	var tuning: GlueDropTuning = load("res://config/gifts/glue_drop_tuning.tres")
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var physics: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	var stub: PeerStubSync = _host_stub()
	var root: Node3D = autofree(Node3D.new())
	add_child_autofree(root)
	var blocks: Array[Block] = []
	for index: int in range(2):
		var block: Block = BlockFactory.build(shape, physics, 0)
		block.net_id = 500 + index
		root.add_child(block)
		block.global_position = _host_field.to_global(Vector3(float(index) * 1.2, 4.0, 0.0))
		blocks.append(block)
		_track_block(block)
	var carrier: FusedBody = GlueFusion.fuse(blocks[0], blocks[1], tuning)
	carrier.sleeping = true
	stub.peers = PackedInt32Array([HOST_PEER])
	_next_snapshot_ids(stub)
	_next_snapshot_ids(stub)
	assert_true(blocks[0].net_sleeping() and blocks[1].net_sleeping(), "fixture: the group sleeps")
	for _i: int in range(3):
		_next_snapshot_ids(stub)

	carrier.wake()
	var ids: Array[int] = _next_snapshot_ids(stub)
	assert_true(ids.has(500) and ids.has(501), "both followers follow their carrier awake")


func test_followers_of_a_disc_anchored_group_are_sent_when_the_group_wakes_without_the_snapshot_disc_moving() -> void:
	var tuning: GlueDropTuning = load("res://config/gifts/glue_drop_tuning.tres")
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var physics: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	var stub: PeerStubSync = _host_stub() # its disc is a fixed node, not _host_field
	_sleepers()
	var root: Node3D = autofree(Node3D.new())
	add_child_autofree(root)
	var blocks: Array[Block] = []
	for index: int in range(2):
		var block: Block = BlockFactory.build(shape, physics, 0)
		block.net_id = 500 + index
		root.add_child(block)
		var rest_y: float = _host_field.surface_y() + 0.5 + float(index)
		block.global_position = _host_field.to_global(Vector3(0.0, rest_y, 0.0))
		blocks.append(block)
		_track_block(block)
	GlueFusion.fuse(blocks[0], blocks[1], tuning)
	GlueFusion.fuse(blocks[0], _host_field, tuning)
	stub.peers = PackedInt32Array([HOST_PEER])
	for _i: int in range(tuning.anchor_rest_ticks + 4):
		await get_tree().physics_frame
		stub.host_tick(TICK)
	assert_true(blocks[1].net_sleeping(), "fixture: the anchored group rests")
	for _i: int in range(4):
		_next_snapshot_ids(stub)

	_host_field.apply_tilt_impulse(Vector2(1.0, 0.0), 1.0)
	for _i: int in range(3):
		await get_tree().physics_frame
	assert_false(blocks[1].net_sleeping(), "fixture: the tilt woke the group")
	var flags: Dictionary = _next_snapshot_sleeping(stub)
	assert_false(bool(flags.get(500, true)), "the first follower goes out awake in the very next snapshot")
	assert_false(bool(flags.get(501, true)), "and so does the second")


# --- A replicated spawn is the start of the body's track --------------------

func test_a_new_replicated_body_stays_at_its_spawn_pose_until_render_time_reaches_its_first_sample() -> void:
	var spawn_pose: Vector3 = Vector3(0.0, 1.0, 0.0)
	var first_sample: Vector3 = Vector3(1.0, 1.0, 0.0)
	var block: Block = _make_block(FIRST_NET_ID, false, spawn_pose)
	_client_registry.bind_net_id(block, FIRST_NET_ID)
	Events.block_replicated.emit(block, FIRST_NET_ID)

	# The first snapshot naming the body, one physics tick after the spawn, already has it a step on.
	var body: Dictionary = {"net_id": FIRST_NET_ID, "position": first_sample, "rotation": Quaternion.IDENTITY, "sleeping": false}
	var packets: Array[PackedByteArray] = SnapshotWire.build_snapshot(
		1, 1017, SnapshotWire.FLAG_DISK_STATE, [body], Transform3D.IDENTITY, _bounds(), _config
	)
	await _deliver_to_client(packets[0])

	assert_almost_eq(block.global_position.x, spawn_pose.x, 0.02, "the render clock is still before the first sample")
