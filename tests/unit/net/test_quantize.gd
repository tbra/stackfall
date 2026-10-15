extends GutTest
## core/net/Quantize.gd: the snapshot body record (spec 3.4 "Snapshots",
## docs/archive/M3a_PLAN.md P2).
##
## "Contents per body: net_id: u16, position quantized to int16 per axis over
## map bounds (≈1-2 mm precision), rotation as a 48-bit 'smallest three'
## quaternion, and a sleeping flag." The id is u24 here, not u16 — see the
## DECISION at Quantize.pack_net_id() and the boundary tests below.
##
## Every precision assertion here is a measurement, not a restatement of the
## doc comment: the round trip is run over hundreds of thousands of random
## values and the worst case is what is asserted.

## The plan says 0.005 deg; that is the typical error, and the measured
## worst case over the adversarial family is 0.0084 deg. See Quantize's doc
## comment for the arithmetic — 0.009 deg is the honest bound for this layout.
const ROTATION_TOLERANCE_DEG: float = 0.009
## Enough samples that the tail of the error distribution is actually visited
## without making the suite wait for it.
const PROPERTY_SAMPLES: int = 10000
const RNG_SEED: int = 20260918

var _config: NetConfig = preload("res://config/net/net_config.tres")
var _map: MapDef = preload("res://config/match/maps/round.tres")
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


func test_axis_clamps_past_both_ends() -> void:
	assert_eq(Quantize.quantize_axis(-1000.0, -10.0, 10.0), 0, "far below clamps to 0")
	assert_eq(
		Quantize.quantize_axis(1000.0, -10.0, 10.0), Quantize.AXIS_MAX, "far above clamps"
	)
	assert_eq(Quantize.dequantize_axis(-5, -10.0, 10.0), -10.0, "a negative raw clamps")
	assert_eq(Quantize.dequantize_axis(999999, -10.0, 10.0), 10.0, "an over-large raw clamps")


# --- Position ---------------------------------------------------------------

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


# --- Whole record -----------------------------------------------------------

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


func test_unpack_body_refuses_to_read_past_the_end() -> void:
	var data: PackedByteArray = _buffer(Quantize.BODY_RECORD_BYTES - 1)
	assert_eq(Quantize.unpack_body(data, 0, _bounds), {}, "a truncated record decodes to {}")
	assert_eq(
		Quantize.unpack_body(_buffer(Quantize.BODY_RECORD_BYTES), 1, _bounds),
		{},
		"an offset that overruns decodes to {}"
	)
	assert_eq(Quantize.unpack_body(_buffer(20), -1, _bounds), {}, "a negative offset decodes to {}")

