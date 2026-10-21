extends GutTest
## net/match/TerritoryReplicator.gd: the host encodes the territory raster and the analytic circle
## list as full and diff packets, a client applies them. Driven only through encode_full /
## encode_diff / apply / force_full, so the byte layout stays the replicator's business.

const TerritoryReplicatorScript: GDScript = preload("res://net/match/TerritoryReplicator.gd")
const GRID_SIZE_M: float = 20.0
const GRID_CELL_M: float = 1.0
const XZ_BOUND: float = 67.5
const RADIUS_MAX: float = 27.0

var _tuning: TerritoryTuning = TerritoryTuning.new()
var _config: NetConfig = NetConfig.new()
var _circles: Dictionary = {}
var _received_circles: Dictionary = {}


func before_each() -> void:
	_circles = {
		"xs": PackedFloat32Array([0.0, -10.5, 12.25]),
		"zs": PackedFloat32Array([0.0, 3.0, -7.5]),
		"radii": PackedFloat32Array([6.0, 2.5, 4.0]),
		"teams": PackedInt32Array([0, 1, 2]),
		"goal_positions": PackedVector2Array(),
		"goal_radii": PackedFloat32Array(),
		"argmax_mode": false,
	}
	_received_circles = {}


func _raster() -> TerritoryRaster:
	return TerritoryRaster.new(CellGrid.new(GRID_SIZE_M, GRID_CELL_M), _tuning)


## One replicator over `raster`. The host's circle list comes from `_circles`; a client's decoded
## list lands in `_received_circles`. This is the one place that follows the replicator's
## constructor (the stub has none yet, so it is built bare there).
func _replicator(raster: TerritoryRaster) -> TerritoryReplicator:
	var source: Callable = func() -> Dictionary:
		return _circles
	var sink: Callable = func(arrays: Dictionary) -> void:
		_received_circles = arrays
	var script: GDScript = TerritoryReplicatorScript
	for method: Dictionary in script.get_script_method_list():
		if method["name"] == "_init" and not (method["args"] as Array).is_empty():
			return script.callv("new", [raster, source, sink, _config, XZ_BOUND, RADIUS_MAX]) as TerritoryReplicator
	return TerritoryReplicator.new()


func _seed(raster: TerritoryRaster, cells: Dictionary) -> void:
	var owners: PackedByteArray = raster.owner_bytes()
	var states: PackedByteArray = raster.state_bytes()
	for index: int in cells:
		owners[index] = int((cells[index] as Array)[0])
		states[index] = int((cells[index] as Array)[1])
	raster.apply_replicated_state(owners, states)


func _assert_same_raster(got: TerritoryRaster, want: TerritoryRaster, context: String) -> void:
	assert_eq(got.owner_bytes(), want.owner_bytes(), "%s: owners" % context)
	assert_eq(got.state_bytes(), want.state_bytes(), "%s: states" % context)


func test_a_full_packet_rebuilds_the_host_raster_on_a_client() -> void:
	var host_raster: TerritoryRaster = _raster()
	var count: int = host_raster.owner_bytes().size()
	_seed(host_raster, {
		0: [1, TerritoryRaster.STATE_CONTESTED],
		count / 2: [2, TerritoryRaster.STATE_HOLE],
		count - 1: [3, 0],
	})
	var client_raster: TerritoryRaster = _raster()
	var packet: PackedByteArray = _replicator(host_raster).encode_full()
	assert_gt(packet.size(), 0, "a full packet is never empty")
	assert_true(_replicator(client_raster).apply(packet))
	_assert_same_raster(client_raster, host_raster, "full round trip")
	assert_true(client_raster.is_hole_index(count / 2), "the hole bit survives")


func test_a_diff_packet_carries_only_the_cells_that_changed() -> void:
	var host_raster: TerritoryRaster = _raster()
	var host: TerritoryReplicator = _replicator(host_raster)
	var client_raster: TerritoryRaster = _raster()
	var client: TerritoryReplicator = _replicator(client_raster)
	_seed(host_raster, {10: [1, 0]})
	assert_true(client.apply(host.encode_diff()))
	_assert_same_raster(client_raster, host_raster, "after the first packet")

	_seed(host_raster, {10: [1, 0], 7: [2, TerritoryRaster.STATE_HOLE], 90: [3, TerritoryRaster.STATE_CONTESTED]})
	var diff: PackedByteArray = host.encode_diff()
	assert_gt(diff.size(), 0)
	assert_lt(diff.size(), host.encode_full().size(), "three cells cost less than the keyframe")
	assert_true(client.apply(diff))
	_assert_same_raster(client_raster, host_raster, "diff round trip")


func test_nothing_changed_means_an_empty_diff() -> void:
	var host_raster: TerritoryRaster = _raster()
	var host: TerritoryReplicator = _replicator(host_raster)
	_seed(host_raster, {5: [1, 0]})
	assert_gt(host.encode_diff().size(), 0, "the first call has everything to say")
	assert_eq(host.encode_diff().size(), 0, "an unchanged raster sends nothing")


