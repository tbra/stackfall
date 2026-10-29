extends GutTest
## The snapshot numbers the F3 panel reads, through their public getters:
## SnapshotSync.snapshots_total() and last_snapshot_bytes/bodies/fragments()
## (host sends and client applies), arrival_jitter_ms() and dropped_unknown()
## (client), and Interpolator.jitter_ms().

const PEER_ID: int = 2
const TICK: float = 1.0 / 60.0
## Longer than any snapshot interval, so every host_tick() sends one snapshot.
const ONE_SNAPSHOT_S: float = 1.0
const FIRST_NET_ID: int = 900
## Enough bodies that one snapshot needs more than one fragment.
const MANY_BODIES: int = 130
const FEW_BODIES: int = 3
const HOST_TIME_STEP_MS: int = 33
const SNAPSHOTS: int = 3
const CALM_JITTER_MS: float = 0.5
const JITTER_OFFSET_S: float = 0.02
const MIN_JITTERY_MS: float = 5.0
const BEHIND_S: float = 0.5

var _config: NetConfig = preload("res://config/net/net_config.tres")
var _map: MapDef = null
var _registry: BlockRegistry = null
var _disc: Node3D = null
var _next_net_id: int = FIRST_NET_ID


## The production SnapshotSync with its two network seams replaced. The host
## sends through it and the client applies through it.
class PeerStubSync:
	extends "res://net/SnapshotSync.gd"
	var has_peer: bool = true
	var sent: Array[PackedByteArray] = []

	func _remote_peers() -> PackedInt32Array:
		return PackedInt32Array([PEER_ID]) if has_peer else PackedInt32Array()

	func _send_packet(packet: PackedByteArray) -> void:
		sent.append(packet)


## The one method a client SnapshotSync asks its registry for: nothing has spawned.
class EmptyRegistry:
	extends Node

	func block_for_net_id(_net_id: int) -> BlockBody:
		return null


func before_each() -> void:
	_map = MapDef.new()
	_map.id = &"test_snapshot_stats"
	_map.field_radius = 6.0
	_map.cell_size = 1.0
	_map.disk_height = 1.0
	_map.territory_res = 32
	_next_net_id = FIRST_NET_ID


# --- Fixtures ------------------------------------------------------------------

func _host(block_count: int) -> PeerStubSync:
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	_disc = Node3D.new()
	add_child_autofree(_disc)
	var sync: PeerStubSync = PeerStubSync.new()
	add_child_autofree(sync)
	sync.bind_session(FakeSessionPort.new(FakeNet.host()))
	sync.begin_match(_registry, _map)
	sync.set_disk(_disc)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var physics: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	for index: int in range(block_count):
		var block: Block = BlockFactory.build(shape, physics, 0)
		block.net_id = _next_net_id
		_next_net_id += 1
		add_child_autofree(block)
		block.global_position = Vector3(
			float(index % 10) * 0.5 - 2.0, 1.0, float(floori(float(index) / 10.0)) * 0.5 - 2.0
		)
		block.sleeping = true
		Events.block_replicated.emit(block, block.net_id)
	return sync


func _empty_registry() -> EmptyRegistry:
	var registry: EmptyRegistry = EmptyRegistry.new()
	add_child_autofree(registry)
	return registry


func _client() -> PeerStubSync:
	var registry: EmptyRegistry = _empty_registry()
	var sync: PeerStubSync = PeerStubSync.new()
	add_child_autofree(sync)
	sync.bind_session(FakeSessionPort.new(FakeNet.client(0)))
	sync.begin_match(registry, _map)
	return sync


## The fragments of snapshot `sequence` carrying `body_count` bodies.
func _snapshot(sequence: int, body_count: int) -> Array[PackedByteArray]:
	var bounds: AABB = _config.position_bounds(_map)
	var bodies: Array = []
	for index: int in range(body_count):
		bodies.append({
			"net_id": FIRST_NET_ID + index,
			"position": bounds.position + bounds.size * 0.5,
			"rotation": Quaternion.IDENTITY,
			"sleeping": false,
		})
	return SnapshotWire.build_snapshot(
		sequence, sequence * HOST_TIME_STEP_MS, SnapshotWire.FLAG_DISK_STATE, bodies,
		Transform3D.IDENTITY, bounds, _config
	)


func _deliver(sync: PeerStubSync, sequence: int, body_count: int) -> Array[PackedByteArray]:
	var packets: Array[PackedByteArray] = _snapshot(sequence, body_count)
	for packet: PackedByteArray in packets:
		sync.receive_packet(packet)
	return packets


func _total_size(packets: Array[PackedByteArray]) -> int:
	var total: int = 0
	for packet: PackedByteArray in packets:
		total += packet.size()
	return total


func _total(sync: PeerStubSync) -> int:
	return sync.snapshots_total()


# --- Host: snapshots_total ---------------------------------------------------------

func test_a_host_starts_with_no_snapshots() -> void:
	assert_eq(_total(_host(0)), 0)


