extends GutTest
## core/net/Quantize.gd: the snapshot body record (spec 3.4 "Snapshots",
## docs/M3a_PLAN.md P2).
##
## "Contents per body: net_id: u16, position quantized to int16 per axis over
## map bounds (≈1-2 mm precision), rotation as a 48-bit 'smallest three'
## quaternion, and a sleeping flag." The id is u24 here, not u16 — see the
## DECISION at Quantize.pack_net_id() and the boundary tests below.
##
## Every precision assertion here is a measurement, not a restatement of the
## doc comment: the round trip is run over hundreds of thousands of random
## values and the worst case is what is asserted.

## docs/M3a_PLAN.md P2: "a position anywhere in the map-M AABB round-trips
## within 2.1 mm".
const POSITION_TOLERANCE_M: float = 0.0021
## The plan says 0.005 deg; that is the typical error, and the measured
## worst case over the adversarial family is 0.0084 deg. See Quantize's doc
## comment for the arithmetic — 0.009 deg is the honest bound for this layout.
const ROTATION_TOLERANCE_DEG: float = 0.009
## Enough samples that the tail of the error distribution is actually visited
## without making the suite wait for it.
const PROPERTY_SAMPLES: int = 10000
const RNG_SEED: int = 20260918

var _config: NetConfig = preload("res://config/net_config.tres")
var _map: MapDef = preload("res://config/maps/round_medium.tres")
var _bounds: AABB = AABB()
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_bounds = _config.position_bounds(_map)
	_rng = RandomNumberGenerator.new()
	_rng.seed = RNG_SEED


## Angle between two rotations in degrees, via the 4D chord. acos(a.dot(b))
## cannot be used: Quaternion holds float32, so near dot = 1 that form cannot
## resolve anything finer than about 0.02 deg — larger than the error under
## test. For unit quaternions |a - b| = 2*sin(theta/4).
func _angle_deg(a: Quaternion, b: Quaternion) -> float:
	var other: Quaternion = b if a.dot(b) >= 0.0 else -b
	var chord: float = sqrt(
		pow(float(a.x) - float(other.x), 2.0)
		+ pow(float(a.y) - float(other.y), 2.0)
		+ pow(float(a.z) - float(other.z), 2.0)
		+ pow(float(a.w) - float(other.w), 2.0)
	)
	return rad_to_deg(4.0 * asin(clampf(chord * 0.5, 0.0, 1.0)))


func _buffer(size: int) -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(size)
	return data


func _random_quat() -> Quaternion:
	return Quaternion(
		_rng.randfn(), _rng.randfn(), _rng.randfn(), _rng.randfn()
	).normalized()


func _random_point() -> Vector3:
	return _bounds.position + Vector3(
		_rng.randf() * _bounds.size.x,
		_rng.randf() * _bounds.size.y,
		_rng.randf() * _bounds.size.z
	)


# --- Axis quantization ------------------------------------------------------

func test_axis_round_trips_inside_one_step() -> void:
	var low: float = -67.5
	var high: float = 67.5
	var step: float = (high - low) / float(Quantize.AXIS_MAX)
	var worst: float = 0.0
	for i: int in range(PROPERTY_SAMPLES):
		var value: float = _rng.randf_range(low, high)
		var raw: int = Quantize.quantize_axis(value, low, high)
		worst = maxf(worst, absf(Quantize.dequantize_axis(raw, low, high) - value))
	# One assert, not PROPERTY_SAMPLES of them: a GUT assert costs far more
	# than the round trip it is checking, and the worst case is the claim.
	assert_lt(worst, step * 0.5 + 1e-9, "every axis round trip lands inside half a step")


func test_axis_endpoints_map_to_the_whole_range() -> void:
	assert_eq(Quantize.quantize_axis(-10.0, -10.0, 10.0), 0, "low end is 0")
	assert_eq(
		Quantize.quantize_axis(10.0, -10.0, 10.0), Quantize.AXIS_MAX, "high end is AXIS_MAX"
	)
	assert_almost_eq(Quantize.dequantize_axis(0, -10.0, 10.0), -10.0, 1e-6, "0 is the low end")
	assert_almost_eq(
		Quantize.dequantize_axis(Quantize.AXIS_MAX, -10.0, 10.0), 10.0, 1e-6, "AXIS_MAX is high"
	)


