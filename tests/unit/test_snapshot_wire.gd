extends GutTest
## net/SnapshotSync.gd's packet format (spec 3.4 "Snapshots",
## docs/M3a_PLAN.md P2 and "The wire, byte for byte").
##
## "Split into several packets if needed to stay under ~1200 bytes each" and
## "tag each with a sequence number". Everything here is the static half of
## SnapshotSync, which is pure by design so the whole format can be asserted
## without a peer, a registry or a scene tree.
##
## SnapshotSync has no `class_name` (it is an autoload), and the integrator
## registers it, not P2 — so the tests reach it through an instance built from
## the script. Static functions are callable on an instance, which is why the
## helpers below go through `_sync`.

const RNG_SEED: int = 20260918
## Spec 3.4's headline case: "300 awake bodies x ~13 bytes = 4 KB per packet."
const SPEC_BODY_COUNT: int = 300

var _config: NetConfig = preload("res://config/net_config.tres")
var _map: MapDef = preload("res://config/maps/round_medium.tres")
var _bounds: AABB = AABB()
var _rng: RandomNumberGenerator = null
var _sync: Node = null


func before_each() -> void:
	_bounds = _config.position_bounds(_map)
	_rng = RandomNumberGenerator.new()
	_rng.seed = RNG_SEED
	_sync = (load("res://net/SnapshotSync.gd") as GDScript).new() as Node


func after_each() -> void:
	if is_instance_valid(_sync):
		_sync.free()
	_sync = null


# --- Helpers ----------------------------------------------------------------

func _encode(
	sequence: int,
	fragment_index: int,
	fragment_count: int,
	host_time_ms: int,
	flags: int,
	bodies: Array,
	disk_transform: Transform3D = Transform3D.IDENTITY
) -> PackedByteArray:
	return _sync.call(
		"encode_fragment", sequence, fragment_index, fragment_count, host_time_ms,
		flags, bodies, disk_transform, _bounds
	) as PackedByteArray


func _decode(packet: PackedByteArray) -> Dictionary:
	return _sync.call("decode_fragment", packet, _bounds) as Dictionary


func _build(sequence: int, host_time_ms: int, flags: int, bodies: Array,
		disk_transform: Transform3D = Transform3D.IDENTITY) -> Array:
	return _sync.call(
		"build_snapshot", sequence, host_time_ms, flags, bodies, disk_transform,
		_bounds, _config
	) as Array


func _const(name: String) -> int:
	return int((load("res://net/SnapshotSync.gd") as GDScript).get_script_constant_map()[name])


func _bodies(count: int, first_net_id: int = 1) -> Array:
	var bodies: Array = []
	for index: int in range(count):
		bodies.append({
			"net_id": first_net_id + index,
			"position": _bounds.position + Vector3(
				_rng.randf() * _bounds.size.x,
				_rng.randf() * _bounds.size.y,
				_rng.randf() * _bounds.size.z
			),
			"rotation": Quaternion(
				_rng.randfn(), _rng.randfn(), _rng.randfn(), _rng.randfn()
			).normalized(),
			"sleeping": index % 4 == 0,
		})
	return bodies


func _flag_disk() -> int:
	return _const("FLAG_DISK_STATE")


func _flag_keyframe() -> int:
	return _const("FLAG_KEYFRAME")


func _header_bytes() -> int:
	return _const("HEADER_BYTES")


func _disk_bytes() -> int:
	return _const("DISK_STATE_BYTES")


# --- Header -----------------------------------------------------------------

func test_the_header_is_twelve_bytes_and_twenty_four_with_the_disk() -> void:
	assert_eq(_header_bytes(), 12, "the fragment header is 12 bytes")
	assert_eq(_disk_bytes(), 12, "the disk state is 12 bytes")
	assert_eq(_encode(1, 0, 1, 0, 0, []).size(), 12, "an empty fragment is just the header")
	assert_eq(
		_encode(1, 0, 1, 0, _flag_disk(), []).size(),
		24,
		"with the disk flag it is the header plus the disk state"
	)


