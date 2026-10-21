extends GutTest
## the cloud puffs are shader-drawn instances, not physics bodies, so a physics
## ray never sees them and the additive sun flare drew straight over every cloud. CloudSea now
## records bounds for every clump and puff when it builds and answers
## sun_ray_cloud_occlusion(from, dir) -> 0..1 (soft) from them, no physics. These tests build
## a CloudSea holding exactly one puff (so every expectation is exact), then check the
## shipped cycle's recorded totals and the per-query cost.

const SEPARATION_RADII: float = 2.0
const FAR_M: float = 500.0
const FIXTURE_PATH: String = "res://tests/unit/sky/fixtures/cloud_sea_frame_expected.json"
const EXPECTED_QUERIES: int = 9
const QUERY_EPSILON: float = 0.00001
const SWEEP_STEP_M: float = 2.0
const SWEEP_PRECISION_M: float = 0.001
const SWEEP_RADII: float = 8.0
const PROBE_HIDDEN: float = 0.5
const DRIFT_SHIFT_RADII: float = 3.0
const DRIFT_ACCURACY_M: float = 0.05

func after_each() -> void:
	Settings.set_graphics_preset(&"high")


## A sea with a single sea-layer puff (no banks, no far ring, no upper layer) and the cycle's
## drift replaced by `drift_mps`, so the puff's rest position is the one it was built at.
func _single_puff_sea(drift_mps: float = 0.0) -> CloudSea:
	var def: SkyCycleDef = _sunset_cycle()
	def.cloud_clump_count = 1
	def.cloud_bank_count = 0
	def.proc_far_count = 0
	def.cloud_puffs_per_clump = 1
	def.cloud_drift_speed_min_mps = drift_mps
	def.cloud_drift_speed_max_mps = drift_mps
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure_cycle(def, null, 1.0, 1)
	return sea


func _sunset_cycle() -> SkyCycleDef:
	return SkyTestKit.cycle()


func _centre(sea: CloudSea) -> Vector3:
	return SkyTestKit.puff_centre(sea)


## How much a vertical ray `sideways` metres off `centre` along +z, started far below, is hidden
## at the wind `offset`. A vertical ray sees the puff's horizontal silhouette whatever its height.
func _cover_beside(sea: CloudSea, centre: Vector3, sideways: float, offset: Vector2 = Vector2.ZERO,
		tuning: SunFlareConfig = null) -> float:
	return sea.sun_ray_cloud_occlusion(Vector3(centre.x, centre.y - FAR_M, centre.z + sideways), Vector3.UP, tuning, offset)


## The puff's horizontal radius, measured from the sweep: how far a vertical ray can be moved
## sideways before the sea hides nothing of it.
func _horizontal_radius(sea: CloudSea, centre: Vector3) -> float:
	var inside: float = 0.0
	var outside: float = SWEEP_STEP_M
	while _cover_beside(sea, centre, outside) > 0.0 and outside < FAR_M:
		inside = outside
		outside *= 2.0
	while outside - inside > SWEEP_PRECISION_M:
		var middle: float = (inside + outside) * 0.5
		if _cover_beside(sea, centre, middle) > 0.0:
			inside = middle
		else:
			outside = middle
	return inside


## Where the puff sits along z at the wind `offset`, found by sweeping a vertical ray over the
## hidden span (middle of its two edges); INF when it is hidden nowhere in the sweep.
func _centre_z_at(sea: CloudSea, centre: Vector3, radius: float, offset: Vector2) -> float:
	var span: float = radius * SWEEP_RADII
	var z: float = -span
	var first: float = INF
	while z <= span:
		if _cover_beside(sea, centre, z, offset) > PROBE_HIDDEN:
			first = z
			break
		z += radius * 0.5
	if first == INF:
		return INF
	var edges: Array[float] = []
	for direction: float in [-1.0, 1.0]:
		var inside: float = first
		var outside: float = first + direction * radius * SWEEP_RADII
		while absf(outside - inside) > SWEEP_PRECISION_M:
			var middle: float = (inside + outside) * 0.5
			if _cover_beside(sea, centre, middle, offset) > PROBE_HIDDEN:
				inside = middle
			else:
				outside = middle
		edges.append(inside)
	return centre.z + (edges[0] + edges[1]) * 0.5