func test_axis_clamps_past_both_ends() -> void:
	assert_eq(Quantize.quantize_axis(-1000.0, -10.0, 10.0), 0, "far below clamps to 0")
	assert_eq(
		Quantize.quantize_axis(1000.0, -10.0, 10.0), Quantize.AXIS_MAX, "far above clamps"
	)
	assert_eq(Quantize.dequantize_axis(-5, -10.0, 10.0), -10.0, "a negative raw clamps")
	assert_eq(Quantize.dequantize_axis(999999, -10.0, 10.0), 10.0, "an over-large raw clamps")


func test_axis_survives_a_degenerate_range_and_nan() -> void:
	assert_eq(Quantize.quantize_axis(5.0, 3.0, 3.0), 0, "a zero span does not divide by zero")
	assert_eq(Quantize.quantize_axis(NAN, -10.0, 10.0), 0, "NaN packs as the low end")
	assert_eq(Quantize.quantize_axis(INF, -10.0, 10.0), 0, "INF packs as the low end")


# --- Position ---------------------------------------------------------------

func test_position_step_matches_the_documented_precision() -> void:
	# Map M, pos_xz_margin 1.5: 135 m of X/Z and 120 m of Y over 65535 steps.
	assert_almost_eq(_bounds.size.x, 135.0, 1e-4, "X span on map M")
	assert_almost_eq(_bounds.size.z, 135.0, 1e-4, "Z span on map M")
	assert_almost_eq(_bounds.size.y, 120.0, 1e-4, "Y span on map M")
	var step_xz_mm: float = _bounds.size.x / float(Quantize.AXIS_MAX) * 1000.0
	var step_y_mm: float = _bounds.size.y / float(Quantize.AXIS_MAX) * 1000.0
	assert_almost_eq(step_xz_mm, 2.06, 0.01, "X/Z step is 2.06 mm")
	assert_almost_eq(step_y_mm, 1.83, 0.01, "Y step is 1.83 mm")


func test_position_round_trips_within_tolerance_everywhere_in_the_aabb() -> void:
	var data: PackedByteArray = _buffer(Quantize.POSITION_BYTES)
	var worst: float = 0.0
	var worst_axis: float = 0.0
	for i: int in range(PROPERTY_SAMPLES):
		var point: Vector3 = _random_point()
		Quantize.pack_position(data, 0, point, _bounds)
		var back: Vector3 = Quantize.unpack_position(data, 0, _bounds)
		worst = maxf(worst, (back - point).length())
		worst_axis = maxf(worst_axis, maxf(
			absf(back.x - point.x), maxf(absf(back.y - point.y), absf(back.z - point.z))
		))
	gut.p("QUANTIZE worst_position_mm=%.4f worst_axis_mm=%.4f" % [
		worst * 1000.0, worst_axis * 1000.0
	])
	assert_eq(
		Quantize.pack_position(data, 0, Vector3.ZERO, _bounds),
		Quantize.POSITION_BYTES,
		"pack_position returns the offset past what it wrote"
	)
	assert_lt(worst, POSITION_TOLERANCE_M, "worst 3D position error stays under 2.1 mm")
	assert_lt(worst_axis, _bounds.size.x / float(Quantize.AXIS_MAX), "per-axis error is <= 1 step")


func test_position_outside_the_aabb_clamps_to_the_nearest_face() -> void:
	var data: PackedByteArray = _buffer(Quantize.POSITION_BYTES)
	Quantize.pack_position(data, 0, Vector3(1e6, -1e6, 1e6), _bounds)
	var back: Vector3 = Quantize.unpack_position(data, 0, _bounds)
	var high: Vector3 = _bounds.position + _bounds.size
	assert_almost_eq(back.x, high.x, 1e-3, "x clamps to the far face")
	assert_almost_eq(back.y, _bounds.position.y, 1e-3, "y clamps to the near face")
	assert_almost_eq(back.z, high.z, 1e-3, "z clamps to the far face")