func test_header_fields_round_trip() -> void:
	var disk: Transform3D = Transform3D(
		Basis(Quaternion(Vector3.RIGHT, 0.07)), Vector3(0.0, 0.25, 0.0)
	)
	var packet: PackedByteArray = _encode(
		4321, 2, 5, 1234567, _flag_disk() | _flag_keyframe(), _bodies(3), disk
	)
	var decoded: Dictionary = _decode(packet)
	assert_eq(int(decoded["sequence"]), 4321, "sequence")
	assert_eq(int(decoded["fragment_index"]), 2, "fragment_index")
	assert_eq(int(decoded["fragment_count"]), 5, "fragment_count")
	assert_eq(int(decoded["host_time_ms"]), 1234567, "host_time_ms")
	assert_eq(int(decoded["flags"]), _flag_disk() | _flag_keyframe(), "flags")
	assert_eq((decoded["bodies"] as Array).size(), 3, "body count")


func test_the_packet_is_little_endian_where_the_layout_says_it_is() -> void:
	var packet: PackedByteArray = _encode(0x0201, 0, 1, 0x0A0B0C0D, 0, [])
	assert_eq(packet[0], _const("PACKET_VERSION"), "byte 0 is the packet version")
	assert_eq(_const("PACKET_VERSION"), 2, "version 2: the u24 net_id record (Bontago-mv0.1.7)")
	assert_eq(packet[1], 0x01, "sequence low byte first")
	assert_eq(packet[2], 0x02, "sequence high byte second")
	assert_eq(packet[5], 0x0D, "host_time_ms low byte first")
	assert_eq(packet[8], 0x0A, "host_time_ms high byte last")


func test_a_sequence_past_u16_wraps_rather_than_overflowing() -> void:
	assert_eq(int(_decode(_encode(65536, 0, 1, 0, 0, []))["sequence"]), 0, "65536 wraps to 0")
	assert_eq(int(_decode(_encode(65537, 0, 1, 0, 0, []))["sequence"]), 1, "65537 wraps to 1")


# --- Disk state -------------------------------------------------------------

func test_the_disk_transform_round_trips_when_the_flag_is_set() -> void:
	var disk: Transform3D = Transform3D(
		Basis(Quaternion(Vector3(0.3, 0.1, 0.9).normalized(), 0.12)), Vector3(0.4, 1.2, -0.7)
	)
	var decoded: Dictionary = _decode(_encode(1, 0, 1, 0, _flag_disk(), _bodies(2), disk))
	var back: Transform3D = decoded["disk_transform"] as Transform3D
	assert_lt((back.origin - disk.origin).length(), 0.0021, "the disk offset round trips")
	assert_lt(
		back.basis.get_rotation_quaternion().angle_to(disk.basis.get_rotation_quaternion()),
		deg_to_rad(0.01),
		"the disk tilt round trips"
	)


func test_without_the_flag_the_disk_is_absent_and_the_bodies_still_decode() -> void:
	var bodies: Array = _bodies(7)
	var decoded: Dictionary = _decode(_encode(1, 1, 3, 500, 0, bodies))
	assert_eq(decoded["disk_transform"], Transform3D.IDENTITY, "no disk state means identity")
	assert_eq((decoded["bodies"] as Array).size(), 7, "the bodies are where the header says")


# --- Bodies -----------------------------------------------------------------

func test_bodies_round_trip_through_a_fragment() -> void:
	var bodies: Array = _bodies(20)
	var decoded: Dictionary = _decode(_encode(9, 0, 1, 42, _flag_disk(), bodies))
	var back: Array = decoded["bodies"] as Array
	assert_eq(back.size(), bodies.size(), "every body survives")
	for index: int in range(bodies.size()):
		var want: Dictionary = bodies[index] as Dictionary
		var got: Dictionary = back[index] as Dictionary
		assert_eq(int(got["net_id"]), int(want["net_id"]), "net_id %d" % index)
		assert_lt(
			((got["position"] as Vector3) - (want["position"] as Vector3)).length(),
			0.0021,
			"position %d" % index
		)
		assert_eq(bool(got["sleeping"]), bool(want["sleeping"]), "sleeping %d" % index)


func test_a_fragment_grows_by_exactly_one_record_per_body() -> void:
	var base: int = _encode(1, 0, 1, 0, 0, []).size()
	for count: int in [1, 2, 10, 78]:
		assert_eq(
			_encode(1, 0, 1, 0, 0, _bodies(count)).size(),
			base + count * Quantize.BODY_RECORD_BYTES,
			"%d bodies cost %d bytes each" % [count, Quantize.BODY_RECORD_BYTES]
		)


# --- Bad input --------------------------------------------------------------