func test_each_host_snapshot_adds_one() -> void:
	var sync: PeerStubSync = _host(0)
	for count: int in range(1, SNAPSHOTS + 1):
		sync.host_tick(ONE_SNAPSHOT_S)
		assert_eq(_total(sync), count)


func test_a_snapshot_of_many_fragments_still_adds_one() -> void:
	var sync: PeerStubSync = _host(MANY_BODIES)
	sync.host_tick(ONE_SNAPSHOT_S)
	assert_gt(sync.sent.size(), 1, "fixture: the snapshot needed several fragments")
	assert_eq(_total(sync), 1)


func test_a_tick_that_sends_nothing_adds_nothing() -> void:
	var sync: PeerStubSync = _host(0)
	sync.host_tick(ONE_SNAPSHOT_S)
	sync.host_tick(0.0)
	assert_eq(_total(sync), 1, "no snapshot interval elapsed")
	sync.has_peer = false
	sync.host_tick(ONE_SNAPSHOT_S)
	assert_eq(_total(sync), 1, "no peer to send to")


func test_a_new_match_restarts_the_snapshot_count() -> void:
	var sync: PeerStubSync = _host(0)
	sync.host_tick(ONE_SNAPSHOT_S)
	sync.begin_match(_registry, _map)
	assert_eq(_total(sync), 0)


# --- Host: last_snapshot_* ----------------------------------------------------------

func test_a_host_reports_nothing_before_its_first_snapshot() -> void:
	var sync: PeerStubSync = _host(FEW_BODIES)
	assert_eq(sync.last_snapshot_bytes(), 0)
	assert_eq(sync.last_snapshot_bodies(), 0)
	assert_eq(sync.last_snapshot_fragments(), 0)


func test_a_host_reports_the_snapshot_it_just_sent() -> void:
	var sync: PeerStubSync = _host(FEW_BODIES)
	sync.host_tick(ONE_SNAPSHOT_S)
	assert_eq(sync.sent.size(), 1, "fixture: a few bodies fit one fragment")
	assert_eq(sync.last_snapshot_bytes(), _total_size(sync.sent))
	assert_eq(sync.last_snapshot_bodies(), FEW_BODIES, "the first snapshot carries every body")
	assert_eq(sync.last_snapshot_fragments(), 1)


func test_a_host_reports_every_fragment_of_a_large_snapshot() -> void:
	var sync: PeerStubSync = _host(MANY_BODIES)
	sync.host_tick(ONE_SNAPSHOT_S)
	assert_gt(sync.sent.size(), 1, "fixture: several fragments")
	assert_eq(sync.last_snapshot_fragments(), sync.sent.size())
	assert_eq(sync.last_snapshot_bytes(), _total_size(sync.sent))
	assert_eq(sync.last_snapshot_bodies(), MANY_BODIES)


func test_the_last_snapshot_is_the_newest_not_a_sum() -> void:
	var sync: PeerStubSync = _host(MANY_BODIES)
	sync.host_tick(ONE_SNAPSHOT_S)
	var first_bytes: int = sync.last_snapshot_bytes()
	sync.sent.clear()
	for _i: int in range(4):
		sync.host_tick(TICK)
		if not sync.sent.is_empty():
			break
	assert_false(sync.sent.is_empty(), "fixture: a second snapshot went out")
	assert_eq(sync.last_snapshot_bytes(), _total_size(sync.sent))
	assert_lt(sync.last_snapshot_bytes(), first_bytes, "all-asleep deltas are smaller than the full snapshot")
	assert_eq(_total(sync), 2)


# --- Client: snapshots_total ---------------------------------------------------------

func test_a_client_starts_with_no_snapshots() -> void:
	assert_eq(_total(_client()), 0)


func test_each_distinct_sequence_a_client_applies_adds_one() -> void:
	var sync: PeerStubSync = _client()
	for sequence: int in range(1, SNAPSHOTS + 1):
		_deliver(sync, sequence, FEW_BODIES)
		assert_eq(_total(sync), sequence)


func test_the_fragments_of_one_snapshot_count_once() -> void:
	var sync: PeerStubSync = _client()
	var packets: Array[PackedByteArray] = _deliver(sync, 1, MANY_BODIES)
	assert_gt(packets.size(), 1, "fixture: several fragments")
	assert_eq(_total(sync), 1)


func test_a_repeated_sequence_does_not_count_again() -> void:
	var sync: PeerStubSync = _client()
	_deliver(sync, 1, FEW_BODIES)
	_deliver(sync, 1, FEW_BODIES)
	assert_eq(_total(sync), 1)


func test_an_undecodable_packet_counts_nothing() -> void:
	var sync: PeerStubSync = _client()
	sync.receive_packet(PackedByteArray())
	assert_eq(_total(sync), 0)


func test_a_client_new_match_restarts_the_snapshot_count() -> void:
	var sync: PeerStubSync = _client()
	_deliver(sync, 1, FEW_BODIES)
	sync.begin_match(_empty_registry(), _map)
	assert_eq(_total(sync), 0)


