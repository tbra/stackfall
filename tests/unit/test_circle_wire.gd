extends GutTest
## core/net/CircleWire.gd: the analytic circle list's wire format
## (Bontago-cmc.5, "MatchNet replicates the list and a client applies it").
## Pure encode/decode round-trips, mirroring tests/unit/test_quantize.gd's
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


func test_goal_discs_round_trip() -> void:
	var goal_positions: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(18.0, -18.0)])
	var goal_radii: PackedFloat32Array = PackedFloat32Array([4.0, 4.0])

	var payload: PackedByteArray = CircleWire.encode(
		PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array(),
		goal_positions, goal_radii, false, XZ_BOUND, RADIUS_MAX
	)
	var decoded: Dictionary = CircleWire.decode(payload, XZ_BOUND, RADIUS_MAX)

	assert_eq(decoded["goal_positions"].size(), 2)
	var step: float = (XZ_BOUND * 2.0) / 65535.0
	var second: Vector2 = decoded["goal_positions"][1]
	assert_almost_eq(second.x, 18.0, step)
	assert_almost_eq(second.y, -18.0, step)
	assert_almost_eq(float(decoded["goal_radii"][1]), 4.0, RADIUS_MAX / 65535.0)


func test_argmax_mode_survives_the_round_trip() -> void:
	var payload: PackedByteArray = CircleWire.encode(
		PackedFloat32Array([1.0]), PackedFloat32Array([1.0]), PackedFloat32Array([1.0]),
		PackedInt32Array([0]), PackedVector2Array(), PackedFloat32Array(), true, XZ_BOUND, RADIUS_MAX
	)
	var decoded: Dictionary = CircleWire.decode(payload, XZ_BOUND, RADIUS_MAX)
	assert_true(bool(decoded["argmax_mode"]))


func test_an_empty_list_encodes_to_just_the_header() -> void:
	var payload: PackedByteArray = CircleWire.encode(
		PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array(),
		PackedVector2Array(), PackedFloat32Array(), false, XZ_BOUND, RADIUS_MAX
	)
	assert_eq(payload.size(), CircleWire.HEADER_BYTES)
	var decoded: Dictionary = CircleWire.decode(payload, XZ_BOUND, RADIUS_MAX)
	assert_eq(decoded["xs"].size(), 0)
	assert_eq(decoded["goal_positions"].size(), 0)


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


func test_mismatched_array_lengths_use_the_shortest() -> void:
	var payload: PackedByteArray = CircleWire.encode(
		PackedFloat32Array([1.0, 2.0]), PackedFloat32Array([1.0]),
		PackedFloat32Array([1.0, 2.0]), PackedInt32Array([0, 1]),
		PackedVector2Array(), PackedFloat32Array(), false, XZ_BOUND, RADIUS_MAX
	)
	var decoded: Dictionary = CircleWire.decode(payload, XZ_BOUND, RADIUS_MAX)
	assert_eq(decoded["xs"].size(), 1, "zs is the shortest array, so only one circle is real.")


func test_team_is_clamped_into_a_byte() -> void:
	var payload: PackedByteArray = CircleWire.encode(
		PackedFloat32Array([0.0]), PackedFloat32Array([0.0]), PackedFloat32Array([1.0]),
		PackedInt32Array([-5]), PackedVector2Array(), PackedFloat32Array(), false, XZ_BOUND, RADIUS_MAX
	)
	var decoded: Dictionary = CircleWire.decode(payload, XZ_BOUND, RADIUS_MAX)
	assert_eq(int(decoded["teams"][0]), 0, "A negative team clamps to 0 rather than wrapping a byte.")


## Bontago-cmc.5's budget: "the territory event stays <= 4 KB at 400
## circles". 400 circles at CIRCLE_RECORD_BYTES (7) plus a handful of goal
## records must clear that with room to spare (docs estimate ~2.8 KB).
func test_four_hundred_circles_stay_under_the_four_kilobyte_budget() -> void:
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	for i: int in range(400):
		xs.append(fmod(float(i), XZ_BOUND))
		zs.append(fmod(float(i) * 1.3, XZ_BOUND))
		radii.append(fmod(float(i) * 0.2, RADIUS_MAX))
		teams.append(i % 8)
	var goal_positions: PackedVector2Array = PackedVector2Array(
		[Vector2.ZERO, Vector2(10, 10), Vector2(-10, -10), Vector2(10, -10), Vector2(-10, 10)]
	)
	var goal_radii: PackedFloat32Array = PackedFloat32Array([4.0, 4.0, 4.0, 4.0, 4.0])

	var payload: PackedByteArray = CircleWire.encode(
		xs, zs, radii, teams, goal_positions, goal_radii, false, XZ_BOUND, RADIUS_MAX
	)

	assert_eq(
		payload.size(),
		CircleWire.HEADER_BYTES + 400 * CircleWire.CIRCLE_RECORD_BYTES + 5 * CircleWire.GOAL_RECORD_BYTES
	)
	assert_lt(payload.size(), 4096, "Bontago-cmc.5's budget: <= 4 KB at 400 circles.")

	var decoded: Dictionary = CircleWire.decode(payload, XZ_BOUND, RADIUS_MAX)
	assert_eq(decoded["xs"].size(), 400)
	assert_eq(decoded["goal_positions"].size(), 5)