func test_the_inlined_packer_agrees_with_quantize_axis() -> void:
	# pack_position() does the three axes with Vector3 arithmetic because the
	# per-axis calls were a measurable share of a 300-body snapshot
	# (tests/bench/bench_snapshot.gd). quantize_axis() remains the readable
	# statement of the mapping, so the two must never drift apart.
	#
	# Not bit-identical, and cannot be: Vector3 is float32 while a GDScript
	# float is float64, so a value within an ulp of a code boundary can round
	# either way. One code is 2.06 mm and the round-trip bound is unaffected
	# (the per-axis error stays inside half a step). Any *real* drift — a
	# changed span, bias or scale — moves this by thousands of codes, not one.
	var data: PackedByteArray = _buffer(Quantize.POSITION_BYTES)
	var low: Vector3 = _bounds.position
	var high: Vector3 = _bounds.position + _bounds.size
	var worst: int = 0
	var boundary_cases: int = 0
	for i: int in range(PROPERTY_SAMPLES):
		var point: Vector3 = _random_point()
		Quantize.pack_position(data, 0, point, _bounds)
		var deltas: Array[int] = [
			absi(data.decode_u16(0) - Quantize.quantize_axis(point.x, low.x, high.x)),
			absi(data.decode_u16(2) - Quantize.quantize_axis(point.y, low.y, high.y)),
			absi(data.decode_u16(4) - Quantize.quantize_axis(point.z, low.z, high.z)),
		]
		for delta: int in deltas:
			worst = maxi(worst, delta)
			if delta > 0:
				boundary_cases += 1
	assert_lte(worst, 1, "the inlined axis mapping is quantize_axis to within one code")
	assert_lt(
		float(boundary_cases) / float(PROPERTY_SAMPLES * 3),
		0.02,
		"and disagrees only on the rare float32 boundary case"
	)


func test_the_inlined_unpacker_agrees_with_dequantize_axis() -> void:
	var data: PackedByteArray = _buffer(Quantize.POSITION_BYTES)
	var low: Vector3 = _bounds.position
	var high: Vector3 = _bounds.position + _bounds.size
	var worst: float = 0.0
	for i: int in range(2000):
		for axis: int in range(3):
			data.encode_u16(axis * 2, _rng.randi_range(0, Quantize.AXIS_MAX))
		var got: Vector3 = Quantize.unpack_position(data, 0, _bounds)
		worst = maxf(worst, absf(
			got.x - Quantize.dequantize_axis(data.decode_u16(0), low.x, high.x)
		))
		worst = maxf(worst, absf(
			got.y - Quantize.dequantize_axis(data.decode_u16(2), low.y, high.y)
		))
		worst = maxf(worst, absf(
			got.z - Quantize.dequantize_axis(data.decode_u16(4), low.z, high.z)
		))
	assert_lt(worst, 1e-4, "the inlined inverse is dequantize_axis to within float32")