func test_a_truncated_packet_decodes_to_an_empty_dictionary() -> void:
	var packet: PackedByteArray = _encode(1, 0, 1, 0, _flag_disk(), _bodies(5))
	for cut: int in [0, 1, 11, 12, 23, packet.size() - 1]:
		assert_eq(_decode(packet.slice(0, cut)), {}, "truncated to %d bytes decodes to {}" % cut)


func test_a_wrong_version_decodes_to_an_empty_dictionary() -> void:
	var packet: PackedByteArray = _encode(1, 0, 1, 0, 0, _bodies(3))
	packet[0] = 99
	assert_eq(_decode(packet), {}, "a future packet version is dropped, not misread")


func test_a_lying_body_count_decodes_to_an_empty_dictionary() -> void:
	var packet: PackedByteArray = _encode(1, 0, 1, 0, 0, _bodies(3))
	packet.encode_u16(10, 300)
	assert_eq(_decode(packet), {}, "a body count the packet cannot hold is refused")


func test_an_impossible_fragment_index_decodes_to_an_empty_dictionary() -> void:
	var packet: PackedByteArray = _encode(1, 0, 1, 0, 0, [])
	packet[3] = 4
	assert_eq(_decode(packet), {}, "fragment 4 of 1 is refused")
	packet[3] = 0
	packet[4] = 0
	assert_eq(_decode(packet), {}, "a fragment count of 0 is refused")


func test_random_payloads_never_error_and_never_decode() -> void:
	var decoded_anything: int = 0
	for trial: int in range(2000):
		var junk: PackedByteArray = PackedByteArray()
		junk.resize(_rng.randi_range(0, 120))
		for index: int in range(junk.size()):
			junk[index] = _rng.randi_range(0, 255)
		if not _decode(junk).is_empty():
			decoded_anything += 1
	# A random payload can legitimately be a valid packet — it only has to get
	# 12 header bytes and its own length right. What matters is that it never
	# errors; the build-version handshake keeps foreign traffic off the port.
	assert_lt(decoded_anything, 200, "random bytes almost never look like a snapshot")


# --- Fragmentation ----------------------------------------------------------

func test_the_fragment_cap_is_what_net_config_predicts() -> void:
	var per_fragment: int = _config.bodies_per_fragment(
		_header_bytes() + _disk_bytes(), Quantize.BODY_RECORD_BYTES
	)
	assert_eq(per_fragment, 78, "1200 bytes minus a 24-byte header holds 78 15-byte records")


func test_three_hundred_bodies_split_into_the_predicted_fragment_count() -> void:
	var per_fragment: int = _config.bodies_per_fragment(
		_header_bytes() + _disk_bytes(), Quantize.BODY_RECORD_BYTES
	)
	var expected: int = int(ceil(float(SPEC_BODY_COUNT) / float(per_fragment)))
	var packets: Array = _build(77, 1000, _flag_disk(), _bodies(SPEC_BODY_COUNT))
	assert_eq(packets.size(), expected, "300 bodies take %d fragments" % expected)
	assert_eq(expected, 4, "which is spec 3.4's four packets")


func test_every_fragment_stays_under_max_packet_bytes() -> void:
	for count: int in [0, 1, 78, 79, 300, 600]:
		for entry: Variant in _build(1, 0, _flag_disk(), _bodies(count)):
			var packet: PackedByteArray = entry as PackedByteArray
			assert_lte(
				packet.size(),
				_config.max_packet_bytes,
				"a fragment of a %d-body snapshot fits in max_packet_bytes" % count
			)


func test_every_fragment_of_one_snapshot_shares_its_sequence_and_count() -> void:
	var packets: Array = _build(1234, 9000, _flag_disk(), _bodies(SPEC_BODY_COUNT))
	for index: int in range(packets.size()):
		var decoded: Dictionary = _decode(packets[index] as PackedByteArray)
		assert_false(decoded.is_empty(), "fragment %d decodes" % index)
		assert_eq(int(decoded["sequence"]), 1234, "fragment %d shares the sequence" % index)
		assert_eq(int(decoded["fragment_index"]), index, "fragment %d knows its index" % index)
		assert_eq(
			int(decoded["fragment_count"]), packets.size(), "fragment %d knows the total" % index
		)


