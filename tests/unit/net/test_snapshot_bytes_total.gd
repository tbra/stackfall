extends GutTest
## SnapshotSync.snapshot_bytes_total(): the cumulative snapshot byte count the soak
## monitor reads (SOAK_PLAN 6.3). On a host it is the bytes of every fragment sent
## after host_tick(); on a client it is the bytes of every fragment applied by
## receive_packet(). begin_match() starts a fresh count, and it never decreases
## within a match.
##
## The host's transport is replaced by a subclass with a fixed peer list and a
## packet recorder (the same two overrides tests/bench/bench_client_tick.gd uses);
## everything else is the production host_tick / receive_packet path.

const PEER_ID: int = 2
## Longer than any snapshot interval, so every host_tick() sends one snapshot.
const ONE_SNAPSHOT_S: float = 1.0
const SNAPSHOTS: int = 3

var _config: NetConfig = preload("res://config/net/net_config.tres")
var _map: MapDef = null
var _registry: FakeRegistry = null


## The one method SnapshotSync asks its registry for.
class FakeRegistry:
	extends Node

	func block_for_net_id(_net_id: int) -> BlockBody:
		return null


## Production SnapshotSync with the transport replaced: one fake peer, and the
## packets that would have gone out are kept.
class RecordingSync:
	extends "res://net/SnapshotSync.gd"
	var sent: Array[PackedByteArray] = []
	var has_peer: bool = true

	func _remote_peers() -> PackedInt32Array:
		return PackedInt32Array([PEER_ID]) if has_peer else PackedInt32Array()

	func _send_packet(packet: PackedByteArray) -> void:
		sent.append(packet)


func before_each() -> void:
	_map = MapDef.base()
	_registry = FakeRegistry.new()
	add_child_autofree(_registry)


func _host() -> RecordingSync:
	var sync: RecordingSync = RecordingSync.new()
	add_child_autofree(sync)
	sync.bind_session(FakeSessionPort.new(FakeNet.host()))
	sync.begin_match(_registry, _map)
	return sync


func _client() -> Node:
	var sync: Node = (load("res://net/SnapshotSync.gd") as GDScript).new() as Node
	add_child_autofree(sync)
	sync.call("bind_session", FakeSessionPort.new(FakeNet.client(0)))
	sync.call("begin_match", _registry, _map)
	return sync


func _total_size(packets: Array[PackedByteArray]) -> int:
	var total: int = 0
	for packet: PackedByteArray in packets:
		total += packet.size()
	return total


func _packet(sequence: int) -> PackedByteArray:
	var packets: Array[PackedByteArray] = SnapshotWire.build_snapshot(
		sequence, sequence * 100, SnapshotWire.FLAG_DISK_STATE, [], Transform3D.IDENTITY,
		_config.position_bounds(_map), _config
	)
	return packets[0]


# --- Host side ----------------------------------------------------------------

func test_the_total_starts_at_zero() -> void:
	assert_eq(_host().snapshot_bytes_total(), 0, "nothing sent yet")


func test_a_host_tick_grows_the_total_by_the_bytes_sent() -> void:
	var sync: RecordingSync = _host()
	sync.host_tick(ONE_SNAPSHOT_S)
	assert_gt(sync.sent.size(), 0, "fixture: a snapshot went out")
	assert_gt(sync.snapshot_bytes_total(), 0, "bytes are counted")
	assert_eq(sync.snapshot_bytes_total(), _total_size(sync.sent), "the total is every packet's size")


func test_the_total_accumulates_across_snapshots_and_never_decreases() -> void:
	var sync: RecordingSync = _host()
	var previous: int = 0
	for _i: int in range(SNAPSHOTS):
		sync.host_tick(ONE_SNAPSHOT_S)
		var total: int = sync.snapshot_bytes_total()
		assert_gt(total, previous, "each snapshot adds bytes")
		assert_eq(total, _total_size(sync.sent), "and the total matches everything sent so far")
		previous = total


func test_a_tick_that_sends_nothing_leaves_the_total_alone() -> void:
	var sync: RecordingSync = _host()
	sync.host_tick(ONE_SNAPSHOT_S)
	var total: int = sync.snapshot_bytes_total()
	sync.host_tick(0.0)
	assert_eq(sync.snapshot_bytes_total(), total, "no snapshot interval elapsed")
	sync.has_peer = false
	sync.host_tick(ONE_SNAPSHOT_S)
	assert_eq(sync.snapshot_bytes_total(), total, "no peer to send to: the total does not drop or grow")


func test_begin_match_resets_the_total() -> void:
	var sync: RecordingSync = _host()
	sync.host_tick(ONE_SNAPSHOT_S)
	assert_gt(sync.snapshot_bytes_total(), 0, "fixture: bytes counted")
	sync.begin_match(_registry, _map)
	assert_eq(sync.snapshot_bytes_total(), 0, "a new match starts from zero")
	sync.sent.clear()
	sync.host_tick(ONE_SNAPSHOT_S)
	assert_eq(sync.snapshot_bytes_total(), _total_size(sync.sent), "and counts only the new match")


# --- Client side --------------------------------------------------------------

func test_a_client_counts_the_bytes_it_receives() -> void:
	var sync: Node = _client()
	assert_eq(sync.call("snapshot_bytes_total"), 0, "nothing received yet")
	var first: PackedByteArray = _packet(1)
	sync.call("receive_packet", first)
	assert_eq(sync.call("snapshot_bytes_total"), first.size(), "one fragment's size")
	var second: PackedByteArray = _packet(2)
	sync.call("receive_packet", second)
	assert_eq(sync.call("snapshot_bytes_total"), first.size() + second.size(), "grows by each fragment")


func test_a_client_does_not_count_a_packet_it_cannot_decode() -> void:
	var sync: Node = _client()
	sync.call("receive_packet", PackedByteArray())
	assert_eq(sync.call("snapshot_bytes_total"), 0, "an empty packet adds nothing")
	var good: PackedByteArray = _packet(1)
	sync.call("receive_packet", good)
	var total: int = sync.call("snapshot_bytes_total")
	sync.call("receive_packet", PackedByteArray())
	assert_eq(sync.call("snapshot_bytes_total"), total, "and a bad packet never lowers or raises the total")


func test_a_client_begin_match_resets_the_total() -> void:
	var sync: Node = _client()
	sync.call("receive_packet", _packet(1))
	assert_gt(sync.call("snapshot_bytes_total"), 0, "fixture: bytes counted")
	sync.call("begin_match", _registry, _map)
	assert_eq(sync.call("snapshot_bytes_total"), 0, "a new match starts from zero")
