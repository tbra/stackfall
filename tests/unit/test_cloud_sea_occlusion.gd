extends GutTest
## Bontago-mp0.95: the cloud puffs are shader-drawn instances, not physics bodies, so a physics
## ray never sees them and the additive sun flare drew straight over every cloud. CloudSea now
## records bounds for every clump and puff when it builds and answers
## sun_ray_cloud_occlusion(from, dir) -> 0..1 (soft) from them, no physics. These tests build
## a CloudSea holding exactly one puff (so every expectation is exact), then check the
## real sunset theme's recorded totals and the per-query cost.

const SEPARATION_RADII: float = 2.0
const FAR_M: float = 500.0
## Looser than any sane machine needs; the measured cost is printed for the Bead.
const QUERY_BUDGET_MS: float = 12.0


func after_each() -> void:
	Settings.set_graphics_preset(&"high")


## A sea with a single sea-layer puff (no banks, no far ring, no upper layer) and the theme's
## drift replaced by `drift_mps`, so the puff's rest position is the one it was built at.
func _single_puff_sea(drift_mps: float = 0.0) -> CloudSea:
	var theme: SkyThemeDef = Skybox.load_theme("sunset").duplicate() as SkyThemeDef
	theme.cloud_clump_count = 1
	theme.cloud_bank_count = 0
	theme.proc_far_count = 0
	theme.cloud_puffs_per_clump = 1
	theme.cloud_drift_speed_min_mps = drift_mps
	theme.cloud_drift_speed_max_mps = drift_mps
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure(theme, 1.0, null, 1)
	return sea


func _centre(sea: CloudSea) -> Vector3:
	return Vector3(sea._occ_puffs[0], sea._occ_puffs[1], sea._occ_puffs[2])


func _horizontal_radius(sea: CloudSea) -> float:
	return sea._occ_puffs[3]


func test_one_puff_is_recorded_with_its_clump_bounds() -> void:
	var sea: CloudSea = _single_puff_sea()
	assert_eq(sea.occlusion_clump_count(), 1)
	assert_eq(sea.occlusion_puff_count(), 1)
	var centre: Vector3 = _centre(sea)
	assert_true(sea._occ_centre[0].distance_to(centre) < 0.01, "a one-puff clump is bounded around its puff")
	assert_gte(sea._occ_radius[0], _horizontal_radius(sea), "the bounding sphere reaches the puff's silhouette")


func test_sun_behind_a_puff_is_fully_occluded() -> void:
	var sea: CloudSea = _single_puff_sea()
	var centre: Vector3 = _centre(sea)
	var occlusion: float = sea.sun_ray_cloud_occlusion(centre - Vector3(FAR_M, 0.0, 0.0), Vector3.RIGHT, null, 0.0)
	assert_gt(occlusion, 0.99, "a ray through the puff's centre is hidden")


func test_clear_sky_is_not_occluded() -> void:
	var sea: CloudSea = _single_puff_sea()
	var centre: Vector3 = _centre(sea)
	var radius: float = _horizontal_radius(sea)
	# Far to the side of the puff.
	var aside: float = sea.sun_ray_cloud_occlusion(centre + Vector3(-FAR_M, 0.0, radius * 3.0), Vector3.RIGHT, null, 0.0)
	assert_eq(aside, 0.0, "a ray passing clear of the puff sees open sky")
	# Pointing away: the puff is behind the camera, so it cannot hide the sun.
	var behind: float = sea.sun_ray_cloud_occlusion(centre + Vector3(FAR_M, 0.0, 0.0), Vector3.RIGHT, null, 0.0)
	assert_eq(behind, 0.0, "a puff behind the camera hides nothing")
	# Above everything, looking up.
	var above: float = sea.sun_ray_cloud_occlusion(centre + Vector3(0.0, FAR_M, 0.0), Vector3.UP, null, 0.0)
	assert_eq(above, 0.0, "a camera above the clouds looking up sees open sky")


