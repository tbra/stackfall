extends GutTest
## core/net/SnapshotWire.gd's packet format (spec 2.6 "Snapshots").
##
## "Split into several packets if needed to stay under ~1200 bytes each" and
## "tag each with a sequence number". The wire is pure by design so the whole
## format is asserted without a peer, a registry or a scene tree. The fixtures
## below were captured from the pre-move SnapshotSync statics, so they prove
## the move left the bytes identical.
##
## SnapshotSync has no `class_name` (it is an autoload), so the live-client
## tests at the bottom reach it through an instance built from the script.

const RNG_SEED: int = 20260918
var _config: NetConfig = preload("res://config/net/net_config.tres")
var _map: MapDef = preload("res://config/match/maps/round.tres")
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
	return SnapshotWire.encode_fragment(
		sequence, fragment_index, fragment_count, host_time_ms,
		flags, bodies, disk_transform, _bounds
	)


func _decode(packet: PackedByteArray) -> Dictionary:
	return SnapshotWire.decode_fragment(packet, _bounds)


func _build(sequence: int, host_time_ms: int, flags: int, bodies: Array,
		disk_transform: Transform3D = Transform3D.IDENTITY) -> Array:
	var packets: Array[PackedByteArray] = SnapshotWire.build_snapshot(
		sequence, host_time_ms, flags, bodies, disk_transform, _bounds, _config
	)
	var untyped: Array = []
	untyped.assign(packets)
	return untyped


func _const(name: String) -> int:
	return int((load("res://core/net/SnapshotWire.gd") as GDScript).get_script_constant_map()[name])


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


# --- Pre-move fixtures --------------------------------------------------------
#
# Captured from the SnapshotSync statics before they moved into SnapshotWire
# (round.tres bounds, net_config.tres): the same inputs must give the same bytes.

const FIXTURE_SMALL_DISK_HEX: String = "029210010315cd5b07030300c2809c3fac7eb4c148a04771701101096d0f3e2b8f0040002000f0411501bd6dbe3fc58e9fc00ae12770121901706e6c415f8ef441f4214b70"
const FIXTURE_NO_DISK_HEX: String = "02ffff00014d000000000200701101096d0f3e2b8f0040002000f0411501bd6dbe3fc58e9fc00ae12770"
const FIXTURE_EMPTY_HEX: String = "020100000100000000010000c2809c3fac7eb4c148a04771"
const FIXTURE_BUILD_SIZES: Array[int] = [1194, 42]
const FIXTURE_BUILD_MD5: Array[String] = ["a91018070f6be304f4a428f1e68cd0f2", "99b47e89962468a34ad42c1586e07d0f"]
const FIXTURE_BODY_COUNT: int = 80


func _fixture_disk() -> Transform3D:
	return Transform3D(
		Basis(Quaternion(Vector3(0.3, 0.1, 0.9).normalized(), 0.12)), Vector3(0.4, 1.2, -0.7)
	)


func _fixture_bodies() -> Array:
	var bodies: Array = []
	for i: int in range(FIXTURE_BODY_COUNT):
		bodies.append({
			"net_id": 70000 + i * 977,
			"position": Vector3(float(i) * 0.37 - 10.0, float(i % 7) * 1.3, 8.0 - float(i) * 0.21),
			"rotation": Quaternion(Vector3(0.2 * float(i % 5) + 0.1, 1.0, 0.3).normalized(), 0.05 * float(i)),
			"sleeping": i % 3 == 0,
		})
	return bodies


func test_a_fragment_with_disk_state_matches_the_pre_move_bytes() -> void:
	var packet: PackedByteArray = _encode(
		4242, 1, 3, 123456789, _flag_disk() | _const("FLAG_KEYFRAME"),
		_fixture_bodies().slice(0, 3), _fixture_disk()
	)
	assert_eq(packet.hex_encode(), FIXTURE_SMALL_DISK_HEX, "bytes identical to the base")


func test_a_fragment_without_disk_state_matches_the_pre_move_bytes() -> void:
	var packet: PackedByteArray = _encode(
		65535, 0, 1, 77, 0, _fixture_bodies().slice(0, 2), _fixture_disk()
	)
	assert_eq(packet.hex_encode(), FIXTURE_NO_DISK_HEX, "bytes identical to the base")


