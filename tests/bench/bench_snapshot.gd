extends Node3D
## docs/M3a_PLAN.md, P2 acceptance: "bench_snapshot.gd packs 300 awake bodies
## and reports bytes and pack time — budget <= 2 ms per snapshot at 30 Hz and
## <= 4.5 KB total. Miss it and raise max_packet_bytes or lower snapshot_hz
## **in the resource**, never in code."
##
## Run headless:
##   godot --headless --path . res://tests/bench/bench_snapshot.tscn
## Prints one machine-readable row per body count, then quits non-zero if the
## graded row missed either budget.
##
## Spec 3.4 sets the numbers this checks: "300 awake bodies x ~13 bytes ≈ 4 KB
## per packet. Split into several packets if needed to stay under ~1200 bytes
## each" and "Rate: 30 Hz". Packing is pure, so there is no physics to step and
## everything happens in _ready.
##
## Decode is measured as well as encode, because the client pays it at the same
## rate the host pays encode and it is the half that runs on the machine with
## less headroom.

## The graded configuration (spec 3.4's headline case).
const GRADED_BODIES: int = 300
## docs/M3a_PLAN.md: 2 ms of the 33.3 ms available at snapshot_hz = 30.
const ENCODE_BUDGET_MS: float = 2.0
## docs/M3a_PLAN.md: "<= 4.5 KB total".
const BYTES_BUDGET: int = 4608
## Extra rows for context only, not graded: a full eight-player late game and
## PhysicsTuning's max_active_blocks ceiling.
const EXTRA_BODIES: Array[int] = [84, 600]
const RUNS: int = 200
const RNG_SEED: int = 20260918

var _config: NetConfig = preload("res://config/net_config.tres")
var _map: MapDef = preload("res://config/maps/round_medium.tres")
var _sync: Node = null
var _constants: Dictionary = {}
var _bounds: AABB = AABB()
var _rng: RandomNumberGenerator = null


func _ready() -> void:
	var script: GDScript = load("res://net/SnapshotSync.gd") as GDScript
	_sync = script.new() as Node
	_constants = script.get_script_constant_map()
	_bounds = _config.position_bounds(_map)
	_rng = RandomNumberGenerator.new()
	_rng.seed = RNG_SEED

	var per_fragment: int = _config.bodies_per_fragment(
		int(_constants["HEADER_BYTES"]) + int(_constants["DISK_STATE_BYTES"]),
		Quantize.BODY_RECORD_BYTES
	)
	print(
		("BENCH_SNAPSHOT start map=%s record_bytes=%d max_packet_bytes=%d "
		+ "bodies_per_fragment=%d snapshot_hz=%.0f runs=%d bounds=%.1fx%.1fx%.1f") % [
			_map.id, Quantize.BODY_RECORD_BYTES, _config.max_packet_bytes, per_fragment,
			_config.snapshot_hz, RUNS, _bounds.size.x, _bounds.size.y, _bounds.size.z
		]
	)

	_report_quantization_error()

	var passed: bool = _measure(GRADED_BODIES, true)
	for count: int in EXTRA_BODIES:
		_measure(count, false)

	print("BENCH_SNAPSHOT result=%s" % ["PASS" if passed else "FAIL"])
	_sync.free()
	get_tree().quit(0 if passed else 1)


