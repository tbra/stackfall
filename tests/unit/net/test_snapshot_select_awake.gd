extends GutTest
## Which bodies a host snapshot carries (spec 2.6 "Snapshots"): awake or changed
## bodies, the sleep-flip resend, the disc-moved drift test, and the keyframe
## slice that refreshes every sleeper once per keyframe_interval. Everything is
## read from the bytes the host would send, decoded with SnapshotWire, so the
## tests hold for any way the host chooses to find those bodies.

const SnapshotSyncScript: GDScript = preload("res://net/SnapshotSync.gd")

const TICK: float = 1.0 / 60.0
const HOST_PEER: int = 2
const FIRST_NET_ID: int = 900
## Under keyframe_interval x snapshot_hz (60) so a one-per-snapshot slice covers all of them in time.
const SLEEPER_COUNT: int = 45
## A set that needs a keyframe slice of 3 per snapshot (and still 3 with one body fewer).
const SLEEPER_MIDDLE: int = 22
const LARGE_SLEEPER_COUNT: int = 130
## Position tolerance for a decoded body (the quantization step is about 3 mm).
const POSE_TOLERANCE: float = 0.02

var _config: NetConfig = preload("res://config/net/net_config.tres")
var _map: MapDef = null
var _registry: BlockRegistry = null
var _disc: Node3D = null
var _stub: PeerStubSync = null
var _blocks: Array[Block] = []
var _next_net_id: int = FIRST_NET_ID


## The production host path with its two network seams replaced (the same seam
## test_snapshot_sync.gd uses): the peer list, and the one send.
class PeerStubSync:
	extends "res://net/SnapshotSync.gd"
	var peers: PackedInt32Array = PackedInt32Array()
	var sent: Array[PackedByteArray] = []

	func _remote_peers() -> PackedInt32Array:
		return peers

	func _send_packet(packet: PackedByteArray) -> void:
		sent.append(packet)


func before_each() -> void:
	_map = MapDef.new()
	_map.id = &"test_snapshot_select_awake"
	_map.field_radius = 6.0
	_map.cell_size = 1.0
	_map.disk_height = 1.0
	_map.territory_res = 32
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	_disc = Node3D.new()
	add_child_autofree(_disc)
	_stub = PeerStubSync.new()
	add_child_autofree(_stub)
	_stub.bind_session(FakeSessionPort.new(FakeNet.host()))
	_stub.begin_match(_registry, _map)
	_stub.set_disk(_disc)
	_blocks.clear()
	_next_net_id = FIRST_NET_ID


func after_each() -> void:
	if _stub != null and is_instance_valid(_stub):
		_stub.end_match()
	_stub = null
	_registry = null
	_disc = null
	_blocks.clear()


# --- Fixtures ------------------------------------------------------------------

func _spawn(sleeping: bool, at: Vector3) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var physics: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	var block: Block = BlockFactory.build(shape, physics, 0)
	block.net_id = _next_net_id
	_next_net_id += 1
	add_child_autofree(block)
	block.global_position = at
	block.sleeping = sleeping
	Events.block_replicated.emit(block, block.net_id)
	_blocks.append(block)
	return block


## `count` sleepers on a grid inside the map, tracked by the host.
func _spawn_sleepers(count: int) -> Array[Block]:
	var made: Array[Block] = []
	for index: int in range(count):
		var at: Vector3 = Vector3(float(index % 10) * 0.5 - 2.0, 1.0, float(floori(float(index) / 10.0)) * 0.5 - 2.0)
		var block: Block = _spawn(true, at)
		assert_true(block.net_sleeping(), "fixture: body %d sleeps" % index)
		made.append(block)
	return made


## One host_tick per physics tick, collecting what went out as snapshots:
## an Array of {net_id: {"position": Vector3, "sleeping": bool}}, oldest first.
func _run_ticks(ticks: int) -> Array[Dictionary]:
	_stub.sent.clear()
	for _i: int in range(ticks):
		_stub.host_tick(TICK)
	return _decode_sent()


func _run_seconds(seconds: float) -> Array[Dictionary]:
	return _run_ticks(int(round(seconds / TICK)))