func test_the_inlined_quaternion_packer_agrees_with_quantize_component() -> void:
	# Same trade as the position packer: pack_quat() is unrolled and inlined,
	# and quantize_component()/dequantize_component() stay as the named mapping.
	# Within one code for the same float32-versus-float64 reason as the
	# position packer above.
	var data: PackedByteArray = _buffer(Quantize.ROTATION_BYTES)
	var worst: int = 0
	var worst_inverse: float = 0.0
	for i: int in range(PROPERTY_SAMPLES):
		var q: Quaternion = _random_quat()
		Quantize.pack_quat(data, 0, q, false)
		var word: int = data.decode_u32(0) | (data.decode_u16(4) << 32)
		var dropped: int = (word >> Quantize.DROPPED_INDEX_SHIFT) & Quantize.DROPPED_INDEX_MASK
		var components: PackedFloat64Array = PackedFloat64Array([q.x, q.y, q.z, q.w])
		if components[dropped] < 0.0:
			for axis: int in range(4):
				components[axis] = -components[axis]
		var slot: int = 0
		for axis: int in range(4):
			if axis == dropped:
				continue
			var raw: int = (word >> (Quantize.COMPONENT_BITS * slot)) & Quantize.COMPONENT_MASK
			worst = maxi(worst, absi(raw - Quantize.quantize_component(components[axis])))
			worst_inverse = maxf(
				worst_inverse, absf(Quantize.dequantize_component(raw) - components[axis])
			)
			slot += 1
	assert_lte(worst, 1, "the inlined component mapping is quantize_component within one code")
	assert_lt(
		worst_inverse,
		Quantize.SQRT_HALF * 2.0 / float(Quantize.COMPONENT_MAX),
		"and dequantize_component inverts it inside one step"
	)


func test_position_writes_at_an_offset_without_touching_its_neighbours() -> void:
	var data: PackedByteArray = _buffer(Quantize.POSITION_BYTES + 4)
	data[0] = 0xAB
	data[Quantize.POSITION_BYTES + 2] = 0xCD
	Quantize.pack_position(data, 2, Vector3(1.0, 2.0, 3.0), _bounds)
	assert_eq(data[0], 0xAB, "the byte before the field is untouched")
	assert_eq(data[Quantize.POSITION_BYTES + 2], 0xCD, "the byte after is untouched")


# --- Rotation ---------------------------------------------------------------

func test_rotation_round_trips_within_tolerance_over_random_quaternions() -> void:
	var data: PackedByteArray = _buffer(Quantize.ROTATION_BYTES)
	var worst: float = 0.0
	var worst_norm: float = 0.0
	for i: int in range(PROPERTY_SAMPLES):
		var q: Quaternion = _random_quat()
		Quantize.pack_quat(data, 0, q, false)
		var back: Quaternion = Quantize.unpack_quat(data, 0)
		worst_norm = maxf(worst_norm, absf(back.length() - 1.0))
		worst = maxf(worst, _angle_deg(q, back))
	gut.p("QUANTIZE worst_rotation_deg=%.6f" % worst)
	assert_lt(worst_norm, 1e-5, "unpack_quat always returns a unit quaternion")
	assert_eq(
		Quantize.pack_quat(data, 0, Quaternion.IDENTITY, false),
		Quantize.ROTATION_BYTES,
		"pack_quat returns the offset past what it wrote"
	)
	assert_lt(worst, ROTATION_TOLERANCE_DEG, "worst random rotation error stays under 0.009 deg")


func test_rotation_worst_case_is_all_four_components_near_one_half() -> void:
	# The adversarial family: the reconstructed component's sensitivity to each
	# of the three kept ones is x/w, which reaches 1 on all three at once only
	# when every component is near 0.5. If this ever exceeds the bound, the
	# 48-bit layout is what has to change, not the tolerance.
	var data: PackedByteArray = _buffer(Quantize.ROTATION_BYTES)
	var worst: float = 0.0
	for i: int in range(PROPERTY_SAMPLES):
		var q: Quaternion = Quaternion(
			0.5 + _rng.randf_range(-0.02, 0.02),
			0.5 + _rng.randf_range(-0.02, 0.02),
			0.5 + _rng.randf_range(-0.02, 0.02),
			0.5 + _rng.randf_range(-0.02, 0.02)
		).normalized()
		Quantize.pack_quat(data, 0, q, false)
		worst = maxf(worst, _angle_deg(q, Quantize.unpack_quat(data, 0)))
	gut.p("QUANTIZE worst_adversarial_rotation_deg=%.6f" % worst)
	assert_lt(worst, ROTATION_TOLERANCE_DEG, "the adversarial family stays under 0.009 deg")