func test_force_full_makes_the_next_diff_a_full_packet() -> void:
	var host_raster: TerritoryRaster = _raster()
	var host: TerritoryReplicator = _replicator(host_raster)
	_seed(host_raster, {5: [1, 0]})
	host.encode_diff()
	host.force_full()
	var packet: PackedByteArray = host.encode_diff()
	var fresh_client: TerritoryRaster = _raster()
	assert_true(_replicator(fresh_client).apply(packet), "a client with no baseline can use it")
	_assert_same_raster(fresh_client, host_raster, "forced keyframe")


func test_a_diff_over_the_threshold_is_sent_as_a_full_packet() -> void:
	var host_raster: TerritoryRaster = _raster()
	var host: TerritoryReplicator = _replicator(host_raster)
	host.encode_diff()
	var cells: Dictionary = {}
	var count: int = host_raster.owner_bytes().size()
	for index: int in range(int(float(count) * (_config.raster_full_threshold_fraction + 0.1))):
		cells[index] = [1, 0]
	_seed(host_raster, cells)
	var packet: PackedByteArray = host.encode_diff()
	var fresh_client: TerritoryRaster = _raster()
	assert_true(_replicator(fresh_client).apply(packet), "the keyframe stands alone")
	_assert_same_raster(fresh_client, host_raster, "over-threshold change")


func test_a_malformed_packet_is_refused_and_leaves_the_mirror_alone() -> void:
	var host_raster: TerritoryRaster = _raster()
	_seed(host_raster, {3: [2, 0], 40: [1, TerritoryRaster.STATE_HOLE]})
	var good: PackedByteArray = _replicator(host_raster).encode_full()
	var client_raster: TerritoryRaster = _raster()
	var client: TerritoryReplicator = _replicator(client_raster)
	var untouched: PackedByteArray = client_raster.owner_bytes()
	var foreign: PackedByteArray = good.duplicate()
	if not foreign.is_empty():
		foreign[0] = 200
	var packets: Array[PackedByteArray] = [
		PackedByteArray(), PackedByteArray([9, 9, 9]), foreign,
		good.slice(0, 3), good.slice(0, good.size() / 2), good.slice(0, good.size() - 1),
	]
	for packet: PackedByteArray in packets:
		assert_false(client.apply(packet), "refused: %d bytes" % packet.size())
	assert_eq(client_raster.owner_bytes(), untouched, "nothing was half-applied")
	assert_true(client.apply(good), "the well-formed control is accepted")


func test_circles_ride_the_full_packet_within_the_quantization_step() -> void:
	var host_raster: TerritoryRaster = _raster()
	_seed(host_raster, {1: [1, 0]})
	var packet: PackedByteArray = _replicator(host_raster).encode_full()
	assert_true(_replicator(_raster()).apply(packet))
	var step: float = (XZ_BOUND * 2.0) / 65535.0
	var xs: PackedFloat32Array = _received_circles.get("xs", PackedFloat32Array())
	assert_eq(xs.size(), 3, "all three circles arrive")
	for i: int in range(mini(xs.size(), 3)):
		assert_almost_eq(xs[i], (_circles["xs"] as PackedFloat32Array)[i], step)
		assert_almost_eq(
			(_received_circles["zs"] as PackedFloat32Array)[i], (_circles["zs"] as PackedFloat32Array)[i], step
		)
		assert_almost_eq(
			(_received_circles["radii"] as PackedFloat32Array)[i],
			(_circles["radii"] as PackedFloat32Array)[i], RADIUS_MAX / 65535.0
		)
		assert_eq((_received_circles["teams"] as PackedInt32Array)[i], (_circles["teams"] as PackedInt32Array)[i])


func test_circles_outside_the_map_bounds_stay_inside_the_wire_bounds() -> void:
	_circles["xs"] = PackedFloat32Array([5000.0, -5000.0, 0.0])
	_circles["radii"] = PackedFloat32Array([900.0, 1.0, 1.0])
	var packet: PackedByteArray = _replicator(_raster()).encode_full()
	if _replicator(_raster()).apply(packet):
		for x: float in (_received_circles.get("xs", PackedFloat32Array()) as PackedFloat32Array):
			assert_true(absf(x) <= XZ_BOUND + 0.01, "x %f inside the wire bound" % x)
		for r: float in (_received_circles.get("radii", PackedFloat32Array()) as PackedFloat32Array):
			assert_true(r <= RADIUS_MAX + 0.01, "radius %f inside the wire bound" % r)
	else:
		assert_eq(_received_circles.size(), 0, "a refused packet applies no circles")
	assert_gt(packet.size(), 0, "the host still produces a packet")


func test_an_empty_circle_list_still_makes_a_valid_packet() -> void:
	_circles["xs"] = PackedFloat32Array()
	_circles["zs"] = PackedFloat32Array()
	_circles["radii"] = PackedFloat32Array()
	_circles["teams"] = PackedInt32Array()
	var host_raster: TerritoryRaster = _raster()
	_seed(host_raster, {2: [1, 0]})
	var client_raster: TerritoryRaster = _raster()
	assert_true(_replicator(client_raster).apply(_replicator(host_raster).encode_full()))
	assert_eq((_received_circles.get("xs", PackedFloat32Array([1.0])) as PackedFloat32Array).size(), 0, "no stale circles")
	_assert_same_raster(client_raster, host_raster, "no circles")