## Ticks until exactly one snapshot has gone out and returns its bodies.
func _next_snapshot() -> Dictionary:
	_stub.sent.clear()
	for _i: int in range(4):
		_stub.host_tick(TICK)
		if not _stub.sent.is_empty():
			break
	var snapshots: Array[Dictionary] = _decode_sent()
	assert_eq(snapshots.size(), 1, "fixture: exactly one snapshot went out")
	return snapshots[0] if not snapshots.is_empty() else {}


func _decode_sent() -> Array[Dictionary]:
	var bounds: AABB = _config.position_bounds(_map)
	var by_sequence: Dictionary = {}
	var order: Array[int] = []
	for packet: PackedByteArray in _stub.sent:
		var fragment: Dictionary = SnapshotWire.decode_fragment(packet, bounds)
		var sequence: int = int(fragment["sequence"])
		if not by_sequence.has(sequence):
			by_sequence[sequence] = {}
			order.append(sequence)
		for entry: Variant in fragment["bodies"] as Array:
			var body: Dictionary = entry as Dictionary
			(by_sequence[sequence] as Dictionary)[int(body["net_id"])] = {
				"position": body["position"] as Vector3,
				"sleeping": bool(body["sleeping"]),
			}
	var snapshots: Array[Dictionary] = []
	for sequence: int in order:
		snapshots.append(by_sequence[sequence] as Dictionary)
	return snapshots


## Connects the one peer, sends the first (full) snapshot, then lets the stream go quiet.
func _connect_and_settle() -> void:
	_stub.peers = PackedInt32Array([HOST_PEER])
	var first: Dictionary = _next_snapshot()
	assert_eq(first.size(), _blocks.size(), "fixture: the first snapshot to a peer carries every body")
	for _i: int in range(3):
		_next_snapshot()


func _slice_for(body_count: int) -> int:
	return SnapshotSyncScript.keyframe_slice_for(body_count, _config)


## Largest number of unchanged sleepers one snapshot may carry (the keyframe slice).
func _slice() -> int:
	return _slice_for(_blocks.size())


func _window_seconds() -> float:
	return _config.keyframe_interval


func _appearances(snapshots: Array[Dictionary], net_id: int) -> int:
	var count: int = 0
	for snapshot: Dictionary in snapshots:
		if snapshot.has(net_id):
			count += 1
	return count


func _union_ids(snapshots: Array[Dictionary]) -> Dictionary:
	var seen: Dictionary = {}
	for snapshot: Dictionary in snapshots:
		for net_id: Variant in snapshot.keys():
			seen[net_id] = true
	return seen


func _assert_snapshots_at_most(snapshots: Array[Dictionary], limit: int, what: String) -> void:
	assert_gt(snapshots.size(), 0, "fixture: snapshots were sent (%s)" % what)
	for snapshot: Dictionary in snapshots:
		assert_lte(snapshot.size(), limit, "%s: no more than %d bodies in one snapshot" % [what, limit])


# --- A body that wakes, moves and sleeps -------------------------------------------

func test_a_body_that_wakes_moves_and_sleeps_appears_in_the_right_snapshots() -> void:
	_spawn_sleepers(SLEEPER_COUNT)
	var subject: Block = _blocks[SLEEPER_MIDDLE]
	var slice: int = _slice()
	_connect_and_settle()
	_assert_snapshots_at_most(_run_ticks(12), slice, "asleep and unchanged")

	# Woken in place (inside the resend epsilon): the next snapshot says so.
	subject.sleeping = false
	var woke: Dictionary = _next_snapshot()
	assert_true(woke.has(subject.net_id), "the woken body is in the very next snapshot")
	assert_false((woke[subject.net_id] as Dictionary)["sleeping"], "and it is flagged awake")

	# Moving: every snapshot carries it at its current pose.
	var pose: Vector3 = subject.global_position
	for step: int in range(5):
		pose += Vector3(0.1, 0.0, 0.0)
		subject.global_position = pose
		var moving: Dictionary = _next_snapshot()
		assert_true(moving.has(subject.net_id), "moving step %d: the awake body is sent" % step)
		var entry: Dictionary = moving[subject.net_id] as Dictionary
		assert_lt((entry["position"] as Vector3).distance_to(pose), POSE_TOLERANCE, "moving step %d: at its current pose" % step)
		assert_false(entry["sleeping"], "moving step %d: awake" % step)

	# Awake but standing still is still sent every snapshot.
	for step: int in range(3):
		assert_true(_next_snapshot().has(subject.net_id), "awake and still, step %d: sent" % step)

	# Falls asleep where it is: one snapshot says so, then it is only a sleeper.
	subject.sleeping = true
	var slept: Dictionary = _next_snapshot()
	assert_true(slept.has(subject.net_id), "the sleep flip is in the very next snapshot")
	var slept_entry: Dictionary = slept[subject.net_id] as Dictionary
	assert_true(slept_entry["sleeping"], "carrying sleeping=true")
	assert_lt((slept_entry["position"] as Vector3).distance_to(pose), POSE_TOLERANCE, "at the pose it rested at")
	_assert_snapshots_at_most(_run_ticks(12), slice, "asleep again")