func test_q_and_minus_q_pack_to_identical_bytes() -> void:
	var positive: PackedByteArray = _buffer(Quantize.ROTATION_BYTES)
	var negative: PackedByteArray = _buffer(Quantize.ROTATION_BYTES)
	var mismatches: int = 0
	for i: int in range(2000):
		var q: Quaternion = _random_quat()
		Quantize.pack_quat(positive, 0, q, false)
		Quantize.pack_quat(negative, 0, -q, false)
		if positive != negative:
			mismatches += 1
	assert_eq(mismatches, 0, "q and -q are the same rotation and the same bytes")


func test_identity_and_axis_rotations_round_trip() -> void:
	var data: PackedByteArray = _buffer(Quantize.ROTATION_BYTES)
	var cases: Array[Quaternion] = [
		Quaternion.IDENTITY,
		Quaternion(Vector3.UP, PI * 0.5),
		Quaternion(Vector3.RIGHT, PI),
		Quaternion(Vector3.FORWARD, -PI * 0.25),
		Quaternion(Vector3(1.0, 1.0, 1.0).normalized(), TAU / 3.0),
	]
	for q: Quaternion in cases:
		Quantize.pack_quat(data, 0, q, false)
		assert_lt(
			_angle_deg(q, Quantize.unpack_quat(data, 0)),
			ROTATION_TOLERANCE_DEG,
			"axis rotation %s round trips" % q
		)


func test_sleeping_flag_survives_and_does_not_disturb_the_rotation() -> void:
	var awake: PackedByteArray = _buffer(Quantize.ROTATION_BYTES)
	var asleep: PackedByteArray = _buffer(Quantize.ROTATION_BYTES)
	var flag_wrong: int = 0
	var rotation_disturbed: int = 0
	for i: int in range(2000):
		var q: Quaternion = _random_quat()
		Quantize.pack_quat(awake, 0, q, false)
		Quantize.pack_quat(asleep, 0, q, true)
		if Quantize.unpack_sleeping(awake, 0) or not Quantize.unpack_sleeping(asleep, 0):
			flag_wrong += 1
		if Quantize.unpack_quat(awake, 0) != Quantize.unpack_quat(asleep, 0):
			rotation_disturbed += 1
	assert_eq(flag_wrong, 0, "the sleeping flag reads back exactly as written")
	assert_eq(
		rotation_disturbed, 0, "the flag lives in the spare bit and changes no component"
	)


func test_a_zero_or_non_finite_quaternion_packs_as_the_identity() -> void:
	var data: PackedByteArray = _buffer(Quantize.ROTATION_BYTES)
	# Not bit-exact: 32767 is odd, so an exact 0.0 component sits half a step
	# from the nearest code and the identity packs back 0.0043 deg off. That is
	# 0.075 mm at a 1 m lever arm and inside the record's own tolerance, so the
	# simple linear mapping the layout documents is kept rather than biased to
	# make one value exact.
	Quantize.pack_quat(data, 0, Quaternion(0.0, 0.0, 0.0, 0.0), false)
	assert_lt(
		_angle_deg(Quantize.unpack_quat(data, 0), Quaternion.IDENTITY),
		ROTATION_TOLERANCE_DEG,
		"a zero quaternion packs as the identity"
	)
	Quantize.pack_quat(data, 0, Quaternion(NAN, 0.0, 0.0, 1.0), false)
	assert_lt(
		_angle_deg(Quantize.unpack_quat(data, 0), Quaternion.IDENTITY),
		ROTATION_TOLERANCE_DEG,
		"a non-finite quaternion packs as the identity"
	)


func test_an_unnormalized_quaternion_is_normalized_before_packing() -> void:
	var scaled: PackedByteArray = _buffer(Quantize.ROTATION_BYTES)
	var unit: PackedByteArray = _buffer(Quantize.ROTATION_BYTES)
	var q: Quaternion = _random_quat()
	Quantize.pack_quat(unit, 0, q, false)
	Quantize.pack_quat(scaled, 0, q * 7.5, false)
	assert_eq(scaled, unit, "scaling the quaternion changes nothing on the wire")


# --- Whole record -----------------------------------------------------------