## Times RUNS encode+decode cycles for `count` bodies and prints one row.
## Returns whether the graded budgets were met.
func _measure(count: int, graded: bool) -> bool:
	var bodies: Array = _make_bodies(count)
	var disk: Transform3D = Transform3D(
		Basis(Quaternion(Vector3.RIGHT, 0.05)), Vector3(0.0, 0.1, 0.0)
	)
	var flags: int = int(_constants["FLAG_DISK_STATE"])

	# One untimed cycle so the first run does not pay for the buffers growing.
	var warm: Array = _build(flags, bodies, disk)
	for packet: Variant in warm:
		_sync.call("decode_fragment", packet as PackedByteArray, _bounds)

	var encode_start: int = Time.get_ticks_usec()
	var packets: Array = []
	for run: int in range(RUNS):
		packets = _build(flags, bodies, disk)
	var encode_ms: float = float(Time.get_ticks_usec() - encode_start) / 1000.0 / float(RUNS)

	var decode_start: int = Time.get_ticks_usec()
	for run: int in range(RUNS):
		for packet: Variant in packets:
			_sync.call("decode_fragment", packet as PackedByteArray, _bounds)
	var decode_ms: float = float(Time.get_ticks_usec() - decode_start) / 1000.0 / float(RUNS)

	var total_bytes: int = 0
	var largest: int = 0
	for packet: Variant in packets:
		var size: int = (packet as PackedByteArray).size()
		total_bytes += size
		largest = maxi(largest, size)

	var over_mtu: bool = largest > _config.max_packet_bytes
	var within_time: bool = encode_ms <= ENCODE_BUDGET_MS
	var within_size: bool = total_bytes <= BYTES_BUDGET
	print(
		("BENCH_SNAPSHOT bodies=%d fragments=%d bytes=%d bytes_per_body=%.2f "
		+ "largest_fragment=%d encode_ms=%.3f decode_ms=%.3f bandwidth_kbps=%.1f graded=%s") % [
			bodies.size(), packets.size(), total_bytes,
			float(total_bytes) / float(maxi(bodies.size(), 1)), largest,
			encode_ms, decode_ms,
			float(total_bytes) * 8.0 * _config.snapshot_hz / 1000.0,
			"yes" if graded else "no"
		]
	)
	if not graded:
		return true

	if over_mtu:
		print("BENCH_SNAPSHOT FAIL a fragment of %d bytes exceeds max_packet_bytes=%d" % [
			largest, _config.max_packet_bytes
		])
	if not within_time:
		print("BENCH_SNAPSHOT FAIL encode_ms=%.3f over the %.1f ms budget" % [
			encode_ms, ENCODE_BUDGET_MS
		])
	if not within_size:
		print("BENCH_SNAPSHOT FAIL bytes=%d over the %d byte budget" % [total_bytes, BYTES_BUDGET])
	return within_time and within_size and not over_mtu


## Reports what the wire costs in precision, so the size numbers above are
## always read next to what was traded for them (spec 3.4: "≈1-2 mm").
func _report_quantization_error() -> void:
	var samples: int = 50000
	var data: PackedByteArray = PackedByteArray()
	data.resize(Quantize.BODY_RECORD_BYTES)
	var worst_position: float = 0.0
	var worst_rotation: float = 0.0
	for index: int in range(samples):
		var position: Vector3 = _random_point()
		var rotation: Quaternion = _random_quat()
		Quantize.pack_body(data, 0, 1, position, rotation, false, _bounds)
		var back: Dictionary = Quantize.unpack_body(data, 0, _bounds)
		worst_position = maxf(
			worst_position, ((back["position"] as Vector3) - position).length()
		)
		worst_rotation = maxf(
			worst_rotation, _angle_deg(back["rotation"] as Quaternion, rotation)
		)
	print(
		"BENCH_SNAPSHOT quantization samples=%d worst_position_mm=%.4f worst_rotation_deg=%.5f "
		% [samples, worst_position * 1000.0, worst_rotation]
		+ "step_xz_mm=%.4f step_y_mm=%.4f" % [
			_bounds.size.x / float(Quantize.AXIS_MAX) * 1000.0,
			_bounds.size.y / float(Quantize.AXIS_MAX) * 1000.0
		]
	)


func _build(flags: int, bodies: Array, disk: Transform3D) -> Array:
	return _sync.call(
		"build_snapshot", 1, 1000, flags, bodies, disk, _bounds, _config
	) as Array


## Bodies spread over the disk and the tower volume above it, the shape a real
## late-game snapshot has: mostly low, a long tail upwards.
func _make_bodies(count: int) -> Array:
	var bodies: Array = []
	for index: int in range(count):
		var angle: float = _rng.randf() * TAU
		var radius: float = sqrt(_rng.randf()) * _map.field_radius
		bodies.append({
			"net_id": index + 1,
			"position": Vector3(
				cos(angle) * radius, _rng.randf() * 12.0, sin(angle) * radius
			),
			"rotation": _random_quat(),
			"sleeping": false,
		})
	return bodies


func _random_point() -> Vector3:
	return _bounds.position + Vector3(
		_rng.randf() * _bounds.size.x,
		_rng.randf() * _bounds.size.y,
		_rng.randf() * _bounds.size.z
	)


func _random_quat() -> Quaternion:
	return Quaternion(
		_rng.randfn(), _rng.randfn(), _rng.randfn(), _rng.randfn()
	).normalized()


## See tests/unit/test_quantize.gd: acos(dot) cannot resolve this error on
## float32 quaternions, so the 4D chord is used instead.
func _angle_deg(a: Quaternion, b: Quaternion) -> float:
	var other: Quaternion = b if a.dot(b) >= 0.0 else -b
	var chord: float = sqrt(
		pow(float(a.x) - float(other.x), 2.0)
		+ pow(float(a.y) - float(other.y), 2.0)
		+ pow(float(a.z) - float(other.z), 2.0)
		+ pow(float(a.w) - float(other.w), 2.0)
	)
	return rad_to_deg(4.0 * asin(clampf(chord * 0.5, 0.0, 1.0)))