func test_the_fragments_carry_every_body_exactly_once_and_the_disk_once() -> void:
	var bodies: Array = _bodies(SPEC_BODY_COUNT)
	var packets: Array = _build(5, 0, _flag_disk(), bodies)
	var seen: Dictionary = {}
	var disk_fragments: int = 0
	for index: int in range(packets.size()):
		var decoded: Dictionary = _decode(packets[index] as PackedByteArray)
		if (int(decoded["flags"]) & _flag_disk()) != 0:
			disk_fragments += 1
			assert_eq(index, 0, "the disk rides fragment 0")
		for entry: Variant in decoded["bodies"] as Array:
			var net_id: int = int((entry as Dictionary)["net_id"])
			assert_false(seen.has(net_id), "net_id %d appears in one fragment only" % net_id)
			seen[net_id] = true
	assert_eq(seen.size(), bodies.size(), "no body was lost in the split")
	assert_eq(disk_fragments, 1, "the disk state is sent once per snapshot")


func test_an_empty_snapshot_is_still_one_fragment() -> void:
	var packets: Array = _build(1, 0, _flag_disk(), [])
	assert_eq(packets.size(), 1, "an empty snapshot still advances the sequence")
	assert_eq((_decode(packets[0] as PackedByteArray)["bodies"] as Array).size(), 0, "no bodies")


func test_three_hundred_bodies_cost_about_four_kilobytes() -> void:
	var total: int = 0
	var packets: Array = _build(1, 0, _flag_disk(), _bodies(SPEC_BODY_COUNT))
	for entry: Variant in packets:
		total += (entry as PackedByteArray).size()
	gut.p("SNAPSHOT_WIRE bodies=%d fragments=%d bytes=%d bytes_per_body=%.2f" % [
		SPEC_BODY_COUNT, packets.size(), total, float(total) / float(SPEC_BODY_COUNT)
	])
	# 300 x 15 = 4500 plus four headers (24 + 3 x 12 = 60). docs/M3a_PLAN.md:
	# "300 awake bodies cost 4.56 KB - still spec 3.4's '≈4 KB'" and inside
	# the P2 acceptance budget of 4.5 KB = 4608 B that bench_snapshot.gd grades.
	assert_between(total, 4500, 4608, "a 300-body snapshot is about 4 KB")
	assert_eq(total, 4560, "exactly 300 records plus one disk header and three plain ones")


# --- Keyframe rotation ------------------------------------------------------

func test_the_keyframe_slice_refreshes_every_sleeper_once_per_interval() -> void:
	# Spec 3.4: "Every 2 s, send a full keyframe for sleeping bodies at a low
	# rate." At 30 Hz that is 60 ticks, so 300 sleepers cost 5 a tick.
	var ticks: int = int(_config.keyframe_interval * _config.snapshot_hz)
	for sleepers: int in [0, 1, 59, 60, 61, 300, 600]:
		var slice: int = int(_sync.call("keyframe_slice_for", sleepers, _config))
		assert_eq(
			slice,
			0 if sleepers == 0 else maxi(1, int(ceil(float(sleepers) / float(ticks)))),
			"%d sleepers need %d per tick" % [sleepers, slice]
		)
		assert_lte(slice * ticks, sleepers + ticks, "the slice never over-sends by a whole pass")
	assert_eq(int(_sync.call("keyframe_slice_for", 300, _config)), 5, "300 sleepers cost 5 a tick")


# --- The live client path ---------------------------------------------------
#
# autoload/Net.gd is a stub until P1 lands, so it answers is_host() = true and
# is_offline() = true: host_tick() and client_tick() both no-op and cannot be
# driven here. What *can* be driven is everything either side of that gate —
# the match lifecycle, the Events subscription, decoding an inbound packet into
# the interpolator, and the frozen-body rule — which is where the bugs that
# would survive the wire tests live.

var _registry: BlockRegistry = null


func _start_match() -> void:
	_registry = BlockRegistry.new()
	add_child_autofree(_registry)
	_sync.call("begin_match", _registry, _map)


## A Block registered the way Match registers one, so BlockRegistry allocates
## it a net_id and both it and SnapshotSync start tracking it.
func _spawn_block() -> Block:
	var block: Block = Block.new()
	block.owner_slot = 0
	add_child_autofree(block)
	Events.block_placed.emit(block, &"unit")
	return block