func test_edge_of_a_puff_is_soft_and_monotonic() -> void:
	var sea: CloudSea = _single_puff_sea()
	var centre: Vector3 = _centre(sea)
	var radius: float = _horizontal_radius(sea)
	var tuning: SunFlareConfig = (load("res://config/sun_flare.tres") as SunFlareConfig).duplicate() as SunFlareConfig
	tuning.cloud_edge_softness = 0.3
	var previous: float = 2.0
	for fraction: float in [0.0, 0.6, 0.7, 0.8, 0.85, 0.9, 0.99, 1.05]:
		var from: Vector3 = centre + Vector3(-FAR_M, 0.0, radius * fraction)
		var occlusion: float = sea.sun_ray_cloud_occlusion(from, Vector3.RIGHT, tuning, 0.0)
		assert_lte(occlusion, previous + 0.0001, "occlusion never grows toward the silhouette (%.2f)" % fraction)
		previous = occlusion
		if fraction <= 0.7:
			assert_gt(occlusion, 0.99, "inside the soft band's inner edge the puff is solid (%.2f)" % fraction)
		if fraction >= 1.0:
			assert_eq(occlusion, 0.0, "outside the silhouette nothing is hidden")
	var half: float = sea.sun_ray_cloud_occlusion(centre + Vector3(-FAR_M, 0.0, radius * 0.85), Vector3.RIGHT, tuning, 0.0)
	assert_almost_eq(half, 0.5, 0.03, "midway through the soft band the sun is half hidden")
	tuning.cloud_edge_softness = 0.0
	var hard: float = sea.sun_ray_cloud_occlusion(centre + Vector3(-FAR_M, 0.0, radius * 0.95), Vector3.RIGHT, tuning, 0.0)
	assert_gt(hard, 0.99, "zero softness keeps the whole disc solid")


func test_flat_base_blocks_nothing_below_the_cut() -> void:
	var sea: CloudSea = _single_puff_sea()
	var cut: float = sea._occ_puffs[5]
	assert_gt(cut, CloudSea.NO_BASE_CUT, "the sea's flat-bottomed puff records its base plane")
	var centre: Vector3 = _centre(sea)
	var under: float = sea.sun_ray_cloud_occlusion(Vector3(centre.x - FAR_M, cut - 0.2, centre.z), Vector3.RIGHT, null, 0.0)
	assert_eq(under, 0.0, "a horizontal ray just under the flat base passes below the puff")
	var up_through: float = sea.sun_ray_cloud_occlusion(Vector3(centre.x, cut - 40.0, centre.z), Vector3.UP, null, 0.0)
	assert_gt(up_through, 0.99, "a ray from below the sea that climbs through the puff is hidden by its base")


func test_clump_orbit_follows_the_shader_clock() -> void:
	var sea: CloudSea = _single_puff_sea(10.0)
	var speed: float = sea._occ_speed[0]
	assert_gt(speed, 0.0, "fixture: the clump drifts")
	var rest: Vector3 = _centre(sea)
	var radius: float = _horizontal_radius(sea)
	var angle: float = 2.0
	var time_s: float = angle / speed
	# shaders/cloud_puffs.gdshader: rot2(a) = mat2(vec2(cos, sin), vec2(-sin, cos)) applied to xz.
	var c: float = cos(angle)
	var s: float = sin(angle)
	var moved: Vector3 = Vector3(c * rest.x - s * rest.z, rest.y, s * rest.x + c * rest.z)
	assert_gt(moved.distance_to(rest), SEPARATION_RADII * radius, "fixture: the clump moved well clear of where it was")
	assert_gt(sea.sun_ray_cloud_occlusion(moved - Vector3(FAR_M, 0.0, 0.0), Vector3.RIGHT, null, time_s), 0.99,
			"the puff is where the shader's orbit put it")
	assert_eq(sea.sun_ray_cloud_occlusion(rest - Vector3(FAR_M, 0.0, 0.0), Vector3.RIGHT, null, time_s), 0.0,
			"and no longer where it started")
	assert_gt(sea.sun_ray_cloud_occlusion(rest - Vector3(FAR_M, 0.0, 0.0), Vector3.RIGHT, null, 0.0), 0.99,
			"at time zero it is at its build position")