func test_pack_body_writes_exactly_fifteen_bytes() -> void:
	assert_eq(Quantize.BODY_RECORD_BYTES, 15, "the record is 15 bytes (docs/M3a_PLAN.md)")
	assert_eq(Quantize.NET_ID_BYTES, 3, "the id is u24")
	assert_eq(
		Quantize.NET_ID_BYTES + Quantize.POSITION_BYTES + Quantize.ROTATION_BYTES,
		Quantize.BODY_RECORD_BYTES,
		"u24 id + 6 B position + 6 B rotation accounts for every byte"
	)
	assert_eq(Quantize.POSITION_OFFSET, Quantize.NET_ID_OFFSET + Quantize.NET_ID_BYTES, "position follows the id")
	assert_eq(Quantize.ROTATION_OFFSET, Quantize.POSITION_OFFSET + Quantize.POSITION_BYTES, "rotation follows it")
	var data: PackedByteArray = _buffer(Quantize.BODY_RECORD_BYTES * 2)
	var after: int = Quantize.pack_body(
		data, 0, 1234, Vector3(1.0, 2.0, 3.0), Quaternion.IDENTITY, false, _bounds
	)
	assert_eq(after, Quantize.BODY_RECORD_BYTES, "pack_body returns the offset past the record")
	assert_eq(
		data.slice(Quantize.BODY_RECORD_BYTES),
		_buffer(Quantize.BODY_RECORD_BYTES),
		"it wrote nothing past its own record"
	)


func test_body_records_round_trip_back_to_back() -> void:
	var count: int = 64
	var data: PackedByteArray = _buffer(count * Quantize.BODY_RECORD_BYTES)
	var expected: Array[Dictionary] = []
	var offset: int = 0
	for index: int in range(count):
		var entry: Dictionary = {
			"net_id": index + 1,
			"position": _random_point(),
			"rotation": _random_quat(),
			"sleeping": index % 3 == 0,
		}
		expected.append(entry)
		offset = Quantize.pack_body(
			data, offset, int(entry["net_id"]), entry["position"] as Vector3,
			entry["rotation"] as Quaternion, bool(entry["sleeping"]), _bounds
		)
	assert_eq(offset, data.size(), "the records tile the buffer exactly")

	offset = 0
	for index: int in range(count):
		var got: Dictionary = Quantize.unpack_body(data, offset, _bounds)
		var want: Dictionary = expected[index]
		assert_eq(int(got["net_id"]), int(want["net_id"]), "net_id %d" % index)
		assert_lt(
			((got["position"] as Vector3) - (want["position"] as Vector3)).length(),
			POSITION_TOLERANCE_M,
			"position %d" % index
		)
		assert_lt(
			_angle_deg(got["rotation"] as Quaternion, want["rotation"] as Quaternion),
			ROTATION_TOLERANCE_DEG,
			"rotation %d" % index
		)
		assert_eq(bool(got["sleeping"]), bool(want["sleeping"]), "sleeping %d" % index)
		offset += Quantize.BODY_RECORD_BYTES


func test_net_id_uses_the_full_u24_range() -> void:
	var data: PackedByteArray = _buffer(Quantize.BODY_RECORD_BYTES)
	for net_id: int in [1, 255, 256, 30000, 65535, 65536, 65537, 0x123456, Quantize.NET_ID_MAX]:
		Quantize.pack_body(
			data, 0, net_id, Vector3.ZERO, Quaternion.IDENTITY, false, _bounds
		)
		assert_eq(
			int(Quantize.unpack_body(data, 0, _bounds)["net_id"]), net_id, "net_id %d" % net_id
		)
	assert_eq(Quantize.NET_ID_MAX, 0xFFFFFF, "the ceiling is the u24 maximum")


func test_the_net_id_is_little_endian_over_its_three_bytes() -> void:
	var data: PackedByteArray = _buffer(Quantize.NET_ID_BYTES)
	assert_eq(Quantize.pack_net_id(data, 0, 0x030201), Quantize.NET_ID_BYTES, "returns the offset past it")
	assert_eq(Array(data), [0x01, 0x02, 0x03], "low byte first")
	assert_eq(Quantize.unpack_net_id(data, 0), 0x030201, "and reads back")