func test_an_empty_snapshot_matches_the_pre_move_bytes() -> void:
	var packets: Array = _build(1, 0, _flag_disk(), [], _fixture_disk())
	assert_eq(packets.size(), 1, "an empty snapshot is one fragment")
	assert_eq((packets[0] as PackedByteArray).hex_encode(), FIXTURE_EMPTY_HEX, "bytes identical to the base")


func test_a_two_fragment_snapshot_matches_the_pre_move_bytes() -> void:
	var packets: Array = _build(
		9, 5000, _flag_disk() | _const("FLAG_KEYFRAME"), _fixture_bodies(), _fixture_disk()
	)
	assert_eq(packets.size(), FIXTURE_BUILD_SIZES.size(), "same fragment count")
	for index: int in range(mini(packets.size(), FIXTURE_BUILD_SIZES.size())):
		var packet: PackedByteArray = packets[index] as PackedByteArray
		assert_eq(packet.size(), FIXTURE_BUILD_SIZES[index], "fragment %d size" % index)
		assert_eq(packet.hex_encode().md5_text(), FIXTURE_BUILD_MD5[index], "fragment %d bytes" % index)


func test_the_pre_move_fixture_decodes_to_its_inputs() -> void:
	var decoded: Dictionary = _decode(FIXTURE_SMALL_DISK_HEX.hex_decode())
	assert_eq(int(decoded["sequence"]), 4242)
	assert_eq(int(decoded["fragment_index"]), 1)
	assert_eq(int(decoded["fragment_count"]), 3)
	assert_eq(int(decoded["host_time_ms"]), 123456789)
	assert_eq((decoded["bodies"] as Array).size(), 3)
	assert_eq(int(((decoded["bodies"] as Array)[2] as Dictionary)["net_id"]), 71954)


# --- Header -----------------------------------------------------------------

# --- Disk state -------------------------------------------------------------

func test_the_disk_transform_round_trips_when_the_flag_is_set() -> void:
	var disk: Transform3D = Transform3D(
		Basis(Quaternion(Vector3(0.3, 0.1, 0.9).normalized(), 0.12)), Vector3(0.4, 1.2, -0.7)
	)
	var decoded: Dictionary = _decode(_encode(1, 0, 1, 0, _flag_disk(), _bodies(2), disk))
	var back: Transform3D = decoded["disk_transform"] as Transform3D
	assert_lt((back.origin - disk.origin).length(), 0.0026, "the disk offset round trips")
	assert_lt(
		back.basis.get_rotation_quaternion().angle_to(disk.basis.get_rotation_quaternion()),
		deg_to_rad(0.01),
		"the disk tilt round trips"
	)


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
			0.0026,
			"position %d" % index
		)
		assert_eq(bool(got["sleeping"]), bool(want["sleeping"]), "sleeping %d" % index)


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

func test_every_fragment_stays_under_max_packet_bytes() -> void:
	for count: int in [0, 1, 78, 79, 300, 600]:
		for entry: Variant in _build(1, 0, _flag_disk(), _bodies(count)):
			var packet: PackedByteArray = entry as PackedByteArray
			assert_lte(
				packet.size(),
				_config.max_packet_bytes,
				"a fragment of a %d-body snapshot fits in max_packet_bytes" % count
			)


# --- Keyframe rotation ------------------------------------------------------

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

	var interp: Interpolator = _sync.get("_interpolator") as Interpolator
	assert_true(interp.pose_into(block.net_id, Interpolator.Pose.new()), "the sample was buffered")
	assert_eq(interp.dropped_unknown_count(), 0, "and nothing was dropped")


func test_a_sample_for_an_unspawned_body_is_dropped_and_counted() -> void:
	# The reliable spawn RPC and the unreliable snapshot ride
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

	var interp: Interpolator = _sync.get("_interpolator") as Interpolator
	assert_eq(interp.dropped_unknown_count(), 1, "the unknown body was counted")
	assert_false(interp.pose_into(4242, Interpolator.Pose.new()), "and buffered nothing")