func test_sun_behind_a_puff_is_fully_occluded() -> void:
	var sea: CloudSea = _single_puff_sea()
	var centre: Vector3 = _centre(sea)
	var occlusion: float = sea.sun_ray_cloud_occlusion(centre - Vector3(FAR_M, 0.0, 0.0), Vector3.RIGHT, null, Vector2.ZERO)
	assert_gt(occlusion, 0.99, "a ray through the puff's centre is hidden")


func test_clear_sky_is_not_occluded() -> void:
	var sea: CloudSea = _single_puff_sea()
	var centre: Vector3 = _centre(sea)
	var radius: float = _horizontal_radius(sea, centre)
	assert_gt(radius, 0.0, "fixture: the sweep finds the puff's edge")
	# Far to the side of the puff.
	var aside: float = _cover_beside(sea, centre, radius * 3.0)
	assert_eq(aside, 0.0, "a ray passing clear of the puff sees open sky")
	# Pointing away: the puff is behind the camera, so it cannot hide the sun.
	var behind: float = sea.sun_ray_cloud_occlusion(centre + Vector3(FAR_M, 0.0, 0.0), Vector3.RIGHT, null, Vector2.ZERO)
	assert_eq(behind, 0.0, "a puff behind the camera hides nothing")
	# Above everything, looking up.
	var above: float = sea.sun_ray_cloud_occlusion(centre + Vector3(0.0, FAR_M, 0.0), Vector3.UP, null, Vector2.ZERO)
	assert_eq(above, 0.0, "a camera above the clouds looking up sees open sky")


func test_edge_of_a_puff_is_soft_and_monotonic() -> void:
	var sea: CloudSea = _single_puff_sea()
	var centre: Vector3 = _centre(sea)
	var radius: float = _horizontal_radius(sea, centre)
	var tuning: SunFlareConfig = (load("res://config/sky/sun_flare.tres") as SunFlareConfig).duplicate() as SunFlareConfig
	tuning.cloud_edge_softness = 0.3
	var previous: float = 2.0
	for fraction: float in [0.0, 0.6, 0.7, 0.8, 0.85, 0.9, 0.99, 1.05]:
		var occlusion: float = _cover_beside(sea, centre, radius * fraction, Vector2.ZERO, tuning)
		assert_lte(occlusion, previous + 0.0001, "occlusion never grows toward the silhouette (%.2f)" % fraction)
		previous = occlusion
		if fraction <= 0.7:
			assert_gt(occlusion, 0.99, "inside the soft band's inner edge the puff is solid (%.2f)" % fraction)
		if fraction >= 1.0:
			assert_eq(occlusion, 0.0, "outside the silhouette nothing is hidden")
	var half: float = _cover_beside(sea, centre, radius * 0.85, Vector2.ZERO, tuning)
	assert_almost_eq(half, 0.5, 0.03, "midway through the soft band the sun is half hidden")
	tuning.cloud_edge_softness = 0.0
	var hard: float = _cover_beside(sea, centre, radius * 0.95, Vector2.ZERO, tuning)
	assert_gt(hard, 0.99, "zero softness keeps the whole disc solid")


func test_clump_drift_follows_the_shared_wind_offset() -> void:
	var sea: CloudSea = _single_puff_sea(10.0)
	var rest: Vector3 = _centre(sea)
	var radius: float = _horizontal_radius(sea, rest)
	# A wind along z slides the puff along z by a distance proportional to the offset.
	var offset: Vector2 = Vector2(0.0, DRIFT_SHIFT_RADII * radius / 10.0)
	var moved: float = _centre_z_at(sea, rest, radius, offset)
	assert_ne(moved, INF, "the puff is still found under the wind")
	var shift: float = moved - rest.z
	assert_gt(shift, 0.0, "the clump drifts downwind: fixture")
	var doubled: float = _centre_z_at(sea, rest, radius, offset * 2.0)
	assert_almost_eq(doubled - rest.z, shift * 2.0, DRIFT_ACCURACY_M, "twice the wind offset moves it twice as far")
	assert_gt(shift, radius, "fixture: the clump moved well clear of where it was")
	var at_rest: Vector3 = Vector3(rest.x, rest.y - FAR_M, rest.z)
	assert_eq(sea.sun_ray_cloud_occlusion(at_rest, Vector3.UP, null, offset), 0.0, "and no longer where it started")
	assert_gt(sea.sun_ray_cloud_occlusion(at_rest, Vector3.UP, null, Vector2.ZERO), 0.99, "with no wind it is at its build position")
	var at_moved: Vector3 = Vector3(rest.x, rest.y - FAR_M, moved)
	var explicit: float = sea.sun_ray_cloud_occlusion(at_moved, Vector3.UP, null, offset)
	assert_gt(explicit, PROBE_HIDDEN, "the puff is where the drift put it")
	sea.set_drift_offset(offset)
	assert_eq(sea.sun_ray_cloud_occlusion(at_moved, Vector3.UP), explicit,
			"the default query uses the live offset set by set_drift_offset()")