func test_a_sleep_flip_inside_the_resend_epsilon_is_resent_once() -> void:
	_spawn_sleepers(SLEEPER_COUNT)
	var settling: Block = _spawn(false, Vector3(0.0, 1.0, 3.0))
	var slice: int = _slice()
	_connect_and_settle()
	assert_true(_next_snapshot().has(settling.net_id), "fixture: the awake body is sent every snapshot")

	settling.sleeping = true
	var flip: Dictionary = _next_snapshot()
	assert_true(flip.has(settling.net_id), "the flip is sent")
	assert_true((flip[settling.net_id] as Dictionary)["sleeping"], "carrying the new flag")
	# Not re-sent as an awake body would be: every later snapshot is the slice alone.
	_assert_snapshots_at_most(_run_ticks(12), slice, "after the flip")


func test_an_awake_body_costs_one_entry_per_snapshot_on_top_of_the_slice() -> void:
	_spawn_sleepers(SLEEPER_COUNT)
	var awake_bodies: Array[Block] = []
	for index: int in range(5):
		awake_bodies.append(_spawn(false, Vector3(float(index), 2.0, 3.0)))
	var slice: int = _slice()
	_connect_and_settle()
	var snapshots: Array[Dictionary] = _run_ticks(24)
	_assert_snapshots_at_most(snapshots, slice + awake_bodies.size(), "five awake bodies")
	for snapshot: Dictionary in snapshots:
		for body: Block in awake_bodies:
			assert_true(snapshot.has(body.net_id), "awake body %d is in every snapshot" % body.net_id)


# --- A sleeping body that did not change --------------------------------------------

func test_unchanged_sleepers_are_not_resent_outside_their_keyframe_slice() -> void:
	_spawn_sleepers(SLEEPER_COUNT)
	var slice: int = _slice()
	_connect_and_settle()
	var snapshots: Array[Dictionary] = _run_seconds(_window_seconds())
	_assert_snapshots_at_most(snapshots, slice, "a quiet world")
	for snapshot: Dictionary in snapshots:
		assert_gt(snapshot.size(), 0, "the keyframe slice keeps flowing while nothing changes")
	for block: Block in _blocks:
		assert_lt(_appearances(snapshots, block.net_id), int(snapshots.size() * 0.5), "a sleeper is not in most snapshots")


func test_a_sleeper_moved_inside_the_epsilon_with_the_disc_still_is_not_resent() -> void:
	var sleepers: Array[Block] = _spawn_sleepers(SLEEPER_COUNT)
	var slice: int = _slice()
	_connect_and_settle()
	var nudged: Block = sleepers[3]
	nudged.global_position += Vector3(_config.resend_position_epsilon * 0.4, 0.0, 0.0)
	_disc.global_position += Vector3(0.0, 0.2, 0.0)
	_assert_snapshots_at_most(_run_ticks(2), slice, "a disc move and a sub-epsilon nudge")


# --- The keyframe slice covers every sleeper ----------------------------------------

func _assert_keyframe_covers_everyone() -> void:
	_connect_and_settle()
	var snapshots: Array[Dictionary] = _run_seconds(_window_seconds())
	var seen: Dictionary = _union_ids(snapshots)
	var missing: Array[int] = []
	for block: Block in _blocks:
		if not seen.has(block.net_id):
			missing.append(block.net_id)
	assert_eq(missing, [] as Array[int], "every sleeper was refreshed within keyframe_interval")


