extends GutTest
## core/net/CircleWire.gd: the analytic circle list's wire format
## (Bontago-cmc.5, "MatchNet replicates the list and a client applies it").
## Pure encode/decode round-trips, mirroring tests/unit/net/test_quantize.gd's
## style — no MatchNet, no Match, no peer.

## A representative map's bounds: MapDef.field_radius = 45 (map M) with
## NetConfig's default pos_xz_margin (1.5) gives +-67.5 m; influence_max at
## the same map is 0.6 * 45 = 27 m.
const XZ_BOUND: float = 67.5
const RADIUS_MAX: float = 27.0


func test_a_circle_list_round_trips_within_one_quantization_step() -> void:
	var xs: PackedFloat32Array = PackedFloat32Array([0.0, -30.0, 42.5, 10.0])
	var zs: PackedFloat32Array = PackedFloat32Array([0.0, 12.5, -8.0, -40.0])
	var radii: PackedFloat32Array = PackedFloat32Array([6.0, 1.5, 27.0, 0.0])
	var teams: PackedInt32Array = PackedInt32Array([0, 1, 2, 0])

	var payload: PackedByteArray = CircleWire.encode(
		xs, zs, radii, teams, PackedVector2Array(), PackedFloat32Array(), false, XZ_BOUND, RADIUS_MAX
	)
	var decoded: Dictionary = CircleWire.decode(payload, XZ_BOUND, RADIUS_MAX)

	assert_false(decoded.is_empty())
	var step: float = (XZ_BOUND * 2.0) / 65535.0
	for i: int in range(xs.size()):
		assert_almost_eq(float(decoded["xs"][i]), xs[i], step, "x within one quantization step")
		assert_almost_eq(float(decoded["zs"][i]), zs[i], step, "z within one quantization step")
		assert_eq(int(decoded["teams"][i]), teams[i])
	var radius_step: float = RADIUS_MAX / 65535.0
	for i: int in range(radii.size()):
		assert_almost_eq(float(decoded["radii"][i]), radii[i], radius_step, "radius within one step")
	assert_eq(decoded["goal_positions"].size(), 0)
	assert_false(bool(decoded["argmax_mode"]))


func test_a_truncated_or_foreign_payload_decodes_to_nothing() -> void:
	assert_true(CircleWire.decode(PackedByteArray(), XZ_BOUND, RADIUS_MAX).is_empty())
	assert_true(CircleWire.decode(PackedByteArray([9, 9, 9]), XZ_BOUND, RADIUS_MAX).is_empty())

	var foreign: PackedByteArray = PackedByteArray([200, 1, 0, 0, 0])
	assert_true(
		CircleWire.decode(foreign, XZ_BOUND, RADIUS_MAX).is_empty(),
		"A payload from another packet version must be dropped, not misread."
	)

	var ragged: PackedByteArray = PackedByteArray([CircleWire.VERSION, 1, 0, 0, 0, 1, 2, 3])
	assert_true(
		CircleWire.decode(ragged, XZ_BOUND, RADIUS_MAX).is_empty(),
		"A header claiming one circle record needs 5 + 7 bytes, not 8."
	)