## The shipped sea answers the nine sun-ray queries captured from the old configure(sunset theme, ...)
## entry (fixtures/cloud_sea_frame_expected.json, "occlusion"), at a fixed wind offset.
func test_shipped_cycle_records_the_captured_bounds() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	assert_true(parsed is Dictionary, "fixture parses")
	var expected: Dictionary = (parsed as Dictionary)["occlusion"] as Dictionary
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure_cycle(_sunset_cycle(), null, 1.0, 1)
	var queries: Array = expected["queries"] as Array
	assert_eq(queries.size(), EXPECTED_QUERIES, "the fixture holds the nine queries")
	for query: Dictionary in queries:
		var from_parts: Array = query["from"] as Array
		var dir_parts: Array = query["dir"] as Array
		var from: Vector3 = Vector3(float(from_parts[0]), float(from_parts[1]), float(from_parts[2]))
		var dir: Vector3 = Vector3(float(dir_parts[0]), float(dir_parts[1]), float(dir_parts[2]))
		assert_almost_eq(sea.sun_ray_cloud_occlusion(from, dir, null, Vector2(37.0, -12.0)), float(query["cover"]), QUERY_EPSILON,
				"same query result from %s along %s" % [from, dir])


func test_empty_bounds_hide_nothing() -> void:
	assert_eq(CloudOcclusionBounds.new().ray_cover(Vector3(-FAR_M, 0.0, 0.0), Vector3.RIGHT, null, Vector2.ZERO), 0.0,
			"empty bounds hide nothing")


## Literal expected values over several clumps (hand computed, not new-vs-new): two unit-radius-10
## round puffs on the ray's line, 8.5 m off their centres with a 0.3 soft band, each cover
## 1 - smoothstep(0.7, 1, 0.85) = 0.5, so the transmittances multiply to 0.25. A third clump 500 m
## up is skipped by the height slab.
func test_several_clumps_multiply_with_literal_values() -> void:
	var bounds: CloudOcclusionBounds = CloudOcclusionBounds.new()
	var domain: float = 1000.0
	for at: Vector3 in [Vector3(0.0, 0.0, 0.0), Vector3(100.0, 0.0, 0.0), Vector3(50.0, 500.0, 0.0)]:
		var first: int = bounds.puff_rows()
		bounds.record_puff(at, 10.0, 10.0, 1.0)
		bounds.record_clump(first, 0.0, false, Color(at.x, at.z, domain, 0.0))
	var tuning: SunFlareConfig = (load("res://config/sky/sun_flare.tres") as SunFlareConfig).duplicate() as SunFlareConfig
	tuning.cloud_edge_softness = 0.3
	assert_almost_eq(bounds.ray_cover(Vector3(-FAR_M, 0.0, 0.0), Vector3.RIGHT, tuning, Vector2.ZERO), 1.0, 0.0001,
			"through both centres: fully hidden")
	assert_almost_eq(bounds.ray_cover(Vector3(-FAR_M, 0.0, 8.5), Vector3.RIGHT, tuning, Vector2.ZERO), 0.75, 0.002,
			"two half-covers: 1 - 0.5 * 0.5")
	assert_almost_eq(bounds.ray_cover(Vector3(-FAR_M, 0.0, 8.5), Vector3.LEFT, tuning, Vector2.ZERO), 0.0, 0.0001,
			"pointing away hides nothing")
	assert_almost_eq(bounds.ray_cover(Vector3(-FAR_M, 0.0, 20.0), Vector3.RIGHT, tuning, Vector2.ZERO), 0.0, 0.0001,
			"passing 20 m off hides nothing")
	assert_almost_eq(bounds.ray_cover(Vector3(50.0, 100.0, 0.0), Vector3.UP, tuning, Vector2.ZERO), 1.0, 0.0001,
			"the high clump hides a ray straight up through it")