func test_begin_match_starts_and_end_match_stops() -> void:
	assert_false(bool(_sync.call("is_running")), "a fresh instance is idle")
	_start_match()
	assert_true(bool(_sync.call("is_running")), "begin_match starts it")
	assert_not_null(_sync.call("interpolator"), "and builds an interpolator")
	assert_true(
		Events.block_placed.is_connected(Callable(_sync, "_on_block_placed")),
		"and subscribes to the bus rather than walking the tree"
	)

	_sync.call("end_match")
	assert_false(bool(_sync.call("is_running")), "end_match stops it")
	assert_null(_sync.call("interpolator"), "and drops the interpolator")
	assert_false(
		Events.block_placed.is_connected(Callable(_sync, "_on_block_placed")),
		"and unsubscribes, so a second match does not double up"
	)


func test_end_match_is_idempotent_and_safe_before_a_match() -> void:
	_sync.call("end_match")
	_start_match()
	_sync.call("end_match")
	_sync.call("end_match")
	assert_false(bool(_sync.call("is_running")), "still stopped, no error")


func test_an_inbound_packet_reaches_the_interpolator() -> void:
	_start_match()
	var block: Block = _spawn_block()
	assert_gt(block.net_id, 0, "BlockRegistry allocated a net_id")

	var packet: PackedByteArray = _encode(1, 0, 1, 5000, _flag_disk(), [{
		"net_id": block.net_id,
		"position": Vector3(1.0, 2.0, 3.0),
		"rotation": Quaternion.IDENTITY,
		"sleeping": false,
	}])
	_sync.call("receive_packet", packet)

	var interp: Interpolator = _sync.call("interpolator") as Interpolator
	assert_eq(interp.buffered_count(block.net_id), 1, "the sample was buffered")
	assert_eq(interp.dropped_unknown_count(), 0, "and nothing was dropped")


func test_a_sample_for_an_unspawned_body_is_dropped_and_counted() -> void:
	# docs/M3a_PLAN.md: the reliable spawn RPC and the unreliable snapshot ride
	# different channels, so a snapshot can name a body whose spawn has not
	# landed. It must be dropped and counted, never buffered and never an error.
	_start_match()
	var packet: PackedByteArray = _encode(1, 0, 1, 5000, 0, [{
		"net_id": 4242,
		"position": Vector3.ZERO,
		"rotation": Quaternion.IDENTITY,
		"sleeping": false,
	}])
	_sync.call("receive_packet", packet)

	var interp: Interpolator = _sync.call("interpolator") as Interpolator
	assert_eq(interp.dropped_unknown_count(), 1, "the unknown body was counted")
	assert_eq(interp.buffered_count(4242), 0, "and buffered nothing")


func test_a_body_past_the_u16_boundary_is_never_aliased_onto_an_older_one() -> void:
	# Bontago-mv0.1.7. BlockRegistry's counter is monotonic and never reused
	# within a match (docs/M3a_PLAN.md, "net_id allocation and the
	# spawn/snapshot race"), so a long match walks past 65535. With a 16-bit
	# wire id the 65536th body packs as 0 and is dropped as unknown, and the
	# 65537th packs as 1 and moves the first block of the match instead. This
	# drives the whole client path — pack, fragment, receive, filter, buffer —
	# with the allocator moved to the boundary.
	_start_match()
	var first: Block = _spawn_block()
	assert_eq(first.net_id, 1, "the first block of the match is net_id 1")

	_registry.debug_set_next_net_id(65535)
	var last_u16: Block = _spawn_block()
	var past_u16: Block = _spawn_block()
	var would_alias_first: Block = _spawn_block()
	assert_eq(
		[last_u16.net_id, past_u16.net_id, would_alias_first.net_id],
		[65535, 65536, 65537],
		"the registry hands out 65535, 65536, 65537 without reuse"
	)

	var bodies: Array = []
	for block: Block in [last_u16, past_u16, would_alias_first]:
		bodies.append({
			"net_id": block.net_id, "position": Vector3.ONE,
			"rotation": Quaternion.IDENTITY, "sleeping": false,
		})
	for entry: Variant in _build(1, 5000, _flag_disk(), bodies):
		_sync.call("receive_packet", entry as PackedByteArray)

	var interp: Interpolator = _sync.call("interpolator") as Interpolator
	assert_eq(interp.dropped_unknown_count(), 0, "no body was lost as unknown")
	assert_eq(interp.buffered_count(first.net_id), 0, "the match's first block was not moved")
	assert_eq(interp.buffered_count(last_u16.net_id), 1, "65535 received its own sample")
	assert_eq(interp.buffered_count(past_u16.net_id), 1, "65536 received its own sample")
	assert_eq(interp.buffered_count(would_alias_first.net_id), 1, "65537 received its own sample")