func test_the_keyframe_slice_covers_every_sleeper_within_the_keyframe_interval() -> void:
	_spawn_sleepers(SLEEPER_COUNT)
	_assert_keyframe_covers_everyone()


func test_the_keyframe_slice_covers_a_large_set_within_the_keyframe_interval() -> void:
	_spawn_sleepers(LARGE_SLEEPER_COUNT)
	assert_gt(_slice(), 1, "fixture: the slice is wider than one body")
	_assert_keyframe_covers_everyone()
	# And the second interval covers them all again.
	var second: Array[Dictionary] = _run_seconds(_window_seconds())
	assert_eq(_union_ids(second).size(), LARGE_SLEEPER_COUNT, "the rotation keeps going")


func test_the_keyframe_slice_covers_every_sleeper_while_other_bodies_are_awake() -> void:
	_spawn_sleepers(SLEEPER_COUNT)
	for index: int in range(6):
		_spawn(false, Vector3(float(index), 2.0, 3.0))
	_connect_and_settle()
	var seen: Dictionary = _union_ids(_run_seconds(_window_seconds()))
	for block: Block in _blocks:
		assert_true(seen.has(block.net_id), "body %d was sent within keyframe_interval" % block.net_id)


func test_a_keyframe_refresh_carries_the_sleepers_current_pose() -> void:
	var sleepers: Array[Block] = _spawn_sleepers(SLEEPER_COUNT)
	var slice: int = _slice()
	_connect_and_settle()
	# Teleported while asleep, no disc change: not sent early, but the rotation reaches it.
	var moved: Block = sleepers[7]
	var target: Vector3 = moved.global_position + Vector3(0.0, 0.0, 1.5)
	moved.global_position = target
	assert_true(moved.net_sleeping(), "fixture: it is still asleep")
	var snapshots: Array[Dictionary] = _run_seconds(_window_seconds())
	_assert_snapshots_at_most(snapshots, slice, "a quiet world with one teleported sleeper")
	var refreshed: Array[Dictionary] = []
	for snapshot: Dictionary in snapshots:
		if snapshot.has(moved.net_id):
			refreshed.append(snapshot[moved.net_id] as Dictionary)
	assert_gt(refreshed.size(), 0, "the keyframe rotation reached the moved sleeper")
	for entry: Dictionary in refreshed:
		assert_lt((entry["position"] as Vector3).distance_to(target), POSE_TOLERANCE, "at its new pose")
		assert_true(entry["sleeping"], "still flagged asleep")


# --- Disc change drift test ---------------------------------------------------------

func test_a_sleeper_moved_while_the_disc_moves_is_resent_next_snapshot() -> void:
	var sleepers: Array[Block] = _spawn_sleepers(SLEEPER_COUNT)
	var slice: int = _slice()
	_connect_and_settle()
	var drifted: Block = sleepers[SLEEPER_COUNT - 2]
	var target: Vector3 = drifted.global_position + Vector3(0.0, 0.0, 1.0)
	drifted.global_position = target
	_disc.global_position += Vector3(0.0, 0.2, 0.0)
	var snapshot: Dictionary = _next_snapshot()
	assert_true(snapshot.has(drifted.net_id), "the disc moved, so the drifted sleeper is drift-tested and resent")
	var drifted_at: Vector3 = (snapshot[drifted.net_id] as Dictionary)["position"] as Vector3
	assert_lt(drifted_at.distance_to(target), POSE_TOLERANCE, "at its new pose")
	assert_lte(snapshot.size(), slice + 1, "bodies that did not move past the epsilon stay out")
	# The disc is now still again: the next snapshot is back to the slice.
	_assert_snapshots_at_most(_run_ticks(6), slice, "after the disc stopped")