func test_an_unrepresentable_net_id_packs_as_no_body_rather_than_truncating() -> void:
	# The registry never allocates these (it refuses at NET_ID_MAX), so this is
	# the packer's own guarantee: whatever reaches it, no bytes on the wire ever
	# name a body other than the one meant.
	var data: PackedByteArray = _buffer(Quantize.NET_ID_BYTES)
	for net_id: int in [-1, 0, Quantize.NET_ID_MAX + 1, Quantize.NET_ID_MAX + 2, 1 << 32]:
		assert_false(Quantize.is_wire_id(net_id), "%d is not a wire id" % net_id)
		Quantize.pack_net_id(data, 0, net_id)
		assert_eq(Quantize.unpack_net_id(data, 0), Quantize.NET_ID_NONE, "%d packs as 'no body'" % net_id)
	assert_true(Quantize.is_wire_id(1), "1 is the first real id")
	assert_true(Quantize.is_wire_id(Quantize.NET_ID_MAX), "and NET_ID_MAX the last")


func test_net_ids_past_the_u16_boundary_do_not_alias_older_bodies() -> void:
	# Bontago-mv0.1.7. game/BlockRegistry.gd allocates net_ids from a monotonic
	# counter and never reuses one within a match, so a long match walks past
	# 65535. A record that carried only 16 bits would pack the 65536th body as
	# 0 — the reserved "no body" — and the 65537th as 1, the very first block of
	# the match, so a snapshot would drop one body and silently move another.
	var data: PackedByteArray = _buffer(Quantize.BODY_RECORD_BYTES)
	var decoded: Dictionary = {}
	for net_id: int in [65535, 65536, 65537]:
		Quantize.pack_body(data, 0, net_id, Vector3.ZERO, Quaternion.IDENTITY, false, _bounds)
		decoded[net_id] = int(Quantize.unpack_body(data, 0, _bounds)["net_id"])
	assert_eq(int(decoded[65535]), 65535, "65535 is the last id a u16 could carry")
	assert_eq(int(decoded[65536]), 65536, "65536 must not collapse to 0, the 'no body' id")
	assert_eq(int(decoded[65537]), 65537, "65537 must not alias an older body")
	assert_ne(int(decoded[65537]), 1, "specifically not net_id 1, the match's first block")


func test_unpack_body_refuses_to_read_past_the_end() -> void:
	var data: PackedByteArray = _buffer(Quantize.BODY_RECORD_BYTES - 1)
	assert_eq(Quantize.unpack_body(data, 0, _bounds), {}, "a truncated record decodes to {}")
	assert_eq(
		Quantize.unpack_body(_buffer(Quantize.BODY_RECORD_BYTES), 1, _bounds),
		{},
		"an offset that overruns decodes to {}"
	)
	assert_eq(Quantize.unpack_body(_buffer(20), -1, _bounds), {}, "a negative offset decodes to {}")


func test_the_same_bytes_decode_differently_under_different_bounds() -> void:
	# docs/M3a_PLAN.md: "Both ends must derive the AABB from the same MapDef ...
	# get it wrong and every body lands somewhere plausible but wrong". This is
	# that failure, pinned down so nobody assumes the record is self-describing.
	var large: AABB = _config.position_bounds(preload("res://config/maps/round_large.tres"))
	var data: PackedByteArray = _buffer(Quantize.BODY_RECORD_BYTES)
	Quantize.pack_body(data, 0, 1, Vector3(20.0, 5.0, -8.0), Quaternion.IDENTITY, false, _bounds)
	var wrong: Vector3 = Quantize.unpack_body(data, 0, large)["position"] as Vector3
	assert_gt(
		(wrong - Vector3(20.0, 5.0, -8.0)).length(),
		1.0,
		"the wrong MapDef puts the body metres away, silently"
	)