func test_a_garbage_packet_is_ignored_without_disturbing_the_stream() -> void:
	_start_match()
	var block: Block = _spawn_block()
	var good: PackedByteArray = _encode(1, 0, 1, 5000, 0, [{
		"net_id": block.net_id, "position": Vector3.ONE,
		"rotation": Quaternion.IDENTITY, "sleeping": false,
	}])
	_sync.call("receive_packet", good)
	_sync.call("receive_packet", good.slice(0, 7))
	_sync.call("receive_packet", PackedByteArray([1, 2, 3]))

	var interp: Interpolator = _sync.call("interpolator") as Interpolator
	assert_eq(interp.buffered_count(block.net_id), 1, "only the good packet landed")


func test_every_fragment_of_one_snapshot_is_noted_once() -> void:
	# Interpolator.note_snapshot is "once per snapshot, not once per fragment";
	# noting each fragment would make a four-fragment snapshot look like four
	# arrivals and wreck both the jitter estimate and the loss measurement.
	_start_match()
	var block: Block = _spawn_block()
	var bodies: Array = []
	for index: int in range(SPEC_BODY_COUNT):
		bodies.append({
			"net_id": block.net_id if index == 0 else 9000 + index,
			"position": Vector3.ZERO, "rotation": Quaternion.IDENTITY, "sleeping": false,
		})
	for entry: Variant in _build(1, 5000, _flag_disk(), bodies):
		_sync.call("receive_packet", entry as PackedByteArray)

	var interp: Interpolator = _sync.call("interpolator") as Interpolator
	assert_eq(interp.loss_fraction(), 0.0, "four fragments are one snapshot, not four")
	assert_eq(interp.buffered_count(block.net_id), 1, "and the known body got one sample")


func test_the_disk_state_is_read_off_the_snapshot() -> void:
	_start_match()
	var disk: Transform3D = Transform3D(
		Basis(Quaternion(Vector3.RIGHT, 0.09)), Vector3(0.0, 0.3, 0.0)
	)
	_sync.call("receive_packet", _encode(1, 0, 1, 5000, _flag_disk(), [], disk))
	assert_lt(
		((_sync.call("disk_position") as Vector3) - disk.origin).length(),
		0.0021,
		"the disk offset arrives every snapshot (spec 3.4 'Disk state')"
	)
	assert_lt(
		(_sync.call("disk_rotation") as Quaternion).angle_to(
			disk.basis.get_rotation_quaternion()
		),
		deg_to_rad(0.01),
		"and so does its tilt"
	)


func test_a_synced_body_is_frozen_kinematically() -> void:
	# Spec 3.4: "Clients set every synced RigidBody3D to freeze = true
	# (kinematic) and move them by interpolating snapshots."
	var block: Block = Block.new()
	add_child_autofree(block)
	assert_false(block.freeze, "a host-side body simulates normally")

	_sync.call("freeze_body", block)
	assert_true(block.freeze, "a client freezes it")
	assert_eq(
		block.freeze_mode,
		RigidBody3D.FREEZE_MODE_KINEMATIC,
		"kinematically, so writing global_transform still moves it"
	)
	assert_eq(block.linear_velocity, Vector3.ZERO, "with no leftover velocity")
	assert_eq(block.angular_velocity, Vector3.ZERO, "and no leftover spin")

	# Idempotent: client_tick calls this for every tracked body every frame.
	_sync.call("freeze_body", block)
	assert_true(block.freeze, "calling it again changes nothing")


func test_a_removed_block_is_forgotten_by_both_sides() -> void:
	_start_match()
	var block: Block = _spawn_block()
	var net_id: int = block.net_id
	_sync.call("receive_packet", _encode(1, 0, 1, 5000, 0, [{
		"net_id": net_id, "position": Vector3.ONE,
		"rotation": Quaternion.IDENTITY, "sleeping": false,
	}]))
	var interp: Interpolator = _sync.call("interpolator") as Interpolator
	assert_eq(interp.buffered_count(net_id), 1, "the body is being tracked")

	Events.block_removed.emit(block, Events.REASON_KILL_PLANE)
	assert_eq(interp.buffered_count(net_id), 0, "a despawned body's samples are dropped")
	assert_eq(Array(interp.tracked_ids()), [], "and it is no longer tracked")