# --- Client: last_snapshot_bytes -----------------------------------------------------

func test_a_client_reports_the_bytes_of_the_newest_applied_snapshot() -> void:
	var sync: PeerStubSync = _client()
	var small: Array[PackedByteArray] = _deliver(sync, 1, 0)
	assert_eq(sync.last_snapshot_bytes(), _total_size(small))
	var larger: Array[PackedByteArray] = _deliver(sync, 2, FEW_BODIES)
	assert_eq(sync.last_snapshot_bytes(), _total_size(larger))
	assert_ne(_total_size(larger), _total_size(small), "fixture: the two sizes differ")


# --- Client: dropped_unknown and arrival jitter ----------------------------------------

func test_unspawned_bodies_are_counted_as_dropped() -> void:
	var sync: PeerStubSync = _client()
	assert_eq(sync.dropped_unknown(), 0)
	_deliver(sync, 1, FEW_BODIES)
	assert_eq(sync.dropped_unknown(), FEW_BODIES, "the registry has none of these ids")
	_deliver(sync, 2, FEW_BODIES)
	assert_eq(sync.dropped_unknown(), 2 * FEW_BODIES)


func test_a_new_match_clears_the_dropped_count() -> void:
	var sync: PeerStubSync = _client()
	_deliver(sync, 1, FEW_BODIES)
	sync.begin_match(_empty_registry(), _map)
	assert_eq(sync.dropped_unknown(), 0)


func test_arrival_jitter_is_zero_before_two_snapshots() -> void:
	var sync: PeerStubSync = _client()
	assert_eq(sync.arrival_jitter_ms(), 0.0)
	_deliver(sync, 1, 0)
	assert_eq(sync.arrival_jitter_ms(), 0.0, "one arrival has no gap to measure")


func test_snapshots_arriving_off_the_beat_show_arrival_jitter() -> void:
	var sync: PeerStubSync = _client()
	# Delivered back to back, far faster than the snapshot interval.
	for sequence: int in range(1, SNAPSHOTS + 1):
		_deliver(sync, sequence, 0)
	assert_gt(sync.arrival_jitter_ms(), 0.0)


func test_a_new_match_clears_the_arrival_jitter() -> void:
	var sync: PeerStubSync = _client()
	for sequence: int in range(1, SNAPSHOTS + 1):
		_deliver(sync, sequence, 0)
	sync.begin_match(_empty_registry(), _map)
	assert_eq(sync.arrival_jitter_ms(), 0.0)


# --- Interpolator.jitter_ms ------------------------------------------------------------

func _interpolator_stream(interp: Interpolator, offset_s: float, count: int) -> void:
	var interval_s: float = 1.0 / _config.snapshot_hz
	for index: int in range(count):
		var late: float = offset_s if index % 2 == 1 else 0.0
		interp.note_snapshot(index + 1, index * HOST_TIME_STEP_MS, float(index) * interval_s + late)


func test_a_steady_stream_has_no_jitter() -> void:
	var interp: Interpolator = Interpolator.new(_config)
	_interpolator_stream(interp, 0.0, 12)
	assert_almost_eq(interp.jitter_ms(), 0.0, CALM_JITTER_MS)


func test_a_stream_arriving_off_the_beat_has_jitter() -> void:
	var interp: Interpolator = Interpolator.new(_config)
	_interpolator_stream(interp, JITTER_OFFSET_S, 12)
	assert_gt(interp.jitter_ms(), MIN_JITTERY_MS)


func test_jitter_is_zero_before_the_second_snapshot() -> void:
	var interp: Interpolator = Interpolator.new(_config)
	assert_eq(interp.jitter_ms(), 0.0)
	interp.note_snapshot(1, 0, 0.0)
	assert_eq(interp.jitter_ms(), 0.0)


func test_clearing_the_interpolator_clears_the_jitter() -> void:
	var interp: Interpolator = Interpolator.new(_config)
	_interpolator_stream(interp, JITTER_OFFSET_S, 12)
	interp.clear()
	assert_eq(interp.jitter_ms(), 0.0)


func test_a_duplicate_sequence_is_not_jitter() -> void:
	var interp: Interpolator = Interpolator.new(_config)
	_interpolator_stream(interp, 0.0, 6)
	interp.note_snapshot(6, 5 * HOST_TIME_STEP_MS, 5.0 / _config.snapshot_hz + BEHIND_S)
	assert_almost_eq(interp.jitter_ms(), 0.0, CALM_JITTER_MS)


func test_dropped_unknown_count_still_counts_unspawned_ids() -> void:
	var interp: Interpolator = Interpolator.new(_config)
	interp.set_known_id_filter(func(_net_id: int) -> bool: return false)
	interp.push_sample(FIRST_NET_ID, 1000, Vector3.ZERO, Quaternion.IDENTITY, false)
	assert_eq(interp.dropped_unknown_count(), 1)
