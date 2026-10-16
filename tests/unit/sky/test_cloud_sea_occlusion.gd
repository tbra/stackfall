extends GutTest
## the cloud puffs are shader-drawn instances, not physics bodies, so a physics
## ray never sees them and the additive sun flare drew straight over every cloud. CloudSea now
## records bounds for every clump and puff when it builds and answers
## sun_ray_cloud_occlusion(from, dir) -> 0..1 (soft) from them, no physics. These tests build
## a CloudSea holding exactly one puff (so every expectation is exact), then check the
## real sunset theme's recorded totals and the per-query cost.

const SEPARATION_RADII: float = 2.0
const FAR_M: float = 500.0
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


func test_sun_behind_a_puff_is_fully_occluded() -> void:
	var sea: CloudSea = _single_puff_sea()
	var centre: Vector3 = _centre(sea)
	var occlusion: float = sea.sun_ray_cloud_occlusion(centre - Vector3(FAR_M, 0.0, 0.0), Vector3.RIGHT, null, Vector2.ZERO)
	assert_gt(occlusion, 0.99, "a ray through the puff's centre is hidden")


func test_clear_sky_is_not_occluded() -> void:
	var sea: CloudSea = _single_puff_sea()
	var centre: Vector3 = _centre(sea)
	var radius: float = _horizontal_radius(sea)
	# Far to the side of the puff.
	var aside: float = sea.sun_ray_cloud_occlusion(centre + Vector3(-FAR_M, 0.0, radius * 3.0), Vector3.RIGHT, null, Vector2.ZERO)
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
	var radius: float = _horizontal_radius(sea)
	var tuning: SunFlareConfig = (load("res://config/sky/sun_flare.tres") as SunFlareConfig).duplicate() as SunFlareConfig
	tuning.cloud_edge_softness = 0.3
	var previous: float = 2.0
	for fraction: float in [0.0, 0.6, 0.7, 0.8, 0.85, 0.9, 0.99, 1.05]:
		var from: Vector3 = centre + Vector3(-FAR_M, 0.0, radius * fraction)
		var occlusion: float = sea.sun_ray_cloud_occlusion(from, Vector3.RIGHT, tuning, Vector2.ZERO)
		assert_lte(occlusion, previous + 0.0001, "occlusion never grows toward the silhouette (%.2f)" % fraction)
		previous = occlusion
		if fraction <= 0.7:
			assert_gt(occlusion, 0.99, "inside the soft band's inner edge the puff is solid (%.2f)" % fraction)
		if fraction >= 1.0:
			assert_eq(occlusion, 0.0, "outside the silhouette nothing is hidden")
	var half: float = sea.sun_ray_cloud_occlusion(centre + Vector3(-FAR_M, 0.0, radius * 0.85), Vector3.RIGHT, tuning, Vector2.ZERO)
	assert_almost_eq(half, 0.5, 0.03, "midway through the soft band the sun is half hidden")
	tuning.cloud_edge_softness = 0.0
	var hard: float = sea.sun_ray_cloud_occlusion(centre + Vector3(-FAR_M, 0.0, radius * 0.95), Vector3.RIGHT, tuning, Vector2.ZERO)
	assert_gt(hard, 0.99, "zero softness keeps the whole disc solid")


func test_clump_drift_follows_the_shared_wind_offset() -> void:
	var sea: CloudSea = _single_puff_sea(10.0)
	var speed: float = sea._occ_speed[0]
	assert_gt(speed, 0.0, "fixture: the clump drifts")
	var rest: Vector3 = _centre(sea)
	var radius: float = _horizontal_radius(sea)
	# shaders/sky/cloud_puffs.gdshader: the clump slides by drift_offset * speed (wrapped in its domain).
	var offset: Vector2 = Vector2(0.0, 1.0) * (SEPARATION_RADII * radius * 4.0 / speed)
	var wrapped: Vector2 = CloudDriftMath.wrapped_position(sea._occ_rest[0], offset * speed, sea._occ_domain[0])
	var moved: Vector3 = rest + Vector3(wrapped.x - sea._occ_rest[0].x, 0.0, wrapped.y - sea._occ_rest[0].y)
	assert_gt(moved.distance_to(rest), SEPARATION_RADII * radius, "fixture: the clump moved well clear of where it was")
	assert_gt(sea.sun_ray_cloud_occlusion(moved - Vector3(FAR_M, 0.0, 0.0), Vector3.RIGHT, null, offset), 0.99,
			"the puff is where the shader's drift put it")
	assert_eq(sea.sun_ray_cloud_occlusion(rest - Vector3(FAR_M, 0.0, 0.0), Vector3.RIGHT, null, offset), 0.0,
			"and no longer where it started")
	assert_gt(sea.sun_ray_cloud_occlusion(rest - Vector3(FAR_M, 0.0, 0.0), Vector3.RIGHT, null, Vector2.ZERO), 0.99,
			"with no wind it is at its build position")
	sea.set_drift_offset(offset)
	assert_eq(sea.sun_ray_cloud_occlusion(rest - Vector3(FAR_M, 0.0, 0.0), Vector3.RIGHT), 0.0,
			"the default query uses the live offset set by set_drift_offset()")