func test_several_thin_puffs_add_up_and_an_empty_sea_is_clear() -> void:
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	assert_eq(sea.sun_ray_cloud_occlusion(Vector3.ZERO, Vector3.UP, null, 0.0), 0.0, "an unbuilt sea hides nothing")
	var single: CloudSea = _single_puff_sea()
	var centre: Vector3 = _centre(single)
	var radius: float = _horizontal_radius(single)
	var tuning: SunFlareConfig = (load("res://config/sun_flare.tres") as SunFlareConfig).duplicate() as SunFlareConfig
	var from: Vector3 = centre + Vector3(-FAR_M, 0.0, radius * 0.85)
	var one: float = single.sun_ray_cloud_occlusion(from, Vector3.RIGHT, tuning, 0.0)
	# The same single puff twice over, as two clumps' worth of records.
	var doubled: CloudSea = _single_puff_sea()
	doubled._occ_puffs.append_array(doubled._occ_puffs.duplicate())
	doubled._occ_centre.append(doubled._occ_centre[0])
	doubled._occ_radius.append(doubled._occ_radius[0])
	doubled._occ_speed.append(doubled._occ_speed[0])
	doubled._occ_y_low.append(doubled._occ_y_low[0])
	doubled._occ_y_high.append(doubled._occ_y_high[0])
	doubled._occ_first.append(1)
	doubled._occ_count.append(1)
	doubled._occ_upper.append(0)
	var two: float = doubled.sun_ray_cloud_occlusion(from, Vector3.RIGHT, tuning, 0.0)
	assert_almost_eq(two, 1.0 - (1.0 - one) * (1.0 - one), 0.001, "transmittances multiply")
	assert_gt(two, one)


func test_real_theme_bounds_match_the_built_puffs_and_a_query_is_cheap() -> void:
	Settings.set_graphics_preset(&"high")
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment: Environment = Environment.new()
	environment.sky = sky
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = Skybox.load_theme("sunset")
	add_child_autofree(skybox)
	skybox.apply_theme(skybox.theme)
	var sea: CloudSea = skybox.get_cloud_sea()
	assert_gt(sea.occlusion_clump_count(), 100, "the full theme records its clumps")
	assert_eq(sea.occlusion_puff_count(), sea.puff_count() + sea.upper_puff_count(), "one bounds row per drawn puff")
	# Typical gameplay: a camera above the sea, low sun; and the worst case: under the sea, high sun.
	var tuning: SunFlareConfig = load("res://config/sun_flare.tres") as SunFlareConfig
	var sun_low: Vector3 = Vector3(0.963087, 0.069011, -0.260192).normalized()
	var sun_high: Vector3 = Vector3(0.3, 0.9, 0.2).normalized()
	var typical_ms: float = _time_query_ms(sea, Vector3(0.0, 40.0, 60.0), sun_low, tuning)
	var worst_ms: float = _time_query_ms(sea, Vector3(0.0, -400.0, 0.0), sun_high, tuning)
	gut.p("sun_ray_cloud_occlusion: typical %.3f ms, worst case %.3f ms per query (%d clumps, %d puffs)" % [
			typical_ms, worst_ms, sea.occlusion_clump_count(), sea.occlusion_puff_count()])
	assert_lt(typical_ms, QUERY_BUDGET_MS)
	assert_lt(worst_ms, QUERY_BUDGET_MS)


func _time_query_ms(sea: CloudSea, from: Vector3, dir: Vector3, tuning: SunFlareConfig) -> float:
	var runs: int = 20
	var begin: int = Time.get_ticks_usec()
	for _i: int in range(runs):
		sea.sun_ray_cloud_occlusion(from, dir, tuning, 12.0)
	return float(Time.get_ticks_usec() - begin) / 1000.0 / float(runs)