func test_every_sleeper_that_drifts_with_a_moving_disc_is_resent_and_the_rest_are_not() -> void:
	var sleepers: Array[Block] = _spawn_sleepers(SLEEPER_COUNT)
	var slice: int = _slice()
	_connect_and_settle()
	var drifted: Array[Block] = [sleepers[0], sleepers[20], sleepers[SLEEPER_COUNT - 1]]
	for block: Block in drifted:
		block.global_position += Vector3(0.0, 0.0, 0.8)
	_disc.global_position += Vector3(0.1, 0.0, 0.0)
	var snapshot: Dictionary = _next_snapshot()
	for block: Block in drifted:
		assert_true(snapshot.has(block.net_id), "drifted sleeper %d is resent" % block.net_id)
	assert_lte(snapshot.size(), slice + drifted.size(), "the others stay out")


# --- Woken after a long sleep -------------------------------------------------------

func test_a_body_woken_after_a_long_sleep_is_sent_the_next_snapshot() -> void:
	var sleepers: Array[Block] = _spawn_sleepers(SLEEPER_COUNT)
	_connect_and_settle()
	# Long enough for every keyframe slice and the rotation to wrap twice.
	_run_seconds(_window_seconds() * 2.0)
	var sleeper: Block = sleepers[11]
	assert_true(sleeper.net_sleeping(), "fixture: it has slept the whole time")
	sleeper.sleeping = false
	var snapshot: Dictionary = _next_snapshot()
	assert_true(snapshot.has(sleeper.net_id), "the woken sleeper is in the next snapshot")
	assert_false((snapshot[sleeper.net_id] as Dictionary)["sleeping"], "flagged awake")
	assert_true(_next_snapshot().has(sleeper.net_id), "and stays in while awake")


func test_a_woken_sleeper_that_moved_is_sent_where_it_is() -> void:
	var sleepers: Array[Block] = _spawn_sleepers(SLEEPER_COUNT)
	_connect_and_settle()
	_run_seconds(_window_seconds())
	var sleeper: Block = sleepers[30]
	var target: Vector3 = sleeper.global_position + Vector3(0.0, 0.5, 0.0)
	sleeper.global_position = target
	sleeper.sleeping = false
	var snapshot: Dictionary = _next_snapshot()
	assert_true(snapshot.has(sleeper.net_id), "sent")
	var sent_at: Vector3 = (snapshot[sleeper.net_id] as Dictionary)["position"] as Vector3
	assert_lt(sent_at.distance_to(target), POSE_TOLERANCE, "at its new pose")


# --- Bodies that appear and disappear -------------------------------------------------

func test_a_body_spawned_into_a_quiet_world_is_sent_the_next_snapshot() -> void:
	_spawn_sleepers(SLEEPER_COUNT)
	_connect_and_settle()
	var late_sleeper: Block = _spawn(true, Vector3(0.0, 1.0, -3.0))
	var late_awake: Block = _spawn(false, Vector3(1.0, 3.0, -3.0))
	var snapshot: Dictionary = _next_snapshot()
	assert_true(snapshot.has(late_sleeper.net_id), "a never-sent sleeper is sent")
	assert_true(snapshot.has(late_awake.net_id), "a never-sent awake body is sent")


func test_a_freed_body_is_dropped_and_the_rest_are_still_covered() -> void:
	var sleepers: Array[Block] = _spawn_sleepers(SLEEPER_COUNT)
	_connect_and_settle()
	var gone: Block = sleepers[5]
	var gone_id: int = gone.net_id
	var others: Array[int] = []
	for block: Block in sleepers:
		if block != gone:
			others.append(block.net_id)
	gone.free()
	var snapshots: Array[Dictionary] = _run_seconds(_window_seconds())
	assert_eq(_appearances(snapshots, gone_id), 0, "the freed body is never sent")
	var seen: Dictionary = _union_ids(snapshots)
	for net_id: int in others:
		assert_true(seen.has(net_id), "body %d still refreshed" % net_id)


func test_an_all_awake_world_sends_every_body_every_snapshot() -> void:
	for index: int in range(8):
		_spawn(false, Vector3(float(index) * 0.5, 2.0, 0.0))
	_connect_and_settle()
	var snapshots: Array[Dictionary] = _run_seconds(0.5)
	assert_gt(snapshots.size(), 0, "fixture: snapshots flowed")
	for snapshot: Dictionary in snapshots:
		assert_eq(snapshot.size(), _blocks.size(), "all bodies awake: all sent")
